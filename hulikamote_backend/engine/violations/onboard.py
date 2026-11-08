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
      roof     feet in the top 30% of the vehicle, head at or above its roof line
      hanging  straddling the left or right edge (a quarter to three quarters of the person over the body),
               with the feet in the lower 60%: on a step, a ladder or the tailgate
    """
    vx, vy, vw, vh = vehicle
    px, py, pw, ph = person
    if pw <= 0 or ph <= 0 or vw <= 0 or vh <= 0 or ph < 0.2 * vh:
        return None
    foot_x, foot_y = px + pw / 2, py + ph
    if vx <= foot_x <= vx + vw and vy - 0.1 * vh <= foot_y <= vy + 0.3 * vh and py <= vy + 0.15 * vh:
        return "roof"
    inside = max(0.0, min(px + pw, vx + vw) - max(px, vx)) / pw
    if 0.25 <= inside <= 0.75 and (px < vx or px + pw > vx + vw) and vy + 0.4 * vh <= foot_y <= vy + 1.05 * vh:
        return "hanging"
    return None
