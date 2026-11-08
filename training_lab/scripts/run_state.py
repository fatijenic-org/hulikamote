"""
run_state.py — The state of a model's trainings, read from YOLO's own files. Shared by the
terminal Training Lab (lab_tui.py) and the backend's Training Studio endpoints.

  runs/<model>/<run>/results.csv   one row per finished epoch
  runs/<model>/<run>/args.yaml     the run's settings (planned epochs ...)
  runs/<model>/<run>/weights/last.pt   saved after every epoch; epoch = -1 once the run finished

"Pause" = stop the training process; "continue" = YOLO's resume from last.pt (it restarts the
epoch that was interrupted). Trainings are launched detached so nothing but Pause stops them.
"""
import csv
import os
import subprocess
from pathlib import Path

import psutil
import yaml

ROOT = Path(__file__).resolve().parent.parent      # training_lab/


def model_runs(model: str) -> list[Path]:
    """Run folders that finished at least one epoch, newest first."""
    runs = [p.parent for p in (ROOT / "runs" / model).glob("*/results.csv")]
    return sorted(runs, key=lambda p: (p / "results.csv").stat().st_mtime, reverse=True)


def read_run(run: Path) -> dict:
    """results.csv as {column: [values]} plus the run's settings."""
    cols: dict[str, list[float]] = {}
    with open(run / "results.csv", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            for k, v in row.items():
                try:
                    cols.setdefault(k.strip(), []).append(float(v))
                except (TypeError, ValueError):
                    pass
    args = yaml.safe_load((run / "args.yaml").read_text(encoding="utf-8")) if (run / "args.yaml").exists() else {}
    return {"cols": cols, "epochs": int(args.get("epochs", 0) or 0), "imgsz": args.get("imgsz"),
            "base": Path(str(args.get("model", "?"))).name}


_FINISHED_CACHE: dict[tuple, bool] = {}


def run_finished(run: Path) -> bool:
    """YOLO marks a completed run by saving last.pt with epoch -1 (cached per file version)."""
    last = run / "weights" / "last.pt"
    if not last.exists():
        return False
    key = (str(last), last.stat().st_mtime)
    if key not in _FINISHED_CACHE:
        import torch
        epoch = torch.load(last, map_location="cpu", weights_only=False).get("epoch", -1)
        _FINISHED_CACHE[key] = epoch is None or epoch < 0
    return _FINISHED_CACHE[key]


def resumable(run: Path | None) -> tuple[bool, str]:
    if run is None or not (run / "weights" / "last.pt").exists():
        return False, "No interrupted run to resume."
    if run_finished(run):
        return False, f"Run '{run.name}' already finished — use Start new."
    data = read_run(run)
    return True, f"Resume '{run.name}' from epoch {len(data['cols'].get('epoch', []))} of {data['epochs']}."


def training_processes(model: str) -> list[psutil.Process]:
    """Running trainings of this model, whoever started them (on Windows a venv launcher + its child)."""
    found = []
    for p in psutil.process_iter(["cmdline"]):
        cmd = " ".join(p.info["cmdline"] or [])
        if ("train.py" in cmd and f"--model {model}" in cmd) or ("resume=True" in cmd and model in cmd):
            found.append(p)
    return found


def training_process(model: str) -> psutil.Process | None:
    procs = training_processes(model)
    return procs[0] if procs else None


def state(model: str) -> dict:
    """One-glance state for buttons: training now / paused (resumable) / idle."""
    procs = training_processes(model)
    runs = model_runs(model)
    run = runs[0] if runs else None
    data = read_run(run) if run else None
    done = len(data["cols"].get("epoch", [])) if data else 0
    total = data["epochs"] if data else 0
    can_resume, message = (False, "Training now.") if procs else resumable(run)
    return {"model": model, "training": bool(procs), "run": run.name if run else None,
            "epochs_done": done, "epochs_total": total, "resumable": can_resume, "message": message}


def pause(model: str) -> int:
    """Stop every running training of this model. Returns how many processes were stopped."""
    procs = training_processes(model)
    for p in procs:
        try:
            p.terminate()
        except psutil.NoSuchProcess:
            pass
    psutil.wait_procs(procs, timeout=10)
    return len(procs)


def resume_command(python: str, model: str) -> list[str]:
    run = model_runs(model)[0]
    last = run / "weights" / "last.pt"
    return [python, "-c", f"from ultralytics import YOLO; YOLO(r'{last}').train(resume=True)"]


def launch_detached(cmd: list[str], log_path: Path) -> subprocess.Popen:
    """Own background process: no console and its own process group, so closing a window, the
    dashboard or a backend restart never stops it. Output goes to log_path."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    flags = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP) if os.name == "nt" else 0
    with open(log_path, "w", encoding="utf-8") as out:
        return subprocess.Popen(cmd, cwd=ROOT, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                creationflags=flags, start_new_session=os.name != "nt",
                                env={**os.environ, "PYTHONUNBUFFERED": "1"})
