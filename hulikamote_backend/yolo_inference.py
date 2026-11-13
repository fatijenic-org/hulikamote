"""
yolo_inference.py
-----------------
Encapsulated YOLOv8 ONNX inference class.
Handles preprocessing, inference, NMS, and postprocessing.

Phase A: Uses pre-trained YOLOv8n ONNX (COCO 80 classes).
Phase B: Swap MODEL_PATH for your custom Roboflow .onnx file and
         update VIOLATION_CLASS_NAMES to match your trained classes.
"""
import base64
import random
import time
from collections import deque
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
import onnxruntime as ort

from engine import marks, specialists
from inference.providers import make_session, active_provider, get_providers

# ─── Config ──────────────────────────────────────────────────────────────────

MODELS_DIR = Path(__file__).parent / "models"
ACTIVE_MODEL_FILE = MODELS_DIR / "active_model.txt"

def _resolve_model_path(name: str) -> Path:
    if (MODELS_DIR / name).exists():
        return MODELS_DIR / name
    for p in MODELS_DIR.rglob("*.onnx"):
        if p.name == name:
            return p
    return MODELS_DIR / name

def _get_persisted_model_name() -> str:
    if ACTIVE_MODEL_FILE.exists():
        name = ACTIVE_MODEL_FILE.read_text().strip()
        if name and _resolve_model_path(name).exists():
            return name
    return "yolov8n.onnx"

def _load_classes_for_model(model_name: str) -> Optional[list[str]]:
    model_path = _resolve_model_path(model_name)
    classes_file = model_path.with_name(f"{model_name}.classes.txt")
    if classes_file.exists():
        lines = [line.strip() for line in classes_file.read_text().splitlines() if line.strip()]
        if lines:
            return lines
    return None

MODEL_PATH = _resolve_model_path(_get_persisted_model_name())
VIOLATION_CLASS_NAMES: Optional[list[str]] = _load_classes_for_model(MODEL_PATH.name)

def list_available_models() -> dict:
    """Return ONNX model names grouped by category."""
    if not MODELS_DIR.exists():
        return {}
    
    categories = {}
    
    # Root level (Uncategorized)
    root_models = sorted(p.name for p in MODELS_DIR.glob("*.onnx"))
    if root_models:
        categories["Uncategorized"] = root_models
        
    for d in MODELS_DIR.iterdir():
        if d.is_dir() and d.name not in ("uploads",):
            cat_models = sorted(p.name for p in d.glob("*.onnx"))
            if cat_models:
                categories[d.name] = cat_models
                
    return categories

def set_model_path(model_name: str) -> Path:
    """Switch the active ONNX model used by the live/video analysis pipeline and persist it."""
    name = (model_name or "yolov8n.onnx").strip()
    
    candidate = None
    if (MODELS_DIR / name).exists():
        candidate = MODELS_DIR / name
    else:
        for p in MODELS_DIR.rglob("*.onnx"):
            if p.name == name:
                candidate = p
                break
                
    if not candidate:
        raise FileNotFoundError(f"Model '{name}' not found in backend/models/ or its subdirectories.")

    global MODEL_PATH, VIOLATION_CLASS_NAMES, _inference
    MODEL_PATH = candidate
    VIOLATION_CLASS_NAMES = _load_classes_for_model(name)
    _inference = None  # Force reload on next frame
    
    # Persist choice
    ACTIVE_MODEL_FILE.write_text(name)
    
    return MODEL_PATH

# ── Phase A: COCO classes we treat as "violations" for testing ─────────────
# YOLOv8n pretrained on COCO 80 classes.
# We map a subset to our violation types so the full pipeline can be tested
# before the custom model is ready.
COCO_VIOLATION_MAP: dict[str, str] = {
    "person":       "no_helmet",     # any person → treat as potential violation
    "bicycle":      "wrong_lane",
    "motorcycle":   "no_helmet",
    "car":          "red_light",
    "bus":          "wrong_lane",
    "truck":        "no_seatbelt",
    "traffic light":"red_light",
    "stop sign":    "red_light",
}

