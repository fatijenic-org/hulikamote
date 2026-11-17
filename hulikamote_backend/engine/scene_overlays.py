"""
scene_overlays.py - road and traffic overlays for a whole video: painted road markings and roadside objects that the
operator places anywhere on the picture in the Forensic wizard, for footage of roads that have none.

It is separate from the overlays of the single violations (those stay as they are). The difference: nothing here is
handed to a rule directly. The overlays are painted on the picture, and the road finder (engine/road_edges.py, classic
edges and shapes, no trained model) then READS the picture and finds the markings, the painted ones and the real ones
alike. What it finds becomes the zones of the selected rules that have nothing drawn:
    solid lines (white, yellow, double yellow)   -> Crossing a solid line
    crosswalk                                    -> Pedestrian lane
    bicycle lane (green surface), bus lane (red) -> Restricted lane, with the lane's own vehicle type
Broken (dashed) lines, stop lines and objects (signs, hydrant, traffic light) are painted and shown; a stop sign is read
by engine/sign_reader.py when a stop zone asks for it. The other objects are not read back (their rules keep their own
sign boxes in the wizard).

One item, in the wizard's 1920x1080 space:
    {"kind": "line", "style": "solid_white" | "solid_yellow" | "double_yellow" | "dashed_white", "points": [[x, y], ...]}
    {"kind": "stop_line", "points": [[x, y], [x, y]]}
    {"kind": "lane", "type": "bicycle" | "bus", "polygon": [[x, y], ...]}
    {"kind": "crosswalk", "polygon": [four corners]}
    {"kind": "object", "type": <a kind of engine/overlay_objects.py>, "at": [x, y], "scale": 1.0}
"""
from __future__ import annotations

import logging
import math

import cv2
import numpy as np

from engine import line_paint, overlay_objects, road_edges

log = logging.getLogger(__name__)

REF = (1920, 1080)
LANES = {"bicycle": {"colour": (70, 165, 60), "sign": "bicycle_only", "label": "bicycle lane"},     # BGR: green
         "bus": {"colour": (55, 55, 190), "sign": "bus_only", "label": "bus lane"}}                 # red
PAINT_WHITE = (238, 240, 240)
MIN_SOLID = 0.20                 # a solid line shorter than this share of the picture's height is not used (same as auto_lines)
RULES = ("crossing_solid_line", "pedestrian_lane", "restricted_lane")


def _points(raw, least: int) -> list[list[float]] | None:
    try:
        pts = [[float(p[0]), float(p[1])] for p in raw or []]
    except (TypeError, ValueError, IndexError):
        return None
    return pts if len(pts) >= least else None


def usable(raw) -> list[dict]:
    """The overlay items that can be painted (anything malformed is left out)."""
    items = []
    for it in raw if isinstance(raw, list) else []:
        if not isinstance(it, dict):
            continue
        kind = it.get("kind")
        if kind == "line" and it.get("style") in line_paint.STYLES and _points(it.get("points"), 2):
            items.append({"kind": "line", "style": it["style"], "points": _points(it["points"], 2)})
        elif kind == "stop_line" and _points(it.get("points"), 2):
            items.append({"kind": "stop_line", "points": _points(it["points"], 2)[:2]})
        elif kind == "lane" and it.get("type") in LANES and _points(it.get("polygon"), 3):
            items.append({"kind": "lane", "type": it["type"], "polygon": _points(it["polygon"], 3)})
        elif kind == "crosswalk" and _points(it.get("polygon"), 4):
            items.append({"kind": "crosswalk", "polygon": _points(it["polygon"], 4)[:4]})
        elif kind == "object" and it.get("type") in overlay_objects.KINDS and _points([it.get("at")], 1):
            items.append({"kind": "object", "type": it["type"], "at": _points([it["at"]], 1)[0],
                          "scale": min(max(float(it.get("scale") or 1.0), 0.3), 4.0)})
    return items


