"""Throwaway - measurement only, not shippable code.

Scoring primitives for the ASR bake-off.

NORMALISATION RULE (applied identically to gold and hypothesis):
  1. Unicode NFC compose
  2. casefold() lowercase
  3. drop every character whose unicode category starts with P (punct) or
     S (symbol) - this removes ' " - , . ? ! and the | separators
  4. collapse runs of whitespace to one space, strip
  Ghanaian letters (U+025B, U+0254, U+014B, U+025D) are category Ll and SURVIVE.
CER = char edit distance / gold chars, spaces removed.
WER = word edit distance / gold words.
"""
import json
import re
import unicodedata
from collections import Counter
from pathlib import Path

PUNCT = re.compile(r"\s+")


def norm(text: str) -> str:
    text = unicodedata.normalize("NFC", text or "")
    text = text.casefold()
    text = "".join(c for c in text if unicodedata.category(c)[0] not in ("P", "S"))
    return PUNCT.sub(" ", text).strip()


def edit_distance(a: list, b: list) -> int:
    if not a:
        return len(b)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def scores(gold: str, hyp: str) -> dict:
    g, h = norm(gold), norm(hyp)
    gc, hc = list(g.replace(" ", "")), list(h.replace(" ", ""))
    gw, hw = g.split(), h.split()
    ce, ch = edit_distance(gc, hc), max(len(gc), 1)
    we, wh = edit_distance(gw, hw), max(len(gw), 1)
    return {"cer": round(ce / ch, 4), "wer": round(we / wh, 4),
            "gold_words": len(gw), "hyp_words": len(hw),
            "norm_gold": g, "norm_hyp": h}


def target_hit(gold_norm: str, hyp_norm: str, target_norm: str) -> bool:
    """Does the closed-set answer survive in the hypothesis?"""
    return target_norm in hyp_norm.split()


def corpus_orthography(manifest_path: Path) -> dict:
    rows = [json.loads(l) for l in manifest_path.open(encoding="utf8")]
    inv = Counter()
    for r in rows:
        inv.update(r["text"])
    letters = "".join(sorted(c for c in inv if not c.isspace()))
    special = [c for c in letters if ord(c) > 127]
    nonascii_rows = sum(1 for r in rows if any(ord(c) > 127 for c in r["text"]))
    return {
        "n_rows": len(rows),
        "letters": letters,
        "letter_count": len(letters),
        "non_ascii_letters": special,
        "non_ascii_codepoints": [hex(ord(c)) for c in special],
        "rows_with_non_ascii": nonascii_rows,
        "rows_with_ee_open_o": sum(1 for r in rows if any(c in r["text"] for c in "\u025b\u0254\u014b\u025d")),
        "examples": [r["text"] for r in rows[:5]],
        "total_seconds": round(sum(r["duration"] for r in rows), 1),
        "sample_rates": sorted({r.get("sample_rate") for r in rows}),
        "duration_min": round(min(r["duration"] for r in rows), 2),
        "duration_max": round(max(r["duration"] for r in rows), 2),
        "duration_mean": round(sum(r["duration"] for r in rows) / max(len(rows), 1), 2),
    }


# self-check: known values
if __name__ == "__main__":
    # "Mi bɛ mi" without spaces is m-i-b-ɛ-m-i = 6 chars, one substitution -> 1/6
    assert scores("Ee", "ee")["cer"] == 0.0
    assert scores("Mi bɛ mi", "mi be mi")["cer"] == round(1 / 6, 4), scores("Mi bɛ mi", "mi be mi")
    assert scores("Ayi", "ee ayi")["wer"] == 1.0, scores("Ayi", "ee ayi")
    assert scores("Ayi ee", "ayee")["wer"] == 1.0
    assert norm("Mi bɛ mi!") == "mi bɛ mi"
    assert "ɛ" in norm("Bɛɛma"), "Ghanaian open-e must survive normalisation"
    print("scorer self-check ok")
