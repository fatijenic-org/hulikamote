"""
road_edges.py - find the road and its painted markings straight from ONE picture of the empty road, with classic
image processing only: brightness, edges and shapes. No trained model, no traffic and no camera calibration are needed.

The rule of thumb behind it: paint that a person can see is BRIGHTER than the road around it and THIN, so it can be
found with a script. The steps:
  1. Road surface: the big, smooth, colourless area that reaches the lower part of the picture (asphalt and concrete have
     little colour and little texture; trees, buildings and signs have a lot). Where traffic was seen moving is added.
  2. Paint: a morphological "top-hat" keeps only what is brighter than its surroundings and narrower than a window. The
     window grows toward the bottom of the picture, because a line near the camera is wider in pixels than a far one.
  3. Shapes: every blob of paint is measured (length, thickness, direction).
       - bars lying side by side, evenly spaced            -> a crosswalk (zebra)
       - long thin pieces, end to end in one direction     -> a lane line; few gaps = solid, regular gaps = dashed
       - a long line across the bars' direction, next to a crosswalk -> a stop line
  Lines are returned as point lists, so a curved line is followed.

Everything is in the pixels of the picture that was given. Limits: paint must stand out from the road (worn paint, night,
rain glare and strong shadows lower the result); a far crosswalk whose bars are 2-3 px thin is not found; a bright curb or
a road joint filled with bright sealant can be read as a line. The answer is a proposal that the operator can correct.
"""
from __future__ import annotations

import math

import cv2
import numpy as np

REF_W = 1280                       # the numbers below are for a picture this wide (others are scaled)
MIN_CONTRAST = 16                  # grey levels paint must stand out from the road around it
TOPHAT_SIZES = (9, 17, 29, 45)     # top-hat windows, far (top of the road) to near (bottom)
MAX_LEVEL = 26                     # ...and the most that is ever asked, however bright the rest of the paint is
MIN_BLOB_AREA = 22                 # px: smaller blobs of "paint" are specks
BAR_MIN_THICK = 4                  # px: a crosswalk bar thinner than this cannot be told from a line
MIN_BARS = 4                       # bars that make a crosswalk
SOLID_COVERAGE = 0.78              # painted share of a line's length from which it is solid
MAX_TURN_DEG = 14.0                # pieces of one line may differ this much in direction


def _unit(dx: float, dy: float) -> tuple[float, float]:
    n = math.hypot(dx, dy)
    return (dx / n, dy / n) if n > 1e-9 else (1.0, 0.0)


