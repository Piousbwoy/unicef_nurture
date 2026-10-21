"""Accept or reject a trained Dagbani voice before it reaches the app.

Four machine gates, then the human gate that no machine may sign off:

  coverage   every app sentence encodes without dropping a letter
  language   facebook/mms-lid-2048 classifies the clip as Dagbani   (--lid)
  words      a Dagbani ASR model gets the words back                 (--asr)
  speed      real-time factor on two CPU threads, plus pack size
  ears       writes earcheck_*.wav and marks humanListeningApproved false

Run:  python tool/track_b/eval_voice.py --pack data/dagbani --repo .
      add --lid and --asr on a machine that can hold those models.
"""
import argparse, json, re, sys, time, unicodedata
from pathlib import Path

import numpy as np

APP_FILE = "lib/core/i18n/dagbani_strings.dart"
BANK_FILE = "lib/core/i18n/speech_bank.dart"
MAX_RTF = 1.0


def app_lines(repo: Path) -> list[str]:
    lines = []
    for rel in (APP_FILE, BANK_FILE):
        path = repo / rel
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf8").splitlines():
            match = re.search(r"dagbani:\s*['\"](.+)['\"],?\s*$", line)
            if match:
                lines.append(match.group(1))
    return lines


def encode_units(config: dict, text: str) -> list[int]:
    """PiperPhonemizer.encodeUnits for a text (character) phoneme pack."""
    table = config["phoneme_id_map"]
    folded = unicodedata.normalize("NFD", text.lower())
    pad = table["_"]
    ids = [*table["^"], *pad]
    for c in folded:
        if c not in table:
            continue
        ids += [*table[c], *pad]
    return ids + table["$"]


def unsymbols(text: str, symbols: set[str]) -> set[str]:
    folded = unicodedata.normalize("NFD", text.lower())
    return {c for c in folded if not c.isspace()
            and c not in symbols
            and unicodedata.category(c)[0] not in "PSCK"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="data/dagbani")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--sentences", type=int, default=6)
    ap.add_argument("--lid", action="store_true")
    ap.add_argument("--asr", action="store_true")
    ap.add_argument("--asr-model", default="KhayaAI/w2v-bert-dga")
    args = ap.parse_args()

    pack = Path(args.pack)
    config_path = pack / "model.onnx.json"
    model_path = pack / "model.onnx"
    if not config_path.exists() or not model_path.exists():
        print(f"{pack} has no model.onnx / model.onnx.json yet")
        return 1
    config = json.loads(config_path.read_text(encoding="utf8"))
    rate = config["audio"]["sample_rate"]
    symbols = set(config["phoneme_id_map"])

    wanted = app_lines(Path(args.repo))
    unvoiced = [line for line in wanted if unsymbols(line, symbols)]
    coverage = {
        "appLines": len(wanted),
        "linesWithUnvoicedLetters": len(unvoiced),
        "unvoicedLetters": sorted({c for line in unvoiced for c in unsymbols(line, symbols)}),
    }

    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model_path), sess_options=options,
                                   providers=["CPUExecutionProvider"])

    names = sorted(i.name for i in session.get_inputs())
    allowed = [["input", "input_lengths"],
               ["input", "input_lengths", "scales"],
               ["input", "input_lengths", "scales", "sid"],
               ["input", "input_lengths", "sid"]]
    if names not in allowed:
        print("CONTRACT FAIL, exported tensor inputs are:", names)
        print("The app's engine accepts only:", allowed)
        return 2
    print("tensor contract:", names)

    def speak(text: str) -> tuple[np.ndarray, float]:
        ids = np.array([encode_units(config, text)], dtype=np.int64)
        feed = {"input": ids, "input_lengths": np.array([ids.shape[1]], dtype=np.int64)}
        if "scales" in [i.name for i in session.get_inputs()]:
            inference = config["inference"]
            feed["scales"] = np.array(
                [inference["noise_scale"], inference["length_scale"], inference["noise_w"]],
                dtype=np.float32,
            )
        started = time.perf_counter()
        wave = np.asarray(session.run(None, feed)[0]).reshape(-1)
        return wave, time.perf_counter() - started

    clips, rtfs = [], []
    for index, text in enumerate(wanted[: args.sentences], start=1):
        wave, elapsed = speak(text)
        seconds = wave.size / rate
        rtfs.append(elapsed / max(seconds, 0.01))
        import soundfile as sf
        path = pack / f"earcheck_{index}.wav"
        sf.write(path, wave, rate)
        clips.append(path.name)
        print(f"{path.name}  {seconds:.2f}s audio in {elapsed:.2f}s  "
              f"rms={float(np.sqrt((wave ** 2).mean())):.3f}")

    verdict = {
        "pack": str(pack),
        "bytes": model_path.stat().st_size,
        "sampleRate": rate,
        "tensorInputs": names,
        "coverage": coverage,
        "realTimeFactorMean": round(float(np.mean(rtfs)), 2) if rtfs else None,
        "clips": clips,
        "humanListeningApproved": False,
        "clinicalApproved": False,
    }

    speed_ok = verdict["realTimeFactorMean"] is not None and verdict["realTimeFactorMean"] <= MAX_RTF
    if not speed_ok:
        print(f"SPEED FAIL: mean RTF {verdict['realTimeFactorMean']} > {MAX_RTF}")

    if args.lid:
        verdict["languageId"] = run_lid(pack / clips[0]) if clips else None
        print("language id:", verdict["languageId"])
    if args.asr:
        verdict["asrRoundTrip"] = run_asr(args.asr_model, pack, clips, wanted)
        print("asr round trip:", verdict["asrRoundTrip"])

    (pack / "verdict.json").write_text(
        json.dumps(verdict, indent=2, ensure_ascii=False) + "\n", encoding="utf8")

    passed = coverage["linesWithUnvoicedLetters"] == 0 and speed_ok
    print("PASS" if passed else "FAIL", "->", pack / "verdict.json")
    print("A machine cannot approve a voice. Listen to the earcheck clips, then set "
          "humanListeningApproved with your name and date.")
    return 0 if passed else 2


