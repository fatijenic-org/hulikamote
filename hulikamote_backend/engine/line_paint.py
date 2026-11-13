"""
line_paint.py - road paint laid on the picture as an overlay: the solid line of "Crossing a solid line" (testing).

An operator who wants to test the rule on a video that has no (or faded) paint saves a line and switches on "Paint it": the line is then drawn
like paint on the road, along the same points the rule judges, so what the photos show is what the rule checks. It is NOT part of the video:
it belongs to the analysis, is drawn on the evidence photos and the result video, and nothing is written into the video file.

Look of a line (wizard form, all optional):
  style   "solid_white", "solid_yellow", "double_yellow" (two lines side by side) or "dashed_white"
  width   0.4 .. 3, 1.0 = normal paint (0.7% of the picture's width where the road is nearest)
  wear    0 .. 1, paint rubbed off in patches and chips
  taper   0 .. 1, how much thinner the paint gets farther up the picture (road perspective); 0 = same width all along
The turn of the line is its points: the wizard rotates / bends them. Realistic (on by default, `lines_realistic`): soft edges like the camera's,
a little grain, paint dulled to the light of the scene, the road's own texture showing through. Vehicles and people are drawn ON TOP of the
paint (it is on the road).
"""
import math
from functools import lru_cache

import cv2
import numpy as np

REF = (1920, 1080)
STYLES = ("solid_white", "solid_yellow", "double_yellow", "dashed_white")
DEFAULTS = {"style": "solid_yellow", "width": 1.0, "wear": 0.2, "taper": 0.6}
MIN_WIDTH, MAX_WIDTH = 0.4, 3.0
BASE_SHARE = 0.0070                  # paint width where the road is nearest, as a share of the picture's width, at width 1.0
SUPERSAMPLE = 2
WHITE = (238.0, 240.0, 240.0)        # BGR
YELLOW = (45.0, 185.0, 235.0)
OCCLUDES = ("car", "motorcycle", "bus", "truck", "tricycle", "bicycle", "person")


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def look_of(raw) -> dict:
    """The look of a line, kept inside what makes sense; anything missing or wrong is the default."""
    raw = raw if isinstance(raw, dict) else {}

    def number(key: str) -> float:
        try:
            value = float(raw.get(key, DEFAULTS[key]))
        except (TypeError, ValueError):
            return float(DEFAULTS[key])
        return value if math.isfinite(value) else float(DEFAULTS[key])

    style = raw.get("style") if raw.get("style") in STYLES else DEFAULTS["style"]
    return {"style": style, "width": _clamp(number("width"), MIN_WIDTH, MAX_WIDTH), "wear": _clamp(number("wear"), 0.0, 1.0),
            "taper": _clamp(number("taper"), 0.0, 1.0)}


def usable_line(raw) -> list[list[float]] | None:
    """The points of a line (two or more, finite), or None."""
    try:
        points = [[float(p[0]), float(p[1])] for p in raw]
    except (TypeError, ValueError, IndexError, KeyError):
        return None
    if len(points) < 2 or not all(math.isfinite(v) for p in points for v in p):
        return None
    return points


def _light_of(frame: np.ndarray) -> int:
    return int(min(3, frame[::16, ::16].mean() / 64.0))


def _samples(points: list[tuple[float, float]], step: float = 2.0) -> list[tuple[float, float, float, float, float]]:
    """Points every ~`step` pixels along the line with the direction there: (x, y, dx, dy, piece length)."""
    out = []
    for (x0, y0), (x1, y1) in zip(points[:-1], points[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        if length < 1e-6:
            continue
        dx, dy = (x1 - x0) / length, (y1 - y0) / length
        n = max(1, int(length / step))
        for k in range(n):
            t = k / n
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, dx, dy, length / n))
    x, y = points[-1]
    if out:
        out.append((x, y, out[-1][2], out[-1][3], 0.0))
    return out


