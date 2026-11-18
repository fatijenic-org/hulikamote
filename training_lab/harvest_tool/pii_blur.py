"""
pii_blur.py - Find and hide personal details (people's heads, number plates) in a still picture before it is saved.

Same idea as the backend's engine/privacy.py (R.A. 10173), for pictures with no tracker:
  - the head of every person the vehicle finder sees (top 30% of the person's box, plus a margin);
  - the head zone above a motorcycle or tricycle whose rider was not found (a safety net);
  - the plate of every vehicle: the plate model's box inside the vehicle when it finds one, otherwise the lower part of
    the vehicle; and any plate the plate model finds in the whole picture (for pictures that are already a vehicle crop).
Faces are not searched for separately: OpenCV's face finder found nothing real in the project's photos.

The Labeller keeps them as blur areas (a layer apart from the labels) that a person can fix, delete or add to; whatever is inside
a blur area is blurred in the saved copy. Nothing here can promise to catch everybody: a person the detector misses stays visible, so the page says so.

Some models must NOT have their own target hidden (PII_ALLOWED): the plate model learns plates, the helmet model learns heads.
"""
import cv2
import numpy as np

from .collect import SUGGEST_CONF
from .frames import COCO_NAMES, FRAME_CONF, VEHICLES, _on_bike

Box = tuple[int, int, int, int]            # x, y, width, height in pixels

HEAD_SHARE, HEAD_PAD, PLATE_PAD = 0.30, 0.15, 0.20
TWO_WHEELERS = ("motorcycle", "tricycle")

# What may be blurred for each model: its own target stays untouched.
PII_ALLOWED = {
    "plate_specialist": {"heads"},
    "helmet_specialist": {"plates"},
    "cabin_specialist": {"heads", "plates"},
    "primary_anchor": {"heads", "plates"},
}


def allowed(model: str, heads: bool, plates: bool) -> tuple[bool, bool]:
    ok = PII_ALLOWED.get(model, set())
    return bool(heads and "heads" in ok), bool(plates and "plates" in ok)


def _grow(box, pad: float) -> Box:
    x, y, w, h = (int(v) for v in box)
    px, py = int(w * pad), int(h * pad)
    return x - px, y - py, w + 2 * px, h + 2 * py


def _clip(box: Box, width: int, height: int) -> Box | None:
    x, y, w, h = box
    x1, y1, x2, y2 = max(0, x), max(0, y), min(width, x + w), min(height, y + h)
    return (x1, y1, x2 - x1, y2 - y1) if x2 > x1 and y2 > y1 else None


def find_pii(img: np.ndarray, *, heads: bool, plates: bool, vehicle_detector=None, plate_detector=None) -> list[Box]:
    """Pixel boxes (x, y, w, h) worth blurring in [img]. Detectors may be None (then only what needs none is found)."""
    height, width = img.shape[:2]
    boxes: list[Box] = []
    dets = vehicle_detector.detect(img, conf=FRAME_CONF) if vehicle_detector is not None else []
    names = (getattr(vehicle_detector, "names", None) or COCO_NAMES) if vehicle_detector is not None else COCO_NAMES
    named = [(names.get(d.cls), d) for d in dets]
    people = [d for n, d in named if n == "person"]
    vehicles = [(n, d) for n, d in named if n in VEHICLES]

    if heads:
        for p in people:
            boxes.append(_grow((p.x1, p.y1, p.x2 - p.x1, (p.y2 - p.y1) * HEAD_SHARE), HEAD_PAD))
        for n, v in vehicles:
            if n in TWO_WHEELERS and not any(_on_bike(p, v) for p in people):
                bw, bh = v.x2 - v.x1, v.y2 - v.y1
                boxes.append((int(v.x1 + bw * 0.10), int(v.y1 - bh * 0.60), int(bw * 0.80), int(bh * 0.80)))   # the head sticks out above the bike

    if plates:
        for _, v in vehicles:
            x1, y1, x2, y2 = (max(0, int(c)) for c in (v.x1, v.y1, v.x2, v.y2))
            found = None
            if plate_detector is not None and x2 > x1 and y2 > y1:
                hits = plate_detector.detect(img[y1:y2, x1:x2], conf=SUGGEST_CONF)
                if hits:
                    p = hits[0]
                    found = _grow((x1 + p.x1, y1 + p.y1, p.x2 - p.x1, p.y2 - p.y1), PLATE_PAD)
            boxes.append(found or (x1, int(y1 + (y2 - y1) * 0.55), x2 - x1, int((y2 - y1) * 0.45)))          # the whole lower part
        if plate_detector is not None:
            for p in plate_detector.detect(img, conf=SUGGEST_CONF):
                boxes.append(_grow((p.x1, p.y1, p.x2 - p.x1, p.y2 - p.y1), PLATE_PAD))
    return [c for c in (_clip(b, width, height) for b in boxes) if c]


def to_yolo(box: Box, width: int, height: int, cls: int) -> list:
    x, y, w, h = box
    return [cls, (x + w / 2) / width, (y + h / 2) / height, w / width, h / height]


def blur_regions(img: np.ndarray, boxes) -> None:
    """Blur each pixel box (x, y, w, h) in place, hard enough that a face cannot be recognised (shrink, then a wide Gaussian)."""
    height, width = img.shape[:2]
    for box in boxes:
        clipped = _clip(tuple(int(v) for v in box), width, height)
        if clipped is None:
            continue
        x, y, w, h = clipped
        region = img[y:y + h, x:x + w]
        small = cv2.resize(region, (max(2, w // 6), max(2, h // 6)), interpolation=cv2.INTER_AREA)
        coarse = cv2.resize(small, (w, h), interpolation=cv2.INTER_LINEAR)
        img[y:y + h, x:x + w] = cv2.GaussianBlur(coarse, (0, 0), sigmaX=max(3.0, min(w, h) / 4))


def blur_yolo(img: np.ndarray, boxes) -> None:
    """Blur areas given as normalised YOLO rows [cls, cx, cy, w, h] (the class is ignored)."""
    height, width = img.shape[:2]
    blur_regions(img, [(int((cx - w / 2) * width), int((cy - h / 2) * height), int(w * width), int(h * height))
                       for _, cx, cy, w, h in boxes])
