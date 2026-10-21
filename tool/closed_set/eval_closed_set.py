"""Measure the closed set, then set the thresholds from it.

Voice input is only shippable once two numbers exist, and neither does yet:

  1. how often the listener hears `Ee` as `Ayi` — the clinical error rate;
  2. below which confidence it must stay silent instead — the refusal rate.

This tool computes both from recorded clips and prints the tradeoff that the
floors in `SpeechConfidence` have to come from. It cannot invent the clips:
run `--template` to get the recording manifest, hand it to a Dagbani and a Twi
speaker, then point `--clips` at the folder that comes back.

  python tool/closed_set/eval_closed_set.py --template out/record.csv
  python tool/closed_set/eval_closed_set.py --clips out/wavs --repo <model> --language dagbani
  python tool/closed_set/eval_closed_set.py --selftest

`--selftest` needs no model and no recordings: it checks the sweep arithmetic
against an injected error rate, because a tool that reports a clinical error rate
has to be shown to compute one before anyone quotes its output.
"""
import argparse
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np

NEG = -1e30


def logsumexp(values):
    values = np.asarray(list(values), dtype=np.float64)
    top = float(values.max())
    if not np.isfinite(top):
        return top
    return top + math.log(float(np.exp(values - top).sum()))


def ctc_log_likelihood(log_probs, labels):
    """Exact CTC forward probability of one fixed transcription, in log space.

    States alternate blank, label, blank, so a repeated character must be
    separated by a blank frame — which is precisely what makes `Ee` two
    emissions and not one, and why a doubled letter is worth testing for.
    """
    frames, vocab = log_probs.shape
    if len(labels) == 0:
        return float(log_probs[:, 0].sum())
    states = 2 * len(labels) + 1
    alpha = np.full(states, NEG)
    alpha[0] = 0.0
    for t in range(frames):
        nxt = np.full(states, NEG)
        for s in range(states):
            symbol = 0 if s % 2 == 0 else labels[s // 2]
            emit = float(log_probs[t, symbol])
            best = max(alpha[s], alpha[s - 1] if s > 0 else NEG)
            nxt[s] = emit + best if best > NEG / 2 else NEG
        alpha = nxt
    return float(max(alpha[states - 1], alpha[states - 2]))


def score_clip(log_probs, answer_forms, index, inverse, blank=0):
    """Best answer and its log-likelihood, marginalising spoken-form variants."""
    scores = {}
    for answer, forms in answer_forms.items():
        values = []
        for form in forms:
            ids = [index.get(ch) for ch in form.lower().replace(" ", "")]
            if any(i is None for i in ids):
                continue  # this pack cannot spell the form
            values.append(ctc_log_likelihood(log_probs, ids))
        if values:
            scores[answer] = logsumexp(values)
    if not scores:
        return None, None, ""
    ordered = sorted(scores.items(), key=lambda kv: -kv[1])
    greedy = []
    previous = None
    for row in log_probs:
        best = int(row.argmax())
        # Not `!= 0`: label 0 is a word separator in both of these inventories,
        # and the blank is the pack's own pad index.
        if best != blank and best != previous:
            greedy.append(inverse.get(best, ""))
        previous = best
    return ordered[0], (ordered[1][1] if len(ordered) > 1 else None), "".join(greedy)


def sweep(records, posterior_floors, per_frame_floors):
    """What the app would have done at each pair of thresholds."""
    rows = []
    for floor in posterior_floors:
        for absolute in per_frame_floors:
            accepted = correct = wrong = refused = none = 0
            for best, runner, per_frame, truth, heard in records:
                if best is None:
                    none += 1
                    continue
                margin = (
                    1.0 / (1.0 + math.exp(-(best - runner))) if runner is not None else 1.0
                )
                if margin < floor or per_frame < absolute:
                    refused += 1
                    continue
                accepted += 1
                if heard == truth:
                    correct += 1
                else:
                    wrong += 1
            total = accepted + refused + none
            rows.append(
                {
                    "posterior_floor": floor,
                    "per_frame_floor": absolute,
                    "accepted": accepted,
                    "correct": correct,
                    "wrong": wrong,
                    "refused": refused,
                    "no_speech": none,
                    "accept_rate": round(accepted / total, 4) if total else 0.0,
                    "refusal_rate": round((refused + none) / total, 4) if total else 0.0,
                    "errors_per_100_accepted": (
                        round(100 * wrong / accepted, 2) if accepted else None
                    ),
                }
            )
    return rows


def print_table(rows):
    print(
        f"{'post':>6} {'perFr':>7} {'acc':>4} {'ok':>4} {'bad':>4} {'rej':>4}"
        f" {'none':>5} {'err/100':>9} {'refuse':>7}"
    )
    for r in rows:
        print(
            f"{r['posterior_floor']:6.2f} {r['per_frame_floor']:7.2f}"
            f" {r['accepted']:4d} {r['correct']:4d} {r['wrong']:4d} {r['refused']:4d}"
            f" {r['no_speech']:5d} {str(r['errors_per_100_accepted']):>9}"
            f" {100 * r['refusal_rate']:6.1f}%"
        )


def measure_with_model(clips_dir, answers_path, language, repo):
    """Run a real CTC pack over the recorded folder. Requires the weights."""
    import torch
    from transformers import AutoModelForCTC, AutoProcessor

    answers = json.loads(Path(answers_path).read_text(encoding="utf8"))[language]
    model = AutoModelForCTC.from_pretrained(repo).to("cpu").eval()
    processor = AutoProcessor.from_pretrained(repo)
    feature_extractor = processor.feature_extractor if hasattr(processor, "feature_extractor") else processor
    tokenizer = processor.tokenizer if hasattr(processor, "tokenizer") else None
    index = {}
    if tokenizer is not None:
        for token, ids in tokenizer.get_vocab().items():
            index.setdefault(token, ids)
        if not index:
            index = {t: i for i, t in enumerate(tokenizer.all_special_tokens)}
    inverse = {v: k for k, v in index.items()}
    # The CTC blank is the model's pad token, and the two repos disagree about
    # where it lives. Guessing 0 would score every candidate against the word
    # separator and make the whole measurement meaningless.
    blank = None
    for source in (
        getattr(model.config, "pad_token_id", None),
        getattr(model.config, "blank_padding_id", None),
        getattr(tokenizer, "pad_token_id", None),
    ):
        if source is not None:
            blank = int(source)
            break
    if blank is None:
        raise SystemExit("no pad token on this model: the CTC blank would be a guess")
    print(f"blank label {blank} = {inverse.get(blank)}", file=sys.stderr)

    manifest = Path(clips_dir, "manifest.csv")
    if not manifest.exists():
        print(f"{manifest} missing: the folder needs a manifest.csv of file,answer,speaker", file=sys.stderr)
        return 1

    records = []
    per_clip = []
    with manifest.open(encoding="utf8") as handle:
        for row in csv.DictReader(handle):
            samples, _ = __import__("soundfile").read(Path(clips_dir, row["file"]))
            import soundfile as sf  # noqa: F401  (read above needs the module loaded)

            encoded = feature_extractor(
                np.asarray(samples, dtype=np.float32),
                sampling_rate=answers["sampling_rate"],
                return_tensors="pt",
                padding=False,
            )
            with torch.no_grad():
                logits = model(**dict(encoded)).logits[0]
            log_probs = torch.log_softmax(logits.float(), dim=-1).cpu().numpy()
            best, runner, greedy = score_clip(
                log_probs, answers["answers_by_id"], index, inverse, blank
            )
            # `best` is (answer, log-likelihood); the sweep wants the number, and
            # the absolute score is per frame, not per clip.
            loglike = best[1] if best else None
            per_frame = loglike / len(log_probs) if loglike is not None else None
            records.append(
                (loglike, runner, per_frame, row["answer"], best[0] if best else None)
            )
            per_clip.append(
                {
                    "file": row["file"],
                    "truth": row["answer"],
                    "heard": best[0] if best else None,
                    "margin": (
                        round(1.0 / (1.0 + math.exp(-(loglike - runner))), 4)
                        if best and runner is not None
                        else 1.0
                    ),
                    "per_frame": round(per_frame, 4) if per_frame is not None else None,
                    "greedy": greedy,
                }
            )

    Path(clips_dir, "per_clip.json").write_text(json.dumps(per_clip, indent=1), encoding="utf8")
    rows = sweep(
        records,
        [0.85, 0.9, 0.95, 0.99],
        [-3.0, -2.0, -1.5, -1.0, -0.5, 0.0],
    )
    print_table(rows)
    Path(clips_dir, "operating_points.json").write_text(json.dumps(rows, indent=1), encoding="utf8")
    print(f"\n{len(records)} clips. Pick a row: errors_per_100_accepted is the clinical")
    print("error rate you are prepared to publish, refusal_rate what that costs the user.")
    return 0


def selftest():
    rng = np.random.default_rng(5)

    # 1. The sweep must recover an accuracy rate that was injected on purpose.
    # A correct hearing is given a wide margin over the runner-up and a wrong
    # one a narrow margin, which is how a real recogniser fails: it is most
    # wrong when it is least sure, and that is what a floor can exploit.
    truth_rate = 0.85
    records = []
    for _ in range(2000):
        truth = "yes" if rng.random() < 0.5 else "no"
        heard = truth if rng.random() < truth_rate else ("no" if truth == "yes" else "yes")
        best = -1.0 - rng.random()
        margin = (3.0 + 3.0 * rng.random()) if heard == truth else (0.2 + 0.3 * rng.random())
        records.append((best, best - margin, best / 6.0, truth, heard))
    rows = sweep(records, [0.50], [NEG])
    measured = rows[0]["correct"] / rows[0]["accepted"]
    print(f"injected accuracy {truth_rate:.3f} -> measured {measured:.3f}")
    assert abs(measured - truth_rate) < 0.02, (truth_rate, measured)

    # 2. Raising the confidence floor may only refuse more, never fewer.
    loose = sweep(records, [0.50], [NEG])[0]
    tight = sweep(records, [0.95], [NEG])[0]
    print(f"floor 0.50 -> accept {loose['accepted']}, refuse {100 * loose['refusal_rate']:.1f}%")
    print(f"floor 0.95 -> accept {tight['accepted']}, refuse {100 * tight['refusal_rate']:.1f}%")
    assert tight["refusal_rate"] >= loose["refusal_rate"]
    assert tight["accepted"] <= loose["accepted"]
    # A floor is only worth having if trading refusals for accuracy actually works.
    loose_accuracy = loose["correct"] / loose["accepted"]
    tight_accuracy = tight["correct"] / tight["accepted"]
    assert tight_accuracy > loose_accuracy, (loose_accuracy, tight_accuracy)

    # 3. A frame sequence that separates a doubled letter by a blank must beat
    #    one that does not, or the closed set will mis-score `Ee`.
    separated = np.log([[0.02, 0.97, 0.01], [0.98, 0.01, 0.01], [0.02, 0.97, 0.01], [0.98, 0.01, 0.01]])
    adjacent = np.log([[0.02, 0.97, 0.01], [0.02, 0.97, 0.01], [0.98, 0.01, 0.01], [0.98, 0.01, 0.01]])
    separated_score = ctc_log_likelihood(separated, [1, 1])
    adjacent_score = ctc_log_likelihood(adjacent, [1, 1])
    print(f"blank-separated {separated_score:.2f} vs adjacent {adjacent_score:.2f}")
    assert separated_score > adjacent_score
    empty = ctc_log_likelihood(np.log([[0.5, 0.5], [0.5, 0.5]]), [])
    assert abs(empty - math.log(0.25)) < 1e-9, empty

    print("selftest OK")
    return 0


def write_template(path, answers_path, language, speakers):
    answers = json.loads(Path(answers_path).read_text(encoding="utf8"))[language]
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", newline="", encoding="utf8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["file", "answer", "speaker", "note"])
        for speaker in range(1, speakers + 1):
            for answer in answers["answers_by_id"]:
                writer.writerow(
                    [
                        f"sp{speaker:02d}_{answer}.wav",
                        answer,
                        f"sp{speaker:02d}",
                        "say it the way you would answer at a health post",
                    ]
                )
    print(f"wrote {out}: {speakers} speakers x {len(answers['answers_by_id'])} answers")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", help="write a recording manifest here and exit")
    ap.add_argument("--clips", help="folder of recorded clips with a manifest.csv")
    ap.add_argument("--answers", default=str(Path(__file__).with_name("answers.json")))
    ap.add_argument("--language", default="dagbani", choices=["dagbani", "twi"])
    ap.add_argument("--repo", help="HF id or local snapshot of a CTC model")
    ap.add_argument("--speakers", type=int, default=10)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.template:
        return write_template(args.template, args.answers, args.language, args.speakers)
    if args.clips:
        if not args.repo:
            print("--clips needs --repo (the model to measure)", file=sys.stderr)
            return 1
        return measure_with_model(args.clips, args.answers, args.language, args.repo)
    print("nothing to do: pass --template, --clips with --repo, or --selftest", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
