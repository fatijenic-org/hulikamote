"""
crosswalk_overlay.py - the overlay crosswalk of "Pedestrian lane".

For testing the rule on a road that has no crosswalk. The operator places a zebra crossing on the picture (Forensic wizard). It is NOT
part of the video: it belongs to the analysis, is drawn on the evidence photos and the result video, and it IS the crosswalk zone: a
vehicle that stops on it for longer than the zone's time limit is flagged, exactly as on a drawn zone. Nothing is written into the
video file; removing the overlay (or starting a new analysis) removes it.

Wizard form: {"x", "y", "scale", "depth", "angle", "slant", "stripes", "wear"}, the spot in the 1920x1080 reference space the wizard draws in.
  scale    length of the band across the road; 1.0 = 22% of the picture's width
  depth    how deep the band is along the road, relative to the normal depth (0.25 to 2.0)
  angle    turns the crosswalk in the picture (degrees, clockwise)
  slant    perspective: how far the camera looks along the road; the far edge gets shorter and the band flatter (0 = seen from straight above)
  stripes  how many white bars (3 to 16)
  wear     how worn the paint is: 0 = fresh, 1 = patchy and chipped
`crosswalks_realistic` (wizard setting, on by default) paints it like it was filmed: soft edges, grain, paint dulled to the light of the scene,
the road's texture showing through. Off = flat white bars.

The painted bars are a bilinear grid between the four corners of the zone, so the picture always matches the zone the rule uses.
"""
import math
from functools import lru_cache

import cv2
import numpy as np

REF = (1920, 1080)
SIZE_SHARE = 0.22               # band length (across the road) at scale 1.0, as a share of the picture's width
DEPTH_RATIO = 0.38              # band depth / band length at depth 1.0, seen from straight above
MIN_SCALE, MAX_SCALE = 0.3, 3.0
MIN_DEPTH, MAX_DEPTH = 0.25, 2.0
MAX_ANGLE = 90.0
MAX_SLANT = 70.0
MIN_STRIPES, MAX_STRIPES = 3, 16
FILL = 0.58                     # share of each stripe slot that is paint
DEFAULTS = {"scale": 1.0, "depth": 1.0, "angle": 0.0, "slant": 30.0, "stripes": 8, "wear": 0.2}


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def look_of(raw: dict) -> dict:
    """The size, shape and paint of an overlay crosswalk (wizard form), kept inside what makes sense; missing = the defaults."""
    def number(key: str) -> float:
        try:
            value = float(raw.get(key, DEFAULTS[key]))
        except (TypeError, ValueError):
            return float(DEFAULTS[key])
        return value if math.isfinite(value) else float(DEFAULTS[key])
    return {"scale": _clamp(number("scale"), MIN_SCALE, MAX_SCALE),
            "depth": _clamp(number("depth"), MIN_DEPTH, MAX_DEPTH),
            "angle": _clamp(number("angle"), -MAX_ANGLE, MAX_ANGLE),
            "slant": _clamp(number("slant"), 0.0, MAX_SLANT),
            "stripes": int(_clamp(round(number("stripes")), MIN_STRIPES, MAX_STRIPES)),
            "wear": _clamp(number("wear"), 0.0, 1.0)}


def usable(raw) -> list[dict]:
    """The crosswalks of the wizard settings that make sense: a position (plus their look). Anything else is skipped."""
    out = []
    for item in raw or []:
        try:
            out.append({"x": float(item["x"]), "y": float(item["y"]), **look_of(item)})
        except (AttributeError, KeyError, TypeError, ValueError):
            continue
    return [c for c in out if math.isfinite(c["x"]) and math.isfinite(c["y"])]


def corners(look: dict) -> list[tuple[float, float]]:
    """The four corners (far-left, far-right, near-right, near-left) of the band, relative to its centre, in the reference space.
    The far edge is the top one: `slant` makes it shorter and the band flatter, then `angle` turns the whole thing (clockwise)."""
    look = look_of(look)
    length = REF[0] * SIZE_SHARE * look["scale"]
    depth = length * DEPTH_RATIO * look["depth"]
    slant = math.radians(look["slant"])
    far = 1.0 - 0.55 * math.sin(slant)                          # the far edge's length, relative to the near edge
    flat = 1.0 - 0.45 * math.sin(slant)                         # how much the depth is squashed
    roll = math.radians(look["angle"])
    out = []
    for sx, sy, shrink in ((-0.5, -0.5, far), (0.5, -0.5, far), (0.5, 0.5, 1.0), (-0.5, 0.5, 1.0)):
        x, y = sx * length * shrink, sy * depth * flat
        out.append((x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll)))
    return out


def polygon(overlay: dict) -> list[list[float]]:
    """The crosswalk as a zone: its four corners on the picture, in the reference space."""
    return [[round(overlay["x"] + dx, 1), round(overlay["y"] + dy, 1)] for dx, dy in corners(overlay)]


