"""
illegal_loading - a bus, jeepney, tricycle or truck stopping to load or unload where it is not allowed.

Shared stopped-in-a-zone rule (stopped_in_zone.py), judged only for the vehicle types that load in the road
(default: bus, jeepney, tricycle and truck). The operator draws the no-loading
area (a closed bus stop, a busy corner); one of those vehicles standing still inside it for longer than the
limit (default 8 s) is flagged. Vehicles outside the zone, other types, and a car left standing (that is
illegal_parking) are never flagged here.
Legal basis: MMDA / LGU loading-and-unloading rules (to be confirmed with the Zamboanga City ordinance
before it is quoted on a ticket).
"""
from engine.violations.stopped_in_zone import StoppedInZone


class IllegalLoading(StoppedInZone):
    key = "illegal_loading"
    zone_key = "loading_zones"
    auto = True
    color = (0, 140, 255)
    default_limit_s = 8.0
    default_classes = ("bus", "jeepney", "tricycle", "truck")
