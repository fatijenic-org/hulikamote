"""
traffic_light.py — Light colour helpers: the traffic light (red-light rule) and
vehicle turn indicators (signal-light rule, see amber_fraction / is_blinking).

Two sources, chosen per zone in the wizard:
  - "camera": read the lit colour inside a box the operator drew around the light.
  - "timer":  the operator enters the light cycle (when red starts in the video,
              and how long red / green / yellow last). Meant for recorded footage,
              where the video time is known.
States: "red", "yellow", "green", "unknown". Only "red" can produce a ticket.
"""
import cv2
import numpy as np

# HSV ranges (OpenCV hue is 0-179). Only bright, saturated pixels count as "lit".
_LIT_S, _LIT_V = 90, 150
_HUES = {
    "red":    ((0, 10), (160, 179)),
    "yellow": ((11, 35),),
    "green":  ((40, 95),),
}
MIN_LIT_FRACTION = 0.03   # less lit area than this = can't tell (light off, occluded, too small)
MIN_WINNER_SHARE = 0.6    # the winning colour must own most of the lit pixels


def read_light_colour(crop: np.ndarray) -> str:
    """Return the lit colour of a BGR crop of the traffic light."""
    if crop is None or crop.size == 0:
        return "unknown"
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    lit = (s >= _LIT_S) & (v >= _LIT_V)
    counts = {
        colour: int(sum(np.count_nonzero(lit & (h >= lo) & (h <= hi)) for lo, hi in ranges))
        for colour, ranges in _HUES.items()
    }
    total = sum(counts.values())
    if total < MIN_LIT_FRACTION * h.size:
        return "unknown"
    colour, best = max(counts.items(), key=lambda kv: kv[1])
    return colour if best >= MIN_WINNER_SHARE * total else "unknown"


def timer_phase(t: float, cycle: dict) -> tuple[str, float]:
    """
    (state, seconds left in that state) at video time t for a fixed cycle
    red -> green -> yellow. cycle = {"red_start": s, "red": s, "green": s, "yellow": s};
    red_start is a moment in the video when the light turns red.
    """
    red, green, yellow = (float(cycle.get(k, 0)) for k in ("red", "green", "yellow"))
    period = red + green + yellow
    if period <= 0:
        return "unknown", 0.0
    phase = (t - float(cycle.get("red_start", 0))) % period
    if phase < red:
        return "red", red - phase
    if phase < red + green:
        return "green", red + green - phase
    return "yellow", period - phase


def timer_state(t: float, cycle: dict) -> str:
    """Light state only (see timer_phase)."""
    return timer_phase(t, cycle)[0]


_LAMP_ON = {"red": (0, 0, 255), "yellow": (0, 220, 255), "green": (0, 220, 0)}
_LAMP_OFF = {"red": (0, 0, 70), "yellow": (0, 60, 70), "green": (0, 60, 0)}


def draw_virtual_light(frame: np.ndarray, state: str, seconds_left: float, slot: int = 0) -> None:
    """
    Draw a simulated traffic light in the top-right corner (in place): housing,
    three lamps with the current one lit, and a countdown. `slot` stacks several
    lights side by side. Sized relative to the frame so it reads at any resolution.
    """
    fh, fw = frame.shape[:2]
    r = max(8, fh // 40)                     # lamp radius
    pad = r // 2
    box_w, box_h = 2 * r + 2 * pad, 6 * r + 4 * pad
    x1 = fw - (slot + 1) * (box_w + pad) - pad
    y1 = pad
    cv2.rectangle(frame, (x1, y1), (x1 + box_w, y1 + box_h), (30, 30, 30), -1)
    cv2.rectangle(frame, (x1, y1), (x1 + box_w, y1 + box_h), (200, 200, 200), 1)
    for k, colour in enumerate(("red", "yellow", "green")):
        centre = (x1 + box_w // 2, y1 + pad + r + k * (2 * r + pad))
        lit = colour == state
        cv2.circle(frame, centre, r, _LAMP_ON[colour] if lit else _LAMP_OFF[colour], -1)
    scale = r / 18
    label = f"{int(seconds_left) + 1}s" if state in _LAMP_ON else "--"
    cv2.putText(frame, label, (x1, y1 + box_h + int(r * 1.4)), cv2.FONT_HERSHEY_SIMPLEX,
                scale, (255, 255, 255), max(1, r // 8), cv2.LINE_AA)
    cv2.putText(frame, "SIM", (x1, y1 + box_h + int(r * 2.6)), cv2.FONT_HERSHEY_SIMPLEX,
                scale * 0.8, (180, 180, 180), 1, cv2.LINE_AA)


# ─── Vehicle turn indicators (signal light violation) ────────────────────────

def amber_fraction(crop: np.ndarray) -> float:
    """Share of bright amber pixels in a BGR crop (an indicator lamp that is on)."""
    if crop is None or crop.size == 0:
        return 0.0
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    return float(np.count_nonzero((h >= 8) & (h <= 30) & (s >= 120) & (v >= 180))) / h.size


BLINK_MIN_SWING = 0.004            # on/off difference in amber share needed (ignores noise)
BLINK_PERIOD_S = (0.33, 2.0)       # indicators flash at roughly 0.5 - 3 Hz


def is_blinking(samples: list) -> bool:
    """
    samples = [(t, amber_fraction), ...] for one side of a vehicle.
    Blinking = the amber share switches on and off at least twice with a steady
    indicator-like rhythm. A constantly amber vehicle (yellow paint, parking light)
    never switches, so it does not count.
    """
    if len(samples) < 6 or samples[-1][0] - samples[0][0] < 1.0:
        return False
    vals = np.array([s[1] for s in samples])
    lo, hi = float(vals.min()), float(vals.max())
    if hi - lo < BLINK_MIN_SWING:
        return False
    on = vals > lo + 0.5 * (hi - lo)
    rises = [samples[k][0] for k in range(1, len(samples)) if on[k] and not on[k - 1]]
    if len(rises) < 2:
        return False
    period = (rises[-1] - rises[0]) / (len(rises) - 1)
    return BLINK_PERIOD_S[0] <= period <= BLINK_PERIOD_S[1]


class LightReader:
    """Camera reading with a small debounce: a new colour must be read twice in a row."""

    def __init__(self):
        self.state = "unknown"
        self._last_raw = "unknown"

    def update(self, crop: np.ndarray) -> str:
        raw = read_light_colour(crop)
        if raw == self._last_raw:
            self.state = raw
        self._last_raw = raw
        return self.state
