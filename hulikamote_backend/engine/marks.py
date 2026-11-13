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
TIMER_TTL_S = 1.0      # a stopwatch is rewritten on every frame it runs; it vanishes this long after the rule stops writing it
RED, GREEN, YELLOW = (0, 0, 255), (0, 200, 0), (0, 220, 255)
AMBER = (0, 165, 255)


def clock(seconds: float) -> str:
    """72 -> "1:12"."""
    minutes, secs = divmod(int(max(0, seconds)), 60)
    return f"{minutes}:{secs:02d}"


def set_timer(ledger, key: str, text: str, over: bool, t: float) -> None:
    """A stopwatch on the vehicle's own box (e.g. illegal parking: "PARKED 0:07 / 0:10"): amber while counting, red once over the
    limit. It is a separate chip on the bottom edge of the box: the labels above the box and the marks are not touched."""
    ledger.timers[key] = {"t": t, "text": text, "over": over}


def clear_timer(ledger, key: str) -> None:
    ledger.timers.pop(key, None)


def current_timers(ledger) -> list[tuple]:
    """[(text, BGR colour)] of the stopwatches running on this vehicle now."""
    timers = getattr(ledger, "timers", None)
    if not timers:
        return []
    now = ledger.path[-1][0] if ledger.path else 0.0
    return [(tm["text"], RED if tm["over"] else AMBER) for tm in timers.values() if now - tm["t"] <= TIMER_TTL_S]


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


def line_width(thick: int) -> int:
    """Box line width: half of the old `thick + 1`, never below 1 pixel."""
    return max(1, round((thick + 1) / 2))


def place_block(box: list, size: tuple, bw: int, bh: int) -> tuple[int, int]:
    """Top-left corner of a label block (bw x bh) for a box, kept INSIDE a picture of `size` (W, H) even when the box is
    partly outside it: the block sits on the visible part of the box, above it when there is room, else inside its top edge."""
    width, height = size
    x, y = box[0], box[1]
    x0 = min(max(0, x), max(0, width - bw))
    y0 = max(0, y) - bh
    if y0 < 0:
        y0 = max(0, y)
    return int(x0), int(min(y0, max(0, height - bh)))


def draw_label_block(img: np.ndarray, box: list, lines: list, colour: tuple, text_colour: tuple, scale: float, thick: int) -> None:
    """Stack the lines (top to bottom) on a coloured background above the box, kept inside the picture."""
    height, width = img.shape[:2]
    sizes = [cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)[0] for line in lines]
    rows = [th + 6 for _, th in sizes]
    x0, y = place_block(box, (width, height), max(tw for tw, _ in sizes) + 4, sum(rows))
    for line, (tw, _), row in zip(lines, sizes, rows):
        cv2.rectangle(img, (x0, y), (x0 + tw + 4, y + row), colour, -1)
        cv2.putText(img, line, (x0 + 2, y + row - 4), cv2.FONT_HERSHEY_SIMPLEX, scale, text_colour, thick, cv2.LINE_AA)
        y += row


def draw_timers(frame: np.ndarray, ledger, vehicle: list) -> None:
    """The stopwatch chips, stacked up from the bottom edge of the vehicle's box, kept inside the picture."""
    chips = current_timers(ledger)
    if not chips:
        return
    height, width = frame.shape[:2]
    scale = max(0.4, height / 1400)
    thick = max(1, height // 400)
    vx, vy, vw, vh = vehicle
    bottom = int(min(vy + vh, height))
    for text, colour in chips:
        (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)
        bw, bh = tw + 6, th + 8
        x = int(min(max(0, vx), max(0, width - bw)))
        y = int(max(0, min(bottom - bh, height - bh)))
        cv2.rectangle(frame, (x, y), (x + bw, y + bh), colour, -1)
        cv2.putText(frame, text, (x + 3, y + bh - 5), cv2.FONT_HERSHEY_SIMPLEX, scale,
                    (255, 255, 255) if colour == RED else (0, 0, 0), thick, cv2.LINE_AA)
        bottom = y


def mark_specs(ledger, vehicle: list) -> list[dict]:
    """The marks of one vehicle as plain data (BGR colours), for the replay's box file: {box, color, lines}, {note, at}
    or {timer, box, color}: a stopwatch chip on the bottom edge of the vehicle's box."""
    out = [{"timer": text, "box": [int(v) for v in vehicle], "color": list(colour), "lines": []}
           for text, colour in current_timers(ledger)]
    for box, label, colour in sorted(current_marks(ledger, vehicle), key=lambda it: it[2] == RED):
        if box is None:
            out.append({"note": label, "at": [int(vehicle[0]), int(vehicle[1] + vehicle[3])]})
        else:
            out.append({"box": [int(v) for v in box], "color": list(colour), "lines": [label]})
    return out


def draw_marks(frame: np.ndarray, ledger, vehicle: list) -> np.ndarray:
    """Draw the marks (and the stopwatch chips) of one vehicle in place (and return the frame)."""
    draw_timers(frame, ledger, vehicle)
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
        cv2.rectangle(frame, (x, y), (x + w, y + h), colour, line_width(thick))
        draw_label_block(frame, box, [label], colour, (255, 255, 255), scale, thick)
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
        cv2.rectangle(image, (x, y), (x + bw, y + bh), colour, line_width(thick))
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
