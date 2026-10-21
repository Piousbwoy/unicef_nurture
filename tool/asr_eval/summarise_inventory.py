"""Throwaway - measurement only, not shippable code. Summarise inventory JSON."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent / "out"
d = json.load((OUT / "inventory.json").open(encoding="utf8"))
lines = []
for k, v in d.items():
    lines.append("=== " + k)
    lines.append(f" exists={v.get('exists')} err={str(v.get('error'))[:120]}")
    lines.append(
        f" pipeline={v.get('pipeline_tag')} lib={v.get('library_name')} "
        f"licence_tag={v.get('licence_tag')} card={v.get('card_data_licences')} "
        f"downloads={v.get('downloads')}"
    )
    lines.append(
        f" total_bytes={v.get('total_bytes')} weight_bytes={v.get('weight_bytes')} "
        f"nfiles={v.get('n_files')} remote_py={v.get('has_remote_code')} "
        f"config.json={v.get('config_present')}"
    )
    lines.append(" shards=" + json.dumps(v.get("safetensors_shards")))
    lines.append(" config=" + json.dumps(v.get("config"), ensure_ascii=False))
    lines.append(" config_keys=" + json.dumps(v.get("config_extra_keys")))
    lines.append(" files=" + json.dumps([f["name"] for f in (v.get("files") or [])])[:900])
    lines.append(" big_files=" + json.dumps(
        [{"n": f["name"], "mb": round((f["size"] or 0) / 2**20, 1)}
         for f in (v.get("files") or []) if (f["size"] or 0) > 5 * 2**20][:12]))

lines.append("\n\n########## DATASETS ##########")
ds = json.load((OUT / "datasets.json").open(encoding="utf8"))
for k, v in ds.items():
    lines.append("=== " + k + f" ok={v.get('ok')} err={str(v.get('error'))[:150]}")
    files = v.get("files") or []
    lines.append(f" n_files={v.get('n_files')} first={json.dumps(files[:25])}")
    dag = [f for f in files if "dag" in f.lower()]
    aka = [f for f in files if "aka" in f.lower() or "akan" in f.lower() or "twi" in f.lower()]
    lines.append(f" dag_matches={len(dag)} sample={json.dumps(dag[:12])}")
    lines.append(f" aka_matches={len(aka)} sample={json.dumps(aka[:12])}")
    sizes = v.get("sizes") or {}
    top = sorted(sizes.items(), key=lambda kv: -(kv[1] or 0))[:20]
    lines.append(" largest=" + json.dumps(
        [{"n": n, "mb": round((s or 0) / 2**20, 1)} for n, s in top]))
    lines.append(" total_mb=" + str(round(sum(s or 0 for s in sizes.values()) / 2**20, 1)))

(OUT / "inventory.txt").write_text("\n".join(lines) + "\n", encoding="utf8")
print("wrote inventory.txt", len(lines), "lines")
