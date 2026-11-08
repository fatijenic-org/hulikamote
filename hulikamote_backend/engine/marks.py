"""
marks.py — Boxes that show WHY a vehicle was flagged (the bare head, the phone, the
missing plate area, each rider ...), drawn on the result video and the evidence photos.

The specialist models only look every few frames, so each mark is stored RELATIVE to the
vehicle's box (fractions of its width / height). On every frame it is placed on the
vehicle's current box, so it follows the vehicle. A mark is drawn only while its violation
is flagged on that vehicle, and only for MARK_TTL_S seconds after the last look.
"""
import cv2
import numpy as np

MARK_TTL_S = 3.0
RED, GREEN, YELLOW = (0, 0, 255), (0, 200, 0), (0, 220, 255)


def to_relative(box: list, vehicle: list) -> tuple:
    vx, vy, vw, vh = vehicle
    x, y, w, h = box
    vw, vh = max(vw, 1), max(vh, 1)
    return ((x - vx) / vw, (y - vy) / vh, w / vw, h / vh)


def to_absolute(rel: tuple, vehicle: list) -> list[int]:
    vx, vy, vw, vh = vehicle
    rx, ry, rw, rh = rel
    return [int(vx + rx * vw), int(vy + ry * vh), int(rw * vw), int(rh * vh)]


def set_marks(ledger, violation: str, vehicle: list, boxes: list, note: str | None = None) -> None:
    """Remember the boxes (frame coords [x, y, w, h], label, BGR colour) found by the latest look."""
    t = ledger.path[-1][0] if ledger.path else 0.0
    ledger.marks[violation] = {
        "t": t,
        "items": [(to_relative(b, vehicle), label, colour) for b, label, colour in boxes],
        "note": note,
    }


def current_marks(ledger, vehicle: list) -> list[tuple]:
    """[(box, label, colour)] to draw now, plus notes as box=None entries."""
    if not getattr(ledger, "marks", None):
        return []
    now = ledger.path[-1][0] if ledger.path else 0.0
    out = []
    for violation, mark in ledger.marks.items():
        shown = violation in ledger.violations or violation in getattr(ledger, "pending", ())
        if not shown or now - mark["t"] > MARK_TTL_S:
            continue
        out += [(to_absolute(rel, vehicle), label, colour) for rel, label, colour in mark["items"]]
        if mark["note"]:
            out.append((None, mark["note"], RED))
    return out


def draw_marks(frame: np.ndarray, ledger, vehicle: list) -> np.ndarray:
    """Draw the marks of one vehicle in place (and return the frame)."""
    items = current_marks(ledger, vehicle)
    if not items:
        return frame
    items.sort(key=lambda it: it[2] == RED)   # the violation (red) boxes last, so they stay on top
    scale = max(0.4, frame.shape[0] / 1400)
    thick = max(1, frame.shape[0] // 400)
    notes = []
    for box, label, colour in items:
        if box is None:
            notes.append(label)
            continue
        x, y, w, h = box
        cv2.rectangle(frame, (x, y), (x + w, y + h), colour, thick + 1)
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)
        ty = max(th + 4, y - 4)
        cv2.rectangle(frame, (x, ty - th - 4), (x + tw + 4, ty + 2), colour, -1)
        cv2.putText(frame, label, (x + 2, ty - 2), cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), thick,
                    cv2.LINE_AA)
    vx, vy, vw, vh = vehicle
    for i, note in enumerate(notes):   # e.g. "3 RIDERS (max 2)", "1/2 MIRRORS" under the vehicle
        y = min(frame.shape[0] - 6, vy + vh + int((i + 1) * 28 * scale * 1.6))
        cv2.putText(frame, note, (vx, y), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, (0, 0, 0), thick + 3, cv2.LINE_AA)
        cv2.putText(frame, note, (vx, y), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, RED, thick, cv2.LINE_AA)
    return frame


def draw_boxes(image: np.ndarray, items: list, note: str | None = None) -> np.ndarray:
    """Draw (box, label, colour) items, boxes in the image's OWN pixels, on a small crop in place (the close-ups kept
    as extra evidence). An optional note goes along the top. Returns the image."""
    h, w = image.shape[:2]
    scale = max(0.4, min(h, w) / 420)
    thick = max(1, min(h, w) // 200)
    for box, label, colour in sorted(items, key=lambda it: it[2] == RED):
        x, y, bw, bh = (int(v) for v in box)
        cv2.rectangle(image, (x, y), (x + bw, y + bh), colour, thick + 1)
        text_scale = scale
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, text_scale, thick)
        if tw + 6 > w:                                  # a narrow crop: shrink the label so it is not cut off
            text_scale = max(0.25, text_scale * (w - 6) / tw)
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, text_scale, 1)
            thick_text = 1
        else:
            thick_text = thick
        x_text = min(max(0, x), max(0, w - tw - 4))     # keep it inside the picture
        ty = y - 4 if y - th - 6 >= 0 else y + bh + th + 4
        ty = min(max(th + 2, ty), h - 4)
        cv2.rectangle(image, (x_text, ty - th - 3), (min(w - 1, x_text + tw + 4), ty + 3), colour, -1)
        cv2.putText(image, label, (x_text + 2, ty), cv2.FONT_HERSHEY_SIMPLEX, text_scale, (255, 255, 255), thick_text, cv2.LINE_AA)
    if note:
        cv2.putText(image, note, (4, int(18 * scale * 1.6)), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, (0, 0, 0), thick + 3, cv2.LINE_AA)
        cv2.putText(image, note, (4, int(18 * scale * 1.6)), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, RED, thick, cv2.LINE_AA)
    return image