def _lerp(a, b, t: float) -> list[float]:
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]


def _crosswalk_bars(quad: list[list[float]]) -> list[np.ndarray]:
    """The bars of a crosswalk in a four-corner band: side by side along the band's longer side."""
    a, b, c, d = quad
    long_ab = math.dist(a, b) >= math.dist(a, d)
    if not long_ab:                                       # make a-b the long side
        a, b, c, d = b, c, d, a
    count = int(min(max(round(math.dist(a, b) / max(math.dist(a, d), 1.0) * 3.5), 5), 24))    # about one bar per metre of road width
    bars = []
    for i in range(count):
        t0, t1 = (i + 0.22) / count, (i + 0.78) / count
        bars.append(np.array([_lerp(a, b, t0), _lerp(a, b, t1), _lerp(d, c, t1), _lerp(d, c, t0)], np.int32))
    return bars


def paint(frame: np.ndarray, items: list[dict], boxes=()) -> None:
    """Paint the overlays on `frame` (changed in place). `boxes` are the vehicles and people of this frame ([x, y, w, h]):
    road paint goes under them, so a vehicle drives over a line and not behind it."""
    if not items:
        return
    fh, fw = frame.shape[:2]
    sx, sy = fw / REF[0], fh / REF[1]

    def px(points) -> list[list[float]]:
        return [[x * sx, y * sy] for x, y in points]
    clean = frame.copy() if boxes else None
    surface = frame.copy()
    for it in items:                                      # lane surfaces, then crosswalk bars
        if it["kind"] == "lane":
            poly = np.array(px(it["polygon"]), np.int32)
            cv2.fillPoly(surface, [poly], LANES[it["type"]]["colour"], cv2.LINE_AA)
            cv2.polylines(surface, [poly], True, PAINT_WHITE, max(2, int(fw / 420)), cv2.LINE_AA)
    cv2.addWeighted(surface, 0.62, frame, 0.38, 0, dst=frame)
    bars = frame.copy()
    for it in items:
        if it["kind"] == "crosswalk":
            cv2.fillPoly(bars, _crosswalk_bars(px(it["polygon"])), PAINT_WHITE, cv2.LINE_AA)
    cv2.addWeighted(bars, 0.88, frame, 0.12, 0, dst=frame)
    if clean is not None:                                 # vehicles stay on top of the surfaces and bars
        for x, y, w, h in boxes:
            x0, y0, x1, y1 = max(0, int(x)), max(0, int(y)), min(fw, int(x + w)), min(fh, int(y + h))
            if x1 > x0 and y1 > y0:
                frame[y0:y1, x0:x1] = clean[y0:y1, x0:x1]
    for it in items:
        if it["kind"] == "line":
            line_paint.draw(frame, px(it["points"]), line_paint.look_of({"style": it["style"]}), True, occluders=boxes)
        elif it["kind"] == "stop_line":
            line_paint.draw(frame, px(it["points"]), line_paint.look_of({"style": "solid_white", "width": 2.4}), True, occluders=boxes)
    for it in items:
        if it["kind"] == "object":
            overlay_objects.draw_object(frame, (it["at"][0] * sx, it["at"][1] * sy), it["type"], {"scale": it["scale"]}, True)


