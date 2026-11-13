"""
lane_signs.py - the overlay signs of "Restricted lane".

A sign is placed by the operator on a spot of a road in the picture (Forensic wizard, or the Live Monitor's saved rules). It is NOT
part of the video: it is an overlay that belongs to the analysis, drawn on the evidence photos and the result video, and it says who
may use the road it stands on. Nothing is written into the video file and removing the sign (or starting a new analysis) removes it.

  zone drawn         a sign inside a zone sets who may use that zone (several signs in one zone: all of what they allow)
  nothing drawn      the whole picture is the lane; with one sign it follows that sign, with several each vehicle follows the NEAREST
                     sign (so two roads in one picture can have different signs); without any sign it follows the tick boxes
Wizard form of a sign: {"type": key of SIGNS, "x": ..., "y": ..., "scale": 1.0, "angle": 0.0, "tilt": 0.0} in the 1920x1080 reference space
the wizard draws in. `scale` is the size (1.0 = 8.5% of the picture's width), `angle` turns the sign in the picture (degrees, clockwise) and
`tilt` turns it away from the camera round its upright axis (degrees; positive = the right edge is farther), so a sign can look like it
stands at the roadside at the angle the camera sees it.

Realistic look (on by default, `signs_realistic` in the wizard settings): the sign is drawn like it was filmed, not like a sticker: soft edges
like the camera's, a little grain, colours dulled to the light of the scene, a faint sheen and a soft shadow on the road. It is still an
overlay and still obviously a sign; the look is for photos and video that read as one scene.
"""
import math
from functools import lru_cache

import cv2
import numpy as np

REF = (1920, 1080)
VEHICLE_TYPES = ("bus", "jeepney", "motorcycle", "car", "truck", "tricycle", "bicycle")

SIZE_SHARE = 0.085              # width of a sign at scale 1.0, as a share of the picture's width
HEIGHT_RATIO = 0.62
MIN_SCALE, MAX_SCALE = 0.3, 3.0
MAX_ANGLE = 90.0
MAX_TILT = 70.0


def _all_but(*banned: str) -> list[str]:
    return [t for t in VEHICLE_TYPES if t not in banned]


# key -> the two lines written on the sign, and the vehicle types that MAY use the road (the others are flagged)
SIGNS: dict[str, dict] = {
    "bus_only": {"lines": ("BUS", "LANE"), "allowed": ["bus"]},
    "puv_only": {"lines": ("PUV", "ONLY"), "allowed": ["bus", "jeepney"]},
    "motorcycle_only": {"lines": ("MOTORCYCLE", "LANE"), "allowed": ["motorcycle"]},
    "bicycle_only": {"lines": ("BIKE", "LANE"), "allowed": ["bicycle"]},
    "no_trucks": {"lines": ("NO", "TRUCKS"), "allowed": _all_but("truck")},
    "no_tricycles": {"lines": ("NO", "TRICYCLES"), "allowed": _all_but("tricycle")},
    "no_motorcycles": {"lines": ("NO", "MOTORCYCLES"), "allowed": _all_but("motorcycle")},
}

SIGN_BLUE = (150, 70, 10)       # BGR: a regulatory blue


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def look_of(raw: dict) -> dict:
    """The size, angle and tilt of a sign (wizard form), kept inside what makes sense; missing = a plain upright sign of normal size."""
    def number(key: str, default: float) -> float:
        try:
            value = float(raw.get(key, default))
        except (TypeError, ValueError):
            return default
        return value if math.isfinite(value) else default
    return {"scale": _clamp(number("scale", 1.0), MIN_SCALE, MAX_SCALE),
            "angle": _clamp(number("angle", 0.0), -MAX_ANGLE, MAX_ANGLE),
            "tilt": _clamp(number("tilt", 0.0), -MAX_TILT, MAX_TILT)}


def usable_signs(raw) -> list[dict]:
    """The signs of the wizard settings that make sense: a known type and a position (plus their look). Anything else is skipped."""
    signs = []
    for s in raw or []:
        try:
            if s.get("type") in SIGNS:
                sign = {"type": s["type"], "x": float(s["x"]), "y": float(s["y"]), **look_of(s)}
                if s.get("stand") in ("none", "post", "tripod"):
                    sign["stand"] = s["stand"]                    # what the board is mounted on (engine/overlay_objects.py)
                signs.append(sign)
        except (AttributeError, KeyError, TypeError, ValueError):
            continue
    return signs


def allowed_by(types) -> list[str]:
    """Everything the given signs allow together (in the order of VEHICLE_TYPES)."""
    allowed = {t for key in types for t in SIGNS[key]["allowed"]}
    return [t for t in VEHICLE_TYPES if t in allowed]


