import os
import sys
import uuid
import json
import zipfile
import subprocess
from pathlib import Path
from fastapi import APIRouter, UploadFile, File, Form, BackgroundTasks, HTTPException
from pydantic import BaseModel
import shutil
import csv
import time
import re

router = APIRouter(prefix="/api/train", tags=["Training Studio"])

# Paths
BACKEND_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = BACKEND_DIR.parent
TRAINING_LAB_DIR = REPO_ROOT / "training_lab"
DATASETS_DIR = TRAINING_LAB_DIR / "datasets"
SCRIPTS_DIR = TRAINING_LAB_DIR / "scripts"
LOGS_DIR = TRAINING_LAB_DIR / "runs" / "logs"

LOGS_DIR.mkdir(parents=True, exist_ok=True)

# In-memory status store
TRAINING_TASKS = {}

# Shared with the terminal Training Lab: what is training / paused, pause, continue
sys.path.insert(0, str(SCRIPTS_DIR))
import run_state  # noqa: E402

YOLO_MODELS = ("helmet_specialist", "plate_specialist", "cabin_specialist", "primary_anchor")


def _check_yolo_model(model: str) -> None:
    if model not in YOLO_MODELS:
        raise HTTPException(status_code=404, detail=f"Pause / continue works for {', '.join(YOLO_MODELS)}")


_STATE_CACHE: dict = {}
_STATE_TTL_S = 2.0


@router.get("/state/{model}")
def training_state(model: str):
    """Training now, paused (can continue), or idle — for any training of this model, however it was started.
    A plain `def` (worker thread) with a 2 s cache: the process scan behind it costs ~0.2 s on Windows."""
    _check_yolo_model(model)
    now = time.time()
    hit = _STATE_CACHE.get(model)
    if hit and now - hit[0] < _STATE_TTL_S:
        return hit[1]
    state = run_state.state(model)
    _STATE_CACHE[model] = (now, state)
    return state


@router.post("/pause/{model}")
async def pause_training(model: str):
    """Stop the training to free the GPU. The last finished epoch is kept; Continue resumes from it."""
    _check_yolo_model(model)
    for info in TRAINING_TASKS.values():
        if info.get("model") == model and info.get("status") in ("starting", "running"):
            info["paused"] = True          # the Studio pipeline then reports "paused", not "failed"
    stopped = run_state.pause(model)
    _STATE_CACHE.pop(model, None)
    if not stopped:
        raise HTTPException(status_code=409, detail="Nothing is training for this model.")
    return {"detail": "Paused. Press Continue to resume from the last finished epoch.", **run_state.state(model)}


@router.post("/resume/{model}")
async def resume_training(model: str):
    """Continue the newest interrupted run. Runs detached, so a backend restart cannot stop it."""
    _check_yolo_model(model)
    current = run_state.state(model)
    if current["training"]:
        raise HTTPException(status_code=409, detail="This model is already training.")
    if not current["resumable"]:
        raise HTTPException(status_code=409, detail=current["message"])
    task_id = str(uuid.uuid4())
    proc = run_state.launch_detached(run_state.resume_command(sys.executable, model), LOGS_DIR / f"{task_id}.log")
    TRAINING_TASKS[task_id] = {"status": "running", "model": model, "started": time.time(), "proc": proc,
                               "resumed": True}
    _STATE_CACHE.pop(model, None)
    return {"task_id": task_id, "status": "running", "detail": current["message"]}

