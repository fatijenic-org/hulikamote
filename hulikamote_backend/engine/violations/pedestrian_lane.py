"""
pedestrian_lane - a vehicle stopped on a crosswalk (blocking pedestrians).

Shared stopped-in-a-zone rule (stopped_in_zone.py) with a 3 s default limit on the crosswalk zone.
"""
from engine.violations.stopped_in_zone import StoppedInZone


class PedestrianLane(StoppedInZone):
    key = "pedestrian_lane"
    zone_key = "pedestrian_lane_zones"
    color = (255, 255, 255)
    default_limit_s = 3.0
