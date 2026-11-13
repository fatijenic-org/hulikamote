"""
overlay_objects.py - realistic overlay OBJECTS for the area rules (Illegal parking, Illegal loading).

An operator places an object on the picture (Forensic wizard, or the Live Monitor's saved rules): a fire hydrant, a no-parking sign, a fire
station plate, a driveway plate, a painted kerb at a corner, a no-loading plate. The object stands on a spot of the ground; the AREA that the
rule judges is the box the operator sizes around it (engine/loading_signs.py): it is drawn as a faint tinted patch with a dashed edge, so the
photo shows both the thing and the area it bans.

Like every overlay it is NOT part of the video: it belongs to the analysis, is drawn on the evidence photos and the result video, and nothing
is written into the video file.

Look of an object (wizard form, all optional): `scale` (size, 1.0 = the normal size of that object), `angle` (turned in the picture, degrees
clockwise), `tilt` (turned away from the camera round its upright axis), `stand` for plates: "post" (a pole), "tripod" (a portable stand) or
"none" (the plate rests on the ground). The look is the same as the lane signs' (engine/lane_signs.py): soft edges like the camera's, a
little grain, colours dulled to the light of the scene, a faint sheen and a soft shadow on the road.

Everything is drawn with plain OpenCV shapes: no picture files, no model.
"""
import math
from functools import lru_cache

import cv2
import numpy as np

from engine import lane_signs

STANDS = ("none", "post", "tripod")

RED = (36, 36, 192)             # BGR
DARK_RED = (22, 22, 125)
BLUE = (170, 80, 15)
METAL = (176, 180, 184)
DARK_METAL = (108, 112, 116)
POLE = (150, 152, 155)
WHITE = (245, 245, 245)
BLACK = (30, 30, 30)

# kind -> width of the object at scale 1.0 as a share of the picture's width, what it stands on by default, and the tint of its area
KINDS: dict[str, dict] = {
    "hydrant": {"share": 0.032, "stand": None, "tint": (40, 40, 200), "label": "Fire hydrant"},
    "sign": {"share": 0.045, "stand": "post", "tint": (200, 90, 20), "label": "No-parking sign"},
    "fire_station": {"share": 0.055, "stand": "post", "tint": (40, 40, 200), "label": "Fire station plate"},
    "driveway": {"share": 0.055, "stand": "post", "tint": (0, 190, 255), "label": "Driveway plate"},
    "no_loading": {"share": 0.055, "stand": "post", "tint": (0, 140, 255), "label": "No-loading plate"},
    "corner": {"share": 0.16, "stand": None, "tint": (40, 40, 200), "label": "Painted kerb"},
    "double_parking": {"share": 0.05, "stand": "post", "tint": (40, 40, 200), "label": "No double parking plate"},
    "keep_clear": {"share": 0.05, "stand": "post", "tint": (0, 190, 255), "label": "Keep clear plate", "hatch": True},
    "no_trucks": {"share": 0.05, "stand": "post", "tint": (40, 40, 200), "label": "No trucks sign"},
    "no_tricycles": {"share": 0.05, "stand": "post", "tint": (40, 40, 200), "label": "No tricycles plate"},
    "sidewalk": {"share": 0.05, "stand": "post", "tint": (200, 90, 20), "label": "Sidewalk plate"},
    "stop_sign": {"share": 0.05, "stand": "post", "tint": (40, 40, 200), "label": "Stop sign"},
    "traffic_light_red": {"share": 0.026, "stand": "post", "tint": (40, 40, 200), "label": "Traffic light"},
    "traffic_light_yellow": {"share": 0.026, "stand": "post", "tint": (0, 200, 250), "label": "Traffic light"},
    "traffic_light_green": {"share": 0.026, "stand": "post", "tint": (60, 200, 60), "label": "Traffic light"},
    "traffic_light_off": {"share": 0.026, "stand": "post", "tint": (90, 90, 90), "label": "Traffic light"},
}
DEFAULT_KIND = "sign"
SUPERSAMPLE = 2


