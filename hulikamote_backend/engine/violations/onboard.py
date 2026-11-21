"""
onboard.py - who is riding ON a vehicle, as opposed to standing or walking next to it. Shared by
passenger_outside (open back, roof, hanging on, kuliglig).

Two cues are combined, and both have to hold:
  1. Position: where the person's box sits on the vehicle's box (feet on the body, in the trailing part,
     on the roof, straddling the edge). This depends on the camera view - see each rule's docstring.
  2. Co-motion: the person moves WITH the vehicle (same direction, similar distance over the last 8
     updates). A pedestrian beside a moving truck, or one loading a parked pickup, does not.
People who ride a motorcycle are never counted as passengers of a truck (rider_boxes claims them first).
"""
import math

from engine.violations.geometry import dot, rider_boxes

MOTION_SAMPLES = 8       # position updates compared (about 1 s of video at the live monitor's 10 looks a second)
MIN_MOTION_PX = 8.0      # both must have travelled at least this far
TRAILING_S = -0.2        # in the trailing 40% of the vehicle along its travel (a pickup's bed is its last ~40%)


def recent_motion(ledger, samples: int = MOTION_SAMPLES):
    """(dx, dy) over the last `samples` position updates, or None while there are fewer."""
    if len(ledger.history) < samples:
        return None
    first, last = ledger.history[-samples], ledger.history[-1]
    return (last[1] - first[1], last[2] - first[2])


def moves_with(vehicle_ledger, person_ledger) -> bool:
    """True when the person travels with the vehicle: same direction (within about 37 deg) and 0.5x - 2x its distance."""
    a, b = recent_motion(vehicle_ledger), recent_motion(person_ledger)
    if a is None or b is None:
        return False
    la, lb = math.hypot(*a), math.hypot(*b)
    if la < MIN_MOTION_PX or lb < MIN_MOTION_PX:
        return False
    return dot(a, b) / (la * lb) >= 0.8 and 0.5 <= lb / la <= 2.0


ATTACH_MAX_SHIFT = 0.15  # a rider on board keeps the same spot on the vehicle: offset may drift at most 15% of its size
SEATED_SHARE = 0.6       # a person this much inside a car / tricycle box rides in it
INSIDE_SHARE = 0.9       # a person this much inside a bus / jeepney / truck box is an occupant (driver, seated passenger)


def stays_attached(vehicle_ledger, person_ledger, samples: int = MOTION_SAMPLES) -> bool:
    """True when the person keeps the same spot on the vehicle over the last `samples` updates. A motorcycle or a
    pedestrian passing alongside moves in the same direction but slides along the vehicle, so it fails."""
    if len(vehicle_ledger.history) < samples or len(person_ledger.history) < samples:
        return False
    v0, v1 = vehicle_ledger.history[-samples], vehicle_ledger.history[-1]
    p0, p1 = person_ledger.history[-samples], person_ledger.history[-1]
    _, _, vw, vh = v1[3]
    size = max(vw, vh)
    if size <= 0:
        return False
    drift = math.hypot((p1[1] - v1[1]) - (p0[1] - v0[1]), (p1[2] - v1[2]) - (p0[2] - v0[2]))
    return drift <= ATTACH_MAX_SHIFT * size


def _share_inside(outer: list, person: list) -> float:
    """Share of the person's box that lies inside the outer box (no headroom)."""
    ox, oy, ow, oh = outer
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0:
        return 0.0
    ix = max(0.0, min(px + pw, ox + ow) - max(px, ox))
    iy = max(0.0, min(py + ph, oy + oh) - max(py, oy))
    return ix * iy / (pw * ph)


def claimed_by_small_vehicles(detections: list, people: list) -> set:
    """ids of the person boxes that ride a motorcycle, or sit in a tricycle or car (never someone riding outside a
    bus / jeepney / truck): motorcycle and tricycle riders by rider_boxes, and anyone mostly inside a car / tricycle."""
    boxes = [p.bbox for p in people]
    claimed = set()
    for det in detections:
        if det.cls in ("motorcycle", "tricycle"):
            claimed |= {id(box) for box in rider_boxes(det.bbox, boxes)}
        if det.cls in ("car", "tricycle"):
            claimed |= {id(box) for box in boxes if _share_inside(det.bbox, box) >= SEATED_SHARE}
    return claimed


def claimed_by_motorcycles(detections: list, people: list) -> set:
    """ids of the person boxes that ride a motorcycle (so they are never a truck's passengers)."""
    boxes = [p.bbox for p in people]
    claimed = set()
    for det in detections:
        if det.cls == "motorcycle":
            claimed |= {id(box) for box in rider_boxes(det.bbox, boxes)}
    return claimed


