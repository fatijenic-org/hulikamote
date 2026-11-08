"""
model_catalog.py — Every ONNX model the app can use, grouped by job, with which one is active.

One model is active per type:
  vehicles  the detector run on every frame       -> models/active_model.txt (yolo_inference)
  helmet    rider with / without helmet            -> model_manifest.json "helmet_specialist"
  plate     finds the license plate                -> model_manifest.json "plate_specialist"
  cabin     windshield / seatbelt / phone / mirror -> model_manifest.json "cabin_specialist"
Models trained in training_lab are deployed by export_onnx.py as <key>_<run>_<YYYYMMDD>.onnx;
their scores are read back from training_lab/runs/<key>/<run>/results.csv.
"""
import csv
import json
import re
import time
from pathlib import Path

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
MANIFEST = MODELS_DIR / "model_manifest.json"
RUNS_DIR = MODELS_DIR.parent.parent / "training_lab" / "runs"

TYPES = {
    "vehicles": {"folder": "Vehicle Detectors", "key": "primary_anchor", "label": "Vehicle detector",
                 "job": "Finds cars, motorcycles, buses, trucks and people in every frame.",
                 "applies": "Used from the next analysis / live frame."},
    "helmet": {"folder": "Helmet Detectors", "key": "helmet_specialist", "label": "Helmet model",
               "job": "Decides rider with / without a helmet (No Helmet violation).",
               "applies": "Used from the next analysis."},
    "plate": {"folder": "Plate Models", "key": "plate_specialist", "label": "Plate model",
              "job": "Finds the license plate so it can be read (every ticket, No Plate violation).",
              "applies": "Default for new analyses (the analysis wizard can still pick another)."},
    "cabin": {"folder": "Cabin Models", "key": "cabin_specialist", "label": "Cabin model",
              "job": "Windshield, seatbelt, phone and side mirrors (No Seatbelt, Missing Mirror).",
              "applies": "Used from the next analysis."},
}
DEFAULT_FILES = {"helmet": "helmet_specialist.onnx", "plate": "plate_specialist.onnx",
                 "cabin": "cabin_specialist.onnx"}


def _manifest() -> dict:
    try:
        return json.loads(MANIFEST.read_text()).get("active_models", {})
    except Exception:
        return {}


def _write_manifest(active: dict) -> None:
    data = {}
    if MANIFEST.exists():
        try:
            data = json.loads(MANIFEST.read_text())
        except Exception:
            data = {}
    data["active_models"] = active
    MANIFEST.write_text(json.dumps(data, indent=4))


def training_source(model_file: str, key: str) -> dict | None:
    """Score of the training run a deployed file came from (None for imported / stock models)."""
    m = re.match(rf"{re.escape(key)}_(.+)_(\d{{8}})\.onnx$", model_file)
    if not m:
        return None
    run, day = m.group(1), m.group(2)
    info = {"run": run, "deployed": f"{day[:4]}-{day[4:6]}-{day[6:]}"}
    results = RUNS_DIR / key / run / "results.csv"
    if results.exists():
        with open(results, newline="", encoding="utf-8") as f:
            rows = [{k.strip(): v for k, v in r.items()} for r in csv.DictReader(f)]
        scores = [float(r.get("metrics/mAP50(B)", 0) or 0) for r in rows]
        if scores:
            best = max(range(len(scores)), key=lambda i: scores[i])
            info.update(best_score=round(scores[best], 3), best_epoch=best + 1, epochs=len(scores),
                        precision=round(float(rows[best].get("metrics/precision(B)", 0) or 0), 3),
                        recall=round(float(rows[best].get("metrics/recall(B)", 0) or 0), 3))
    return info


def active_model(kind: str) -> str | None:
    """File name of the active model of a type."""
    if kind == "vehicles":
        import yolo_inference
        return yolo_inference.MODEL_PATH.name
    chosen = _manifest().get(TYPES[kind]["key"])
    if chosen and (MODELS_DIR / chosen).exists():
        return Path(chosen).name
    default = DEFAULT_FILES.get(kind)
    return default if default and any(MODELS_DIR.rglob(default)) else None


def catalog() -> dict:
    out = []
    for kind, t in TYPES.items():
        folder = MODELS_DIR / t["folder"]
        files = sorted(folder.glob("*.onnx"), key=lambda p: p.stat().st_mtime, reverse=True) if folder.exists() else []
        out.append({
            "type": kind, "label": t["label"], "job": t["job"], "applies": t["applies"],
            "active": active_model(kind),
            "models": [{"name": p.name, "size_mb": round(p.stat().st_size / 1e6, 1),
                        "modified": time.strftime("%Y-%m-%d %H:%M", time.localtime(p.stat().st_mtime)),
                        "source": training_source(p.name, t["key"])} for p in files],
        })
    unsorted = sorted(p.name for p in MODELS_DIR.glob("*.onnx"))
    return {"types": out, "unsorted": unsorted}


def activate(kind: str, name: str) -> str:
    """Make `name` the active model of `kind`. Returns a plain-language confirmation."""
    if kind not in TYPES:
        raise ValueError(f"Unknown model type '{kind}'")
    t = TYPES[kind]
    path = MODELS_DIR / t["folder"] / name
    if not path.exists():
        raise FileNotFoundError(f"{name} is not in models/{t['folder']}/")
    active = _manifest()
    active[t["key"]] = f"{t['folder']}/{name}"
    _write_manifest(active)
    if kind == "vehicles":
        import yolo_inference
        yolo_inference.set_model_path(name)
    return f"{t['label']} is now {name}. {t['applies']}"
