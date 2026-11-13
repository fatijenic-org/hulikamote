"""
loading_signs.py - the overlay boxes of two rules: "NO LOADING / UNLOADING" (Illegal loading) and "NO PARKING" (Illegal parking).
Both work the same way. What is drawn in a box is a realistic object (engine/overlay_objects.py): a hydrant, a sign on a pole, ...

An operator places a sign on the picture (Forensic wizard, or the Live Monitor's saved rules) and resizes it: the sign's box IS the
no-loading area. A bus, jeepney, tricycle or truck standing still inside it for longer than the limit is flagged, exactly as in a drawn
zone. A sign is NOT part of the video: it is an overlay that belongs to the analysis, drawn on the evidence photos and the result
video. Nothing is written into the video file, and removing the sign (or starting a new analysis) removes it.

A sign's area is a box by default. An enforcer can give it a free shape: "area" = three or more corners [[x, y], ...] (any polygon; the box
x, y, w, h then holds the shape), and the object may stand anywhere: "ax", "ay" (default: the middle of the box).

Wizard form of a sign: {"x": ..., "y": ..., "w": ..., "h": ...}: the centre and the size, in the 1920x1080 reference space the
wizard draws in (the same space as a drawn zone, so a sign is scaled to the frame the same way).
"""
import numpy as np

REF = (1920, 1080)
MIN_SIDE = 24.0                # a sign smaller than this (in reference pixels) cannot be read, so it is made at least this big
LOOK_KEYS = ("scale", "angle", "tilt", "stand")      # the look of the object in the box (engine/overlay_objects.py look_of clamps them)


def usable_area(raw) -> list[list[float]] | None:
    """The corners of a free-shaped area (three or more, all finite), or None."""
    try:
        points = [[float(p[0]), float(p[1])] for p in raw]
    except (TypeError, ValueError, IndexError, KeyError):
        return None
    return points if len(points) >= 3 and all(np.isfinite(v) for p in points for v in p) else None


def usable_signs(raw) -> list[dict]:
    """The signs of the wizard settings that make sense: a centre and a size. Anything else is skipped; a tiny size is raised."""
    signs = []
    for s in raw or []:
        try:
            x, y, w, h = (float(s[k]) for k in ("x", "y", "w", "h"))
        except (KeyError, TypeError, ValueError):
            continue
        if not all(np.isfinite(v) for v in (x, y, w, h)) or w <= 0 or h <= 0:
            continue
        sign = {"x": x, "y": y, "w": max(w, MIN_SIDE), "h": max(h, MIN_SIDE)}
        if isinstance(s.get("kind"), str):
            sign["kind"] = s["kind"]                  # what the sign stands for (illegal parking: see engine/parking_reasons.py)
        for key in LOOK_KEYS:
            if key in s:
                sign[key] = s[key]
        area = usable_area(s.get("area"))
        if area:
            sign["area"] = area                       # a free shape
        for key in ("ax", "ay"):                      # where the object stands
            try:
                value = float(s[key])
            except (KeyError, TypeError, ValueError):
                continue
            if np.isfinite(value):
                sign[key] = value
        signs.append(sign)
    return signs


def polygon(sign: dict) -> list[list[float]]:
    """The sign's area as a zone polygon: its free shape when it has one, else the box (four corners, clockwise from the top left)."""
    if sign.get("area"):
        return [[float(x), float(y)] for x, y in sign["area"]]
    x0, y0 = sign["x"] - sign["w"] / 2, sign["y"] - sign["h"] / 2
    x1, y1 = x0 + sign["w"], y0 + sign["h"]
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