CONFIDENCE_THRESHOLD = 0.45
# Classes that get their own, lower cutoff. From a CCTV angle the stock COCO model is far less sure of a motorcycle than of
# its rider (4K clip, 2026-10-29: 3 motorcycle vs 30 person boxes at 0.45), so the rider stayed and the bike was dropped.
CLASS_CONFIDENCE: dict[str, float] = {"motorcycle": 0.25}
IOU_THRESHOLD = 0.50
INPUT_SIZE = 640
# Riders and pedestrians (class "person") are tracked apart from vehicles. A rider's box overlaps its motorcycle, and one
# shared tracker hands the motorcycle's id to the rider on any frame where the bike was missed: the track then flips
# between "motorcycle" and "person" and its box jumps to the rider. Person ids start here so the two id spaces never meet.
PERSON_ID_BASE = 1_000_000
# A tracked vehicle keeps the class most of its last looks agreed on (confidence-weighted), so one frame where the model
# says "car" or "truck" for a motorcycle does not flip the label.
CLASS_VOTES = 9
CLASS_VOTES_MAX_TRACKS = 2000

# ─── Colours per violation type ──────────────────────────────────────────────
COLORS: dict[str, tuple] = {
    "no_helmet":   (0, 165, 255),  # Orange
    "no_seatbelt": (0, 255, 255),  # Yellow
    "red_light":   (0, 0, 255),    # Red
    "wrong_lane":  (255, 0, 255),  # Purple
}
DEFAULT_COLOR = (0, 200, 0)       # Green for unknown

# ─── Bounding box appearance — tweak freely to adjust on-screen box style ────
BBOX_THICKNESS_DIVISOR = 600    # higher = thinner box lines (make box bolder)
BBOX_MIN_THICKNESS = 2          # never draw thinner than 2px
BBOX_FONT_SCALE_DIVISOR = 3000.0  # higher = smaller label text (60% smaller than 1200)
BBOX_MIN_FONT_SCALE = 0.3
PLATE_BOX_COLOR = (0, 200, 255)  # amber outline for the detected plate crop


def vehicle_label(d) -> str:
    """What a box says about the vehicle: "PLATE - TYPE", or just "VEHICLE" while the plate is not read. Never an id."""
    plate = getattr(d, "plate_text", None)
    return f"{plate} - {d.cls.upper()}" if plate else "VEHICLE"


def box_specs(detections) -> list[dict]:
    """Boxes to draw, as plain data (BGR colours): vehicles only. People are drawn only through the violation marks
    (riders, passengers outside, pickup bed: engine/marks.py), never as boxes of their own."""
    from engine.violations.base import VEHICLE_CLASSES
    specs = []
    for d in detections:
        if d.cls not in VEHICLE_CLASSES:
            continue
        who = vehicle_label(d)
        if d.is_violator:
            color = COLORS.get(d.violation_type, (0, 0, 255))
            lines = d.violation_type.replace("_", " ").upper().split("+") + [who]   # the plate and type stay with a violation
        else:
            color, lines = (0, 255, 0), [who]
        plate_box = getattr(d, "plate_bbox", None)
        specs.append({"box": [int(v) for v in d.bbox], "color": color, "lines": lines,
                      "plate": [int(v) for v in plate_box] if plate_box else None})
    return specs


