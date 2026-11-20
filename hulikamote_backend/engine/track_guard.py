"""
track_guard.py - is this box really the SAME vehicle as the ledger (the ticket) it is about to join?

The tracker (DeepSORT / ByteTrack) sometimes gives the number of one vehicle to another one: a lost track is kept alive for 90 pictures and
takes whatever shows up near the place it should be (the car behind, the car in the next lane, a vehicle from the other side of the road).
A ledger that follows the number then holds the pictures of two or three vehicles, and its ticket shows a jump.

This guard is a strict, geometric "same vehicle" test, made in the vehicle's OWN frame of reference: the way it was heading.
A new box is accepted for a ledger only when
  - the vehicle was not out of sight for too long;
  - the box has about the same size (a vehicle does not become twice as wide from one picture to the next);
  - it is where the vehicle's own speed says it should be, and
      * not BEHIND where the vehicle was (along its heading: a car that drove on does not appear behind its last place),
      * not much further AHEAD than its speed explains (the car in front is a different car),
      * not SIDEWAYS (across its heading: the next lane, or the other side of the road, is another vehicle);
  - a vehicle that stands still stays on its spot (a small circle);
  - it is not a two-wheeler that became a four-wheeler (or the other way round), and its colours still match.
All distances are measured in box sizes, so the test works the same for a far (small) and a near (big) vehicle, at any speed of the feed.
The functions are pure.
"""
import math

MAX_GAP_S = 3.0               # a vehicle that was out of sight longer than this is not taken back (the same as the track stitcher)
PARKED_GAP_S = 25.0           # ... a vehicle that STOPPED in a no-parking zone may be out of sight this long (engine/track_stitcher.py PARKED_KEEP_S)
STILL_SPEED = 0.25            # box sizes per second under which the vehicle counts as standing still
STILL_RADIUS = 0.5            # a vehicle that stands still stays within this many box sizes of its last place
NEW_RADIUS = 1.0              # a vehicle seen once (no heading yet): this radius
BACK_TOL = 0.30               # behind its last place along its heading by more than this many box sizes = another vehicle (jitter only)
AHEAD_FACTOR = 1.6            # ahead: up to this times the distance its own speed covers ...
AHEAD_SLACK = 0.35            # ... plus this many box sizes
SIDE_TOL = 0.45               # sideways: this share of the vehicle's narrow side ...
SIDE_PER_TRAVEL = 0.12        # ... plus this share of the distance it was expected to cover (a bend in the road) ...
SIDE_SLACK_PX = 6.0           # ... plus this much for the jitter of the box
SIZE_STEP = 1.6               # box width / height may change by this factor from one picture to the next ...
SIZE_PER_S = 0.5              # ... and by this much more for every second without a picture
MAX_HIST_DISTANCE = 0.5       # colour (Bhattacharyya distance, 0 = same)
COLOUR_CHECK_TRAVEL = 0.5     # the colours are compared only when it moved more than this many box sizes, or after a gap (cheap)
COLOUR_CHECK_GAP_S = 0.5
_VELOCITY_SAMPLES = 8

TWO_WHEELERS = ("motorcycle", "bicycle")
BIGGER = ("car", "bus", "truck", "jeepney", "pickup", "van")


def _velocity(samples) -> tuple[float, float]:
    """(vx, vy) in pixels per second over the last few samples of (t, x, y, box); (0, 0) when it cannot be told."""
    part = samples[-_VELOCITY_SAMPLES:]
    if len(part) < 2:
        return 0.0, 0.0
    dt = part[-1][0] - part[0][0]
    if dt <= 0:
        return 0.0, 0.0
    return (part[-1][1] - part[0][1]) / dt, (part[-1][2] - part[0][2]) / dt


def check(history, new_box, now: float, max_gap: float = MAX_GAP_S) -> str | None:
    """None when `new_box` (x, y, w, h at time `now`) can be the next picture of the vehicle whose pictures are `history`
    ((t, ground x, ground y, (x, y, w, h)), oldest first); else why not: gap | size | far | behind | ahead | sideways."""
    samples = list(history)
    if not samples:
        return None
    t1, x1, y1, box1 = samples[-1]
    dt = now - t1
    if dt <= 0:
        return None                                              # the same picture again: nothing new to doubt
    if dt > max_gap:
        return "gap"
    w1, h1 = float(box1[2]), float(box1[3])
    w2, h2 = float(new_box[2]), float(new_box[3])
    if min(w1, h1, w2, h2) <= 0:
        return "size"
    limit = SIZE_STEP + SIZE_PER_S * min(dt, MAX_GAP_S)
    for before, after in ((w1, w2), (h1, h2)):
        if not (1.0 / limit <= after / before <= limit):
            return "size"

    size = max(w1, h1)                                           # how big the vehicle is: distances are measured in this
    narrow = min(w1, h1)                                         # ... and its narrow side is what separates it from the next lane
    nx, ny = new_box[0] + w2 / 2.0, new_box[1] + h2              # the ground point, the same anchor as the ledger
    dx, dy = nx - x1, ny - y1
    vx, vy = _velocity(samples)
    speed = math.hypot(vx, vy)
    if len(samples) < 2 or speed < STILL_SPEED * size:
        radius = (NEW_RADIUS if len(samples) < 2 else STILL_RADIUS) * size + 1.5 * speed * dt + SIDE_SLACK_PX
        return None if math.hypot(dx, dy) <= radius else "far"   # no heading: it is where it was
    hx, hy = vx / speed, vy / speed
    along = dx * hx + dy * hy                                    # + = further the way it was heading
    across = abs(-dx * hy + dy * hx)                             # sideways
    travel = speed * dt                                          # how far its own speed says it went
    if along < -BACK_TOL * size:
        return "behind"
    if along > AHEAD_FACTOR * travel + AHEAD_SLACK * size:
        return "ahead"
    if across > SIDE_TOL * narrow + SIDE_PER_TRAVEL * travel + SIDE_SLACK_PX:
        return "sideways"
    return None


def class_clash(old_class: str | None, new_class: str | None) -> str | None:
    """"class" when a two-wheeler became a four-wheeler (or the other way round): never one vehicle. Other changes are the detector's doubt."""
    if old_class in TWO_WHEELERS and new_class in BIGGER:
        return "class"
    if old_class in BIGGER and new_class in TWO_WHEELERS:
        return "class"
    return None


def wants_colour_check(history, new_box, now: float) -> bool:
    """Comparing colours costs a little: do it only after a gap or a real move (the cases where another vehicle could have taken over)."""
    samples = list(history)
    if not samples:
        return False
    t1, x1, y1, box1 = samples[-1]
    size = max(float(box1[2]), float(box1[3]), 1.0)
    moved = math.hypot(new_box[0] + new_box[2] / 2.0 - x1, new_box[1] + new_box[3] - y1)
    return now - t1 > COLOUR_CHECK_GAP_S or moved > COLOUR_CHECK_TRAVEL * size


def colour_clash(old_signature, new_signature) -> str | None:
    """"colour" when the colour signatures (engine/track_stitcher.py compute_signature) of the two boxes are too different."""
    if old_signature is None or new_signature is None:
        return None
    import cv2

    return "colour" if float(cv2.compareHist(old_signature, new_signature, cv2.HISTCMP_BHATTACHARYYA)) > MAX_HIST_DISTANCE else None