def _share_over(vehicle: list, person: list) -> float:
    """Share of the person's box that lies over the vehicle's box, with room above it for heads sticking out."""
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    top = vy - 0.35 * vh
    ix = max(0.0, min(px + pw, vx + vw) - max(px, vx))
    iy = max(0.0, min(py + ph, vy + vh) - max(py, top))
    return ix * iy / (pw * ph)


def on_body(vehicle: list, person: list) -> bool:
    """A person standing or sitting anywhere ON a vehicle (a kuliglig and its trailer): feet on its box and at least
    half of the person over it. Position only: pair it with moves_with."""
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0 or vw <= 0 or vh <= 0 or ph < 0.2 * vh:
        return False
    foot_x, foot_y = px + pw / 2, py + ph
    return vx <= foot_x <= vx + vw and vy <= foot_y <= vy + 1.05 * vh and _share_over(vehicle, person) >= 0.5


def in_trailing_body(vehicle: list, head: tuple, person: list) -> bool:
    """
    A person standing or sitting in the TRAILING part of a vehicle along its direction of travel `head`
    (unit vector): the open bed of a pickup or truck. Cab occupants sit in the leading part, so they are
    not counted. Works for a view from the side, the front or the rear:
      moving toward the camera  -> the bed is the upper part of the box (farther away)
      moving away from it       -> the bed is the lower part (nearer)
      moving sideways           -> the bed is the trailing horizontal part.
    Needs the person's feet on the vehicle's body, and most of the person over the vehicle.
    """
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0 or vw <= 0 or vh <= 0 or ph < 0.2 * vh:
        return False
    foot_x, foot_y = px + pw / 2, py + ph
    if not (vx <= foot_x <= vx + vw and vy <= foot_y <= vy + 1.05 * vh):
        return False
    if _share_over(vehicle, person) < 0.5:
        return False
    half = abs(head[0]) * vw / 2 + abs(head[1]) * vh / 2          # half the vehicle's extent along its travel
    if half <= 0:
        return False
    along = ((px + pw / 2 - (vx + vw / 2)) * head[0] + (py + ph / 2 - (vy + vh / 2)) * head[1]) / half
    return along <= TRAILING_S                                      # +1 = leading edge, -1 = trailing edge


def outside_position(vehicle: list, person: list, head: tuple | None = None) -> str | None:
    """
    'roof' | 'hanging' | 'rear' | None for a person on a bus / jeepney / truck / car.
      roof     feet in the top 35% of the vehicle (or just above it), head at or above its roof line
      rear     standing tall with the feet at the bottom edge, in the TRAILING part along the travel `head` (unit vector):
               on the back step of a jeepney seen from behind or from the side. Needs `head`. A passenger seated inside shows
               only the upper body, with the box ending well above the bottom edge, so it does not count.
      hanging  straddling the left or right edge (a quarter to three quarters of the person over the body),
               with the feet in the lower 60%: on a step, a ladder or the tailgate
    A person (almost) wholly inside the vehicle's box is an occupant - the driver behind the windshield, a seated
    passenger - and never counts (except the 'rear' case above).
    """
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0 or vw <= 0 or vh <= 0 or ph < ROOF_MIN_SHARE * vh:
        return None
    foot_x, foot_y = px + pw / 2, py + ph
    if vx <= foot_x <= vx + vw and vy - 0.1 * vh <= foot_y <= vy + 0.35 * vh and py <= vy + 0.05 * ph:
        return "roof"                   # also the passenger on the far back step of a jeepney that drives toward the camera: only the upper body shows over the roof
    if ph < 0.2 * vh:
        return None
    if head is not None and ph >= REAR_TALL * vh and vx - 0.1 * vw <= foot_x <= vx + 1.1 * vw and vy + REAR_FEET * vh <= foot_y <= vy + 1.08 * vh:
        half = abs(head[0]) * vw / 2 + abs(head[1]) * vh / 2
        along = ((px + pw / 2 - (vx + vw / 2)) * head[0] + (py + ph / 2 - (vy + vh / 2)) * head[1]) / half if half > 0 else 0.0
        if along <= -0.1:
            return "rear"
    if _share_inside(vehicle, person) >= INSIDE_SHARE:
        return None
    inside = max(0.0, min(px + pw, vx + vw) - max(px, vx)) / pw
    if 0.25 <= inside <= 0.75 and (px < vx or px + pw > vx + vw) and vy + 0.4 * vh <= foot_y <= vy + 1.05 * vh:
        return "hanging"
    return None