def _colour_lanes(picture: np.ndarray) -> list[dict]:
    """Coloured lane surfaces: a large, smooth, strongly green (bicycle) or red (bus) area. In REF points."""
    h, w = picture.shape[:2]
    hsv = cv2.cvtColor(picture, cv2.COLOR_BGR2HSV)
    grey = cv2.GaussianBlur(cv2.cvtColor(picture, cv2.COLOR_BGR2GRAY), (0, 0), 2.0)
    texture = cv2.blur(np.abs(cv2.Laplacian(grey, cv2.CV_32F, ksize=3)), (11, 11))
    strong = (hsv[..., 1] > 85) & (hsv[..., 2] > 60) & (texture < 6.0)
    masks = {"bicycle": strong & (hsv[..., 0] >= 40) & (hsv[..., 0] <= 88),
             "bus": strong & ((hsv[..., 0] <= 8) | (hsv[..., 0] >= 172))}
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(15 * w / 1280) | 1,) * 2)
    lanes = []
    for lane, mask in masks.items():
        m = cv2.morphologyEx(cv2.morphologyEx(mask.astype(np.uint8) * 255, cv2.MORPH_OPEN, k), cv2.MORPH_CLOSE, k)
        contours, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for c in contours:
            if cv2.contourArea(c) < 0.004 * h * w:
                continue
            poly = cv2.approxPolyDP(c, 0.01 * cv2.arcLength(c, True), True).reshape(-1, 2)
            if len(poly) >= 3:
                lanes.append({"type": lane, "polygon": [[round(x * REF[0] / w, 1), round(y * REF[1] / h, 1)] for x, y in poly]})
    return lanes


def find(picture: np.ndarray) -> dict:
    """Read the road markings of a picture (real or painted). Returns {"zones": {rule: [zone, ...]} in REF points,
    "lanes": [{"type", "polygon"}], "found": counts, "edges": the road finder's own result (picture pixels)}."""
    h, w = picture.shape[:2]
    edges = road_edges.find(picture)

    def ref(points) -> list[list[float]]:
        return [[round(x * REF[0] / w, 1), round(y * REF[1] / h, 1)] for x, y in points]
    solid = []
    for ln in edges["lane_lines"]:
        pts = ln["points"]
        if ln["style"] != "solid" or math.dist(pts[0], pts[-1]) < MIN_SOLID * h:
            continue
        if len(pts) > 12:
            pts = [pts[round(i * (len(pts) - 1) / 11)] for i in range(12)]
        solid.append({"line": ref(pts), "auto": True, "colour": ln["colour"]})
    lanes = _colour_lanes(picture)
    dashed = sum(ln["style"] == "dashed" for ln in edges["lane_lines"])
    return {"zones": {"crossing_solid_line": solid,
                      "pedestrian_lane": [{"polygon": ref(c["polygon"]), "auto": True} for c in edges["crosswalks"]],
                      "restricted_lane": [{"polygon": ln["polygon"], "auto": True, "lane": ln["type"]} for ln in lanes]},
            "lanes": lanes, "edges": edges,
            "found": {"solid_lines": len(solid), "dashed_lines": int(dashed), "crosswalks": len(edges["crosswalks"]),
                      "stop_lines": len(edges["stop_lines"]), "bicycle_lanes": sum(ln["type"] == "bicycle" for ln in lanes),
                      "bus_lanes": sum(ln["type"] == "bus" for ln in lanes)}}


def empty_road(video_path, count: int = 12) -> np.ndarray | None:
    """The road without its traffic: the median of a few frames spread over the video (None when it cannot be read)."""
    cap = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    frames = []
    for i in range(count):
        if total > 0:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(total * (i + 0.5) / count))
        ok, frame = cap.read()
        if not ok:
            break
        if frame.shape[1] > 1280:
            frame = cv2.resize(frame, (1280, int(round(frame.shape[0] * 1280 / frame.shape[1]))), interpolation=cv2.INTER_AREA)
        frames.append(frame)
    cap.release()
    if not frames:
        return None
    return np.median(np.stack(frames), axis=0).astype(np.uint8) if len(frames) >= 3 else frames[0]


def _centre(polygon: list[list[float]]) -> tuple[float, float]:
    return sum(p[0] for p in polygon) / len(polygon), sum(p[1] for p in polygon) / len(polygon)


