"""
line_watch.py - one vehicle against one solid line: has it REALLY driven across it?

"The vehicle's number is now on the other side of the line" is not the same thing. The trackers hand a number to another vehicle now and
then (see engine/track_continuity.py), the box of a vehicle half hidden behind a truck jumps about, and a drawn line is never exactly
where the paint is. So a crossing is only believed when ALL of this holds:

  1. the vehicle was followed picture after picture (no long silence, no jump, no change of box size, no change from a two-wheeler
     to a four-wheeler: track_continuity.continues), from before the line to after it, as ONE run. Whenever the run breaks (another vehicle, lost for too long, past either end of
     the line), everything learned so far is forgotten and the vehicle is watched anew;
  2. it first drove ARM_SAMPLES pictures in a row clearly on one side (a box width's third, at least 10 px), so its own side is known;
  3. then it was clearly on the other side for HOLD_SAMPLES pictures in a row (one wrong box does not make a crossing);
  4. its trip from the last picture on its own side to the other side really CUTS the line (geometry.line_cut), not round its end;
  5. it still looks like the same vehicle: the colours of its box did not change into another vehicle's (a colour histogram).

  6. it crossed the way a vehicle crosses a line it drives ALONG (a lane change, an overtaking swerve: at most MAX_CROSS_ANGLE_DEG to
     the line), not the way cross traffic does (a vehicle that turns across the road into a side street, comes out of one, or makes a
     U-turn crosses at a steep angle: that is a turn, and the turning rules judge it, not this one).

A picture that is not new (the vehicle was not seen this frame, the rule is only asked again) is ignored: nothing is counted twice.
"""
import math
from collections import namedtuple

from engine.track_stitcher import blend_signature, hist_distance
from engine.track_continuity import continues
from engine.violations.geometry import line_cut, line_side

Crossing = namedtuple("Crossing", "point t angle")   # where the trip cut the line (x, y), when it was believed, and the angle (deg) it cut at

TWO_WHEELERS = ("motorcycle", "bicycle")   # a ledger that turns from one of these into anything else (or back) is another vehicle

MIN_BOX_PX = 12            # a box smaller than this (width or height) says too little about where the vehicle is
MIN_MARGIN_PX = 10.0       # clearly on a side: at least this far from the line ...
MARGIN_WIDTHS = 0.3        # ... and at least this share of its box width
ARM_SAMPLES = 4            # pictures in a row on one side before that side counts as "its own"
ARM_MIN_SPAN_S = 0.2       # ... and they must cover at least this much time
HOLD_SAMPLES = 3           # pictures in a row on the other side before it counts as crossed
HOLD_MIN_SPAN_S = 0.15     # ... covering at least this much time
LAT_WIDTHS = 0.45          # sideways: it may be this many box widths from where its own sideways speed says ...
LAT_SPEED_SHARE = 0.25     # ... plus this share of the sideways distance it was expected to travel ...
LAT_SLACK_PX = 6.0         # ... plus this much for the jitter of the box
CUT_TOLERANCE_WIDTHS = 0.25  # the line is lengthened by this share of the box width at both ends when asking "did the trip cut it"
MAX_CROSS_ANGLE_DEG = 60.0  # steeper than this (seen on the picture, where a road runs away from the camera: about 40 degrees on the road) it is a turn
SIG_MAX_DISTANCE = 0.6     # colour histogram distance above which it is another vehicle (the stitcher accepts up to 0.5 as the same one)
SIG_REFRESH = 5            # refresh its colours every this many pictures on its own side
RUN_KEEP = 12              # samples of the current run that are remembered
TRAIL_KEEP = 30            # points of its trip since it was last clearly on its own side


