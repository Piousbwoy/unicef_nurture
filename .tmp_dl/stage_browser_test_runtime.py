"""Stage the installed Flutter runtime for its Windows test-server route bug."""
from pathlib import Path
import shutil

source = Path(r"C:\src\flutter\bin\cache\flutter_web_sdk\canvaskit")
target = Path(__file__).resolve().parents[1] / "test" / "canvaskit"
for variant in ("", "chromium"):
    for name in ("canvaskit.js", "canvaskit.wasm"):
        destination = target / variant / name
        if destination.exists():
            raise RuntimeError(f"Refusing to overwrite {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / variant / name, destination)
        print(f"Staged {destination}")