# ─── drawing ────────────────────────────────────────────────────────────────

def sign_width(frame_width: int, scale: float = 1.0) -> float:
    """The sign's width in pixels of a picture that is `frame_width` wide."""
    return max(96.0, frame_width * SIZE_SHARE) * _clamp(scale, MIN_SCALE, MAX_SCALE)


def sign_corners(width: float, angle: float = 0.0, tilt: float = 0.0) -> list[tuple[float, float]]:
    """The four corners (top-left, top-right, bottom-right, bottom-left) of a sign `width` wide, relative to the spot it stands on.
    `tilt` turns it round its upright axis (the far edge gets smaller), then `angle` turns it in the picture (clockwise)."""
    w, h = width, width * HEIGHT_RATIO
    yaw, roll = math.radians(tilt), math.radians(angle)
    distance = 3.0 * w                                            # how far the camera is: a gentle perspective
    corners = []
    for sx, sy in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
        x, y = sx * w, sy * h
        shrink = distance / (distance + x * math.sin(yaw))        # the right edge is farther for a positive tilt
        x, y = x * math.cos(yaw) * shrink, y * shrink
        corners.append((x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll)))
    return corners


def _rounded(img: np.ndarray, x0: int, y0: int, x1: int, y1: int, radius: int, colour) -> None:
    cv2.rectangle(img, (x0 + radius, y0), (x1 - radius, y1), colour, -1)
    cv2.rectangle(img, (x0, y0 + radius), (x1, y1 - radius), colour, -1)
    for cx, cy in ((x0 + radius, y0 + radius), (x1 - radius, y0 + radius), (x0 + radius, y1 - radius), (x1 - radius, y1 - radius)):
        cv2.circle(img, (cx, cy), radius, colour, -1, cv2.LINE_AA)


