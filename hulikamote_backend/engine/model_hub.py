"""
model_hub.py - One list per job: the model that is live and every version we have, with its numbers.

A version is
  a training run         training_lab/runs/<key>/train*   (scores read from results.csv, per-type scores from per_class.json)
  a model file           models/<folder>/*.onnx           (came with the app, was imported, or a run that was exported)
  a car-matcher file     ckpt.t7, ckpt_original.t7, ckpt_backup_*.t7 and training_lab/runs/reid/train_*/ckpt.t7
Training only ADDS a version. use() makes one of them live: a run that was never exported is exported to ONNX first
(training_lab/scripts/export_onnx.py), then it is activated like any other model (engine/model_catalog.py).
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from engine import model_catalog

LAB = model_catalog.RUNS_DIR.parent                       # training_lab/
CKPT_DIR = Path(__file__).resolve().parent / "deep_sort" / "deep" / "checkpoint"

JOBS = {
    "vehicles": {"label": "Vehicles", "kind": "yolo", "key": "primary_anchor"},
    "plate": {"label": "Plates", "kind": "yolo", "key": "plate_specialist"},
    "helmet": {"label": "Helmets", "kind": "yolo", "key": "helmet_specialist"},
    "cabin": {"label": "Cabin", "kind": "yolo", "key": "cabin_specialist"},
    "reader": {"label": "Plate reader", "kind": "ocr", "key": "plate_ocr",
               "purpose": "Reads the characters on a plate crop."},
    "matcher": {"label": "Car matching", "kind": "reid", "key": "reid",
                "purpose": "Tells whether two photos are the same car, so one car keeps one number."},
    "enhancer": {"label": "Plate enhancer", "kind": "enhancer", "key": "plate_enhancer",
                 "purpose": "Sharpens blurry plate crops before they are read."},
}
YOLO_STATS = [("score", "Score", "How often it gets it right"),
              ("trust", "Trust", "When it points at something, it is right"),
              ("coverage", "Coverage", "Share of the real ones it finds")]
REID_STATS = [("score", "Right car found", "Finds the same car again, on cars it never saw"),
              ("ranking", "Ranking", "How well it puts the right car first"),
              ("cars", "Cars tested", "Cars it was checked on")]
RUN_RE = re.compile(r"^train-?(\d*)$")
_CHECKS: dict = {}            # (key, run) -> "running" | "failed: why"
_DIGESTS: dict = {}           # (path, mtime_ns, size) -> sha1


# ---------------------------------------------------------------------------------------------------------- helpers
def _read_results(csv_path: Path) -> dict | None:
    """Best epoch of an Ultralytics results.csv (by mAP50) with its precision / recall, and how many epochs ran."""
    import csv
    try:
        with open(csv_path, newline="", encoding="utf-8") as f:
            rows = [{k.strip(): v for k, v in r.items()} for r in csv.DictReader(f)]
    except OSError:
        return None
    scores = [float(r.get("metrics/mAP50(B)", 0) or 0) for r in rows]
    if not scores:
        return None
    best = max(range(len(scores)), key=lambda i: scores[i])
    num = lambda r, k: round(float(r.get(k, 0) or 0), 3)
    return {"score": round(scores[best], 3), "trust": num(rows[best], "metrics/precision(B)"),
            "coverage": num(rows[best], "metrics/recall(B)"), "best_epoch": best + 1, "epochs_done": len(scores)}


def _run_settings(run_dir: Path) -> dict:
    try:
        text = (run_dir / "args.yaml").read_text(encoding="utf-8")
    except OSError:
        return {}
    out = {}
    for key in ("epochs", "imgsz", "batch"):
        m = re.search(rf"^{key}:\s*(\d+)", text, re.M)
        if m:
            out[key] = int(m.group(1))
    return out


def _per_class(run_dir: Path) -> dict | None:
    try:
        return json.loads((run_dir / "per_class.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _digest(path: Path) -> str:
    st = path.stat()
    key = (str(path), st.st_mtime_ns, st.st_size)
    if key not in _DIGESTS:
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        _DIGESTS[key] = h.hexdigest()
    return _DIGESTS[key]


def _mb(path: Path | None) -> float | None:
    return round(path.stat().st_size / 1e6, 1) if path and path.exists() else None


def _files_for_run(folder: Path, key: str, run: str) -> list[Path]:
    """Exported files of one run (key_run_YYYYMMDD.onnx), newest first."""
    pat = re.compile(rf"^{re.escape(key)}_{re.escape(run)}_(\d{{8}})\.onnx$")
    return sorted((p for p in folder.glob("*.onnx") if pat.match(p.name)), key=lambda p: p.name, reverse=True) if folder.exists() else []


def _version_name(run: str) -> str:
    m = RUN_RE.match(run)
    return f"Version {int(m.group(1) or 1)}" if m else run


def _job_head(job: str) -> dict:
    spec = JOBS[job]
    head = {"job": job, "key": spec["key"], "label": spec["label"], "kind": spec["kind"],
            "purpose": spec.get("purpose", ""), "applies": "", "stats": [], "score_format": "decimal",
            "can_switch": spec["kind"] in ("yolo", "reid")}
    if spec["kind"] == "yolo":
        t = model_catalog.TYPES[job]
        head.update(purpose=t["job"], applies=t["applies"], stats=[dict(key=k, label=a, hint=b) for k, a, b in YOLO_STATS])
    elif spec["kind"] == "reid":
        head.update(applies="Restart the backend to load it.", score_format="percent",
                    stats=[dict(key=k, label=a, hint=b) for k, a, b in REID_STATS])
    else:
        head["note"] = "Training here puts the new model to work by itself. Choosing between versions is not available for this job yet."
    return head


# ------------------------------------------------------------------------------------------------------ detector jobs
def _yolo_versions(job: str) -> list[dict]:
    t = model_catalog.TYPES[job]
    key, folder = t["key"], model_catalog.MODELS_DIR / t["folder"]
    live_file = model_catalog.active_model(job)
    out, claimed = [], set()
    runs_dir = model_catalog.RUNS_DIR / key
    for d in sorted(runs_dir.iterdir()) if runs_dir.exists() else []:
        if not (d.is_dir() and RUN_RE.match(d.name) and (d / "results.csv").exists()):
            continue
        stats = _read_results(d / "results.csv")
        if not stats:
            continue
        files = _files_for_run(folder, key, d.name)
        claimed.update(f.name for f in files)
        settings = _run_settings(d)
        best_pt = d / "weights" / "best.pt"
        out.append({
            "id": d.name, "kind": "run", "origin": "trained", "name": _version_name(d.name), "run": d.name,
            "when": (d / "results.csv").stat().st_mtime,
            "stats": {k: stats[k] for k in ("score", "trust", "coverage")},
            "best_epoch": stats["best_epoch"], "epochs_done": stats["epochs_done"], "epochs_planned": settings.get("epochs"),
            "settings": settings, "classes": _per_class(d), "size_mb": _mb(files[0]) if files else _mb(best_pt),
            "file": files[0].name if files else None, "live": bool(files) and files[0].name == live_file,
            "usable": bool(files) or best_pt.exists(), "checking": _CHECKS.get((key, d.name))})
    for p in sorted(folder.glob("*.onnx"), key=lambda p: p.stat().st_mtime, reverse=True) if folder.exists() else []:
        if p.name in claimed:
            continue
        out.append({
            "id": p.name, "kind": "file", "origin": "stock", "name": p.stem, "run": None, "when": p.stat().st_mtime,
            "stats": {}, "settings": {}, "classes": None, "size_mb": _mb(p), "file": p.name, "live": p.name == live_file,
            "usable": True, "checking": None})
    out.sort(key=lambda v: v["when"], reverse=True)
    return out


def _use_yolo(job: str, version_id: str) -> str:
    version = next((v for v in _yolo_versions(job) if v["id"] == version_id), None)
    if version is None or not version["usable"]:
        raise FileNotFoundError(f"{version_id} is not a version of {JOBS[job]['label']} that can be used.")
    name = version["file"]
    if name is None:                                       # a run nobody exported yet
        key, folder = JOBS[job]["key"], model_catalog.MODELS_DIR / model_catalog.TYPES[job]["folder"]
        done = subprocess.run([sys.executable, str(LAB / "scripts" / "export_onnx.py"), "--model", key, "--run", version["run"]],
                              capture_output=True, text=True, timeout=900, cwd=str(LAB))
        files = _files_for_run(folder, key, version["run"])
        if done.returncode != 0 or not files:
            tail = (done.stderr or done.stdout or "").strip().splitlines()[-3:]
            raise RuntimeError("Could not prepare this version: " + " ".join(tail))
        name = files[0].name
    return model_catalog.activate(job, name)


# ------------------------------------------------------------------------------------------------------- per-type check
def start_check(job: str, run: str) -> str:
    """Score a finished run on its test photos, per type (training_lab/scripts/check_per_class.py). Runs in the background."""
    if job not in JOBS or JOBS[job]["kind"] != "yolo":
        raise ValueError("Per-type scores exist for the detector jobs only.")
    key = JOBS[job]["key"]
    if not (model_catalog.RUNS_DIR / key / run / "weights" / "best.pt").exists():
        raise FileNotFoundError(f"{run} has no saved weights to check.")
    if _CHECKS.get((key, run)) == "running":
        return "running"
    _CHECKS[(key, run)] = "running"

    def work():
        try:
            done = subprocess.run([sys.executable, str(LAB / "scripts" / "check_per_class.py"), "--model", key, "--run", run],
                                  capture_output=True, text=True, timeout=1800, cwd=str(LAB))
            if done.returncode == 0:
                _CHECKS.pop((key, run), None)
            else:
                _CHECKS[(key, run)] = "failed: " + " ".join((done.stderr or done.stdout or "").strip().splitlines()[-2:])
        except Exception as e:                              # a check that cannot run must not stay "running" forever
            _CHECKS[(key, run)] = f"failed: {e}"

    threading.Thread(target=work, daemon=True).start()
    return "running"


# --------------------------------------------------------------------------------------------------------- car matcher
def _matcher_versions() -> list[dict]:
    live_path = CKPT_DIR / "ckpt.t7"
    live_sum = _digest(live_path) if live_path.exists() else None
    cands = []                                              # (digest, version)
    reid_runs = model_catalog.RUNS_DIR / "reid"
    for d in sorted(reid_runs.glob("train_*")) if reid_runs.exists() else []:
        ck = d / "ckpt.t7"
        if not ck.exists():
            continue
        try:
            m = json.loads((d / "metrics.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            m = {}
        stats = {"cars": m.get("held_out_cars") or m.get("cars")}
        if m.get("after") is not None:
            stats.update(score=m["after"], before=m.get("before"), ranking=m.get("after_map"), before_ranking=m.get("before_map"))
        cands.append((_digest(ck), {
            "id": d.name, "kind": "run", "origin": "trained", "run": d.name, "when": ck.stat().st_mtime, "stats": stats,
            "settings": {}, "classes": None, "size_mb": _mb(ck), "path": ck, "usable": True, "checking": None,
            "passed": m.get("passed", m.get("deployed")), "note": m.get("note")}))
    files = [(CKPT_DIR / "ckpt_original.t7", "stock", "Stock")]
    files += [(p, "backup", "Earlier file") for p in sorted(CKPT_DIR.glob("ckpt_backup_*.t7"))]
    files.append((live_path, "stock", "Stock"))             # only kept when it is not any of the above
    for p, origin, label in files:
        if not p.exists():
            continue
        s = _digest(p)
        if any(s == c[0] for c in cands):
            continue
        cands.append((s, {"id": p.stem, "kind": "file", "origin": origin, "run": None, "when": p.stat().st_mtime, "stats": {},
                          "settings": {}, "classes": None, "size_mb": _mb(p), "path": p, "usable": True, "checking": None,
                          "label": label}))
    out = []
    for s, v in cands:
        v["live"] = s == live_sum
        v["name"] = v.get("label") or _version_name("train")
        out.append(v)
    runs = sorted((v for v in out if v["kind"] == "run"), key=lambda v: v["when"])
    for i, v in enumerate(runs, 1):
        v["name"] = f"Version {i}"
    for v in out:
        if v["kind"] == "file" and v["origin"] == "backup":
            v["name"] = "Earlier file"
    out.sort(key=lambda v: v["when"], reverse=True)
    return out


def _use_matcher(version_id: str) -> str:
    version = next((v for v in _matcher_versions() if v["id"] == version_id), None)
    if version is None:
        raise FileNotFoundError(f"{version_id} is not a car-matching version.")
    live = CKPT_DIR / "ckpt.t7"
    if version["live"]:
        return "That version is already live."
    if live.exists():
        if not (CKPT_DIR / "ckpt_original.t7").exists():
            shutil.copy2(live, CKPT_DIR / "ckpt_original.t7")
        elif not any(v["path"] != live and _digest(v["path"]) == _digest(live) for v in _matcher_versions()):
            shutil.copy2(live, CKPT_DIR / f"ckpt_backup_{int(time.time())}.t7")
    shutil.copy2(version["path"], live)
    return f"Car matching now uses {version['name']}. Restart the backend to load it."


# ---------------------------------------------------------------------------------------------------------- public
def hub() -> dict:
    jobs = []
    for job in JOBS:
        head = _job_head(job)
        kind = JOBS[job]["kind"]
        versions = _yolo_versions(job) if kind == "yolo" else _matcher_versions() if kind == "reid" else []
        for v in versions:
            v.pop("path", None)                              # server-side only
        head["versions"] = versions
        head["live_id"] = next((v["id"] for v in versions if v["live"]), None)
        jobs.append(head)
    return {"jobs": jobs}


def use(job: str, version_id: str) -> str:
    """Make one version the live one of its job. Returns a plain-language confirmation."""
    if job not in JOBS:
        raise ValueError(f"Unknown job '{job}'")
    kind = JOBS[job]["kind"]
    if kind == "yolo":
        return _use_yolo(job, version_id)
    if kind == "reid":
        return _use_matcher(version_id)
    raise ValueError("Choosing between versions is not available for this job yet.")