ROOF_MIN_SHARE = 0.08      # the smallest person box (share of the vehicle's height) that can be on the roof or the far back step
REAR_TALL = 0.55          # a person standing on the back step is at least this tall (share of the vehicle's height)
REAR_FEET = 0.82          # ... with the feet in the bottom 18% of the vehicle's box


# ─── who sits where, without person track numbers ────────────────────────────
# A person on a moving vehicle keeps the same place ON it. That is checked from where people were seen over the last second and a half,
# not from a person's own track: a person the detector is unsure of (most people on a roof or a step) is seen on some looks only and
# gets no stable track number, but each look still has a box on the vehicle at the same place.

SEEN_S = 1.6              # how far back the looks are kept
ATTACH_TOL = 0.05         # the same place: within this share of the vehicle's size, from the look before
ATTACH_MIN_S = 0.4        # ... seen at that place at least this long ago
ATTACH_MIN_LOOKS = 2      # ... on at least this many earlier looks
ATTACH_TRAVEL = 0.2       # the vehicle moved at least this share of its size since then (a pedestrian standing by it is left behind)
HITS_NEEDED = 6           # looks with a passenger outside ...  (a rider that follows a vehicle closely can fake a few looks, not six)
HITS_WINDOW_S = 4.0       # ... within this many seconds flag the vehicle


def place_on(vehicle: list, person: list) -> tuple[float, float]:
    """Where the person's feet are on the vehicle, as shares of the vehicle's size from the middle of its box (the same place on
    the vehicle gives the same numbers whatever the distance to the camera)."""
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    size = max(vw, vh, 1)
    return ((px + pw / 2 - (vx + vw / 2)) / size, (py + ph - (vy + vh / 2)) / size)


def attached_here(memory: dict, t: float, vehicle: list, place: tuple[float, float]) -> bool:
    """True when somebody was already seen at this place on the vehicle (see ATTACH_*) while the vehicle drove on."""
    vx, vy, vw, vh = vehicle
    size = max(vw, vh, 1)
    cx, cy = vx + vw / 2, vy + vh / 2
    matched = []
    for seen_t, scx, scy, places in memory.get("seen", ()):
        age = t - seen_t
        if 0 < age <= SEEN_S and any(math.hypot(place[0] - u, place[1] - v) <= ATTACH_TOL for u, v in places):
            matched.append((age, scx, scy))
    if len(matched) < ATTACH_MIN_LOOKS:
        return False
    age, scx, scy = max(matched)
    return age >= ATTACH_MIN_S and math.hypot(cx - scx, cy - scy) / size >= ATTACH_TRAVEL


def remember_places(memory: dict, t: float, vehicle: list, places: list) -> None:
    """Keep this look (when, where the vehicle was, where people sat on it) for the next ones."""
    from collections import deque
    seen = memory.setdefault("seen", deque())
    vx, vy, vw, vh = vehicle
    seen.append((t, vx + vw / 2, vy + vh / 2, list(places)))
    while seen and t - seen[0][0] > SEEN_S:
        seen.popleft()


HITS_MIN = 3              # the fewest looks that can flag a vehicle, when looks come slowly (a slow backend, a camera with few pictures a second)


def count_hit(memory: dict, t: float, hit: bool) -> bool:
    """Note whether this look had a passenger outside; True when enough looks in the last HITS_WINDOW_S seconds did. Enough = HITS_NEEDED when
    there are plenty of looks (about 10 a second), fewer when looks are rare (a quarter of the looks the window would hold at the rate seen,
    at least HITS_MIN): the rule must not need more looks than the window can hold."""
    from collections import deque
    hits = memory.setdefault("hits", deque())
    looks = memory.setdefault("looks", deque())
    looks.append(t)
    if hit:
        hits.append(t)
    while hits and t - hits[0] > HITS_WINDOW_S:
        hits.popleft()
    while looks and t - looks[0] > HITS_WINDOW_S:
        looks.popleft()
    needed = HITS_NEEDED
    span = looks[-1] - looks[0]
    if len(looks) >= 3 and span > 0.8:                       # the look rate is known: a quarter of the looks the window would hold
        rate = (len(looks) - 1) / span
        needed = max(HITS_MIN, min(HITS_NEEDED, round(0.25 * rate * HITS_WINDOW_S)))
    return len(hits) >= needed