def draw_specs(out: np.ndarray, specs: list[dict]) -> None:
    """Draw box_specs() on a picture in place: thin lines, labels kept inside the picture."""
    img_w = out.shape[1]
    font_scale = max(BBOX_MIN_FONT_SCALE, img_w / BBOX_FONT_SCALE_DIVISOR)
    old_thickness = max(BBOX_MIN_THICKNESS, int(img_w / BBOX_THICKNESS_DIVISOR))
    box_thickness = max(1, round(old_thickness / 2))      # half of the old line width
    text_thickness = max(1, int(old_thickness * 0.8))
    text_thickness = max(2, text_thickness) if font_scale >= 0.5 else 1   # bold enough to read, without blobs on small pictures
    for spec in specs:
        x, y, w, h = spec["box"]
        color = tuple(spec["color"])
        cv2.rectangle(out, (x, y), (x + w, y + h), color, box_thickness)
        text_color = (0, 0, 0) if color in [(0, 255, 255), (0, 255, 0)] else (255, 255, 255)
        marks.draw_label_block(out, spec["box"], spec["lines"], color, text_color, font_scale, text_thickness)
        if spec.get("plate"):                              # a thin, unobtrusive box around the plate crop
            px, py, pw, ph = spec["plate"]
            cv2.rectangle(out, (px, py), (px + pw, py + ph), (255, 255, 0), 1)


class YoloDetection:
    __slots__ = ("cls", "confidence", "bbox", "violation_type", "track_id", "is_violator", "assigned_user_id", "assigned_user_name", "plate_text", "plate_bbox", "marks")

    def __init__(self, cls: str, confidence: float, bbox: list[int], violation_type: str, track_id: int = -1, is_violator: bool = False):
        self.cls = cls
        self.confidence = confidence
        self.bbox = bbox  # [x, y, w, h] in original image coords
        self.violation_type = violation_type
        self.track_id = track_id
        self.is_violator = is_violator
        self.assigned_user_id = None
        self.assigned_user_name = None
        self.plate_text: str | None = None    # OCR'd plate number, if resolved yet
        self.plate_bbox: list[int] | None = None  # [x, y, w, h] of the plate crop, global coords
        self.marks: list[dict] = []  # boxes showing why it was flagged (engine/marks.py), for the live overlay


