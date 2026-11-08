"""
lab_core.py - What the Training Lab screens share, with no screen code in it: the model list, the dataset and run
readers, the training-log parser, GPU stats and a plain-language verdict. Used by lab_tui.py (full-screen app)
and lab.py (plain menu).
"""
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
from fetch_datasets import split_dirs, target_classes  # noqa: E402

CONFIG = yaml.safe_load((ROOT / "configs" / "training_config.yaml").read_text(encoding="utf-8"))
LOGS = ROOT / "runs" / "logs"
MANIFEST = ROOT.parent / "hulikamote_backend" / "models" / "model_manifest.json"
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

MODELS = {
    "helmet_specialist": ("Helmet", "riders with / without a helmet"),
    "plate_specialist": ("Plate", "the license plate on a vehicle"),
    "cabin_specialist": ("Cabin", "windshield, seatbelt, phone, mirrors"),
    "primary_anchor": ("Vehicles", "cars, motorcycles, buses, trucks, people, tricycles"),
}
# Overall score (mAP@50) wanted before deploying (from training_config.yaml notes)
TARGET = {"helmet_specialist": 0.85, "plate_specialist": 0.90, "cabin_specialist": 0.80, "primary_anchor": 0.80}


# ─── Reading YOLO's files (pure functions, no UI) ────────────────────────────

def dataset_stats(model: str) -> dict:
    """Images and objects per class for each split (counts the label files)."""
    names = [n for n, _ in sorted(target_classes(model).items(), key=lambda kv: kv[1])]
    splits = {}
    for split in ("train", "val", "test"):
        img_dir, lbl_dir = split_dirs(model, split)
        if not img_dir.exists():
            continue
        images = sum(1 for e in os.scandir(img_dir) if Path(e.name).suffix.lower() in IMAGE_EXT)
        per_class = [0] * len(names)
        if lbl_dir.exists():
            for e in os.scandir(lbl_dir):
                if e.name.endswith(".txt"):
                    with open(e.path, encoding="utf-8") as f:
                        for line in f:
                            parts = line.split()
                            if parts and parts[0].isdigit() and int(parts[0]) < len(names):
                                per_class[int(parts[0])] += 1
        splits[split] = {"images": images, "per_class": per_class}
    return {"classes": names, "splits": splits}


def deployed_run(model: str) -> str | None:
    """Run name of the model the backend loads (export_onnx.py names files <model>_<run>_<date>.onnx)."""
    try:
        import json
        path = json.loads(MANIFEST.read_text()).get("active_models", {}).get(model, "")
        m = re.search(rf"{model}_(.+)_\d{{8}}\.onnx$", path)
        return m.group(1) if m else None
    except Exception:
        return None


# One per-batch progress line of YOLO, e.g.
#   20/100  1.99G  1.106  1.722  1.098  29  640: 98% ━━━ 299/305 1.8it/s 3:06<3.4s
_BATCH = re.compile(r"(\d+)/(\d+)\s+([\d.]+)G\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\d+):\s+(\d+)%.*?"
                    r"(\d+)/(\d+)(?:\s+([\d.]+)(it/s|s/it))?(?:\s+([\d:.]+s?)(?:<([\d:.]+s?))?)?")
_VAL = re.compile(r"^\s*all\s+(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)")


def parse_log(text: str) -> dict:
    """Latest epoch's batch progress, its per-batch losses, and the last validation line."""
    batches, val = [], None
    for raw in text.replace("\r", "\n").split("\n"):
        line = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", raw)
        m = _BATCH.search(line)
        if m:
            g = m.groups()
            batches.append({"epoch": int(g[0]), "epochs": int(g[1]), "gpu_gb": float(g[2]), "box": float(g[3]),
                            "cls": float(g[4]), "dfl": float(g[5]), "objects": int(g[6]), "batch": int(g[9]),
                            "batches": int(g[10]), "speed": f"{g[11]} {g[12]}" if g[11] else "",
                            "elapsed": g[13] or "", "left": g[14] or ""})
            continue
        v = _VAL.match(line)
        if v:
            val = {"precision": float(v.group(3)), "recall": float(v.group(4)), "map50": float(v.group(5))}
    if not batches:
        return {"current": None, "series": [], "val": val}
    cur = batches[-1]
    series = {}
    for b in batches:
        if b["epoch"] == cur["epoch"]:
            series[b["batch"]] = b          # the bar redraws each batch; keep one sample per batch
    return {"current": cur, "series": [series[k] for k in sorted(series)], "val": val}


def find_log(model: str, since: float) -> Path | None:
    """Newest log in runs/logs that belongs to this model and was written after `since`."""
    best = None
    for p in LOGS.glob("*.log"):
        mtime = p.stat().st_mtime
        if mtime < since or (best and mtime <= best.stat().st_mtime):
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            head = f.read(4000)
        if model in p.name or model in head:
            best = p
    return best


def tail(path: Path, size: int = 200_000) -> str:
    with open(path, "rb") as f:
        f.seek(max(0, path.stat().st_size - size))
        return f.read().decode("utf-8", errors="replace")


def trend(values: list[float], n: int = 5) -> float:
    """Slope over the last n points (per epoch); > 0 rising, < 0 falling."""
    v = values[-n:]
    if len(v) < 3:
        return 0.0
    xm, ym = (len(v) - 1) / 2, sum(v) / len(v)
    return sum((i - xm) * (y - ym) for i, y in enumerate(v)) / sum((i - xm) ** 2 for i in range(len(v)))


def verdict(model: str, cols: dict) -> list[str]:
    """Plain-language reading of a run."""
    m50 = cols.get("metrics/mAP50(B)", [])
    if not m50:
        return ["Waiting for the first epoch to finish..."]
    best, target = max(m50), TARGET[model]
    out = [f"[green]✓ Good enough to deploy[/] — best score {best:.2f}, target {target:.2f}." if best >= target
           else f"[yellow]… Not there yet[/] — best score {best:.2f}, target {target:.2f}."]
    if len(m50) >= 6 and abs(trend(m50, 6)) < 0.002:
        out.append("[cyan]≈ The score has flattened[/] — more epochs add little; early stop will end it soon.")
    tl, vl = cols.get("train/box_loss", []), cols.get("val/box_loss", [])
    if len(vl) >= 6 and trend(tl) < 0 and trend(vl) > 0.002:
        out.append("[red]! Overfitting[/] — better on training photos, worse on new ones. The best epoch is the one "
                   "saved, so it's safe, but more varied data would help.")
    p, r = cols.get("metrics/precision(B)", [0])[-1], cols.get("metrics/recall(B)", [0])[-1]
    if r < p - 0.15:
        out.append("[yellow]Misses more than it mistakes[/] — add harder examples (small, blurry, far away).")
    elif p < r - 0.15:
        out.append("[yellow]More false alarms than misses[/] — add photos of look-alikes that are NOT the object.")
    return out


def gpu_stats() -> dict | None:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu",
                              "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=3).stdout
        name, util, used, total, temp = [x.strip() for x in out.strip().splitlines()[0].split(",")]
        return {"name": name, "util": int(util), "used": int(used), "total": int(total), "temp": int(temp)}
    except Exception:
        return None


def bar(fraction: float, width: int = 16) -> str:
    filled = int(round(max(0.0, min(1.0, fraction)) * width))
    return "█" * filled + "░" * (width - filled)


def minutes(seconds: float) -> str:
    return f"{seconds / 3600:.1f} h" if seconds >= 3600 else f"{seconds / 60:.0f} min"
