"""Would closed-vocabulary voice input work on real Dagbani speech?

The app's voice answers are short set phrases, so a no-training mechanism would
have to be template matching: synthesise the words the user is allowed to say,
then find the best-matching window in the microphone buffer. Two measurements,
in this order:

  CONTROL   our own TTS saying 3-word slices, matched against TTS word
            templates. Same voice, same channel, same acoustics, so a matcher
            that works MUST score this near 1.0. It exists to prove the
            features carry word identity at all; without it a low real-speech
            number is uninterpretable.
  REAL      the same templates slid across 400 real corpus sentences (~10 s
            each) with no transcript and no timestamps. Far harder than the
            shipping task (a whole 1-2 s answer), so the number is a lower
            bound on the UX.

Run:  python tool/asr_kws_probe.py --corpus data/dagbani --pack assets/tts/dagbani_piper
"""
import argparse
import hashlib
import io
import json
import random
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf

SR = 16000
HOP = 0.01
NFFT = 512
WIN = 0.025
NMEL = 40
NFIX = 24
LENGTHS = (0.80, 1.20, 1.60, 2.20)


def synthesize(pack: Path, texts: list[str]) -> dict[str, np.ndarray]:
    """Speak each text in isolation with the given voice pack. Cached on disk
    because synthesis is the slow half of this measurement and the matcher
    gets re-run against the same utterances."""
    cache = Path("data/kws_cache")
    cache.mkdir(parents=True, exist_ok=True)
    wanted, out = [], {}
    for text in texts:
        key = hashlib.sha1(f"{pack}|{text}".encode()).hexdigest()[:24]
        hit = cache / f"{key}.npy"
        if hit.exists():
            out[text] = np.load(hit)
        else:
            wanted.append(text)
    if not wanted:
        return out
    config = json.loads((pack / "model.onnx.json").read_text(encoding="utf8"))
    frontend = config["character_frontend"]
    vocab, pad = frontend["vocabulary"], frontend["pad_id"]
    aliases = frontend.get("aliases", {})
    pad_char = next(c for c, i in vocab.items() if i == pad)
    space = vocab.get(" ")
    session = ort.InferenceSession(str(pack / "model.onnx"),
                                   providers=["CPUExecutionProvider"])
    for text in wanted:
        kept = [c for c in "".join(aliases.get(x, x) for x in text.lower()) if c in vocab]
        while kept and vocab[kept[0]] == space:
            kept.pop(0)
        while kept and vocab[kept[-1]] == space:
            kept.pop()
        ids, i = [], 0
        while i < len(kept):
            if kept[i] == pad_char:
                m = 0
                while i + m < len(kept) and kept[i + m] == pad_char:
                    m += 1
                start, end = not ids, i + m == len(kept)
                ids += [pad] * (m if start and end else m + 1 if (start or end) else m + 2)
                i += m
                continue
            if not ids or ids[-1] != pad:
                ids.append(pad)
            ids.append(vocab[kept[i]])
            i += 1
        if ids and ids[-1] != pad:
            ids.append(pad)
        if not ids:
            continue
        audio = session.run(None, {
            "input": np.array([ids], np.int64),
            "input_lengths": np.array([len(ids)], np.int64)})[0]
        samples = np.asarray(audio).reshape(-1).astype(np.float32)
        out[text] = samples
        key = hashlib.sha1(f"{pack}|{text}".encode()).hexdigest()[:24]
        np.save(cache / f"{key}.npy", samples)
    return out


