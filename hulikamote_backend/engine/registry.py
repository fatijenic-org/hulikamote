import json
import threading
from pathlib import Path
from inference.providers import make_session

# Model sessions that are loaded already, shared by every registry this process builds. "Apply" builds a new pipeline (so a new registry)
# every time: a model that did not change is NOT loaded again (a CUDA session takes seconds). The key holds the file's size and time, so a
# model that was replaced on disk is loaded fresh. Only the default session factory shares; an injected one (tests) always loads its own.
_SESSIONS: dict = {}
_SESSIONS_LOCK = threading.RLock()
_SESSIONS_MAX = 8


def _file_key(path: Path) -> tuple:
    try:
        stat = path.stat()
        return (str(path), stat.st_size, stat.st_mtime_ns)
    except (OSError, TypeError, ValueError):
        return (str(path), 0, 0)


def _mark_warm(session) -> bool:
    """True when this session ran once already (the first run of a CUDA session costs seconds: kernel search, lazy init)."""
    if getattr(session, "_hk_warm", False):
        return True
    try:
        session._hk_warm = True
    except Exception:
        pass
    return False


class ModelRegistry:
    def __init__(self, config_path: str, session_factory=None):
        self.session_factory = session_factory or make_session
        self._share = session_factory is None
        self.config_path = Path(config_path)
        if not self.config_path.is_absolute() and not self.config_path.exists():
            backend_path = Path(__file__).resolve().parent.parent / config_path
            if backend_path.exists():
                self.config_path = backend_path

        self.models = {}
        self._lazy: dict = {}                 # models the rules do not use: name -> file, loaded only if somebody asks (get_model)
        self._lazy_lock = threading.Lock()
        self.active_violations = []
        self.plate_model_name = "plate_specialist.onnx"
        self.plate_method = "smart"
        self.primary_model = "yolov8n"
        self._load_config()

    def _load_config(self):
        if not self.config_path.exists():
            print(f"Warning: Config not found at {self.config_path}. Loading defaults.")
            self.active_violations = ["no_helmet", "no_plate", "illegal_parking", "counterflow"]
        else:
            with open(self.config_path, "r") as f:
                data = json.load(f)
                from engine.violations import current_keys      # merged rules: old keys in saved configs still work
                self.active_violations = current_keys(data.get("active_violations", []))
                self.plate_model_name = data.get("plate_model", "plate_specialist.onnx")
                self.plate_method = data.get("plate_method", "smart")
                self.primary_model = data.get("primary_model", "yolov8n")
        self._initialize_models()

    def _initialize_models(self):
        base_dir = Path(__file__).parent.parent / "models"

        # Models deployed by training_lab/scripts/export_onnx.py are recorded here
        # (unique names like helmet_specialist_train3_20261003.onnx); they win over the default file.
        # Plate models are not overridden: the operator picks one by name (camera_config "plate_model").
        try:
            deployed = json.loads((base_dir / "model_manifest.json").read_text()).get("active_models", {})
        except Exception:
            deployed = {}
        default_names = {"helmet_specialist.onnx": "helmet_specialist", "cabin_specialist.onnx": "cabin_specialist"}

        def get_path(name):
            key = default_names.get(name)
            if key and deployed.get(key) and (base_dir / deployed[key]).exists():
                return base_dir / deployed[key]
            if (base_dir / name).exists():
                return base_dir / name
            for p in base_dir.rglob("*.onnx"):
                if p.name == name:
                    return p
            return base_dir / name

        # Only the models the switched-on rules use are loaded now (this runs while the Live Monitor starts). The others wait in
        # `_lazy`: get_model() still gives them, loaded at that moment, but nothing in the live loop asks for them.
        #  - the primary anchor (models/yolov8n.onnx) must exist, but no picture is ever fed to it (the detector is yolo_inference's own);
        #  - the plate model is looked through only by the "no_plate" rule (engine/specialist_jobs.py PlateJob.wanted).
        # IMPORTANT: The primary anchor must exist at models/yolov8n.onnx.
        # Run: venv/Scripts/python.exe scripts/download_model.py
        # to auto-download and convert the .pt -> .onnx before starting the server.
        anchor = get_path("yolov8n.onnx")
        if not anchor.exists():
            raise FileNotFoundError(f"Critical model {anchor} not found!")
        self._lazy["primary_anchor"] = anchor

        if "no_helmet" in self.active_violations or "overloading" in self.active_violations:
            self._load_model("helmet_specialist", get_path("helmet_specialist.onnx"), fallback=True)

        # Filename is selectable via camera_config.json's "plate_model" key.
        plate_path = get_path(self.plate_model_name)
        if "no_plate" in self.active_violations:
            self._load_model("plate_specialist", plate_path, fallback=True)
        else:
            self._lazy["plate_specialist"] = plate_path

        if {"no_seatbelt", "distracted_driving", "missing_side_mirror"} & set(self.active_violations):
            self._load_model("cabin_specialist", get_path("cabin_specialist.onnx"), fallback=True)

        self._forget_unused_sessions()

    def _load_model(self, name: str, path: Path, fallback: bool = False):
        if path.exists():
            self.models[name] = self._session(name, path)

        else:
            if fallback:
                print(f"[Registry] Warning: {path} not found. Specialist {name} will be mocked or skipped.")
            else:
                raise FileNotFoundError(f"Critical model {path} not found!")

    def _session(self, name: str, path: Path):
        """The session of a model file: one that this process loaded before is used again, else it is loaded now."""
        if not self._share:
            print(f"[Registry] Loading {name} from {path}")
            return self.session_factory(str(path))
        key = _file_key(path)
        with _SESSIONS_LOCK:                  # two threads that want the same model (the preparing one and Apply) load it once
            session = _SESSIONS.get(key)
            if session is None:
                print(f"[Registry] Loading {name} from {path}")
                session = _SESSIONS[key] = self.session_factory(str(path))
            else:
                print(f"[Registry] {name} is loaded already ({path.name})")
        return session

    def _forget_unused_sessions(self) -> None:
        """The shared cache keeps this registry's sessions and the latest others, up to _SESSIONS_MAX (an analysis with other rules does not
        throw away what the Live Monitor loaded; a model nobody uses any more gives its GPU memory back once nothing else holds it)."""
        if not self._share:
            return
        mine = list(self.models.values())
        with _SESSIONS_LOCK:
            excess = len(_SESSIONS) - _SESSIONS_MAX
            if excess <= 0:
                return
            others = [k for k, cached in _SESSIONS.items() if not any(cached is s for s in mine)]
            for key in others[:excess]:                  # (dicts keep the order of loading: the oldest go first)
                del _SESSIONS[key]

    def get_model(self, name: str):
        session = self.models.get(name)
        if session is None and name in self._lazy:
            with self._lazy_lock:
                path = self._lazy.pop(name, None)
                if path is not None and name not in self.models:
                    self._load_model(name, path, fallback=True)
            session = self.models.get(name)
        return session

    def warm_up(self) -> None:
        """Run each loaded model once on an empty picture, so the first real picture does not pay for the kernel search and lazy
        start-up of a CUDA session. A model that ran once is not run again. Never raises: a failed warm-up only loses the head start."""
        import numpy as np
        from engine import specialists

        for name, session in list(self.models.items()):
            try:
                if _mark_warm(session):
                    continue
                specialists.detect(session, np.zeros((96, 96, 3), np.uint8), 0.99)
            except Exception as exc:
                print(f"[Registry] Warm-up of {name} skipped: {exc}")