def kind_of(kind) -> str:
    return kind if kind in KINDS else DEFAULT_KIND


def look_of(raw: dict, kind: str) -> dict:
    """Size, angle, tilt and stand of an object, kept inside what makes sense. Hydrants and the painted kerb stand alone ("none")."""
    look = lane_signs.look_of(raw if isinstance(raw, dict) else {})
    kind = kind_of(kind)
    default = KINDS[kind]["stand"]
    stand = raw.get("stand") if isinstance(raw, dict) else None
    look["stand"] = "none" if default is None else (stand if stand in STANDS else default)
    return look


# ─── a little canvas: shapes with simple shading, alpha kept ────────────────────────────────

class _Canvas:
    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.bgr = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)

    def _put(self, sl, mask: np.ndarray, img: np.ndarray) -> None:
        m = mask[..., None]
        self.bgr[sl] = self.bgr[sl] * (1.0 - m) + img * m
        self.a[sl] = self.a[sl] + mask * (1.0 - self.a[sl])

    def rect(self, x0: float, y0: float, x1: float, y1: float, colour, shade: str | None = "v", radius: int = 0) -> None:
        x0, x1 = sorted((int(round(x0)), int(round(x1))))
        y0, y1 = sorted((int(round(y0)), int(round(y1))))
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, self.w), min(y1, self.h)
        if x1 - x0 < 1 or y1 - y0 < 1:
            return
        hh, ww = y1 - y0, x1 - x0
        col = np.array(colour, np.float32)
        if shade == "v":                                          # a pole or barrel: bright a little left of the middle
            k = np.clip(0.50 + 0.55 * np.cos((np.linspace(0, 1, ww) - 0.32) * 2.4), 0.35, 1.15)
            img = np.broadcast_to(col * k[None, :, None], (hh, ww, 3))
        elif shade == "h":                                        # a sideways barrel: bright a little above the middle
            k = np.clip(0.50 + 0.55 * np.cos((np.linspace(0, 1, hh) - 0.32) * 2.4), 0.35, 1.15)
            img = np.broadcast_to(col * k[:, None, None], (hh, ww, 3))
        else:
            img = np.broadcast_to(col, (hh, ww, 3))
        mask = np.ones((hh, ww), np.float32)
        if radius > 0:
            m8 = np.zeros((hh, ww), np.uint8)
            lane_signs._rounded(m8, 0, 0, ww - 1, hh - 1, min(radius, hh // 2, ww // 2), 255)
            mask = m8.astype(np.float32) / 255.0
        self._put((slice(y0, y1), slice(x0, x1)), mask, img)

    def disc(self, cx: float, cy: float, r: float, colour, shade: bool = True) -> None:
        r = max(r, 0.5)
        x0, x1 = max(int(cx - r) - 1, 0), min(int(cx + r) + 2, self.w)
        y0, y1 = max(int(cy - r) - 1, 0), min(int(cy + r) + 2, self.h)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        mask = np.clip(r + 0.5 - d, 0.0, 1.0)
        col = np.array(colour, np.float32)
        if shade:                                                 # lit from the top left
            dl = np.sqrt((xx - (cx - 0.35 * r)) ** 2 + (yy - (cy - 0.35 * r)) ** 2) / (1.7 * r)
            img = col * np.clip(1.12 - 0.55 * dl, 0.5, 1.15)[..., None]
        else:
            img = np.broadcast_to(col, mask.shape + (3,))
        self._put((slice(y0, y1), slice(x0, x1)), mask, img)

    def ring(self, cx: float, cy: float, r_out: float, r_in: float, colour) -> None:
        r_out = max(r_out, 0.5)
        x0, x1 = max(int(cx - r_out) - 1, 0), min(int(cx + r_out) + 2, self.w)
        y0, y1 = max(int(cy - r_out) - 1, 0), min(int(cy + r_out) + 2, self.h)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        mask = np.clip(r_out + 0.5 - d, 0.0, 1.0) * np.clip(d - r_in + 0.5, 0.0, 1.0)
        self._put((slice(y0, y1), slice(x0, x1)), mask, np.broadcast_to(np.array(colour, np.float32), mask.shape + (3,)))

    def polygon(self, points, colour) -> None:
        """A flat-coloured polygon (an octagon for the stop sign)."""
        m8 = np.zeros((self.h, self.w), np.uint8)
        cv2.fillPoly(m8, [np.array([[int(round(x)), int(round(y))] for x, y in points], np.int32)], 255, cv2.LINE_AA)
        self._put((slice(0, self.h), slice(0, self.w)), m8.astype(np.float32) / 255.0,
                  np.broadcast_to(np.array(colour, np.float32), (self.h, self.w, 3)))

    def stroke(self, points, colour, thickness: float) -> None:
        """A line through `points` (several = a chain of segments)."""
        m8 = np.zeros((self.h, self.w), np.uint8)
        pts = np.array([[int(round(x)), int(round(y))] for x, y in points], np.int32)
        cv2.polylines(m8, [pts], False, 255, max(1, int(round(thickness))), cv2.LINE_AA)
        mask = m8.astype(np.float32) / 255.0
        self._put((slice(0, self.h), slice(0, self.w)), mask, np.broadcast_to(np.array(colour, np.float32), mask.shape + (3,)))

    def text(self, lines, x0: float, y0: float, x1: float, y1: float, colour, widest_share: float = 0.84, thick_div: int = 70) -> None:
        """The `lines` of text centred in the box, as large as fits."""
        font = cv2.FONT_HERSHEY_SIMPLEX
        bw, bh = x1 - x0, y1 - y0
        thick = max(1, int(self.w / thick_div))
        widest = max(cv2.getTextSize(t, font, 1.0, thick)[0][0] for t in lines)
        line_h = cv2.getTextSize("H", font, 1.0, thick)[0][1]
        scale = min(bw * widest_share / max(widest, 1), (bh / len(lines)) * 0.62 / max(line_h, 1))
        m8 = np.zeros((self.h, self.w), np.uint8)
        gap = bh / len(lines)
        for i, t in enumerate(lines):
            (tw, th), _ = cv2.getTextSize(t, font, scale, thick)
            cv2.putText(m8, t, (int(x0 + (bw - tw) / 2), int(y0 + gap * (i + 0.5) + th / 2)), font, scale, 255, thick, cv2.LINE_AA)
        mask = m8.astype(np.float32) / 255.0
        self._put((slice(0, self.h), slice(0, self.w)), mask, np.broadcast_to(np.array(colour, np.float32), mask.shape + (3,)))

    def result(self) -> tuple[np.ndarray, np.ndarray]:
        return np.clip(self.bgr, 0, 255).astype(np.uint8), np.clip(self.a * 255.0, 0, 255).astype(np.uint8)


# ─── the objects, upright and flat, `w` pixels wide ─────────────────────────────────────────

def _hydrant(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    h = int(w * 1.55)
    c = _Canvas(w, h)
    X = lambda f: f * w
    Y = lambda f: f * h
    for side in (-1, 1):                                          # the two side outlets, with caps
        xo, xi = 0.5 + side * 0.41, 0.5 + side * 0.22
        c.rect(X(min(xo, xi)), Y(0.47), X(max(xo, xi)), Y(0.58), RED, "h")
        c.disc(X(xo), Y(0.525), X(0.075), METAL)
        c.disc(X(xo), Y(0.525), X(0.03), DARK_METAL)
    c.disc(X(0.5), Y(0.19), X(0.19), RED)                        # the dome
    c.rect(X(0.44), Y(0.045), X(0.56), Y(0.10), METAL, "v")       # the operating nut
    c.disc(X(0.5), Y(0.05), X(0.06), METAL)
    c.rect(X(0.31), Y(0.17), X(0.69), Y(0.29), RED, "v")          # the bonnet
    c.rect(X(0.23), Y(0.285), X(0.77), Y(0.33), DARK_RED, "v")
    c.rect(X(0.26), Y(0.32), X(0.74), Y(0.91), RED, "v")          # the barrel
    c.rect(X(0.23), Y(0.855), X(0.77), Y(0.90), DARK_RED, "v")
    c.rect(X(0.15), Y(0.905), X(0.85), Y(1.0), DARK_RED, "v")     # the base flange
    cx, cy = X(0.5), Y(0.63)                                      # the big front outlet
    c.disc(cx, cy, X(0.165), DARK_RED)
    c.disc(cx, cy, X(0.14), RED)
    c.disc(cx, cy, X(0.10), METAL)
    c.disc(cx, cy, X(0.045), DARK_METAL)
    for angle in range(0, 360, 90):                               # four bolts
        c.disc(cx + X(0.075) * math.cos(math.radians(angle + 45)), cy + X(0.075) * math.sin(math.radians(angle + 45)), X(0.012), DARK_METAL, shade=False)
    c.stroke([(X(0.915), Y(0.575)), (X(0.945), Y(0.66)), (X(0.90), Y(0.73)), (X(0.80), Y(0.70))], DARK_METAL, max(1, w * 0.02))    # the chain
    return c.result()


def _stand_under(c: _Canvas, w: int, plate_h: int, stand: str) -> None:
    """The pole or the portable stand under a plate that is `plate_h` high."""
    h = c.h
    if stand == "post":
        c.rect(w * 0.46, plate_h - 2, w * 0.54, h - w * 0.03, POLE, "v")
        c.rect(w * 0.36, h - w * 0.05, w * 0.64, h, DARK_METAL, "v", radius=2)
    elif stand == "tripod":
        mast_end = plate_h + 0.55 * (h - plate_h)
        c.stroke([(w * 0.5, mast_end), (w * 0.14, h - 2)], POLE, w * 0.05)
        c.stroke([(w * 0.5, mast_end), (w * 0.86, h - 2)], POLE, w * 0.05)
        c.stroke([(w * 0.5, mast_end), (w * 0.58, h - 2)], DARK_METAL, w * 0.04)
        c.rect(w * 0.47, plate_h - 2, w * 0.53, mast_end, POLE, "v")


def _plated(w: int, stand: str, plate_h: int, draw_plate) -> tuple[np.ndarray, np.ndarray]:
    pole = 0 if stand == "none" else int(1.5 * w)
    c = _Canvas(w, plate_h + pole)
    _stand_under(c, w, plate_h, stand)
    draw_plate(c, w, plate_h)
    return c.result()


def _no_parking(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    def plate(c: _Canvas, w: int, h: int) -> None:
        cx = cy = w / 2
        c.disc(cx, cy, w * 0.50, WHITE, shade=False)
        c.ring(cx, cy, w * 0.46, w * 0.35, RED)
        c.disc(cx, cy, w * 0.35, BLUE)
        c.text(["P"], cx - w * 0.2, cy - w * 0.2, cx + w * 0.2, cy + w * 0.2, WHITE, widest_share=0.9, thick_div=40)
        d = w * 0.30
        c.stroke([(cx - d, cy - d), (cx + d, cy + d)], RED, w * 0.075)
    return _plated(w, stand, w, plate)


def _rect_plate(w: int, stand: str, face, border, text_colour, lines) -> tuple[np.ndarray, np.ndarray]:
    def plate(c: _Canvas, w: int, h: int) -> None:
        r = max(2, w // 14)
        c.rect(w * 0.02, 0, w * 0.98, h, WHITE, None, radius=r)
        c.rect(w * 0.05, h * 0.06, w * 0.95, h * 0.94, border, None, radius=r)
        c.rect(w * 0.09, h * 0.14, w * 0.91, h * 0.86, face, None, radius=max(2, r // 2))
        c.text(list(lines), w * 0.12, h * 0.17, w * 0.88, h * 0.83, text_colour)
    return _plated(w, stand, int(w * 0.72), plate)


def _fire_station(w: int, stand: str):
    return _rect_plate(w, stand, RED, RED, WHITE, ("FIRE STATION", "NO PARKING"))


def _driveway(w: int, stand: str):
    return _rect_plate(w, stand, WHITE, RED, BLACK, ("PRIVATE", "DRIVEWAY"))


def _no_loading(w: int, stand: str):
    return _rect_plate(w, stand, WHITE, RED, RED, ("NO LOADING", "UNLOADING"))


def _stop_sign(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    def plate(c: _Canvas, w: int, h: int) -> None:
        cx = cy = w / 2

        def octagon(radius: float) -> list[tuple[float, float]]:
            return [(cx + radius * math.cos(math.radians(22.5 + 45 * k)), cy + radius * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
        c.polygon(octagon(w * 0.54), WHITE)
        c.polygon(octagon(w * 0.48), RED)
        c.text(["STOP"], cx - w * 0.38, cy - w * 0.16, cx + w * 0.38, cy + w * 0.16, WHITE, widest_share=0.96, thick_div=26)
    return _plated(w, stand, w, plate)


def _no_trucks(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    def plate(c: _Canvas, w: int, h: int) -> None:
        cx = cy = w / 2
        c.disc(cx, cy, w * 0.50, WHITE, shade=False)
        c.ring(cx, cy, w * 0.46, w * 0.35, RED)
        c.rect(cx - w * 0.27, cy - w * 0.14, cx + w * 0.05, cy + w * 0.10, BLACK, None)            # the load
        c.rect(cx + w * 0.07, cy - w * 0.04, cx + w * 0.24, cy + w * 0.10, BLACK, None)            # the cab
        c.disc(cx - w * 0.15, cy + w * 0.13, w * 0.055, BLACK, shade=False)
        c.disc(cx + w * 0.14, cy + w * 0.13, w * 0.055, BLACK, shade=False)
        d = w * 0.30
        c.stroke([(cx - d, cy - d), (cx + d, cy + d)], RED, w * 0.075)
    return _plated(w, stand, w, plate)


def _traffic_light(state: str):
    on = {"red": (40, 40, 235), "yellow": (30, 200, 250), "green": (70, 205, 60)}
    off = {"red": (20, 20, 75), "yellow": (20, 65, 75), "green": (25, 75, 25)}

    def draw(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
        h = int(w * 2.9)
        c = _Canvas(w, h + (0 if stand == "none" else int(1.6 * w)))
        _stand_under(c, w, h, stand)
        c.rect(w * 0.05, 0, w * 0.95, h, (34, 36, 38), None, radius=max(2, w // 8))
        c.rect(w * 0.02, h * 0.02, w * 0.98, h * 0.98, (150, 152, 155), None, radius=max(2, w // 8))        # a light rim round the housing
        c.rect(w * 0.07, h * 0.03, w * 0.93, h * 0.97, (34, 36, 38), None, radius=max(2, w // 9))
        for k, colour in enumerate(("red", "yellow", "green")):
            cx, cy = w / 2, h * (0.18 + k * 0.32)
            c.disc(cx, cy, w * 0.37, (12, 12, 14), shade=False)                                       # the lamp well
            c.disc(cx, cy, w * 0.31, on[colour] if colour == state else off[colour])
            if colour == state:
                c.disc(cx - w * 0.07, cy - w * 0.09, w * 0.10, (225, 235, 245), shade=False)           # the lit glass
            c.rect(cx - w * 0.40, cy - w * 0.45, cx + w * 0.40, cy - w * 0.34, (18, 18, 20), "h")      # the visor above the lamp
        return c.result()
    return draw


def _stand_only(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    """Just the pole or the tripod, for a board that is drawn on top of it."""
    c = _Canvas(w, int(1.5 * w))
    _stand_under(c, w, 0, stand)
    return c.result()


def _corner(w: int, stand: str) -> tuple[np.ndarray, np.ndarray]:
    """A kerb painted in red and white blocks, lying along the road."""
    h = max(6, int(w * 0.13))
    c = _Canvas(w, h)
    blocks = 8
    for i in range(blocks):
        c.rect(i * w / blocks, 0, (i + 1) * w / blocks, h, RED if i % 2 == 0 else WHITE, None)
    c.rect(0, h * 0.82, w, h, DARK_RED, None)                     # the kerb face in shade
    return c.result()


_FLAT = {
    "hydrant": _hydrant, "sign": _no_parking, "fire_station": _fire_station, "driveway": _driveway, "no_loading": _no_loading, "corner": _corner,
    "double_parking": lambda w, s: _rect_plate(w, s, WHITE, RED, BLACK, ("NO DOUBLE", "PARKING")),
    "keep_clear": lambda w, s: _rect_plate(w, s, (40, 200, 245), BLACK, BLACK, ("KEEP", "CLEAR")),
    "no_trucks": _no_trucks,
    "stop_sign": _stop_sign,
    "no_tricycles": lambda w, s: _rect_plate(w, s, WHITE, RED, RED, ("NO", "TRICYCLES")),
    "sidewalk": lambda w, s: _rect_plate(w, s, WHITE, BLUE, BLUE, ("NO VEHICLES", "SIDEWALK")),
    "traffic_light_red": _traffic_light("red"), "traffic_light_yellow": _traffic_light("yellow"),
    "traffic_light_green": _traffic_light("green"), "traffic_light_off": _traffic_light("off"),
    "stand_only": _stand_only,
}


def object_width(frame_width: int, kind: str, scale: float = 1.0) -> int:
    """The object's width in pixels of a picture that is `frame_width` wide."""
    share = KINDS[kind_of(kind)]["share"]
    return int(round(max(24.0, frame_width * share) * max(lane_signs.MIN_SCALE, min(lane_signs.MAX_SCALE, scale))))


def object_corners(w: float, h: float, angle: float = 0.0, tilt: float = 0.0) -> list[tuple[float, float]]:
    """The four corners (top-left, top-right, bottom-right, bottom-left) of an object `w` x `h` large, relative to the spot of ground it
    stands on (the middle of its bottom edge). `tilt` turns it round its upright axis (the far edge gets smaller), `angle` turns it in the
    picture (clockwise)."""
    yaw, roll = math.radians(tilt), math.radians(angle)
    distance = 3.0 * w
    out = []
    for sx, sy in ((-0.5, -1.0), (0.5, -1.0), (0.5, 0.0), (-0.5, 0.0)):
        x, y = sx * w, sy * h
        shrink = distance / (distance + x * math.sin(yaw))
        x, y = x * math.cos(yaw) * shrink, y * shrink
        out.append((x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll)))
    return out


@lru_cache(maxsize=96)
def _sprite(kind: str, width: int, angle: float, tilt: float, stand: str, realistic: bool, light: int):
    bgr, alpha = _FLAT[kind](width * SUPERSAMPLE, stand)
    display_h = alpha.shape[0] / SUPERSAMPLE
    return lane_signs.finish_sprite(bgr, alpha, object_corners(width, display_h, angle, tilt), width, realistic, light)


def _sprite_for(kind: str, frame_width: int, look: dict, realistic: bool, light: int):
    kind = kind_of(kind)
    width = object_width(frame_width, kind, look["scale"])
    return _sprite(kind, width, round(look["angle"] * 2) / 2, round(look["tilt"] * 2) / 2, look["stand"], bool(realistic), light)


def draw_object(frame: np.ndarray, at, kind: str, look: dict | None = None, realistic: bool = True) -> None:
    """The object standing on `at` (frame pixels). Changes `frame`."""
    kind = kind_of(kind)
    look = look_of(look or {}, kind)
    lane_signs.blend(frame, _sprite_for(kind, frame.shape[1], look, realistic, lane_signs._light_of(frame)), at)


def draw_area(frame: np.ndarray, polygon, kind: str, realistic: bool = True) -> None:
    """The area the rule judges: a faint patch of the object's tint with a dashed edge. Changes `frame`."""
    pts = np.asarray(polygon, dtype=np.float32)
    if pts.ndim != 2 or len(pts) < 3:
        return
    fh, fw = frame.shape[:2]
    x0, y0 = np.floor(pts.min(axis=0)).astype(int)
    x1, y1 = np.ceil(pts.max(axis=0)).astype(int)
    cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x1, fw), min(y1, fh)
    if cx1 - cx0 < 2 or cy1 - cy0 < 2:
        return
    local = (pts - np.float32([cx0, cy0])).astype(np.int32)
    roi = frame[cy0:cy1, cx0:cx1]
    tinted = roi.copy()
    cv2.fillPoly(tinted, [local], KINDS[kind_of(kind)]["tint"])
    share = 0.10 if realistic else 0.18
    roi[:] = cv2.addWeighted(tinted, share, roi, 1.0 - share, 0)
    if KINDS[kind_of(kind)].get("hatch"):                         # a yellow box junction: diagonal hatching inside the area
        lines = np.zeros_like(roi)
        step = max(10, int(fw * 0.02))
        for k in range(-roi.shape[0], roi.shape[1], step):
            cv2.line(lines, (k, 0), (k + roi.shape[0], roi.shape[0]), (40, 200, 245), max(1, fh // 300), cv2.LINE_AA)
        inside = np.zeros(roi.shape[:2], np.uint8)
        cv2.fillPoly(inside, [local], 255)
        hatched = (inside > 0) & lines.any(axis=2)
        roi[hatched] = (roi[hatched] * 0.35 + lines[hatched] * 0.65).astype(np.uint8)
    dash = max(6, int(fw * 0.010))
    thick = max(1, fh // 400)
    ring = np.vstack([local, local[:1]]).astype(np.float32)
    for a, b in zip(ring[:-1], ring[1:]):
        length = float(np.hypot(*(b - a)))
        if length < 1:
            continue
        for s in np.arange(0.0, length, dash * 2):
            e = min(s + dash, length)
            p, q = a + (b - a) * (s / length), a + (b - a) * (e / length)
            cv2.line(roi, (int(p[0]), int(p[1])), (int(q[0]), int(q[1])), (235, 235, 235), thick, cv2.LINE_AA)


def draw_stand(frame: np.ndarray, ground, width: int, stand: str, realistic: bool = True) -> None:
    """A pole or tripod standing on `ground` (frame pixels), `width` wide, for a board drawn on top of it (the lane signs)."""
    if stand not in ("post", "tripod"):
        return
    lane_signs.blend(frame, _sprite("stand_only", int(width), 0.0, 0.0, stand, bool(realistic), lane_signs._light_of(frame)), ground)


def draw_traffic_light(frame: np.ndarray, state: str, seconds_left, slot: int = 0, box=None, realistic: bool = True) -> None:
    """The simulated traffic light of the red light rule, as a real-looking light with the lit lamp, a countdown and the word SIM.
    With a `box` (the two corners the operator drew round the light) it stands there on a pole; without one it hangs in the top-right
    corner, `slot` stacking several lights side by side. Changes `frame`."""
    kind = f"traffic_light_{state if state in ('red', 'yellow', 'green') else 'off'}"
    fh, fw = frame.shape[:2]
    if box:
        (x1, y1), (x2, y2) = box
        top, bottom = min(float(y1), float(y2)), max(float(y1), float(y2))
        look = look_of({"scale": max(8.0, (bottom - top) / 2.9) / max(24.0, fw * KINDS[kind]["share"])}, kind)   # the box is the housing
        width = object_width(fw, kind, look["scale"])
        draw_object(frame, ((float(x1) + float(x2)) / 2, bottom + 1.6 * width), kind, look, realistic)          # its pole goes down from the box
        label_at = (int(max(float(x1), float(x2)) + 0.5 * width), int(top + width))
    else:
        width = object_width(fw, kind, 1.0)
        pad = max(4, fh // 80)
        at = (fw - (slot + 0.9) * 1.8 * width, pad + 2.9 * width)
        draw_object(frame, at, kind, {"stand": "none"}, realistic)
        label_at = (int(at[0] - width / 2), int(at[1] + 0.9 * width))
    label = f"{int(seconds_left) + 1}s" if (seconds_left is not None and state in ("red", "yellow", "green")) else "--"
    scale = max(0.4, width / 36.0)
    cv2.putText(frame, label, label_at, cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), max(1, int(scale * 1.5)), cv2.LINE_AA)
    cv2.putText(frame, "SIM", (label_at[0], label_at[1] + int(26 * scale)), cv2.FONT_HERSHEY_SIMPLEX, scale * 0.7, (190, 190, 190), 1, cv2.LINE_AA)


def zone_fields(sign: dict, kind: str, cfg: dict) -> dict:
    """What a box zone carries so that it can be drawn as an object: where the object stands (the middle of the box, in the 1920x1080
    reference space, scaled like the zone's own points), its look, and whether it looks filmed."""
    return {"sign_points": [[sign.get("ax", sign["x"]), sign.get("ay", sign["y"])]], "look": look_of(sign, kind),
            "realistic": bool(cfg.get("signs_realistic", True))}


def parsed_fields(raw: dict, polygon, kind: str) -> dict:
    """The same fields read back from a saved zone (older ones without them: the object stands in the middle of the box)."""
    points = raw.get("sign_points")
    if not points:
        pts = np.asarray(polygon, dtype=np.float32)
        points = [[float(pts[:, 0].mean()), float(pts[:, 1].mean())]]
    return {"sign_points": [[float(points[0][0]), float(points[0][1])]], "look": look_of(raw.get("look") or {}, kind),
            "realistic": bool(raw.get("realistic", True))}


def draw_zone_object(frame: np.ndarray, zone: dict, kind: str) -> None:
    """A box zone on the picture: its area (faint patch, dashed edge) and the object standing in it."""
    realistic = zone.get("realistic", True)
    draw_area(frame, zone["polygon"], kind, realistic)
    points = zone.get("sign_points")
    if points:
        draw_object(frame, points[0], kind, zone.get("look"), realistic)


def preview(kind: str, scale: float = 1.0, angle: float = 0.0, tilt: float = 0.0, stand: str | None = None, realistic: bool = True,
            frame_width: int = 1920, light: int = 2) -> tuple[bytes, int, int]:
    """The object as a PNG with see-through parts, and where its top-left pixel sits relative to the spot it stands on (pixels of a picture
    `frame_width` wide). The wizard draws this on the first frame so that what is placed looks like what the photos will show."""
    kind = kind_of(kind)
    look = look_of({"scale": scale, "angle": angle, "tilt": tilt, "stand": stand}, kind)
    face, cover, shadow, ox, oy = _sprite_for(kind, frame_width, look, realistic, light)
    alpha = np.clip(cover + shadow * (1.0 - cover), 0.0, 1.0)
    colour = face * cover[..., None] / np.maximum(alpha, 1e-3)[..., None]
    rgba = np.dstack([np.clip(colour, 0, 255), alpha * 255.0]).astype(np.uint8)
    ok, png = cv2.imencode(".png", rgba)
    return bytes(png.tobytes()) if ok else b"", int(ox), int(oy)
