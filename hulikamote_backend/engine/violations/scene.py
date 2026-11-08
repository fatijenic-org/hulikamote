"""
scene.py - what the traffic around a stopped vehicle is doing (used by the automatic parking / loading rules).

With no drawn zone, "stopped" alone proves nothing: a car at the front of a red-light queue is stopped too.
A vehicle is only parked when other vehicles keep DRIVING past it along the road. The road direction is the
one learned from traffic (FlowField.road_axis); cross traffic at a junction heads another way and does not count.
"""
import math

from engine.violations.geometry import TURN_ALIGN_COS, dot, heading, is_driving

NEIGHBOUR_WIDTHS = 6.0      # a passing vehicle counts when it is within this many box widths of the stopped one
FLOW_MEMORY_S = 3.0         # traffic seen driving past this recently still counts (it comes in gaps)
FRESH_S = 1.0               # a vehicle not seen for longer than this has left the scene


def traffic_flows_past(mgr, ledger, field, frame_size) -> bool:
    """True when another vehicle is driving along the learned road axis right next to this one."""
    t, cx, cy, width = ledger.path[-1]
    axis = field.road_axis(cx, cy, *frame_size)
    if axis is None:                                    # road not learned here yet, or traffic goes every which way
        return False
    radius = NEIGHBOUR_WIDTHS * max(width, 1)
    for other in mgr.ledgers.values():
        if other is ledger or not other.path or "person" in (other.vclass, other.latest_class):
            continue
        ot, ox, oy, _w = other.path[-1]
        if t - ot > FRESH_S or math.hypot(ox - cx, oy - cy) > radius:
            continue
        head = heading(other)
        if head is not None and is_driving(other) and abs(dot(head, axis)) >= TURN_ALIGN_COS:
            return True
    return False


def recently_flowing(mgr, ledger, zone: dict, key: str) -> bool:
    """Automatic zones only: has traffic driven past this vehicle in the last FLOW_MEMORY_S seconds?
    Call it every frame the vehicle is stopped, so the memory stays fresh."""
    t = ledger.path[-1][0]
    memory = f"{key}:flow"
    if traffic_flows_past(mgr, ledger, zone["field"], zone["frame_size"]):
        ledger.stop_timers[memory] = t
    return t - ledger.stop_timers.get(memory, -math.inf) <= FLOW_MEMORY_S
