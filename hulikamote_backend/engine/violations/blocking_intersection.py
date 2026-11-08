"""
blocking_intersection - a vehicle that stops inside the junction box and blocks the cross traffic.

Shared stopped-in-a-zone rule (stopped_in_zone.py): the operator draws the junction box, and a vehicle
that stands still inside it for longer than the limit (default 5 s) is flagged. A car that is moving
through, or waiting BEFORE the box, is never flagged. Legal basis: local "anti-obstruction" rules (to be
confirmed with the LGU before it is quoted on a ticket).
"""
from engine.violations.stopped_in_zone import StoppedInZone


class BlockingIntersection(StoppedInZone):
    key = "blocking_intersection"
    zone_key = "intersection_zones"
    color = (180, 0, 180)
    default_limit_s = 5.0
