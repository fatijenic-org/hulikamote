"""
sidewalk_driving - a vehicle driving on the sidewalk or in a bike lane.

Shared banned-type rule (banned_in_zone.py), judged for every vehicle type (default: car, motorcycle, bus, truck,
tricycle). The operator draws the sidewalk; a MOVING vehicle that stays inside for 1.5 s is flagged. A vehicle
only crossing it to reach a driveway is shorter than that, and one left standing there is illegal_parking.
Legal basis: not confirmed (no source found yet): check the LGU ordinance before it is quoted on a ticket.
"""
from engine.violations.box_signs import BoxSigns
from engine.violations.banned_in_zone import BannedInZone
from engine.violations.base import VEHICLE_CLASSES


class SidewalkDriving(BoxSigns, BannedInZone):
    sign_kind = "sidewalk"                       # the object placed for it (engine/overlay_objects.py)
    key = "sidewalk_driving"
    zone_key = "sidewalk_zones"
    color = (255, 0, 160)
    banned_default = VEHICLE_CLASSES
    sustain_s = 1.5
    moving_only = True