class LineWatch:
    """The memory of one vehicle (one ledger) about one line (one zone). Feed it every NEW picture of the vehicle with update()."""

    def __init__(self):
        self.done = False             # it was flagged: nothing more to watch
        self.last_angle = None        # the angle (deg) of the newest crossing that was weighed
        self.last_t = None            # time of the newest picture seen (a picture is only ever used once)
        self._forget()

    def _forget(self) -> None:
        """Back to "knows nothing": a new run starts with the next picture."""
        self.run: list = []           # (t, x, y, w, h, s): the pictures of the current run, s = signed distance to the line
        self.side = 0                 # +1 / -1: the side it is armed on, 0: not known yet
        self.cand_side = 0            # the side it has been on for the last few pictures (before it is armed)
        self.cand_n = 0
        self.cand_t0 = 0.0
        self.cross_n = 0              # pictures in a row clearly on the other side
        self.cross_t0 = 0.0
        self.last_own = None          # (x, y) of its last picture clearly on its own side
        self.trail: list = []         # (x, y) of every picture since
        self.arm_sig = None           # the colours it had on its own side
        self.own_n = 0
        self.family = None            # 2: a two-wheeler, 4: any other vehicle (what the current run is)

    def leave(self, t) -> None:
        """The vehicle is outside the road section of this zone: it is not judged here, and what was known is stale."""
        if not self.done:
            self.last_t = t
            self._forget()

    # ── one new picture ──
    def update(self, sample, line, signature=None, kind=None):
        """`sample` = (t, x, y, w, h): the ground point and the box of the newest picture. `signature` = a function returning the colour
        histogram of the vehicle's box now (or None), called only when it is needed. `kind` = what the tracker calls the vehicle now
        ("car", "motorcycle" ...). Returns a Crossing when this picture makes the crossing believable, else None."""
        if self.done:
            return None
        t, x, y, w, h = sample
        if self.last_t is not None and t <= self.last_t:
            return None
        self.last_t = t
        if w < MIN_BOX_PX or h < MIN_BOX_PX:
            self._forget()
            return None
        s = line_side(line, x, y)
        if s is None:                               # beside neither end of the line: not judged, and what was known is stale
            self._forget()
            return None
        new = (t, x, y, w, h, s)
        family = None if kind in (None, "unknown") else (2 if kind in TWO_WHEELERS else 4)
        if self.run and (not self._same_vehicle(new) or (family and self.family and family != self.family)):
            self._forget()
        self.family = family or self.family
        self.run.append(new)
        del self.run[:-RUN_KEEP]

        margin = max(MIN_MARGIN_PX, MARGIN_WIDTHS * w)
        now = 1 if s >= margin else (-1 if s <= -margin else 0)

        if self.side == 0:                          # not armed: which side does it keep to?
            if now == 0:
                self.cand_side, self.cand_n = 0, 0
                return None
            if now == self.cand_side:
                self.cand_n += 1
            else:
                self.cand_side, self.cand_n, self.cand_t0 = now, 1, t
            if self.cand_n >= ARM_SAMPLES and t - self.cand_t0 >= ARM_MIN_SPAN_S:
                self.side, self.last_own, self.trail, self.cross_n, self.own_n = self.cand_side, (x, y), [], 0, 0
                self.arm_sig = signature() if signature else None
            return None

        if now == self.side:                        # on its own side
            self.cross_n, self.trail, self.last_own = 0, [], (x, y)
            self.own_n += 1
            if signature and self.own_n % SIG_REFRESH == 0:
                self.arm_sig = blend_signature(self.arm_sig, signature())
            return None

        self.trail.append((x, y))                   # on the line, or past it
        del self.trail[:-TRAIL_KEEP]
        if now == 0:
            self.cross_n = 0
            return None
        if self.cross_n == 0:
            self.cross_t0 = t
        self.cross_n += 1
        if self.cross_n < HOLD_SAMPLES or t - self.cross_t0 < HOLD_MIN_SPAN_S:
            return None
        return self._confirm(line, w, t, signature)

    def _same_vehicle(self, new) -> bool:
        """Is `new` the next picture of the vehicle of the current run? (the general check, then the check across the line)"""
        run = [r[:5] for r in self.run]
        if not continues(run, new[:5]):
            return False
        last = self.run[-1]
        dt = new[0] - last[0]
        if dt <= 0:
            return True
        part = self.run[-4:]
        span = part[-1][0] - part[0][0]
        vs = (part[-1][5] - part[0][5]) / span if len(part) >= 2 and span > 0 else 0.0     # sideways speed (px per second)
        err = abs(new[5] - (last[5] + vs * dt))
        return err <= LAT_WIDTHS * max(last[3], new[3]) + LAT_SPEED_SHARE * abs(vs) * dt + LAT_SLACK_PX

    def _confirm(self, line, w, t, signature):
        trip = ([self.last_own] if self.last_own else []) + self.trail
        cut = line_cut(trip, line, tol=max(4.0, CUT_TOLERANCE_WIDTHS * w))
        if cut is None:                             # it went round the end of the line (or the line bends away): never crossed
            self._forget()
            return None
        dx, dy = trip[-1][0] - trip[0][0], trip[-1][1] - trip[0][1]
        travelled = math.hypot(dx, dy)
        angle = math.degrees(math.acos(min(1.0, abs(dx * cut.tangent[0] + dy * cut.tangent[1]) / travelled))) if travelled > 0 else 90.0
        self.last_angle = angle                     # (for the notes of the evidence and for tuning)
        if angle > MAX_CROSS_ANGLE_DEG:             # cross traffic: it did not drive along the line and drift over it, it went across
            self._rearm_on_other_side(trip[-1])
            return None
        if signature and self.arm_sig is not None:
            colours = signature()
            if colours is not None and hist_distance(self.arm_sig, colours) > SIG_MAX_DISTANCE:
                self._forget()                      # other colours than the vehicle that was on this side: another vehicle
                return None
        self.done = True
        return Crossing(cut.point, t, angle)

    def _rearm_on_other_side(self, here) -> None:
        """The vehicle crossed, but not as a violation: from now on the side it is on is its own (so one turn is not judged on every picture)."""
        self.side = -self.side
        self.last_own, self.trail, self.cross_n, self.own_n = here, [], 0, 0
