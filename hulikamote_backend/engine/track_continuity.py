"""
track_continuity.py - is a new position of a tracked vehicle really the SAME vehicle as the one before it?

The trackers do not always keep one number for one vehicle. DeepSORT keeps a lost track alive for 90 pictures and gives its number to
whatever vehicle shows up near the place it should be; the ledger stitches new tracks onto lost ones as well (engine/track_stitcher.py).
So the path of one ledger can be the paths of two or three different vehicles, one after the other, with a jump (and usually a silence
of a few seconds) between them. A rule that reads that path as ONE vehicle's trip can be fooled: "the vehicle crossed the line" when
the number only moved from a vehicle on the left of the line to another one on the right.

On a real clip (4K CCTV, 120 s, 5-10 pictures a second) 26 of 27 "crossings" were exactly that: the next picture of the number came
2 to 5 seconds later, 100 to 450 px away, often with a box of another size. Only a vehicle that is followed picture after picture,
moving the way it was moving, can be said to have driven across something.

A sample is (t, x, y, w, h): the time, the ground point (bottom centre of the box) and the size of the box. A "run" is a list of
samples that belong to one vehicle as far as anyone can tell. All functions are pure.
"""
import math

MAX_GAP_S = 0.8          # no picture of the vehicle for this long: what shows up next may be another vehicle
GAP_PICTURES = 3.5       # ... or for this many times the usual time between two pictures of it (a slow live feed)
SIZE_JUMP = 1.8          # its box became this many times wider / taller (or narrower / shorter) from one picture to the next
POS_WIDTHS = 0.8         # it may be this many box widths away from where its own speed says it should be ...
POS_SPEED_SHARE = 0.25   # ... plus this share of the distance it was expected to travel since ...
POS_SLACK_PX = 8.0       # ... plus this much for the jitter of the box
USUAL_DT = 0.1           # the usual time between two pictures when too few are known


def usual_dt(run) -> float:
    """The usual time between two pictures of this vehicle: the middle value of its last few intervals."""
    part = run[-7:]
    gaps = sorted(b[0] - a[0] for a, b in zip(part, part[1:]) if b[0] > a[0])
    if not gaps:
        return USUAL_DT
    return gaps[len(gaps) // 2]


def velocity(run, count: int = 4) -> tuple[float, float]:
    """(vx, vy) in pixels per second over the last `count` samples; (0, 0) when it cannot be told."""
    part = run[-count:]
    if len(part) < 2:
        return 0.0, 0.0
    dt = part[-1][0] - part[0][0]
    if dt <= 0:
        return 0.0, 0.0
    return (part[-1][1] - part[0][1]) / dt, (part[-1][2] - part[0][2]) / dt


def continues(run, new) -> bool:
    """True when `new` can be the next picture of the vehicle whose earlier pictures are `run` (oldest first, at least one).
    False when it was not seen for too long, its box suddenly has another size, or it is not where its own movement says it would be."""
    last = run[-1]
    dt = new[0] - last[0]
    if dt <= 0:
        return True                                               # the same picture again: nothing new to doubt
    if dt > max(MAX_GAP_S, GAP_PICTURES * usual_dt(run)):
        return False
    for before, after in ((last[3], new[3]), (last[4], new[4])):
        if before <= 0 or after <= 0 or not (1.0 / SIZE_JUMP <= after / before <= SIZE_JUMP):
            return False
    vx, vy = velocity(run)
    err = math.hypot(new[1] - (last[1] + vx * dt), new[2] - (last[2] + vy * dt))
    allowed = POS_WIDTHS * max(last[3], new[3]) + POS_SPEED_SHARE * math.hypot(vx, vy) * dt + POS_SLACK_PX
    return err <= allowed


def last_run(points) -> list:
    """The newest part of a path that is one vehicle: from `points` ((t, x, y, w) or (t, x, y, w, h), oldest first) back to the
    last place where `continues` says "another vehicle". The height is taken as the width when it is not given."""
    samples = [(p[0], p[1], p[2], p[3], p[4] if len(p) > 4 else p[3]) for p in points]
    start = 0
    for i in range(1, len(samples)):
        if not continues(samples[start:i], samples[i]):
            start = i
    return samples[start:]
