"""Vendor pinned, data-only Twi frontend references; never execute upstream code."""
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
REVISION = "b19ca90ac07882b8cb87a349d85caf4aa984a20a"
BASE = f"https://raw.githubusercontent.com/GhanaNLP/stable-twi-tts/{REVISION}"
EXPECTED = {
    "mobile/twi_rules.json": "89da4682f0bb6730345da019890812ff6d2f5dea1c4f5a0d3660cb34e5236fcd",
    "mobile/test_vectors.json": "e26fac25b53da55aba204280439962a436eb052dae905cd789fa6606e434b0eb",
}
FILES = {
    "mobile/twi_rules.json": "assets/tts/twi_piper/twi_rules.json",
    "mobile/test_vectors.json": "test/fixtures/voice/twi_reference_vectors.json",
    "pyproject.toml": "assets/tts/twi_piper/frontend_project.toml",
}


def main():
    records = []
    for source, destination in FILES.items():
        url = f"{BASE}/{source}"
        with urlopen(Request(url, headers={"User-Agent": "CareBridge-model-tools"}), timeout=90) as response:
            data = response.read(2 * 1024 * 1024)
        if source.endswith(".json"):
            json.loads(data)
        digest = hashlib.sha256(data).hexdigest()
        if source in EXPECTED and digest != EXPECTED[source]:
            raise RuntimeError(f"Pinned artifact integrity mismatch: {source}")
        path = ROOT / destination
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"Refusing to overwrite a differing frontend artifact: {destination}")
        path.write_bytes(data)
        records.append({"source": url, "path": destination, "sha256": digest, "bytes": len(data)})
        print(f"Verified download: {destination} ({len(data)} bytes, sha256={digest})")
    provenance = {
        "repository": "https://github.com/GhanaNLP/stable-twi-tts",
        "revision": REVISION,
        "note": "Frontend reference data only. Model weights retain their separate noncommercial license. Rule data attributes Simon Ager/Omniglot in twi_rules.json.",
        "files": records,
    }
    (ROOT / "assets/tts/twi_piper/frontend_provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