def mel_bank():
    low, high = 60.0, SR / 2
    points = np.linspace(low, high, NMEL + 2)
    bins = np.floor(points / SR * NFFT).astype(int)
    bank = np.zeros((NMEL, NFFT // 2 + 1))
    for i in range(NMEL):
        left, centre, right = bins[i], bins[i + 1], bins[i + 2]
        for j in range(left, centre):
            bank[i, j] = (j - left) / max(centre - left, 1)
        for j in range(centre, right):
            bank[i, j] = (right - j) / max(right - centre, 1)
    return bank


BANK = mel_bank()
DCT = np.array([[np.cos(np.pi * k * (n + 0.5) / NMEL) for n in range(NMEL)]
                for k in range(13)], dtype=np.float64) * (2.0 / NMEL) ** 0.5


def to_16k(samples: np.ndarray, source_sr: int) -> np.ndarray:
    if source_sr == SR:
        return samples
    count = int(round(len(samples) * SR / source_sr))
    pos = np.linspace(0, len(samples) - 1, count)
    return np.interp(pos, np.arange(len(samples)), samples).astype(np.float32)


def trim(samples: np.ndarray) -> np.ndarray:
    """Drop the leading and trailing silence VITS leaves around an utterance."""
    step = int(HOP * SR)
    count = max(len(samples) // step, 1)
    energy = np.sqrt((samples[: count * step].reshape(count, step) ** 2).mean(1))
    limit = 0.05 * energy.max()
    voiced = np.nonzero(energy > limit)[0]
    if len(voiced) == 0:
        return samples
    return samples[voiced[0] * step: min((voiced[-1] + 3) * step, len(samples))]


def mfcc(samples: np.ndarray) -> np.ndarray:
    samples = trim(samples)
    if samples.size < NFFT:
        samples = np.pad(samples, (0, NFFT - samples.size))
    size = int(WIN * SR)
    step = int(HOP * SR)
    count = 1 + (len(samples) - size) // step
    if count <= 0:
        return np.zeros((1, 13), np.float32)
    view = np.lib.stride_tricks.as_strided(
        samples, (count, size), (samples.strides[0] * step, samples.strides[0]))
    spec = np.abs(np.fft.rfft(view * np.hanning(size), NFFT)) ** 2
    logmel = np.log(np.maximum(spec @ BANK.T, 1e-10))
    coef = logmel @ DCT.T
    return ((coef - coef.mean(0)) / (coef.std(0) + 1e-8)).astype(np.float32)


def resample(frames: np.ndarray, target: int = NFIX) -> np.ndarray:
    """Interpolate the time axis (second-to-last) to `target` frames; works
    per-item on a batched (windows, frames, coeffs) array."""
    length = frames.shape[-2]
    idx = np.linspace(0, length - 1, target)
    low = np.floor(idx).astype(int)
    high = np.minimum(low + 1, length - 1)
    frac = (idx - low)[:, None]
    return frames[..., low, :] * (1 - frac) + frames[..., high, :] * frac


def normalize(frames: np.ndarray) -> np.ndarray:
    """Per-window mean/variance removal, flatten, unit L2. Broadcasts over a
    leading batch axis, so one call normalises every window in a clip."""
    centred = (frames - frames.mean(axis=-2, keepdims=True))
    scaled = centred / (centred.std(axis=-2, keepdims=True) + 1e-6)
    flat = scaled.reshape(*scaled.shape[:-2], -1)
    return (flat / (np.linalg.norm(flat, axis=-1, keepdims=True) + 1e-9)).astype(np.float32)


def template_vector(samples: np.ndarray) -> np.ndarray:
    return normalize(resample(mfcc(samples)))


def candidate_windows(frames: np.ndarray, seconds: float) -> np.ndarray | None:
    length = max(int(seconds / HOP), NFIX + 1)
    count = len(frames) - length + 1
    if count <= 0:
        return None
    view = np.lib.stride_tricks.as_strided(
        frames, (count, length, frames.shape[1]),
        (frames.strides[0], frames.strides[0], frames.strides[1]))
    return normalize(resample(view, NFIX))


def best_scores(clip_frames: np.ndarray, vectors: np.ndarray,
                durations: list[float]) -> np.ndarray:
    """Per-word best cosine, each word searched at windows near its own length:
    a 0.4 s word buried in a 2 s window is 20% of the frame statistics."""
    best = np.full(vectors.shape[1], -1.0, np.float32)
    for i, seconds in enumerate(durations):
        for factor in (0.8, 1.0, 1.3, 1.7):
            cand = candidate_windows(clip_frames, max(seconds * factor, 0.3))
            if cand is not None:
                best[i] = max(best[i], float((cand @ vectors[:, i]).max()))
    return best


def auc(pos: list[float], neg: list[float]) -> float:
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def report(label: str, words: list[str], vectors: np.ndarray, durations: list[float],
           clips: list[tuple[np.ndarray, set[str]]], rng: np.random.Generator) -> list[float]:
    pos = {w: [] for w in words}
    neg = {w: [] for w in words}
    for frames, spoken in clips:
        got = best_scores(frames, vectors, durations)
        for i, word in enumerate(words):
            (pos if word in spoken else neg)[word].append(float(got[i]))
    print(f"\n{label}  ({len(clips)} clips)")
    print(f"{'word':8s} {'hits':>4s} {'misses':>6s} {'AUC':>6s} {'shuffled':>9s}")
    scored = []
    for word in words:
        p, n = pos[word], neg[word]
        if len(p) < 5 or len(n) < 5:
            print(f"{word:8s} {len(p):4d} {len(n):6d}    too few hits to score")
            continue
        shuffled = list(rng.permutation(np.array(p + n))[: len(p)])
        a = auc(p, n)
        scored.append(a)
        print(f"{word:8s} {len(p):4d} {len(n):6d} {a:6.3f} {auc(shuffled, n):9.3f}")
    if scored:
        print(f"mean AUC {float(np.mean(scored)):.3f} over {len(scored)} words "
              f"(0.5 = no signal, 1.0 = perfect separation)")
    else:
        print("nothing scored")
    return scored


def slices(text: str, word: str, limit: int) -> list[str]:
    tokens = text.split()
    out = []
    for j, token in enumerate(tokens):
        if token.strip("?.,!:;") == word and len(out) < limit:
            out.append(" ".join(tokens[max(0, j - 1): j + 2]))
    return out


def main() -> int:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="data/dagbani")
    ap.add_argument("--pack", default="assets/tts/dagbani_piper")
    ap.add_argument("--clips", type=int, default=400)
    ap.add_argument("--slices", type=int, default=10, help="synthetic positives per word")
    ap.add_argument("--neg-slices", type=int, default=30, help="shared synthetic negatives")
    ap.add_argument("--no-real", action="store_true")
    ap.add_argument("--words", default="dauda,mini,maa,nyɛ,ŋun")
    args = ap.parse_args()

    rows = [json.loads(line) for line in
            Path(args.corpus, "metadata.jsonl").read_text(encoding="utf8").splitlines()
            if line]
    vocab = set(json.loads((Path(args.pack) / "model.onnx.json")
                           .read_text(encoding="utf8"))
                ["character_frontend"]["vocabulary"])
    words = [w for w in args.words.split(",") if w and all(c in vocab for c in w)]

    raw = synthesize(Path(args.pack), words)
    words = [w for w in words if w in raw]
    vectors = np.stack([template_vector(raw[w]) for w in words], axis=1)
    durations = [len(trim(raw[w])) / SR for w in words]
    print("templates: "
          f"{len(words)} words spoken in isolation by our own TTS, "
          f"{[round(d, 2) for d in durations]}s of speech")

    rng = np.random.default_rng(7)
    control = report("CONTROL (our TTS vs our TTS: a working matcher must score ~1.0)",
                     words, vectors, durations,
                     synthetic_clips(rows, words, vocab, args, raw), rng)

    if not args.no_real:
        clips = []
        for row in rows[: args.clips]:
            samples, source_sr = sf.read(Path(args.corpus) / row["audio"])
            clip = mfcc(to_16k(np.asarray(samples, np.float32), source_sr))
            clips.append((clip, set(row["text"].lower().split())))
        real = report("REAL SPEECH (the task we would ship)", words, vectors, durations,
                      clips, rng)
        if real and control:
            print(f"\nverdict: control {float(np.mean(control)):.3f} "
                  f"(matcher ceiling) vs real {float(np.mean(real)):.3f}")

    return 0


def synthetic_clips(rows, words, vocab, args, raw):
    """3-word slices spoken by the same TTS: positives contain the word."""
    texts: dict[str, set[str]] = {}
    for word in words:
        for row in rows:
            text = row["text"].lower()
            if f" {word} " not in f" {text} ":
                continue
            for piece in slices(text, word, args.slices):
                if piece not in raw and all(c in vocab for c in piece):
                    texts.setdefault(piece, set()).add(word)
            if len([t for t, s in texts.items() if word in s]) >= args.slices:
                break
    others = [r for r in rows
              if not any(f" {w} " in f" {r['text'].lower()} " for w in words)]
    picked = random.Random(11).sample(others, min(args.neg_slices, len(others)))
    for row in picked:
        tokens = row["text"].lower().split()
        piece = " ".join(tokens[:3])
        if piece and piece not in raw and piece not in texts and all(c in vocab for c in piece):
            texts[piece] = set()
    said = synthesize(Path(args.pack), [t for t in texts if t not in raw])
    clips = []
    for piece, spoken_words in texts.items():
        audio = raw[piece] if piece in raw else said.get(piece)
        if audio is None:
            continue
        clips.append((mfcc(audio), spoken_words))
    return clips


if __name__ == "__main__":
    sys.exit(main())