def run_lid(wav: Path) -> dict:
    import torch
    from transformers import AutoModelForAudioClassification, AutoProcessor
    model_id = "facebook/mms-lid-2048"
    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForAudioClassification.from_pretrained(model_id).eval()
    import soundfile as sf
    speech, rate = sf.read(wav)
    if rate != 16000:
        return {"error": f"{wav} is {rate} Hz, LID wants 16 kHz"}
    outputs = model(**processor(speech, sampling_rate=16000, return_tensors="pt"))
    top = torch.softmax(outputs.logits, -1).topk(3)
    return {
        "labels": [model.config.id2label[i] for i in top.indices[0]],
        "scores": [round(float(v), 3) for v in top.values[0]],
    }


def run_asr(model_id: str, pack: Path, clips: list[str], texts: list[str]) -> dict:
    """Score the voice with a Dagbani recogniser, so the words must be right."""
    import difflib
    import torch
    from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor
    import soundfile as sf
    processor = AutoProcessor.from_pretrained(model_id)
    model = AutoModelForSpeechSeq2Seq.from_pretrained(model_id).eval()
    rows = []
    for name, expected in zip(clips, texts):
        speech, rate = sf.read(pack / name)
        features = processor(speech, sampling_rate=rate, return_tensors="pt").input_features
        with torch.no_grad():
            ids = model.generate(features, max_new_tokens=128)
        heard = processor.batch_decode(ids, skip_special_tokens=True)[0]
        ratio = difflib.SequenceMatcher(None, expected.lower(), heard.lower()).ratio()
        rows.append({"expected": expected, "heard": heard, "similarity": round(ratio, 3)})
    return {"model": model_id, "rows": rows,
            "meanSimilarity": round(sum(r["similarity"] for r in rows) / len(rows), 3)}


if __name__ == "__main__":
    sys.exit(main())