@lru_cache(maxsize=32)
def _layer(points: tuple, style: str, width: float, wear: float, taper: float, realistic: bool, light: int, fw: int, fh: int):
    """The paint as it is laid on the picture: (alpha 0..1, paint colour BGR, x offset, y offset) or None. Cached: the same line is drawn on
    every frame of the video."""
    pts = [(points[i], points[i + 1]) for i in range(0, len(points), 2)]
    base = max(1.5, BASE_SHARE * fw * width)
    pad = int(base * 4) + 8
    x0, y0 = int(math.floor(min(p[0] for p in pts))) - pad, int(math.floor(min(p[1] for p in pts))) - pad
    x1, y1 = int(math.ceil(max(p[0] for p in pts))) + pad, int(math.ceil(max(p[1] for p in pts))) + pad
    x0, y0, x1, y1 = max(x0, -pad), max(y0, -pad), min(x1, fw + pad), min(y1, fh + pad)
    w, h = x1 - x0, y1 - y0
    if w < 4 or h < 4 or w * h > 6_000_000:
        return None
    ss = SUPERSAMPLE
    mask = np.zeros((h * ss, w * ss), np.uint8)

    def thickness(y: float) -> float:
        near = _clamp(y / max(fh, 1), 0.0, 1.2)
        return max(1.0, base * (1.0 - taper + taper * _clamp(0.25 + 0.75 * near, 0.25, 1.2)))

    def at(x: float, y: float) -> tuple[int, int]:
        return int(round((x - x0) * ss)), int(round((y - y0) * ss))

    samples = _samples([(float(a), float(b)) for a, b in pts])
    run = 0.0                                                     # length along the line in units of the local paint width (dashes keep their perspective)
    previous = None
    for x, y, dx, dy, ds in samples:
        t = thickness(y)
        if previous is not None:
            px, py, pt = previous
            on = True
            if style == "dashed_white":
                on = (run % 18.0) < 8.0
            if on:
                if style == "double_yellow":
                    gap = 1.7 * t
                    for side in (-1, 1):
                        nx, ny = -dy * side * gap / 2, dx * side * gap / 2
                        cv2.line(mask, at(px + nx, py + ny), at(x + nx, y + ny), 255, max(1, int(round(0.7 * t * ss))), cv2.LINE_AA)
                else:
                    cv2.line(mask, at(px, py), at(x, y), 255, max(1, int(round(t * ss))), cv2.LINE_AA)
        run += ds / max(t, 1.0)
        previous = (x, y, t)
    alpha = cv2.resize(mask, (w, h), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    rng = np.random.RandomState(23 + int(width * 10))
    if wear > 0:                                                  # patches where the paint has gone, and fine chips
        low = cv2.GaussianBlur(rng.rand(h, w).astype(np.float32), (0, 0), max(2.0, base * 1.5))
        spread = max(float(low.std()), 1e-6)
        patches = np.clip((low - float(np.quantile(low, 1.0 - 0.5 * wear))) / (0.5 * spread), 0.0, 1.0)     # up to half of the paint is gone in patches
        chips = (rng.rand(h, w) > 1.0 - 0.16 * wear).astype(np.float32)
        alpha *= 1.0 - 0.92 * patches
        alpha *= 1.0 - 0.75 * chips
    colour = np.array(YELLOW if style in ("solid_yellow", "double_yellow") else WHITE, np.float32)
    if realistic:
        alpha = cv2.GaussianBlur(alpha, (0, 0), 0.7)
        alpha += rng.normal(0.0, 0.03, alpha.shape).astype(np.float32) * (alpha > 0.02)
        alpha = np.clip(alpha, 0.0, 1.0)
        colour = colour * (0.78 + 0.22 * light / 3.0)             # dull scene = dull paint
    return alpha, colour, x0, y0


def _key(points) -> tuple | None:
    line = usable_line(points)
    return None if line is None else tuple(int(round(v)) for p in line for v in p)


def draw(frame: np.ndarray, points, look: dict | None = None, realistic: bool = True, occluders=()) -> None:
    """The line painted on the picture along `points` (frame pixels). Changes `frame`.
    `occluders` are boxes [x, y, w, h] of vehicles and people: the paint is on the road, so it goes UNDER them (soft edge)."""
    key = _key(points)
    if key is None:
        return
    look = look_of(look)
    fh, fw = frame.shape[:2]
    layer = _layer(key, look["style"], round(look["width"], 2), round(look["wear"], 2), round(look["taper"], 2), bool(realistic),
                   _light_of(frame), fw, fh)
    if layer is None:
        return
    alpha, colour, ox, oy = layer
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
        painted, opacity = roi * 0.2 + colour * 0.8, 0.95          # the road's own texture still shows through the paint
    else:
        painted, opacity = colour, 0.9
    frame[ys:ye, xs:xe] = np.clip(roi * (1.0 - a * opacity) + painted * (a * opacity), 0, 255).astype(np.uint8)


def preview(points, look: dict | None = None, realistic: bool = True, frame_size: tuple[int, int] = REF, light: int = 2) -> tuple[bytes, int, int]:
    """The paint as a PNG with see-through parts (cropped to the line) and where its top-left pixel sits on a picture of `frame_size`. The
    wizard draws this on the first frame, so what is set looks like what the photos will show. Empty when the line is not usable."""
    key = _key(points)
    if key is None:
        return b"", 0, 0
    look = look_of(look)
    fw, fh = frame_size
    layer = _layer(key, look["style"], round(look["width"], 2), round(look["wear"], 2), round(look["taper"], 2), bool(realistic), light, fw, fh)
    if layer is None:
        return b"", 0, 0
    alpha, colour, ox, oy = layer
    opacity = 0.95 if realistic else 0.9
    rgba = np.dstack([np.broadcast_to(colour, alpha.shape + (3,)), alpha * opacity * 255.0]).astype(np.uint8)
    ok, png = cv2.imencode(".png", rgba)
    return (bytes(png.tobytes()) if ok else b""), int(ox), int(oy)