def road_mask(bgr: np.ndarray, hint: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """(road, core), uint8 with 255 = road. `core` is the bare road surface that was recognised; `road` is the same with the
    paint, shadows and standing vehicles inside it filled in. `hint`: a mask of where traffic moved (any size); when given,
    the road is grown from there, otherwise from the smooth colourless ground in the lower part of the picture."""
    h, w = bgr.shape[:2]
    s = w / REF_W
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.int16)
    grey = cv2.GaussianBlur(cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY), (0, 0), 2.0 * s)
    texture = cv2.blur(np.abs(cv2.Laplacian(grey, cv2.CV_32F, ksize=3)), (int(11 * s) | 1,) * 2)
    smooth = (hsv[..., 1] < 75) & (texture < 5.0) & (hsv[..., 2] > 30)
    seeds = np.zeros((h, w), bool)
    ceiling = 0                                           # rows above this are never road
    if hint is not None and (hint > 0).mean() >= 0.015:
        traffic = cv2.resize((hint > 0).astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST) > 0
        seeds = traffic & smooth
        ceiling = max(0, int(np.where(traffic.any(axis=1))[0][0] - 0.06 * h))   # a bridge or a wall above the traffic is not road
    if seeds.mean() < 0.01:                               # no traffic seen: the ground in front of the camera
        seeds = smooth.copy()
        seeds[:int(0.55 * h)] = False
        seeds[:, :int(0.05 * w)] = False
        seeds[:, int(0.95 * w):] = False
    if not seeds.any():
        return np.zeros((h, w), np.uint8), np.zeros((h, w), np.uint8)
    dark, light = (float(v) for v in np.percentile(lab[..., 0][seeds], (5, 95)))
    ca, cb = (float(np.median(lab[..., i][seeds])) for i in (1, 2))
    # the road may be darker than what was sampled (shadows) but hardly brighter (sky, walls in the sun), and it has its faint colour
    similar = (smooth & (lab[..., 0] >= dark - 70) & (lab[..., 0] <= light + 25)
               & (np.abs(lab[..., 1] - ca) < 12) & (np.abs(lab[..., 2] - cb) < 14)).astype(np.uint8) * 255
    similar[:ceiling] = 0
    similar = cv2.morphologyEx(similar, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(7 * s) | 1,) * 2))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(similar, connectivity=8)
    core = np.zeros((h, w), np.uint8)
    seed_total = max(int(seeds.sum()), 1)
    for i in range(1, count):
        area = stats[i][4]
        if area < 0.003 * h * w:
            continue
        part = labels == i
        on_seeds = int(seeds[part].sum())
        if on_seeds >= 0.05 * area or on_seeds >= 0.20 * seed_total:
            core[part] = 255
    # a painted lane surface next to the road is road too: smooth and strongly green or red (a bicycle or a bus lane)
    lane = ((hsv[..., 1] > 85) & (texture < 6.0)
            & (((hsv[..., 0] >= 40) & (hsv[..., 0] <= 88)) | (hsv[..., 0] <= 8) | (hsv[..., 0] >= 172))).astype(np.uint8) * 255
    lane = cv2.morphologyEx(lane, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(7 * s) | 1,) * 2))
    if lane.any() and core.any():
        beside = cv2.dilate(core, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(31 * s) | 1,) * 2))
        count, labels, stats, _ = cv2.connectedComponentsWithStats(lane, connectivity=8)
        for i in range(1, count):
            part = labels == i
            if stats[i][4] >= 0.002 * h * w and (beside[part] > 0).any():
                core[part] = 255
    # a painted line is not smooth (its edges), so it cuts the bare road in two: the closing must be wider than that cut
    road = cv2.morphologyEx(core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(37 * s) | 1,) * 2))
    contours, _ = cv2.findContours(road, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled = np.zeros_like(road)
    cv2.drawContours(filled, [c for c in contours if cv2.contourArea(c) > 0.01 * h * w], -1, 255, cv2.FILLED)
    # holes: a small one is paint, a shadow or a standing vehicle (road); a big one with colour in it is a block of buildings or an island
    holes = cv2.bitwise_and(filled, cv2.bitwise_not(road))
    # Thin things (a line, a lane's border) join holes that have nothing to do with each other: cut the holes apart
    # where they are thin, and judge each part by itself. What is too thin to be a part is paint: it stays road.
    cut = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(21 * s) | 1,) * 2)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(cv2.erode(holes, cut), connectivity=8)
    colourless = hsv[..., 1] < 75
    for i in range(1, count):
        part = (cv2.dilate((labels == i).astype(np.uint8) * 255, cut) > 0) & (holes > 0)
        if int(part.sum()) > 0.02 * h * w and colourless[part].mean() < 0.85:      # ...unless it is colourless all over: a crosswalk or road lettering
            filled[part] = 0
    # Colourless ground BETWEEN parts of the road is road as well, also when it is not closed in on every side:
    # a crosswalk with its stop line that reaches a painted lane or the kerb.
    reach = int(0.14 * w) | 1
    between = cv2.morphologyEx(core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (reach, reach)))
    filled[(between > 0) & colourless] = 255
    return filled, core