def _lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def bars(quad, stripes: int) -> list[list[tuple[float, float]]]:
    """The white bars: each one a four-corner shape between the far and near edge of the quad, side by side along the band."""
    far_left, far_right, near_right, near_left = quad
    n = int(_clamp(stripes, MIN_STRIPES, MAX_STRIPES))
    out = []
    for k in range(n):
        u0, u1 = (k + (1 - FILL) / 2) / n, (k + 1 - (1 - FILL) / 2) / n
        out.append([_lerp(far_left, far_right, u0), _lerp(far_left, far_right, u1),
                    _lerp(near_left, near_right, u1), _lerp(near_left, near_right, u0)])
    return out


# ─── drawing ────────────────────────────────────────────────────────────────

def _light_of(frame: np.ndarray) -> int:
    """How bright the scene is, 0 (dark) to 3 (bright); from a coarse look at the whole picture, so it hardly changes from frame to frame."""
    return int(min(3, frame[::16, ::16].mean() / 64.0))


@lru_cache(maxsize=48)
def _layer(points: tuple, stripes: int, wear: float, realistic: bool, light: int):
    """The paint as it is laid on the picture: (alpha 0..1, paint grey level, x offset, y offset), the offsets being where the top-left
    pixel of the alpha sits on the picture. Cached: the same crosswalk is drawn on every frame of the video."""
    quad = [(points[i], points[i + 1]) for i in range(0, 8, 2)]
    pad = 4
    x0, y0 = int(math.floor(min(p[0] for p in quad))) - pad, int(math.floor(min(p[1] for p in quad))) - pad
    x1, y1 = int(math.ceil(max(p[0] for p in quad))) + pad, int(math.ceil(max(p[1] for p in quad))) + pad
    w, h = x1 - x0, y1 - y0
    if w < 4 or h < 4 or w * h > 4_000_000:
        return None
    mask = np.zeros((h, w), np.uint8)
    for bar in bars(quad, stripes):
        cv2.fillConvexPoly(mask, np.int32([[round(x - x0), round(y - y0)] for x, y in bar]), 255, lineType=cv2.LINE_AA)
    alpha = mask.astype(np.float32) / 255.0
    rng = np.random.RandomState(11 + stripes)
    if wear > 0:                                                  # patches where the paint has gone, and fine chips
        low = cv2.GaussianBlur(rng.rand(h, w).astype(np.float32), (0, 0), max(1.5, 0.03 * w))
        low = (low - low.min()) / max(float(low.max() - low.min()), 1e-6)
        patches = np.clip((low - (1.05 - 0.40 * wear)) * 8.0, 0.0, 1.0)
        chips = (rng.rand(h, w) > 1.0 - 0.12 * wear).astype(np.float32)
        alpha *= 1.0 - 0.9 * patches
        alpha *= 1.0 - 0.7 * chips
    if realistic:
        alpha = cv2.GaussianBlur(alpha, (0, 0), max(0.6, 0.004 * w))
        alpha += rng.normal(0.0, 0.03, alpha.shape).astype(np.float32) * (alpha > 0.02)       # a little grain, the same on every frame
        alpha = np.clip(alpha, 0.0, 1.0)
        paint = 240.0 * (0.78 + 0.22 * light / 3.0)               # dull scene = dull paint
    else:
        paint = 245.0
    return alpha, paint, x0, y0


def draw(frame: np.ndarray, zone_polygon, look: dict, realistic: bool = True, occluders=()) -> None:
    """The crosswalk on the picture: bars between the four corners of `zone_polygon` (frame pixels). Changes `frame`.
    `occluders` are boxes [x, y, w, h] of vehicles and people: the paint is on the road, so it goes UNDER them (soft edge)."""
    if zone_polygon is None or len(zone_polygon) != 4:
        return
    fh, fw = frame.shape[:2]
    points = tuple(int(round(float(v))) for p in zone_polygon for v in p)
    layer = _layer(points, int(_clamp(int(look.get("stripes", DEFAULTS["stripes"])), MIN_STRIPES, MAX_STRIPES)),
                   round(_clamp(float(look.get("wear", DEFAULTS["wear"])), 0.0, 1.0), 2), bool(realistic), _light_of(frame))
    if layer is None:
        return
    alpha, paint, ox, oy = layer
    h, w = alpha.shape
    xs, ys, xe, ye = max(ox, 0), max(oy, 0), min(ox + w, fw), min(oy + h, fh)
    if xs >= xe or ys >= ye:
        return                                                    # off the picture
    a = alpha[ys - oy:ye - oy, xs - ox:xe - ox, None]
    cover = np.zeros(a.shape[:2], np.float32)
    for bx, by, bw, bh in occluders:
        cx0, cy0, cx1, cy1 = max(int(bx), xs) - xs, max(int(by), ys) - ys, min(int(bx + bw), xe) - xs, min(int(by + bh), ye) - ys
        if cx1 > cx0 and cy1 > cy0:
            cover[cy0:cy1, cx0:cx1] = 1.0
    if cover.any():
        a = a * (1.0 - cv2.GaussianBlur(cover, (0, 0), 2.0))[..., None]
    roi = frame[ys:ye, xs:xe].astype(np.float32)
    if realistic:
        painted = roi * 0.2 + paint * 0.8                         # the road's own texture still shows through the paint
        opacity = 0.95
    else:
        painted, opacity = paint, 0.85
    frame[ys:ye, xs:xe] = np.clip(roi * (1.0 - a * opacity) + painted * (a * opacity), 0, 255).astype(np.uint8)
