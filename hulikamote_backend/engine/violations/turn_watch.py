"""
turn_watch.py - one vehicle against one turn rule: has it REALLY turned the way that is banned?

The old check read the heading of a tracker NUMBER. But the trackers hand a number to another vehicle now and then (see
engine/track_continuity.py), so "the heading swung 90 degrees" was often only the number jumping from a vehicle going one way to another
vehicle going another way. The rule then flagged random vehicles, coming and going. So a turn is only believed when ALL of this holds:

  1. the vehicle was followed picture after picture as ONE run (track_continuity.continues: no long silence, no jump, no change of box
     size, no change from a two-wheeler to a four-wheeler). Whenever the run breaks, everything learned so far is forgotten;
  2. its way in is known: its first stretch of travel in the zone (a box width and a bit) gives the ENTRY heading;
  3. its heading NOW (over about a box width of travel, ending at the newest picture) has swung 45 to 150 degrees from the entry heading
     (wider is a U-turn: that is another rule) and it is really moving (not a stopped box that wobbles);
  4. the same verdict holds for HOLD_SAMPLES pictures in a row (one wrong box does not make a turn);
  5. the run is at least MIN_RUN_S long, and the colours of the box still look like the vehicle that came in.

A vehicle that goes straight on for a few seconds starts again from its new heading, so a long gentle bend of the road is not a turn.
Left and right are as the driver sees them: a right turn is clockwise on the picture. A picture that is not new is ignored.
"""
import math
from collections import namedtuple

from engine.track_continuity import continues
from engine.track_stitcher import blend_signature, hist_distance

Turn = namedtuple("Turn", "side angle point t")      # which way it turned, how far (deg), where it was when believed, and when

TWO_WHEELERS = ("motorcycle", "bicycle")

MIN_BOX_PX = 12            # a box smaller than this says too little about where the vehicle is
ENTRY_WIDTHS = 1.2         # travel (box widths) before the entry heading is read ...
ENTRY_MIN_PX = 24.0        # ... and at least this many pixels (beats box jitter)
LOOK_WIDTHS = 1.0          # the heading now is read over this much travel ...
LOOK_MIN_PX = 20.0         # ... and at least this many pixels
MIN_SWING_DEG = 45.0       # a swing smaller than this is a bend, not a turn
MAX_SWING_DEG = 150.0      # a swing wider than this is a U-turn
MOVING_WIDTHS_PER_S = 0.3  # it must travel at least this many box widths a second over the look: a stopped box is not turning
HOLD_SAMPLES = 4           # pictures in a row with the same verdict
HOLD_MIN_SPAN_S = 0.3      # ... covering at least this much time
MIN_RUN_S = 1.2            # the run must be at least this long (seconds)
STRAIGHT_DEG = 20.0        # a heading this close to the entry heading is "straight on" ...
REBASE_S = 3.0             # ... and after this long the entry heading is read again from here
RUN_KEEP = 150             # samples of the current run that are remembered
SIG_MAX_DISTANCE = 0.6     # colour histogram distance above which it is another vehicle
SIG_REFRESH = 6            # refresh its colours every this many pictures


def _unit(x: float, y: float):
    d = math.hypot(x, y)
    return (x / d, y / d) if d > 0 else (0.0, 0.0)