class YoloInference:
    def __init__(self, session_factory=None, tracker_type: str = "bytetrack"):
        if not MODEL_PATH.exists():
            raise FileNotFoundError(
                f"ONNX model not found at {MODEL_PATH}. "
                "Run: venv/Scripts/python.exe scripts/download_model.py"
            )

        self.session_factory = session_factory or make_session
        print(f"[YOLO] Loading model from {MODEL_PATH}")
        
        # Determine architecture version for routing (e.g. YOLO11, YOLO26)
        path_lower = MODEL_PATH.name.lower()
        if "yolo26" in path_lower:
            self.model_version = "v26"
            print("[YOLO] Detected YOLO26 architecture. NMS will be bypassed.")
        elif "yolo11" in path_lower:
            self.model_version = "v11"
            print("[YOLO] Detected YOLO11 architecture.")
        else:
            self.model_version = "v8"

        self._session = self.session_factory(str(MODEL_PATH))
        self._input_name = self._session.get_inputs()[0].name
        
        # Load tracker via Strategy Pattern
        self.tracker_type = tracker_type
        self.tracker = self._new_tracker()              # vehicles
        self.people_tracker = self._new_tracker()       # riders and pedestrians (see PERSON_ID_BASE)
        self._class_votes: dict[int, deque] = {}        # vehicle track id -> recent (class, confidence)

        # If using Phase B custom model, load class names from model metadata
        if VIOLATION_CLASS_NAMES is not None:
            self._classes = VIOLATION_CLASS_NAMES
            self._use_coco_map = False
        else:
            # Build class list from COCO (YOLOv8n default 80 classes)
            self._classes = self._get_coco_classes()
            self._use_coco_map = True

        print(f"[YOLO] Ready. {len(self._classes)} classes. "
              f"Provider: {self._session.get_providers()[0]}")

    def _new_tracker(self):
        from engine.tracker import ByteTrackStrategy, DeepSortStrategy
        if self.tracker_type.lower() == "deepsort":
            print("[Tracker] Initializing DeepSORT Strategy (GPU enabled if available)")
            return DeepSortStrategy(lost_track_buffer=60)
        print("[Tracker] Initializing ByteTrack Strategy")
        return ByteTrackStrategy(lost_track_buffer=60, minimum_matching_threshold=0.2)

    def reset_tracker(self) -> None:
        """Forget every tracked vehicle (new ids from 1) without reloading the model."""
        self.tracker = self._new_tracker()
        self.people_tracker = self._new_tracker()
        self._class_votes = {}

    def _stable_class(self, track_id: int, cls: str, confidence: float) -> str:
        """The class this vehicle track is called: the confidence-weighted majority of its last CLASS_VOTES looks."""
        votes = self._class_votes.get(track_id)
        if votes is None:
            if len(self._class_votes) >= CLASS_VOTES_MAX_TRACKS:        # long live runs: forget the oldest half
                for old in list(self._class_votes)[:CLASS_VOTES_MAX_TRACKS // 2]:
                    del self._class_votes[old]
            votes = self._class_votes[track_id] = deque(maxlen=CLASS_VOTES)
        votes.append((cls, confidence))
        totals: dict[str, float] = {}
        for name, score in votes:
            totals[name] = totals.get(name, 0.0) + score
        return max(totals, key=totals.get)

    def _track(self, tracker, dets: list, frame: np.ndarray, id_offset: int) -> None:
        """Run `tracker` on `dets` and give each detection its track id (+ id_offset). Ids are one-to-one."""
        import supervision as sv
        if not dets:
            tracker.update_with_detections(sv.Detections.empty(), frame)
            return
        sv_dets = sv.Detections(
            xyxy=np.array([[d.bbox[0], d.bbox[1], d.bbox[0] + d.bbox[2], d.bbox[1] + d.bbox[3]] for d in dets],
                          dtype=np.float32),
            confidence=np.array([d.confidence for d in dets], dtype=np.float32),
            class_id=np.zeros(len(dets), dtype=int),            # class_id is not used by the trackers
        )
        # Pass both detections and the raw BGR frame (for DeepSORT appearance features)
        tracked = tracker.update_with_detections(sv_dets, frame)

        # Map updated tracker IDs back to our detections by IoU matching.
        # One-to-one: each detection takes at most one track id and each track id is
        # used at most once. Pairs are assigned by descending IoU so a track can never
        # overwrite the id of a detection that another track matches better.
        pairs = []
        for t_idx in range(len(tracked)):
            t_box = tracked.xyxy[t_idx]
            t_id = int(tracked.tracker_id[t_idx])
            for d_idx, d in enumerate(dets):
                dx1, dy1 = d.bbox[0], d.bbox[1]
                dx2, dy2 = dx1 + d.bbox[2], dy1 + d.bbox[3]
                ix = max(0, min(t_box[2], dx2) - max(t_box[0], dx1))
                iy = max(0, min(t_box[3], dy2) - max(t_box[1], dy1))
                inter = ix * iy
                if inter == 0:
                    continue
                union = (t_box[2]-t_box[0])*(t_box[3]-t_box[1]) + d.bbox[2]*d.bbox[3] - inter
                iou = inter / (union + 1e-6)
                if iou > 0.1:
                    pairs.append((iou, t_id, d_idx))
        pairs.sort(key=lambda p: p[0], reverse=True)
        used_tracks, used_dets = set(), set()
        for _iou, t_id, d_idx in pairs:
            if t_id in used_tracks or d_idx in used_dets:
                continue
            dets[d_idx].track_id = t_id + id_offset
            used_tracks.add(t_id)
            used_dets.add(d_idx)

    def _get_coco_classes(self) -> list[str]:
        """Returns the 80 standard COCO class names in order."""
        return [
            "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train",
            "truck", "boat", "traffic light", "fire hydrant", "stop sign",
            "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep",
            "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
            "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard",
            "sports ball", "kite", "baseball bat", "baseball glove", "skateboard",
            "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork",
            "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
            "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
            "couch", "potted plant", "bed", "dining table", "toilet", "tv",
            "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave",
            "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase",
            "scissors", "teddy bear", "hair drier", "toothbrush",
        ]

    def preprocess(self, frame: np.ndarray) -> tuple[np.ndarray, float, float, int, int]:
        """Resize and normalise frame for YOLOv8 input."""
        h, w = frame.shape[:2]
        scale = min(INPUT_SIZE / w, INPUT_SIZE / h)
        nw, nh = int(w * scale), int(h * scale)

        resized = cv2.resize(frame, (nw, nh))
        padded = np.full((INPUT_SIZE, INPUT_SIZE, 3), 114, dtype=np.uint8)
        pad_x = (INPUT_SIZE - nw) // 2
        pad_y = (INPUT_SIZE - nh) // 2
        
        padded[pad_y:pad_y + nh, pad_x:pad_x + nw] = resized

        # OpenCV frames are BGR; the model was trained on RGB
        blob = np.ascontiguousarray(padded[:, :, ::-1]).astype(np.float32) / 255.0
        blob = blob.transpose(2, 0, 1)[np.newaxis]  # HWC → 1CHW

        return blob, scale, scale, int(pad_x), int(pad_y)

    def _class_thresholds(self, n_classes: int) -> np.ndarray:
        """Confidence cutoff per class id: CONFIDENCE_THRESHOLD, or the lower one in CLASS_CONFIDENCE."""
        key = (id(self._classes), n_classes, tuple(sorted(CLASS_CONFIDENCE.items())))
        if getattr(self, "_threshold_key", None) != key:
            thresholds = np.full(n_classes, CONFIDENCE_THRESHOLD, dtype=np.float32)
            for i, name in enumerate(self._classes[:n_classes]):
                if name in CLASS_CONFIDENCE:
                    thresholds[i] = CLASS_CONFIDENCE[name]
            self._threshold_key, self._thresholds = key, thresholds
        return self._thresholds

    def _nms(self, boxes, scores, iou_thresh: float) -> list[int]:
        """Simple IoU-based NMS (shared with the specialist models, see engine/specialists.py)."""
        return specialists.nms(boxes, scores, iou_thresh)

    def infer(self, frame: np.ndarray, track: bool = True) -> list[YoloDetection]:
        """
        Run inference on one BGR frame.
        Returns a list of YoloDetection objects (only violation classes).
        track=False returns the boxes only and leaves the trackers alone: for a second caller (the road scan) that must not
        disturb the live tracking.
        """
        orig_h, orig_w = frame.shape[:2]
        blob, sx, sy, pad_x, pad_y = self.preprocess(frame)

        outputs = self._session.run(None, {self._input_name: blob})
        preds = outputs[0][0]  # shape: (num_detections, 4+num_classes) or (84, 8400)

        # YOLOv8 output shape: (84, 8400) → transpose to (8400, 84)
        if preds.shape[0] < preds.shape[1]:
            preds = preds.T

        detections: list[YoloDetection] = []
        if preds.shape[0] == 0:
            return detections

        boxes_raw = preds[:, :4]      # cx, cy, w, h (normalised to input size)
        class_scores = preds[:, 4:]   # (N, num_classes)

        class_ids = class_scores.argmax(axis=1)
        confidences = class_scores[np.arange(len(class_ids)), class_ids]

        # Filter by confidence (one cutoff per class, see CLASS_CONFIDENCE)
        mask = confidences >= self._class_thresholds(class_scores.shape[1])[class_ids]
        if not mask.any():
            return detections

        boxes_raw = boxes_raw[mask]
        confidences = confidences[mask]
        class_ids = class_ids[mask]

        # cx,cy,w,h → x1,y1,x2,y2 in original image space
        cx, cy, bw, bh = boxes_raw[:, 0], boxes_raw[:, 1], boxes_raw[:, 2], boxes_raw[:, 3]
        # Undo letterbox padding + scale
        x1 = ((cx - bw / 2 - pad_x) / sx).clip(0, orig_w)
        y1 = ((cy - bh / 2 - pad_y) / sy).clip(0, orig_h)
        x2 = ((cx + bw / 2 - pad_x) / sx).clip(0, orig_w)
        y2 = ((cy + bh / 2 - pad_y) / sy).clip(0, orig_h)
        boxes_xyxy = np.stack([x1, y1, x2, y2], axis=1)

        # ---------------------------------------------------------
        # YOLO26 NMS Bypass Route
        # ---------------------------------------------------------
        if getattr(self, "model_version", "v8") == "v26":
            # YOLO26 is NMS-free by design, skip filtering
            keep = list(range(len(confidences)))
        else:
            # Standard YOLOv8 / YOLO11 NMS Filtering.
            # People get their own NMS group: a rider's box overlaps the motorcycle
            # (and the other riders) heavily, and must not delete it (overloading /
            # helmet checks count them). Vehicles stay in one group so a car is not
            # reported twice as car + truck.
            is_person = np.array([
                c < len(self._classes) and self._classes[c] == "person" for c in class_ids
            ], dtype=bool)
            keep = []
            for group in (np.flatnonzero(is_person), np.flatnonzero(~is_person)):
                if group.size:
                    keep.extend(group[self._nms(boxes_xyxy[group], confidences[group], IOU_THRESHOLD)])

        for i in keep:
            cls_name = self._classes[class_ids[i]] if class_ids[i] < len(self._classes) else "unknown"

            if self._use_coco_map:
                violation = COCO_VIOLATION_MAP.get(cls_name)
                if violation is None:
                    continue  # Not a class we care about in Phase A
            else:
                violation = cls_name

            bx1, by1, bx2, by2 = boxes_xyxy[i].astype(int)
            # Default to the raw class name as the 'violation_type' for now. stream.py will override this if it mocks a violation.
            detections.append(YoloDetection(
                cls=cls_name,
                confidence=float(confidences[i]),
                bbox=[int(bx1), int(by1), int(bx2 - bx1), int(by2 - by1)],
                violation_type=cls_name,
            ))

        # ── Tracking ─────────────────────────────────────────────────────────
        # Riders / pedestrians and vehicles are tracked apart (see PERSON_ID_BASE): the trackers know nothing
        # about classes, so in one pool a rider box takes over the motorcycle's id whenever the bike is missed.
        if not track:
            return detections
        people = [d for d in detections if d.cls == "person"]
        vehicles = [d for d in detections if d.cls != "person"]
        self._track(self.tracker, vehicles, frame, 0)
        self._track(self.people_tracker, people, frame, PERSON_ID_BASE)
        for d in vehicles:
            if d.track_id != -1:                    # one frame of "car" on a motorcycle does not change its class
                d.cls = d.violation_type = self._stable_class(d.track_id, d.cls, d.confidence)

        return detections

    def draw_detections(self, frame: np.ndarray, detections: list[YoloDetection]) -> np.ndarray:
        """Draw the vehicle boxes and labels on a copy of the frame."""
        out = frame.copy()
        draw_specs(out, box_specs(detections))
        return out

    @staticmethod
    def encode_frame(frame: np.ndarray, quality: int = 75) -> str:
        """JPEG-encode a BGR frame and return as base64 string."""
        _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
        return base64.b64encode(buf).decode("utf-8")

    @staticmethod
    def save_snapshot(frame: np.ndarray, snapshots_dir: Path, prefix: str = "") -> str:
        """Save a JPEG snapshot under snapshots_dir. Returns the path relative to
        the "snapshots" mount root, so subfolders (e.g. evidence/) resolve correctly.
        `prefix` starts the file name (e.g. "detail_helmet_": the close-ups the apps recognise by it)."""
        snapshots_dir.mkdir(parents=True, exist_ok=True)
        # Millisecond names collide when several images are saved in the same instant
        # (evidence photo + crops): add a counter instead of overwriting.
        stamp = int(time.time() * 1000)
        filename = f"{prefix}{stamp}.jpg"
        n = 1
        while (snapshots_dir / filename).exists():
            filename = f"{prefix}{stamp}_{n}.jpg"
            n += 1
        path = snapshots_dir / filename
        cv2.imwrite(str(path), frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
        snapshots_root = Path(__file__).parent / "snapshots"
        try:
            rel = path.relative_to(snapshots_root)
        except ValueError:
            rel = Path(filename)
        return f"snapshots/{rel.as_posix()}"


# ─── Singleton ───────────────────────────────────────────────────────────────

_inference: Optional[YoloInference] = None


def get_inference(force_reload: bool = False, session_factory=None, tracker_type: str = "bytetrack") -> YoloInference:
    """Return the singleton YoloInference instance (lazy-loaded)."""
    global _inference
    if force_reload or _inference is None:
        _inference = YoloInference(session_factory=session_factory, tracker_type=tracker_type)
    return _inference

_reader = None
import threading
_ocr_lock = threading.Lock()

def get_easyocr_reader():
    global _reader
    if _reader is None:
        with _ocr_lock:
            if _reader is None:
                try:
                    import easyocr
                    # Initialize EasyOCR for English (you can add 'tl' if available/needed)
                    print("[OCR] Initializing EasyOCR model (this may take a moment)...")
                    _reader = easyocr.Reader(['en'], gpu=True)
                    print("[OCR] EasyOCR ready.")
                except ImportError:
                    print("[OCR] Error: 'easyocr' is not installed. Run: pip install easyocr")
                    return None
    return _reader

def _extract_plate_text(frame_crop: np.ndarray) -> str:
    """
    Real OCR plate extraction for JIT evaluation using EasyOCR.
    """
    reader = get_easyocr_reader()
    if reader is None:
        return "OCR_NOT_INSTALLED"
        
    import cv2
    import re
    import numpy as np
    
    # 1. Upscale the crop (CRITICAL)
    # License plates in a 1080p frame are tiny. EasyOCR's CNN struggles without pixel density.
    h, w = frame_crop.shape[:2]
    enlarged = cv2.resize(frame_crop, (w * 3, h * 3), interpolation=cv2.INTER_CUBIC)
    
    # 2. Grayscale and CLAHE (Contrast Limited Adaptive Histogram Equalization)
    gray = cv2.cvtColor(enlarged, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    gray = clahe.apply(gray)
    
    # 3. Sharpening filter to enhance edges of letters
    sharpen_kernel = np.array([[-1,-1,-1], [-1,9,-1], [-1,-1,-1]])
    sharpened = cv2.filter2D(gray, -1, sharpen_kernel)
    
    # 4. Read text with a strict allowlist (Philippine plates only use A-Z, 0-9)
    # mag_ratio=1.5 tells EasyOCR to do another internal upscale pass.
    results = reader.readtext(
        sharpened, 
        allowlist='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        mag_ratio=1.5,
        contrast_ths=0.1,
        adjust_contrast=0.5
    )
    
    if not results:
        return "unidentified"
        
    texts = []
    
    # Words drawn by our own YOLO overlay that we MUST ignore
    ignore_words = ["ID", "FLOW", "HELMET", "BELT", "LANE", "TURN", "SIGN", "RED", "LIGHT", "CAR", "MOTOR"]
    
    for (bbox, text, prob) in results:
        if prob < 0.2:  # Ignore very low confidence noise
            continue
            
        text_upper = text.upper()
        
        # 1. Reject if it's picking up the YOLO annotation bounding box label!
        if any(word in text_upper for word in ignore_words):
            continue
            
        # 2. Clean up text (strip out weird symbols OCR might guess)
        clean_text = "".join(c for c in text_upper if c.isalnum())
        
        # 3. Philippine plates are generally 4 to 7 characters (e.g., ABC1234, XY123)
        if 4 <= len(clean_text) <= 8:
            # Add a hyphen for standard 3-letter + 3/4-number formats to make it look clean
            if re.match(r"^[A-Z]{3}[0-9]{3,4}$", clean_text):
                clean_text = f"{clean_text[:3]}-{clean_text[3:]}"
            elif re.match(r"^[A-Z]{2}[0-9]{4,5}$", clean_text):
                clean_text = f"{clean_text[:2]}-{clean_text[2:]}"
                
            texts.append(clean_text)
            
    if not texts:
        return "unidentified"
        
    return "-".join(texts)


