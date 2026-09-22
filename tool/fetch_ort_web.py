"""Vendor the pinned MIT-licensed WASM runtime; never execute npm lifecycle scripts."""
import base64
import hashlib
import io
import json
import tarfile
from pathlib import Path
from urllib.request import urlopen

VERSION = "1.20.1"
URL = f"https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-{VERSION}.tgz"
INTEGRITY = "TePF6XVpLL1rWVMIl5Y9ACBQcyCNFThZON/jgElNd9Txb73CIEGlklhYR3UEr1cp5r0rbGI6nDwwrs79g7WjoA=="
NAMES = ["dist/ort.wasm.min.js", "dist/ort-wasm-simd-threaded.mjs",
         "dist/ort-wasm-simd-threaded.wasm", "package.json"]
SOURCE_REVISION = "5c1b7ccbff7e5141c1da7a9d963d660e5741c319"


def main():
    with urlopen(URL, timeout=180) as response:
        archive = response.read()
    if base64.b64encode(hashlib.sha512(archive).digest()).decode() != INTEGRITY:
        raise ValueError("Runtime archive integrity mismatch")
    output = Path(__file__).resolve().parents[1] / "web" / "voice_runtime"
    output.mkdir(parents=True, exist_ok=True)
    records = []
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
        for name in NAMES:
            member = package.getmember(f"package/{name}")
            if not member.isfile():
                raise ValueError("Unexpected runtime archive entry")
            data = package.extractfile(member).read()
            path = output / Path(name).name
            if path.exists() and path.read_bytes() != data:
                raise ValueError(f"Refusing to replace changed artifact: {path}")
            path.write_bytes(data)
            records.append({"name": path.name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    for name in ["LICENSE", "ThirdPartyNotices.txt"]:
        url = f"https://raw.githubusercontent.com/microsoft/onnxruntime/{SOURCE_REVISION}/{name}"
        with urlopen(url, timeout=90) as response:
            data = response.read()
        (output / name).write_bytes(data)
        records.append({"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    (output / "runtime_manifest.json").write_text(json.dumps({"version": VERSION, "source_revision": SOURCE_REVISION,
        "source": URL, "integrity": f"sha512-{INTEGRITY}", "license": "MIT", "files": records}, indent=2) + "\n", encoding="utf-8")
    print(f"Verified ONNX Runtime Web {VERSION}: {sum(r['bytes'] for r in records):,} bytes")


if __name__ == "__main__":
    main()
