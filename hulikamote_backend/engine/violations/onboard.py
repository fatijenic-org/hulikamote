"""
onboard.py - who is riding ON a vehicle, as opposed to standing or walking next to it. Shared by
pickup_passengers (people in the open back) and riding_outside_vehicle (roof, hanging on).

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


def outside_position(vehicle: list, person: list) -> str | None:
    """
    'roof' | 'hanging' | None for a person on a bus / jeepney / truck.
      roof     feet in the top 30% of the vehicle, head sticking out above its roof line (by 15% of the person)
      hanging  straddling the left or right edge (a quarter to three quarters of the person over the body),
               with the feet in the lower 60%: on a step, a ladder or the tailgate
    A person (almost) wholly inside the vehicle's box is an occupant - the driver behind the windshield, a seated
    passenger - and never counts.
    """
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0 or vw <= 0 or vh <= 0 or ph < 0.2 * vh:
        return None
    if _share_inside(vehicle, person) >= INSIDE_SHARE:
        return None
    foot_x, foot_y = px + pw / 2, py + ph
    if vx <= foot_x <= vx + vw and vy - 0.1 * vh <= foot_y <= vy + 0.3 * vh and py <= vy - 0.15 * ph:
        return "roof"
    inside = max(0.0, min(px + pw, vx + vw) - max(px, vx)) / pw
    if 0.25 <= inside <= 0.75 and (px < vx or px + pw > vx + vw) and vy + 0.4 * vh <= foot_y <= vy + 1.05 * vh:
        return "hanging"
    return None
