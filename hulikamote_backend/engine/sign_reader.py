"""
sign_reader.py - finds real STOP signs in the camera picture.

No new model and no new training data: the stock COCO detector that ships with the project
(models/Vehicle Detectors/yolo11_primary.onnx or yolov8n.onnx; COCO pictures are CC BY 4.0) already has the
class "stop sign" (COCO id 11). The trained vehicle models (train-3, train-4) do not, so this module loads the
stock model by itself, only when a stop zone asks for it, and runs it once every few seconds (a sign does not move).

Used by engine/violations/disregarding_signs.py: a stop zone with "read_sign": true is judged only after a
real stop sign was read near it.

Limits: COCO stop signs are the red octagon with the word STOP (the Philippine sign is the same shape).
A sign smaller than about 20 px, seen from behind, or hidden by a tree is not found.
"""
import logging
from pathlib import Path

import numpy as np

from engine import specialists

log = logging.getLogger(__name__)

STOP_SIGN_ID = 11                 # "stop sign" in the 80 COCO classes
MIN_CONF = 0.35
MODELS = Path(__file__).resolve().parent.parent / "models"
CANDIDATES = ("Vehicle Detectors/yolo11_primary.onnx", "Vehicle Detectors/yolov8n.onnx", "yolov8n.onnx")

_session = None
_tried = False


def _load():
    """The stock COCO detector (loaded once; None when no such file exists or it has no COCO classes)."""
    global _session, _tried
    if _tried:
        return _session
    _tried = True
    for name in CANDIDATES:
        path = MODELS / name
        if not path.exists():
            continue
        try:
            from inference.providers import make_session
            session = make_session(str(path))
            classes = session.get_outputs()[0].shape
            if 84 not in classes:                    # 4 box values + 80 COCO classes
                continue
            _session = session
            log.info("[SignReader] stop signs are read with %s", path.name)
            break
        except Exception as e:                       # a broken file must not stop the analysis
            log.warning("[SignReader] could not load %s: %s", path.name, e)
    return _session


def available() -> bool:
    return _load() is not None


def find_stop_signs(frame: np.ndarray, min_conf: float = MIN_CONF) -> list[dict]:
    """Stop signs in the picture: [{"box": [x, y, w, h] in frame pixels, "confidence": float}], best first."""
    session = _load()
    if session is None or frame is None or not frame.size:
        return []
    return [{"box": d["box"], "confidence": d["confidence"]}
            for d in specialists.detect(session, frame, min_conf) if d["class_id"] == STOP_SIGN_ID]


def near_zone(sign_box: list, polygon: list, reach: float = 1.0) -> bool:
    """True when the sign stands at the zone: its centre is inside the zone's bounding box grown by `reach` times its size
    on every side (a sign stands beside the road, not on it)."""
    xs, ys = [p[0] for p in polygon], [p[1] for p in polygon]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = sign_box[0] + sign_box[2] / 2, sign_box[1] + sign_box[3] / 2
    return min(xs) - reach * w <= cx <= max(xs) + reach * w and min(ys) - reach * h <= cy <= max(ys) + reach * h