class TurnWatch:
    """The memory of one vehicle (one ledger) about one turn rule in one zone. Feed it every NEW picture with update()."""

    def __init__(self):
        self.done = False             # it was flagged: nothing more to watch
        self.last_t = None            # time of the newest picture seen (a picture is only ever used once)
        self.last_angle = None        # swing (deg) of the newest weighed picture (for notes and tuning)
        self._forget()

    def _forget(self) -> None:
        self.run: list = []           # (t, x, y, w, h): the pictures of the current run
        self.entry = None             # unit heading of its first stretch
        self.entry_t = 0.0            # time when that stretch ended (a time, not an index: the oldest pictures of a long run are dropped)
        self.hold_n = 0
        self.hold_t0 = 0.0
        self.hold_side = None
        self.straight_since = None
        self.arm_sig = None           # the colours it had on the way in
        self.sig_n = 0
        self.family = None            # 2: a two-wheeler, 4: any other vehicle

    def leave(self, t) -> None:
        """The vehicle is outside this zone: it is not judged here, and what was known is stale."""
        if not self.done:
            self.last_t = t
            self._forget()

    def update(self, sample, judge, signature=None, kind=None):
        """`sample` = (t, x, y, w, h): the ground point and box of the newest picture. `judge(entry, current, side)` says whether a swing
        from `entry` to `current` (unit headings, `side` = "left" / "right") is a BANNED turn. `signature` = a function returning the colour
        histogram of the vehicle's box now (or None), called only when needed. `kind` = what the tracker calls the vehicle.
        Returns a Turn when this picture makes the turn believable, else None."""
        if self.done:
            return None
        t, x, y, w, h = sample
        if self.last_t is not None and t <= self.last_t:
            return None
        self.last_t = t
        if w < MIN_BOX_PX or h < MIN_BOX_PX:
            self._forget()
            return None
        new = (t, x, y, w, h)
        family = None if kind in (None, "unknown") else (2 if kind in TWO_WHEELERS else 4)
        if self.run and (not continues(self.run[-12:], new) or (family and self.family and family != self.family)):
            self._forget()
        self.family = family or self.family
        self.run.append(new)
        del self.run[:-RUN_KEEP]

        if self.entry is None:                      # its way in: the first stretch of travel
            need = max(ENTRY_MIN_PX, ENTRY_WIDTHS * w)
            x0, y0 = self.run[0][1], self.run[0][2]
            for j in range(1, len(self.run)):
                if math.hypot(self.run[j][1] - x0, self.run[j][2] - y0) >= need:
                    self.entry = _unit(self.run[j][1] - x0, self.run[j][2] - y0)
                    self.entry_t = self.run[j][0]
                    self.arm_sig = signature() if signature else None
                    break
            return None

        look = max(LOOK_MIN_PX, LOOK_WIDTHS * w)    # the heading now, over the newest stretch of travel (after the entry stretch)
        start = None
        for j in range(len(self.run) - 2, -1, -1):
            if self.run[j][0] < self.entry_t:
                break
            if math.hypot(x - self.run[j][1], y - self.run[j][2]) >= look:
                start = j
                break
        if start is None:
            return None
        ts, xs, ys = self.run[start][0], self.run[start][1], self.run[start][2]
        dist = math.hypot(x - xs, y - ys)
        current = _unit(x - xs, y - ys)
        moving = t > ts and dist / (t - ts) >= MOVING_WIDTHS_PER_S * w
        cosine = max(-1.0, min(1.0, self.entry[0] * current[0] + self.entry[1] * current[1]))
        angle = math.degrees(math.acos(cosine))
        self.last_angle = angle
        side = "right" if self.entry[0] * current[1] - self.entry[1] * current[0] > 0 else "left"

        if moving and angle < STRAIGHT_DEG:         # straight on: after a while it is the new "way in" (a long bend is not a turn)
            if self.straight_since is None:
                self.straight_since = t
            elif t - self.straight_since >= REBASE_S:
                self.entry, self.entry_t, self.straight_since = current, t, None
                self._reset_hold()
                return None
        elif angle >= STRAIGHT_DEG:
            self.straight_since = None
        if signature and self.sig_n % SIG_REFRESH == 0 and angle < STRAIGHT_DEG:
            self.arm_sig = blend_signature(self.arm_sig, signature())
        self.sig_n += 1

        hit = moving and MIN_SWING_DEG <= angle <= MAX_SWING_DEG and judge(self.entry, current, side)
        if not hit or (self.hold_side is not None and side != self.hold_side):
            self._reset_hold()
            if not hit:
                return None
        if self.hold_n == 0:
            self.hold_t0, self.hold_side = t, side
        self.hold_n += 1
        if self.hold_n < HOLD_SAMPLES or t - self.hold_t0 < HOLD_MIN_SPAN_S or t - self.run[0][0] < MIN_RUN_S:
            return None
        if signature and self.arm_sig is not None:
            colours = signature()
            if colours is not None and hist_distance(self.arm_sig, colours) > SIG_MAX_DISTANCE:
                self._forget()                      # other colours than the vehicle that came in: another vehicle
                return None
        self.done = True
        return Turn(side, angle, (x, y), t)

    def _reset_hold(self) -> None:
        self.hold_n, self.hold_side = 0, None