@router.post("/upload")
async def upload_dataset(
    model_name: str = Form(...),
    file: UploadFile = File(...)
):
    """
    Receives a ZIP file containing YOLO format (images/ and labels/ dirs),
    extracts it to training_lab/datasets/{model_name}/.
    """
    if not file.filename.endswith('.zip'):
        raise HTTPException(status_code=400, detail="Only .zip files are supported")
        
    target_dir = DATASETS_DIR / model_name
    
    # Clean previous dataset if it exists
    if target_dir.exists():
        shutil.rmtree(target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    
    zip_path = target_dir / "uploaded_dataset.zip"
    
    # Save the uploaded ZIP
    with open(zip_path, "wb") as f:
        shutil.copyfileobj(file.file, f)
        
    # Extract the ZIP
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(target_dir)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to extract ZIP: {e}")
    finally:
        if zip_path.exists():
            os.remove(zip_path) # Clean up ZIP
            
    return {"status": "success", "message": f"Dataset for {model_name} extracted successfully."}


def _run_training_pipeline(task_id: str, config: dict):
    """Runs the pipeline, then writes the run to the persistent per-model history."""
    try:
        _run_training_pipeline_inner(task_id, config)
    finally:
        try:
            _record_history(task_id, config)
        except Exception as e:
            print(f"[Training] could not record history for {task_id}: {e}")


def _run_training_pipeline_inner(task_id: str, config: dict):
    task_type = config.get("task_type", "yolo")
    model = config.get("model_name")
    epochs = config.get("epochs", 100)
    imgsz = config.get("imgsz", 640)
    batch = config.get("batch", 8)
    auto_split = config.get("auto_split", True)
    
    log_file = LOGS_DIR / f"{task_id}.log"
    
    def log(msg):
        with open(log_file, "a") as f:
            f.write(msg + "\n")
            
    TRAINING_TASKS[task_id]["status"] = "running"
    
    try:
        if task_type == "ocr":
            engine = config.get("engine", "easyocr")
            log(f"--- [1/2] Training OCR ({engine}) (Epochs: {epochs}, Batch: {batch}) ---")
            train_cmd = [sys.executable, str(SCRIPTS_DIR / "train_ocr.py"), "--engine", engine, "--epochs", str(epochs), "--batch", str(batch)]
            subprocess.run(train_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
            log("OCR Training complete.\n")
            
            log(f"--- [2/2] Exporting and Deploying OCR weights ---")
            if engine == "easyocr":
                # EasyOCR outputs a .pth in the experiment dir
                weights_path = TRAINING_LAB_DIR / "runs" / "easyocr_finetune"
            else:
                weights_path = TRAINING_LAB_DIR / "runs" / "paddleocr_finetune" / "output" / "best_accuracy"
                
            export_cmd = [sys.executable, str(SCRIPTS_DIR / "export_ocr.py"), "--engine", engine, "--weights", str(weights_path)]
            subprocess.run(export_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
            log("Export complete! OCR Model deployed to backend.\n")
            
        elif task_type == "reid":
            log(f"--- [1/1] Training car-matching (ReID) model (Epochs: {epochs}, Batch: {batch}) ---")
            # No --deploy: training only adds a version. The Models page shows how it did and "Use this" switches to it.
            train_cmd = [sys.executable, str(SCRIPTS_DIR / "train_reid.py"), "--epochs", str(epochs), "--batch", str(batch)]
            subprocess.run(train_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
            log("ReID training finished. It is a new version on the Models page: it is NOT live until you press Use this.\n")

        elif task_type == "enhancer":
            log(f"--- [1/1] Training plate enhancer (Real-ESRGAN) (Epochs: {epochs}) ---")
            train_cmd = [sys.executable, str(SCRIPTS_DIR / "train_realesrgan.py"), "--epochs", str(epochs)]
            subprocess.run(train_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
            log("Enhancer training + ONNX export complete.\n")

        else:
            if auto_split:
                log(f"--- [1/2] Auto-Splitting Dataset for {model} ---")
                split_cmd = [sys.executable, str(SCRIPTS_DIR / "split_dataset.py"), "--model", model, "--ratio", "0.8"]
                subprocess.run(split_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
                log("Dataset split complete.\n")
                
            log(f"--- [2/2] Training {model} (Epochs: {epochs}, Imgsz: {imgsz}) ---")
            train_cmd = [sys.executable, str(SCRIPTS_DIR / "train.py"), "--model", model, "--epochs", str(epochs), "--imgsz", str(imgsz)]
            subprocess.run(train_cmd, stdout=open(log_file, "a"), stderr=subprocess.STDOUT, check=True)
            # Training only adds a version. The Models page shows its scores, and "Use this" exports it and switches to it,
            # so a weak run can no longer replace the live model by itself.
            log("Training complete. It is a new version on the Models page: it is NOT live until you press Use this.\n")
            
        TRAINING_TASKS[task_id]["status"] = "completed"
        
    except subprocess.CalledProcessError as e:
        if TRAINING_TASKS[task_id].get("paused"):
            log("\n[PAUSED] Training stopped on request. Press Continue to resume from the last finished epoch.")
            TRAINING_TASKS[task_id]["status"] = "paused"
            return
        log(f"\n[ERROR] Pipeline failed during execution. Exit code: {e.returncode}")
        TRAINING_TASKS[task_id]["status"] = "failed"
    except Exception as e:
        log(f"\n[ERROR] Unexpected pipeline failure: {str(e)}")
        TRAINING_TASKS[task_id]["status"] = "failed"


@router.post("/open-lab")
async def open_training_lab(model: str | None = None, ui: str = "menu"):
    """
    Open the terminal Training Lab in its own console window: the plain menu (training_lab/lab.py), or the
    full-screen app with ui=tui (training_lab/lab_tui.py). `model` opens the menu straight on that model.
    It is fully detached: closing the dashboard, or a backend restart, does not touch it,
    and trainings it starts run in their own process outside the backend.
    """
    if model is not None and model not in YOLO_MODELS:
        raise HTTPException(status_code=400, detail=f"Unknown model '{model}'. Choose one of: {', '.join(YOLO_MODELS)}")
    script = TRAINING_LAB_DIR / ("lab_tui.py" if ui == "tui" else "lab.py")
    if not script.exists():
        raise HTTPException(status_code=404, detail=f"training_lab/{script.name} not found")
    cmd = [sys.executable, str(script)] + (["--model", model] if model and ui != "tui" else [])
    flags = (subprocess.CREATE_NEW_CONSOLE | subprocess.CREATE_NEW_PROCESS_GROUP) if os.name == "nt" else 0
    proc = subprocess.Popen(cmd, cwd=REPO_ROOT, creationflags=flags, start_new_session=os.name != "nt", close_fds=True)
    return {"status": "opened", "pid": proc.pid}


@router.post("/start")
async def start_training(
    background_tasks: BackgroundTasks,
    config_json: str = Form(...)
):
    config = json.loads(config_json)
    if config.get("model_name") in YOLO_MODELS and run_state.training_processes(config["model_name"]):
        raise HTTPException(status_code=409, detail="This model is already training (Pause it first).")
    task_id = str(uuid.uuid4())
    
    # Initialize task state and log file
    TRAINING_TASKS[task_id] = {"status": "starting", "model": config.get("model_name"), "started": time.time()}
    log_file = LOGS_DIR / f"{task_id}.log"
    with open(log_file, "w") as f:
        f.write("Initializing AI Training Studio Pipeline...\n")
        
    # Dispatch
    background_tasks.add_task(_run_training_pipeline, task_id, config)
    return {"task_id": task_id, "status": "starting"}


_LOG_TAIL_BYTES = 96 * 1024      # what the Studio shows; the whole file stays on disk


def _read_log_tail(log_file: Path, max_bytes: int = _LOG_TAIL_BYTES) -> tuple[str, bool]:
    """The last `max_bytes` of a training log as text, and whether older output was left out."""
    size = log_file.stat().st_size
    with open(log_file, "rb") as f:
        if size > max_bytes:
            f.seek(size - max_bytes)
        data = f.read()
    text = data.decode("utf-8", errors="replace")
    if size > max_bytes:
        text = text.split("\n", 1)[-1]          # drop the line that was cut in half
    return text, size > max_bytes


@router.get("/status/{task_id}")
def get_training_status(task_id: str):
    # A plain `def`: FastAPI runs it in a worker thread. As `async def` it read and cleaned the
    # whole log on the event loop, which froze every live stream for 0.1 - 0.6 s per poll.
    if task_id not in TRAINING_TASKS:
        raise HTTPException(status_code=404, detail="Task not found")

    task_info = TRAINING_TASKS[task_id]
    proc = task_info.get("proc")   # a resumed (detached) run: its state is its process
    if proc is not None and task_info["status"] == "running" and proc.poll() is not None:
        task_info["status"] = ("paused" if task_info.get("paused") else
                               "completed" if proc.returncode == 0 else "failed")
    log_file = LOGS_DIR / f"{task_id}.log"

    logs = ""
    truncated = False
    current_epoch = 0
    total_epochs = 100

    if log_file.exists():
        raw_data, truncated = _read_log_tail(log_file)

        clean_lines = []
        for line in raw_data.split('\n'):
            parts = line.split('\r')
            final_part = parts[-1] if parts[-1] else (parts[-2] if len(parts) > 1 else line)
            clean_lines.append(final_part)

            match = re.search(r'\s+(\d+)/(\d+)\s+', final_part)
            if match:
                try:
                    current_epoch = int(match.group(1))
                    total_epochs = int(match.group(2))
                except ValueError:
                    pass

        logs = "\n".join(clean_lines)

    result = None
    if task_info.get("model") == "reid":
        if task_info["status"] == "completed":
            result = _run_summary({"task_type": "reid"}) or None

    return {
        "status": task_info["status"],
        "logs": logs,
        "log_truncated": truncated,
        "current_epoch": current_epoch,
        "total_epochs": total_epochs,
        "result": result,
    }

HISTORY_FILE = TRAINING_LAB_DIR / "runs" / "history.jsonl"


def _newest(runs_dir: Path, prefix: str, need: str) -> Path | None:
    cands = [d for d in runs_dir.iterdir() if d.is_dir() and d.name.startswith(prefix) and (d / need).exists()] if runs_dir.exists() else []
    return max(cands, key=lambda d: d.stat().st_mtime) if cands else None


def _yolo_summary(run_dir: Path) -> dict:
    """Last-epoch metrics of an Ultralytics run (results.csv)."""
    try:
        with open(run_dir / "results.csv", newline="") as f:
            rows = list(csv.DictReader(f))
        last = {k.strip(): v for k, v in rows[-1].items()}
        pick = lambda sub: next((float(v) for k, v in last.items() if sub in k), None)
        return {"run_folder": run_dir.name, "epochs_done": len(rows),
                "map50": pick("mAP50(B)"), "map50_95": pick("mAP50-95(B)")}
    except Exception:
        return {"run_folder": run_dir.name}


def _run_summary(config: dict) -> dict:
    kind = config.get("task_type", "yolo")
    if kind == "reid":
        d = _newest(TRAINING_LAB_DIR / "runs" / "reid", "train", "metrics.json")
        return json.loads((d / "metrics.json").read_text()) if d else {}
    if kind in ("ocr", "enhancer"):
        return {}
    d = _newest(TRAINING_LAB_DIR / "runs" / config.get("model_name", ""), "train", "results.csv")
    return _yolo_summary(d) if d else {}


def _record_history(task_id: str, config: dict) -> None:
    info = TRAINING_TASKS.get(task_id, {})
    entry = {
        "task_id": task_id,
        "model": config.get("model_name") or ("plate_ocr" if config.get("task_type") == "ocr" else "unknown"),
        "kind": config.get("task_type", "yolo"),
        "status": info.get("status", "failed"),
        "started": info.get("started"),
        "finished": time.time(),
        "config": {k: v for k, v in config.items() if k not in ("task_type", "model_name")},
        "summary": _run_summary(config) if info.get("status") == "completed" else {},
    }
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(HISTORY_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def _clean_log(task_id: str) -> str:
    log_file = LOGS_DIR / f"{task_id}.log"
    if not log_file.exists():
        return ""
    raw = log_file.read_text(encoding="utf-8", errors="replace")
    out = []
    for line in raw.split("\n"):
        parts = line.split("\r")
        out.append(parts[-1] if parts[-1] else (parts[-2] if len(parts) > 1 else line))
    return "\n".join(out)


@router.get("/history/{model_key}")
async def training_history(model_key: str):
    """Every training run of ONE model, newest first (isolated per model)."""
    runs = []
    seen_folders = set()
    if HISTORY_FILE.exists():
        for line in HISTORY_FILE.read_text(encoding="utf-8").splitlines():
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("model") == model_key:
                runs.append(e)
                if e.get("summary", {}).get("run_folder"):
                    seen_folders.add(e["summary"]["run_folder"])
    # Runs made before history was recorded (Ultralytics folders on disk)
    legacy_root = TRAINING_LAB_DIR / "runs" / model_key
    if legacy_root.exists():
        for d in legacy_root.iterdir():
            if d.is_dir() and d.name.startswith("train") and (d / "results.csv").exists() and d.name not in seen_folders:
                runs.append({"task_id": None, "model": model_key, "kind": "yolo", "status": "completed",
                             "started": None, "finished": (d / "results.csv").stat().st_mtime,
                             "config": {}, "summary": _yolo_summary(d), "legacy": True})
    runs.sort(key=lambda r: r.get("finished") or 0, reverse=True)
    return {"model": model_key, "runs": runs}


@router.get("/log/{task_id}")
def training_log(task_id: str):
    if not re.fullmatch(r"[0-9a-fA-F-]{36}", task_id):
        raise HTTPException(status_code=400, detail="Invalid task id")
    return {"logs": _clean_log(task_id)}


_LOG_SCAN_FILES = 12          # newest log files looked at when a model's log has to be found by what is written in it
_LOG_SCAN_HEAD = 20_000       # bytes read from the top of each


def _clean_text(raw: str) -> str:
    """A log as it looks on screen: a progress bar redrawn with carriage returns keeps only its last state."""
    out = []
    for line in raw.split("\n"):
        parts = line.split("\r")
        out.append(parts[-1] if parts[-1] else (parts[-2] if len(parts) > 1 else line))
    return "\n".join(out)


def _latest_log(model: str) -> Path | None:
    """The newest training log of one model, however the training was started: the Studio's own tasks first, then the
    newest log files that name the model (a Continue / resume run and the terminal Training Lab write logs the backend has no
    task for, and a backend restart forgets the tasks)."""
    mine = [(t.get("started", 0), tid) for tid, t in TRAINING_TASKS.items() if t.get("model") == model]
    for _started, tid in sorted(mine, reverse=True):
        f = LOGS_DIR / f"{tid}.log"
        if f.exists():
            return f
    files = sorted((p for p in LOGS_DIR.glob("*.log") if p.is_file()), key=lambda p: p.stat().st_mtime, reverse=True)
    for f in files[:_LOG_SCAN_FILES]:
        if model in f.name:
            return f
        try:
            with open(f, "rb") as fh:
                head = fh.read(_LOG_SCAN_HEAD)
        except OSError:
            continue
        if model.encode() in head:
            return f
    return None


@router.get("/log/model/{model}")
def model_log(model: str):
    """The tail of a model's newest training log, and whether it is training now. A plain `def` (worker thread), like the
    status call: it reads a file."""
    if not re.fullmatch(r"[a-z_0-9]{1,40}", model):
        raise HTTPException(status_code=400, detail="Invalid model name")
    f = _latest_log(model)
    if f is None:
        return {"model": model, "file": None, "logs": "", "truncated": False, "training": False, "updated": None}
    text, truncated = _read_log_tail(f)
    if model in YOLO_MODELS:
        training = bool(training_state(model).get("training"))
    else:
        training = any(t.get("model") == model and t.get("status") in ("starting", "running") for t in TRAINING_TASKS.values())
    return {"model": model, "file": f.name, "logs": _clean_text(text), "truncated": truncated, "training": training,
            "updated": f.stat().st_mtime}


# What Training Studio can train. `kind` decides the settings panel and the backend pipeline.
STUDIO_MODELS = [
    {"key": "plate_specialist", "name": "License Plate Detector", "kind": "yolo",
     "purpose": "Finds the license plate on a vehicle.", "min_images": 300},
    {"key": "helmet_specialist", "name": "Helmet Detector", "kind": "yolo",
     "purpose": "Finds riders with or without helmets on motorcycle crops.", "min_images": 300},
    {"key": "cabin_specialist", "name": "Cabin Detector", "kind": "yolo",
     "purpose": "Seatbelt and phone checks on car windshields.", "min_images": 300},
    {"key": "primary_anchor", "name": "Primary Vehicle Detector", "kind": "yolo",
     "purpose": "Finds every vehicle on screen (the main detector).", "min_images": 500},
    {"key": "plate_ocr", "name": "Plate Reader (OCR)", "kind": "ocr",
     "purpose": "Reads the characters on a plate crop. Uses your True/False Positive and corrected plates.",
     "min_images": 200},
    {"key": "reid", "name": "Car Matching (ReID)", "kind": "reid",
     "purpose": "Tells whether two photos are the same car. Uses your merge / separate decisions.",
     "min_images": 150},
    {"key": "plate_enhancer", "name": "Plate Enhancer (Real-ESRGAN)", "kind": "enhancer",
     "purpose": "Sharpens blurry plate crops before reading. Advanced / experimental: builds from the plate detector dataset.",
     "min_images": 500},
]
_IMG_EXT = {".jpg", ".jpeg", ".png", ".bmp"}


def _count_images(folder: Path) -> int:
    if not folder.exists():
        return 0
    return sum(1 for _r, _d, files in os.walk(folder) for f in files if Path(f).suffix.lower() in _IMG_EXT)


def _dataset_stats(m: dict) -> dict:
    key, kind = m["key"], m["kind"]
    if kind == "reid":
        root = DATASETS_DIR / "reid" / "images"
        cars = 0
        photos = 0
        if root.exists():
            for task in (p for p in root.iterdir() if p.is_dir()):
                for ident in (p for p in task.iterdir() if p.is_dir()):
                    n = _count_images(ident)
                    photos += n
                    cars += 1 if n >= 2 else 0
        detail = f"{cars} cars with 2+ photos"
        enough = cars >= 5
        return {"images": photos, "detail": detail, "can_train": enough, "dataset_path": "datasets/reid",
                "hint": None if enough else "Needs at least 5 cars with 2+ photos. Keep merging / separating tickets in the Forensic Analyzer."}
    if kind == "ocr":
        n = _count_images(DATASETS_DIR / "plate_ocr" / "images")
        return {"images": n, "detail": f"{n} plate crops", "can_train": n >= 20, "dataset_path": "datasets/plate_ocr",
                "hint": None if n >= 20 else "Needs plate crops: use the True / False Positive / Corrected buttons in the Forensic Analyzer."}
    folder = "plate_specialist" if kind == "enhancer" else key
    n = _count_images(DATASETS_DIR / folder)
    return {"images": n, "detail": f"{n} images", "can_train": n >= 50, "dataset_path": f"datasets/{folder}",
            "hint": None if n >= 50 else "Upload a YOLO dataset ZIP (images/ and labels/) to this model."}


@router.get("/overview")
async def training_overview():
    """Every trainable model with its dataset size and whether it is ready to train."""
    out = []
    for m in STUDIO_MODELS:
        stats = _dataset_stats(m)
        runs = TRAINING_LAB_DIR / "runs" / ("reid" if m["kind"] == "reid" else m["key"])
        last = None
        if runs.exists():
            last = max((p.stat().st_mtime for p in runs.rglob("results.csv")), default=None)
        out.append({**m, **stats, "recommended": m["min_images"],
                    "enough_for_good_results": stats["images"] >= m["min_images"], "last_trained": last})
    return {"models": out}


@router.get("/report/{model_name}")
async def get_training_report(model_name: str, run: str | None = None):
    import pandas as pd
    
    metadata = {
        "primary_anchor": {"category": "Vehicle Detectors", "purpose": "Core bounding box generation for all vehicles on screen."},
        "plate_specialist": {"category": "Plate Models", "purpose": "Sub-cropping and detecting license plates on vehicles."},
        "helmet_specialist": {"category": "Helmet Detectors", "purpose": "Analyzing motorcycle crops to detect rider helmets."},
        "cabin_specialist": {"category": "Cabin Detectors", "purpose": "Analyzing car windshields for seatbelts and phones."}
    }
    
    runs_dir = TRAINING_LAB_DIR / "runs" / model_name
    meta = metadata.get(model_name, {"category": "Uncategorized", "purpose": "Unknown specialist model."})
    
    if not runs_dir.exists():
        return {"status": "not_found", "data": [], "metadata": meta, "run_folder": None}
        
    train_dirs = [d for d in runs_dir.iterdir() if d.is_dir() and d.name.startswith("train")]
    if not train_dirs:
        return {"status": "not_found", "data": [], "metadata": meta, "run_folder": None}
        
    latest_train_dir = max(train_dirs, key=lambda d: d.stat().st_mtime)
    if run:
        chosen = [d for d in train_dirs if d.name == run]
        if chosen:
            latest_train_dir = chosen[0]
    results_path = latest_train_dir / "results.csv"
    
    if not results_path.exists():
        return {"status": "not_found", "data": [], "metadata": meta, "run_folder": latest_train_dir.name}
        
    try:
        df = pd.read_csv(results_path)
        df.columns = df.columns.str.strip()
        data = df.to_dict(orient="records")
        return {"status": "success", "data": data, "metadata": meta, "run_folder": latest_train_dir.name}
    except Exception as e:
        return {"status": "error", "message": str(e), "metadata": meta, "run_folder": latest_train_dir.name}

class ReleaseBatchRequest(BaseModel):
    model_paths: list[str]

@router.get("/local-models")
async def get_local_models(sync_github: bool = False):
    """Returns a list of all local ONNX models and their GitHub release status."""
    import dotenv
    import requests
    import json
    import os
    
    dotenv.load_dotenv(BACKEND_DIR / ".env")
    token = os.environ.get("GITHUB_TOKEN")
    models_dir = BACKEND_DIR / "models"
    manifest_path = models_dir / "published_manifest.json"
    
    published_tags = set()
    
    # Load local manifest first
    if manifest_path.exists():
        try:
            with open(manifest_path, "r") as f:
                published_tags = set(json.load(f))
        except Exception:
            pass

    # 1. Fetch live releases from GitHub ONLY if requested
    if sync_github and token:
        try:
            repo = "fatijenic-org/huli-kamote"
            headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json"}
            res = requests.get(f"https://api.github.com/repos/{repo}/releases", headers=headers, timeout=5)
            if res.status_code == 200:
                live_tags = {release.get("tag_name") for release in res.json()}
                published_tags.update(live_tags)
                # Update local manifest
                with open(manifest_path, "w") as f:
                    json.dump(list(published_tags), f)
        except Exception as e:
            print(f"Failed to fetch GitHub releases: {e}")

    # 2. Scan local models
    local_models = []
    
    if not models_dir.exists():
        return {"status": "success", "data": []}
        
    for p in models_dir.rglob("*.onnx"):
        size_mb = p.stat().st_size / (1024 * 1024)
        mtime = p.stat().st_mtime
        rel_path = p.relative_to(models_dir).as_posix()
        
        category = p.parent.name if p.parent != models_dir else "Uncategorized"
        
        expected_tag = p.stem.replace(" ", "_")
        is_published = expected_tag in published_tags
        
        local_models.append({
            "name": p.name,
            "path": rel_path,
            "category": category,
            "size_mb": round(size_mb, 2),
            "timestamp": mtime,
            "is_published": is_published
        })
        
    local_models.sort(key=lambda x: x["timestamp"], reverse=True)
    return {"status": "success", "data": local_models}

@router.post("/release/batch")
async def batch_release_models(req: ReleaseBatchRequest):
    """Releases a batch of models to GitHub."""
    import dotenv
    import json
    import os
    dotenv.load_dotenv(BACKEND_DIR / ".env")
    
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise HTTPException(status_code=400, detail="GITHUB_TOKEN not found in .env")
        
    results = []
    script_path = SCRIPTS_DIR / "publish_release.py"
    successful_tags = []
    
    for rel_path in req.model_paths:
        abs_path = BACKEND_DIR / "models" / rel_path
        if not abs_path.exists():
            results.append({"model": rel_path, "status": "error", "message": "File not found"})
            continue
            
        tag = abs_path.stem.replace(" ", "_")
        
        cmd = [sys.executable, str(script_path), "--file", str(abs_path), "--tag", tag]
        try:
            env = os.environ.copy()
            env["GITHUB_TOKEN"] = token
            proc = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
            results.append({"model": rel_path, "status": "success", "output": proc.stdout})
            successful_tags.append(tag)
        except subprocess.CalledProcessError as e:
            results.append({"model": rel_path, "status": "error", "message": f"{e.stdout}\n{e.stderr}"})
            
    # Update local manifest
    if successful_tags:
        models_dir = BACKEND_DIR / "models"
        manifest_path = models_dir / "published_manifest.json"
        published_tags = set()
        if manifest_path.exists():
            try:
                with open(manifest_path, "r") as f:
                    published_tags = set(json.load(f))
            except: pass
        published_tags.update(successful_tags)
        with open(manifest_path, "w") as f:
            json.dump(list(published_tags), f)
            
    return {"status": "success", "results": results}