def apply(config: dict, video_path) -> str | None:
    """Before a Forensic run: paint the overlays on the empty road, read the markings back, and give them to the selected rules
    that have nothing drawn. Changes `config` (the wizard payload) in place. Returns a sentence for the operator, or None when
    there are no overlays. Never raises."""
    items = usable(config.get("scene_overlays"))
    if not items:
        return None
    config["scene_overlays"] = items
    try:
        road = empty_road(video_path)
        if road is None:
            return "Road overlays: the video could not be read, so nothing was found from them."
        paint(road, items)
        found = find(road)
    except Exception as exc:
        log.exception("[scene_overlays] reading the overlays failed")
        return f"Road overlays: the markings could not be read ({exc})."
    active = config.get("active_violations") or []
    per_violation = config.setdefault("per_violation_configs", {})
    used = []
    for rule in RULES:
        zones = found["zones"][rule]
        if rule not in active or not zones:
            continue
        settings = per_violation.setdefault(rule, {})
        if settings.get("rois"):
            continue                                      # what the operator drew wins
        settings["rois"] = [{k: v for k, v in z.items() if k != "lane"} for z in zones]
        if rule == "restricted_lane":                     # each lane gets its own vehicle type through a lane sign at its middle
            signs = settings.setdefault("signs", [])
            for z in zones:
                x, y = _centre(z["polygon"])
                signs.append({"type": LANES[z["lane"]]["sign"], "x": round(x, 1), "y": round(y, 1)})
        used.append(f"{len(zones)} for {rule.replace('_', ' ')}")
    f = found["found"]
    seen = (f"{f['solid_lines']} solid and {f['dashed_lines']} broken lines, {f['crosswalks']} crosswalks, "
            f"{f['bicycle_lanes']} bicycle and {f['bus_lanes']} bus lanes")
    return f"Road markings read from the picture: {seen}. Used: {', '.join(used) if used else 'none (no selected rule needed them)'}."


def preview(video_path, seconds: float, raw_items) -> tuple[np.ndarray | None, dict]:
    """One frame of the video with the overlays painted and what the road finder reads from it outlined (thin lines):
    cyan = solid line, yellow dots = broken line, green = crosswalk, magenta = coloured lane, red = stop line."""
    cap = cv2.VideoCapture(str(video_path))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    cap.set(cv2.CAP_PROP_POS_FRAMES, int(max(seconds, 0.0) * fps))
    ok, frame = cap.read()
    cap.release()
    if not ok:
        return None, {}
    if frame.shape[1] > 1280:
        frame = cv2.resize(frame, (1280, int(round(frame.shape[0] * 1280 / frame.shape[1]))), interpolation=cv2.INTER_AREA)
    items = usable(raw_items)
    paint(frame, items)
    try:
        found = find(frame)
    except Exception:                       # the finder must never hide the picture the operator places things on
        logging.getLogger(__name__).exception("road finder failed on the preview frame")
        return frame, {}
    h, w = frame.shape[:2]
    out = frame.copy()
    edges = found["edges"]
    for ln in edges["lane_lines"]:
        pts = np.array(ln["points"], np.int32)
        if ln["style"] == "solid":
            cv2.polylines(out, [pts], False, (255, 220, 0), 2, cv2.LINE_AA)
        else:
            for p in pts:
                cv2.circle(out, (int(p[0]), int(p[1])), 3, (0, 230, 255), -1, cv2.LINE_AA)
    for s in edges["stop_lines"]:
        cv2.polylines(out, [np.array(s["points"], np.int32)], False, (0, 0, 255), 2, cv2.LINE_AA)
    for c in edges["crosswalks"]:
        cv2.polylines(out, [np.array(c["polygon"], np.int32)], True, (0, 220, 0), 2, cv2.LINE_AA)
    for ln in found["lanes"]:
        poly = np.array([[x * w / REF[0], y * h / REF[1]] for x, y in ln["polygon"]], np.int32)
        cv2.polylines(out, [poly], True, (255, 0, 255), 2, cv2.LINE_AA)
    return out, found["found"]
