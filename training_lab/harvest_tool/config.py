"""
config.py - Where the harvest tool reads and writes, which models it feeds, plain-language help.

The tool READS from the backend's saved analyses (evidence photos, report.json, the tickets
database) and WRITES only inside training_lab/harvest_inbox/ - plus, when you press "Add to
dataset", into training_lab/datasets/<model>/ (refused while that model is training).
It never writes inside hulikamote_backend/, so it can run while the backend and a training run.
"""
import json
from dataclasses import dataclass
from pathlib import Path

import yaml

LAB = Path(__file__).resolve().parent.parent          # training_lab/
REPO = LAB.parent


@dataclass(frozen=True)
class Paths:
    lab: Path = LAB
    backend: Path = REPO / "hulikamote_backend"

    @property
    def inbox(self) -> Path:
        return self.lab / "harvest_inbox"

    @property
    def datasets(self) -> Path:
        return self.lab / "datasets"

    @property
    def evidence(self) -> Path:
        return self.backend / "snapshots" / "evidence"

    @property
    def forensic(self) -> Path:
        return self.evidence / "forensic"

    @property
    def db(self) -> Path:
        return self.backend / "hulikamote.db"

    @property
    def models(self) -> Path:
        return self.backend / "models"


# The vision models the harvest feeds. Key = training_lab/datasets/<key>/ (and runs/<key>/).
MODELS = {
    "plate_specialist": {
        "title": "Plate",
        "does": "finds the license plate on a vehicle",
        "folder": "Plate Models",
        "default_file": "plate_specialist.onnx",
    },
    "helmet_specialist": {
        "title": "Helmet",
        "does": "tells riders with a helmet from riders without",
        "folder": "Helmet Detectors",
        "default_file": "helmet_specialist.onnx",
    },
    "cabin_specialist": {
        "title": "Cabin",
        "does": "finds the windshield, seatbelt, phone and side mirrors",
        "folder": "Cabin Models",
        "default_file": "cabin_specialist.onnx",
    },
    # Whole frames of a clip (not vehicle crops): the vehicle finder the app runs first. Its suggestions come from
    # the deployed vehicle detector (active_vehicle_onnx), matched to this dataset's classes by name.
    "primary_anchor": {
        "title": "Vehicles",
        "does": "finds every vehicle and rider in the picture",
        "folder": "Vehicle Detectors",
        "default_file": "yolo11_primary.onnx",
    },
}

# What to draw, in plain words (shown next to the class buttons in the labelling page).
CLASS_HELP = {
    "plate_specialist": {
        "license_plate": "The number plate. Draw the box tight around it.",
    },
    "helmet_specialist": {
        "rider_with_helmet": "A rider wearing a helmet. Box the whole rider (head to waist).",
        "rider_without_helmet": "A rider with a bare head, or a helmet held in hand / on the lap.",
    },
    "cabin_specialist": {
        "clear_window": "A windshield you can see through.",
        "tinted_window": "A windshield too dark to see inside.",
        "seatbelt": "The seatbelt strap across the driver.",
        "driver_phone": "A phone held by the driver.",
        "side_mirror": "A side mirror.",
    },
    "primary_anchor": {
        "motorcycle": "A motorcycle. Box the whole bike.",
        "car": "A car, van or SUV.",
        "bus": "A bus or a jeepney.",
        "truck": "A truck or a pickup.",
        "person": "A rider or passenger sitting on a motorcycle or tricycle (not people walking).",
        "tricycle": "A tricycle: a motorcycle with a sidecar.",
    },
}

# Colours used for the boxes in the labelling page (one per class index).
CLASS_COLORS = ["#2f9e44", "#e03131", "#1971c2", "#f08c00", "#9c36b5", "#0c8599"]

# Data the app already collects by itself; shown on the board so everything is in one place.
AUTOMATIC = [
    {"key": "plate_ocr", "title": "Plate text (OCR)", "how": "Pop Quiz corrections in the review screens",
     "folder": "plate_ocr/images/train", "need": 500},
    {"key": "reid", "title": "Car matcher (ReID)", "how": "merge / separate decisions in the review screens",
     "folder": "reid/images", "need": 5, "unit": "cars with 2+ photos"},
]


def class_names(paths: Paths, model: str) -> list[str]:
    """Class names of a model, in training order, from datasets/<model>/data.yaml."""
    cfg = yaml.safe_load((paths.datasets / model / "data.yaml").read_text(encoding="utf-8"))
    names = cfg["names"]
    items = names.items() if isinstance(names, dict) else enumerate(names)
    return [str(n) for _, n in sorted(items, key=lambda kv: int(kv[0]))]


def active_onnx(paths: Paths, model: str) -> Path | None:
    """The ONNX file the app currently uses for this model (manifest first, then the default name)."""
    if model == "primary_anchor":
        return active_vehicle_onnx(paths)                  # the app's vehicle finder, whatever it was trained on
    spec = MODELS[model]
    try:
        active = json.loads((paths.models / "model_manifest.json").read_text()).get("active_models", {})
    except Exception:
        active = {}
    chosen = active.get(model)
    if chosen and (paths.models / chosen).exists():
        return paths.models / chosen
    for candidate in (paths.models / spec["folder"] / spec["default_file"], paths.models / spec["default_file"]):
        if candidate.exists():
            return candidate
    return None


def active_vehicle_onnx(paths: Paths) -> Path | None:
    """The vehicle detector the app currently uses (models/active_model.txt)."""
    try:
        name = (paths.models / "active_model.txt").read_text().strip()
    except Exception:
        name = "yolov8n.onnx"
    if (paths.models / name).exists():
        return paths.models / name
    found = list(paths.models.rglob(name))
    return found[0] if found else None