def _flat_sign(sign_type: str, width: int, supersample: int = 2) -> tuple[np.ndarray, np.ndarray]:
    """The sign face, upright and flat, `supersample` times larger than it will be shown: (BGR, alpha)."""
    spec = SIGNS[sign_type]
    w, h = width * supersample, int(width * HEIGHT_RATIO) * supersample
    bgr = np.zeros((h, w, 3), np.uint8)
    alpha = np.zeros((h, w), np.uint8)
    radius = max(2, w // 22)
    _rounded(alpha, 0, 0, w - 1, h - 1, radius, 255)
    _rounded(bgr, 0, 0, w - 1, h - 1, radius, SIGN_BLUE)
    border = max(2, w // 40)
    inner = max(border * 2, w // 28)
    cv2.rectangle(bgr, (inner, inner), (w - 1 - inner, h - 1 - inner), (255, 255, 255), border, cv2.LINE_AA)
    font, thick = cv2.FONT_HERSHEY_SIMPLEX, max(1, w // 70)
    widest = max(cv2.getTextSize(line, font, 1.0, thick)[0][0] for line in spec["lines"])
    scale = (w * 0.8) / max(widest, 1)
    for line, baseline in zip(spec["lines"], (0.46, 0.86)):
        (tw, _th), _ = cv2.getTextSize(line, font, scale, thick)
        cv2.putText(bgr, line, ((w - tw) // 2, int(h * baseline)), font, scale, (255, 255, 255), thick, cv2.LINE_AA)
    return bgr, alpha


@lru_cache(maxsize=96)
def _sprite(sign_type: str, width: int, angle: float, tilt: float, realistic: bool, light: int):
    """The finished sign as it is laid on the picture: (BGR float32, alpha 0..1, shadow 0..1, x offset, y offset), the offsets being where
    the top-left pixel sits relative to the spot the sign stands on. Cached: the same sign is drawn on every frame of the video."""
    bgr, alpha = _flat_sign(sign_type, width)
    return finish_sprite(bgr, alpha, sign_corners(width, angle, tilt), width, realistic, light)


def finish_sprite(bgr: np.ndarray, alpha: np.ndarray, corners, width: int, realistic: bool, light: int):
    """Lays a flat, upright picture of an object (BGR + alpha, drawn larger than it will be shown) on the four `corners` (relative to the spot
    it stands on) and gives it the look of a filmed object when `realistic`. Shared by the signs and the other overlay objects
    (engine/overlay_objects.py). Returns (BGR float32, alpha 0..1, shadow 0..1, x offset, y offset)."""
    corners = np.float32(corners)
    pad = int(0.14 * width) + 4                                   # room for the soft edge and the shadow
    low, high = corners.min(axis=0), corners.max(axis=0)
    out_w, out_h = int(math.ceil(high[0] - low[0])) + 2 * pad, int(math.ceil(high[1] - low[1])) + 2 * pad
    target = corners - low + pad
    fh, fw = bgr.shape[:2]
    matrix = cv2.getPerspectiveTransform(np.float32([[0, 0], [fw, 0], [fw, fh], [0, fh]]), target)
    face = cv2.warpPerspective(bgr, matrix, (out_w, out_h), flags=cv2.INTER_LINEAR).astype(np.float32)
    cover = cv2.warpPerspective(alpha, matrix, (out_w, out_h), flags=cv2.INTER_LINEAR).astype(np.float32) / 255.0
    shadow = np.zeros_like(cover)
    if realistic:
        sigma = max(0.7, width * 0.005)                           # as soft as the camera's own picture
        face = cv2.GaussianBlur(face, (0, 0), sigma)
        cover = cv2.GaussianBlur(cover, (0, 0), sigma * 0.6)
        grey = face.mean(axis=2, keepdims=True)
        face = grey + 0.86 * (face - grey)                        # a little less colourful, like real paint in daylight
        face *= 0.66 + 0.40 * (light / 3.0)                       # dull scene = dull sign
        yy, xx = np.mgrid[0:out_h, 0:out_w].astype(np.float32)
        face *= (1.07 - 0.14 * (xx / max(out_w, 1) * 0.5 + yy / max(out_h, 1) * 0.5))[..., None]     # a faint sheen from the top left
        noise = np.random.RandomState(7 + width).normal(0.0, 4.0, (out_h, out_w)).astype(np.float32)   # a little grain, the same on every frame
        face = np.clip(face + noise[..., None], 0, 255)
        shift = np.float32([[1, 0, 0.045 * width], [0, 1, 0.07 * width]])
        shadow = cv2.GaussianBlur(cv2.warpAffine(cover, shift, (out_w, out_h)), (0, 0), max(1.0, 0.03 * width)) * 0.38
    return face, cover, shadow, int(math.floor(low[0])) - pad, int(math.floor(low[1])) - pad


def _light_of(frame: np.ndarray) -> int:
    """How bright the scene is, 0 (dark) to 3 (bright); from a coarse look at the whole picture, so it hardly changes from frame to frame."""
    return int(min(3, frame[::16, ::16].mean() / 64.0))


def look_with_stand(sign: dict) -> dict:
    """The look of a sign as the wizard sent it: size, angle, tilt, and the stand when one was chosen."""
    return {k: sign[k] for k in ("scale", "angle", "tilt", "stand") if k in sign}


def draw_sign(frame: np.ndarray, at, sign_type: str, scale: float = 1.0, angle: float = 0.0, tilt: float = 0.0, realistic: bool = True,
              stand: str = "none") -> None:
    """The sign on the picture, its middle on `at` (frame pixels): sized by `scale`, turned by `angle`, turned away by `tilt`, on a pole or
    a tripod when `stand` says so (the stand goes down from the board to the ground). Changes `frame`."""
    if sign_type not in SIGNS:
        return
    look = look_of({"scale": scale, "angle": angle, "tilt": tilt})
    fh, fw = frame.shape[:2]
    width = int(round(sign_width(fw, look["scale"])))
    if stand in ("post", "tripod"):
        from engine import overlay_objects                              # imported here: overlay_objects uses this module
        overlay_objects.draw_stand(frame, (at[0], at[1] + 0.5 * width * HEIGHT_RATIO + 1.5 * width), width, stand, realistic)
    blend(frame, _sprite(sign_type, width, round(look["angle"] * 2) / 2, round(look["tilt"] * 2) / 2, bool(realistic), _light_of(frame)), at)


def blend(frame: np.ndarray, sprite, at) -> None:
    """Lays a finished sprite (see finish_sprite) on the picture, standing on `at` (frame pixels). Changes `frame`."""
    face, cover, shadow, ox, oy = sprite
    fh, fw = frame.shape[:2]
    x0, y0 = int(round(at[0])) + ox, int(round(at[1])) + oy
    h, w = cover.shape
    xs, ys, xe, ye = max(x0, 0), max(y0, 0), min(x0 + w, fw), min(y0 + h, fh)
    if xs >= xe or ys >= ye:
        return                                                    # off the picture
    sx, sy = xs - x0, ys - y0
    ex, ey = sx + (xe - xs), sy + (ye - ys)
    roi = frame[ys:ye, xs:xe].astype(np.float32)
    roi *= (1.0 - shadow[sy:ey, sx:ex])[..., None]
    a = cover[sy:ey, sx:ex, None]
    frame[ys:ye, xs:xe] = np.clip(roi * (1.0 - a) + face[sy:ey, sx:ex] * a, 0, 255).astype(np.uint8)
