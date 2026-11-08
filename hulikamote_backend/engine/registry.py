import json
from pathlib import Path
from inference.providers import make_session

class ModelRegistry:
    def __init__(self, config_path: str, session_factory=None):
        self.session_factory = session_factory or make_session
        self.config_path = Path(config_path)
        if not self.config_path.is_absolute() and not self.config_path.exists():
            backend_path = Path(__file__).resolve().parent.parent / config_path
            if backend_path.exists():
                self.config_path = backend_path

        self.models = {}
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
                self.active_violations = data.get("active_violations", [])
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

        # IMPORTANT: The primary anchor must exist at models/yolov8n.onnx.
        # Run: venv/Scripts/python.exe scripts/download_model.py
        # to auto-download and convert the .pt -> .onnx before starting the server.
        self._load_model("primary_anchor", get_path("yolov8n.onnx"), fallback=False)

        if "no_helmet" in self.active_violations:
            self._load_model("helmet_specialist", get_path("helmet_specialist.onnx"), fallback=True)

        # Always loaded — every violation ticket (counterflow, parking, etc.)
        # should carry the plate number, not only "no_plate" sessions.
        # Filename is selectable via camera_config.json's "plate_model" key.
        self._load_model("plate_specialist", get_path(self.plate_model_name), fallback=True)

        if {"no_seatbelt", "distracted_driving", "missing_side_mirror"} & set(self.active_violations):
            self._load_model("cabin_specialist", get_path("cabin_specialist.onnx"), fallback=True)

    def _load_model(self, name: str, path: Path, fallback: bool = False):
        if path.exists():
            print(f"[Registry] Loading {name} from {path}")
            self.models[name] = self.session_factory(str(path))

        else:
            if fallback:
                print(f"[Registry] Warning: {path} not found. Specialist {name} will be mocked or skipped.")
            else:
                raise FileNotFoundError(f"Critical model {path} not found!")

    def get_model(self, name: str):
        return self.models.get(name)