def paint_mask(bgr: np.ndarray, road: np.ndarray, sizes: tuple = TOPHAT_SIZES) -> tuple[np.ndarray, np.ndarray]:
    """(paint, yellow): what is brighter than the road around it and thin, inside the road; and the yellow part of it."""
    h, w = bgr.shape[:2]
    s = w / REF_W
    bright = cv2.medianBlur(bgr.max(axis=2), 3)
    rows = np.where(road.any(axis=1))[0]
    if len(rows) == 0:
        return np.zeros((h, w), np.uint8), np.zeros((h, w), np.uint8)
    top, bottom = int(rows[0]), int(rows[-1]) + 1
    response = np.zeros((h, w), np.uint8)
    bands = np.linspace(top, bottom, len(sizes) + 1).astype(int)
    for size, y0, y1 in zip(sizes, bands[:-1], bands[1:]):
        if y1 <= y0:
            continue
        k = int(size * s) | 1
        pad = k                                            # compute a little beyond the band so its edge rows are right
        a, b = max(0, y0 - pad), min(h, y1 + pad)
        hat = cv2.morphologyEx(bright[a:b], cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_RECT, (k, k)))
        response[y0:y1] = hat[y0 - a:y1 - a]
    near = cv2.dilate(road, np.ones((int(9 * s) | 1,) * 2, np.uint8))
    # how much the bare road itself "glows" in this measure (its grain, joints, shadows' edges) sets the bar: paint must
    # stand well above that. Taken from the road's own spread, so bright paint elsewhere cannot hide a faint line.
    values = response[near > 0]
    grain = float(np.percentile(values[::5], 75)) if len(values) > 500 else 0.0
    level = int(min(max(MIN_CONTRAST, 1.5 * grain + 6.0), MAX_LEVEL))
    paint = ((response >= level) & (near > 0)).astype(np.uint8) * 255
    paint = cv2.morphologyEx(paint, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    yellow = ((paint > 0) & (hsv[..., 0] >= 14) & (hsv[..., 0] <= 38) & (hsv[..., 1] > 70)).astype(np.uint8) * 255
    return paint, yellow


def _blobs(paint: np.ndarray, yellow: np.ndarray, scale: float) -> list[dict]:
    """Every blob of paint with its length, thickness, direction and centre line."""
    out = []
    contours, _ = cv2.findContours(paint, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    for c in contours:
        area = cv2.contourArea(c)
        if area < MIN_BLOB_AREA * scale * scale:
            continue
        (cx, cy), (rw, rh), _angle = cv2.minAreaRect(c)
        length, thick = max(rw, rh), max(min(rw, rh), 1.0)
        x, y, bw, bh = cv2.boundingRect(c)
        local = np.zeros((bh, bw), np.uint8)
        cv2.drawContours(local, [c - [x, y]], -1, 255, cv2.FILLED)
        ys, xs = np.nonzero(local)
        pts = np.stack([xs + x, ys + y], axis=1).astype(np.float32)
        vx, vy, x0, y0 = cv2.fitLine(pts, cv2.DIST_L2, 0, 0.01, 0.01).ravel()
        along = (pts[:, 0] - x0) * vx + (pts[:, 1] - y0) * vy
        across = -(pts[:, 0] - x0) * vy + (pts[:, 1] - y0) * vx
        step = max(12.0 * scale, 2.0 * thick)
        edges = np.arange(along.min(), along.max() + step, step)
        line, spread = [], []
        for a, b in zip(edges[:-1], edges[1:]):
            sel = (along >= a) & (along < b)
            if sel.sum() >= 3:
                line.append([float(pts[sel, 0].mean()), float(pts[sel, 1].mean())])
                spread.append(float(across[sel].max() - across[sel].min()) + 1.0)
        if len(line) < 2:                                   # short blob: its two ends along the fitted direction
            line = [[float(x0 + along.min() * vx), float(y0 + along.min() * vy)], [float(x0 + along.max() * vx), float(y0 + along.max() * vy)]]
        else:                                               # reach the true ends, not the centre of the end slices
            line[0] = [float(x0 + along.min() * vx + across[along <= edges[1]].mean() * -vy), float(y0 + along.min() * vy + across[along <= edges[1]].mean() * vx)]
            line[-1] = [float(x0 + along.max() * vx + across[along >= edges[-2]].mean() * -vy), float(y0 + along.max() * vy + across[along >= edges[-2]].mean() * vx)]
        path = sum(math.hypot(q[0] - p[0], q[1] - p[1]) for p, q in zip(line, line[1:]))
        width = float(np.median(spread)) if spread else thick       # thickness across the line itself (a curved line has a fat rectangle)
        out.append({"centre": (float(cx), float(cy)), "length": float(length), "thick": float(thick), "width": width, "path": float(path),
                    "axis": _unit(float(vx), float(vy)), "area": float(area), "fill": float(area / (length * thick)),
                    "line": line, "yellow": float((yellow[ys + y, xs + x] > 0).mean()), "rect": cv2.boxPoints(((cx, cy), (rw, rh), _angle))})
    return out


def _groups(n: int, linked) -> list[list[int]]:
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i in range(n):
        for j in range(i + 1, n):
            if linked(i, j):
                parent[find(i)] = find(j)
    groups: dict[int, list[int]] = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


def _angle_between(a: tuple, b: tuple) -> float:
    """Angle in degrees between two directions, ignoring which way they point (0 - 90)."""
    return math.degrees(math.acos(min(1.0, abs(a[0] * b[0] + a[1] * b[1]))))


def _crosswalks(blobs: list[dict], scale: float) -> tuple[list[dict], set[int]]:
    """Bars side by side: a crosswalk. Returns the crosswalks and the indexes of the blobs they use."""
    bars = [i for i, b in enumerate(blobs)
            if b["thick"] >= BAR_MIN_THICK * scale and 1.4 <= b["length"] / b["thick"] <= 30 and b["fill"] >= 0.55]

    def side_by_side(p: int, q: int) -> bool:
        a, b = blobs[bars[p]], blobs[bars[q]]
        if _angle_between(a["axis"], b["axis"]) > 15 or not 0.4 <= a["length"] / b["length"] <= 2.5 or not 0.4 <= a["thick"] / b["thick"] <= 2.5:
            return False
        dx, dy = b["centre"][0] - a["centre"][0], b["centre"][1] - a["centre"][1]
        along = abs(dx * a["axis"][0] + dy * a["axis"][1])
        across = abs(-dx * a["axis"][1] + dy * a["axis"][0])
        mean_thick = (a["thick"] + b["thick"]) / 2
        return 1.2 * mean_thick <= across <= 4.5 * mean_thick and along <= 0.6 * max(a["length"], b["length"])
    found, used = [], set()
    for group in _groups(len(bars), side_by_side):
        if len(group) < MIN_BARS:
            continue
        members = [bars[g] for g in group]
        corners = np.concatenate([blobs[m]["rect"] for m in members]).astype(np.float32)
        polygon = cv2.boxPoints(cv2.minAreaRect(corners))
        axis = _unit(sum(blobs[m]["axis"][0] * (1 if blobs[m]["axis"][0] * blobs[members[0]]["axis"][0] + blobs[m]["axis"][1] * blobs[members[0]]["axis"][1] >= 0 else -1) for m in members),
                     sum(blobs[m]["axis"][1] * (1 if blobs[m]["axis"][0] * blobs[members[0]]["axis"][0] + blobs[m]["axis"][1] * blobs[members[0]]["axis"][1] >= 0 else -1) for m in members))
        found.append({"polygon": [[float(x), float(y)] for x, y in polygon], "stripes": len(members), "bar_axis": axis,
                      "bar_length": float(np.median([blobs[m]["length"] for m in members])),
                      "centre": (float(corners[:, 0].mean()), float(corners[:, 1].mean()))})
        used.update(members)
    return found, used


def _road_both_sides(piece: dict, bright: np.ndarray, core: np.ndarray) -> bool:
    """Paint lies ON the road: the same road surface is on both sides of it. A curb, a wall or a barrier has the road on one
    side only (or a shadow on the other), so it is not a painted line."""
    h, w = bright.shape[:2]
    reach = piece["width"] * 1.5 + 4.0
    left, right, on_left, on_right = [], [], 0, 0
    pts = piece["line"]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        ux, uy = _unit(x1 - x0, y1 - y0)
        for t in (0.25, 0.5, 0.75):
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            ax, ay, bx, by = int(x - uy * reach), int(y + ux * reach), int(x + uy * reach), int(y - ux * reach)
            if not (0 <= ax < w and 0 <= ay < h and 0 <= bx < w and 0 <= by < h):
                continue
            left.append(int(bright[ay, ax]))
            right.append(int(bright[by, bx]))
            on_left += core[ay, ax] > 0
            on_right += core[by, bx] > 0
    if len(left) < 2:
        return False
    return (abs(float(np.median(left)) - float(np.median(right))) <= 30
            and on_left >= 0.5 * len(left) and on_right >= 0.5 * len(right))


def _lines(blobs: list[dict], skip: set[int], size: tuple[int, int], scale: float, bright: np.ndarray, core: np.ndarray,
           zebra: list | None = None) -> list[dict]:
    """Long thin pieces, end to end in one direction: lines (solid or dashed), as point lists."""
    w, h = size

    def at_crosswalk(b: dict) -> bool:                    # a stop line has the crosswalk's bars on one side, not bare road
        return any(cv2.pointPolygonTest(z, b["centre"], True) >= -0.08 * h for z in zebra or [])
    pieces = [b for i, b in enumerate(blobs)
              if i not in skip and b["path"] >= max(3.5 * b["width"], 10.0 * scale) and b["width"] <= 0.03 * w
              and (at_crosswalk(b) or _road_both_sides(b, bright, core))]

    def ends(p: dict) -> tuple[tuple, tuple]:
        return tuple(p["line"][0]), tuple(p["line"][-1])

    def end_to_end(i: int, j: int) -> bool:
        a, b = pieces[i], pieces[j]
        if _angle_between(a["axis"], b["axis"]) > MAX_TURN_DEG:
            return False
        gap, pa, pb = min((math.hypot(p[0] - q[0], p[1] - q[1]), p, q) for p in ends(a) for q in ends(b))
        if gap > min(0.30 * h, 6.0 * max(a["path"], b["path"])):
            return False
        join = _unit(pb[0] - pa[0], pb[1] - pa[1]) if gap > 3 else a["axis"]
        # the gap must run along both pieces (a neighbouring parallel line is beside, not ahead)
        return gap <= 3 or (_angle_between(join, a["axis"]) <= MAX_TURN_DEG and _angle_between(join, b["axis"]) <= MAX_TURN_DEG)
    lines = []
    for group in _groups(len(pieces), end_to_end):
        members = [pieces[g] for g in group]
        lead = max(members, key=lambda p: p["path"])
        ax = lead["axis"]
        members.sort(key=lambda p: p["centre"][0] * ax[0] + p["centre"][1] * ax[1])
        points: list[list[float]] = []
        for p in members:
            seg = p["line"] if (p["line"][-1][0] - p["line"][0][0]) * ax[0] + (p["line"][-1][1] - p["line"][0][1]) * ax[1] >= 0 else p["line"][::-1]
            points.extend(seg)
        extent = sum(math.hypot(q[0] - p[0], q[1] - p[1]) for p, q in zip(points, points[1:]))
        painted = sum(p["path"] for p in members)
        coverage = min(1.0, painted / max(extent, 1.0))
        solid = coverage >= SOLID_COVERAGE
        if extent < (0.10 if solid else 0.06) * h:
            continue
        if not solid and len(members) < 3:                  # two stray pieces are not a dashed line
            continue
        area = sum(p["area"] for p in members)
        lines.append({"points": [[round(x, 1), round(y, 1)] for x, y in points], "style": "solid" if solid else "dashed",
                      "colour": "yellow" if sum(p["yellow"] * p["area"] for p in members) / area > 0.4 else "white",
                      "coverage": round(coverage, 2), "length": round(extent, 1), "pieces": len(members),
                      "axis": _unit(points[-1][0] - points[0][0], points[-1][1] - points[0][1])})
    return lines


def find(bgr: np.ndarray, road_hint: np.ndarray | None = None) -> dict:
    """
    The road and its markings in one picture of the (empty) road.
    Returns {"road": mask, "paint": mask, "road_polygons": [...], "crosswalks": [{"polygon", "stripes"}],
             "stop_lines": [{"points"}], "lane_lines": [{"points", "style", "colour", "coverage", "length"}]}, all in `bgr`'s pixels.
    """
    h, w = bgr.shape[:2]
    scale = w / REF_W
    road, core = road_mask(bgr, road_hint)
    paint, yellow = paint_mask(bgr, road)
    # the two lines of a double line are one marking: join what is a few pixels apart
    joined = cv2.morphologyEx(paint, cv2.MORPH_CLOSE, np.ones((int(7 * scale) | 1,) * 2, np.uint8))
    blobs = _blobs(joined, yellow, scale)
    # crosswalk bars can be wide (a crosswalk near the camera, or one painted as an overlay): they are looked for with the
    # widest window on every row. Four or more equal bars side by side is a strict enough test to allow that.
    wide, _ = paint_mask(bgr, road, (TOPHAT_SIZES[-1] + 16,) * 2)
    crosswalks, _used = _crosswalks(_blobs(wide, yellow, scale), scale)
    zebra = [np.array(c["polygon"], np.float32) for c in crosswalks]
    used = {i for i, b in enumerate(blobs) if any(cv2.pointPolygonTest(z, b["centre"], False) >= 0 for z in zebra)}
    lines = _lines(blobs, used, (w, h), scale, cv2.medianBlur(bgr.max(axis=2), 5), cv2.dilate(core, np.ones((5, 5), np.uint8)), zebra)
    stops, lanes = [], []
    for line in lines:
        mid = line["points"][len(line["points"]) // 2]
        beside = [c for c in crosswalks
                  if _angle_between(line["axis"], c["bar_axis"]) >= 55
                  # ...and right next to it: no farther from the crosswalk than one bar is long
                  and cv2.pointPolygonTest(np.array(c["polygon"], np.float32), (float(mid[0]), float(mid[1])), True) >= -c["bar_length"]]
        (stops if beside and line["style"] == "solid" else lanes).append(line)
    contours, _ = cv2.findContours(road, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    polygons = [[[float(x), float(y)] for x, y in cv2.approxPolyDP(c, 0.004 * (w + h), True).reshape(-1, 2)] for c in contours]
    return {"road": road, "paint": paint, "road_polygons": polygons,
            "crosswalks": [{"polygon": c["polygon"], "stripes": c["stripes"]} for c in crosswalks],
            "stop_lines": [{"points": s["points"], "length": s["length"]} for s in stops],
            "lane_lines": [{k: ln[k] for k in ("points", "style", "colour", "coverage", "length", "pieces")} for ln in lanes]}


def draw(bgr: np.ndarray, found: dict) -> np.ndarray:
    """The picture with the road tinted and every marking drawn on it (for a person to check)."""
    out = bgr.copy()
    tint = out.copy()
    tint[found["road"] > 0] = (0.65 * tint[found["road"] > 0] + 0.35 * np.array([200, 120, 0])).astype(np.uint8)
    out = tint
    width = max(2, int(round(out.shape[1] / 480)))
    for c in found["crosswalks"]:
        cv2.polylines(out, [np.array(c["polygon"], np.int32)], True, (0, 220, 0), width)
    for ln in found["lane_lines"]:
        colour = (0, 215, 255) if ln["colour"] == "yellow" else (255, 200, 0)
        pts = np.array(ln["points"], np.int32)
        if ln["style"] == "solid":
            cv2.polylines(out, [pts], False, colour, width)
        else:
            for p, q in zip(pts[:-1:2], pts[1::2]):
                cv2.line(out, tuple(int(v) for v in p), tuple(int(v) for v in q), colour, width)
    for s in found["stop_lines"]:
        cv2.polylines(out, [np.array(s["points"], np.int32)], False, (0, 0, 255), width + 1)
    return out
