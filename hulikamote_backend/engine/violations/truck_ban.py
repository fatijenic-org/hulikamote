"""
truck_ban - a truck on a road or lane that is closed to trucks (truck ban / truck lane).

Shared banned-type rule (banned_in_zone.py): the operator draws the closed road or lane; a truck that stays inside
for 1 s is flagged. There is no clock: for a ban that only applies at certain hours, analyse footage from those
hours. The wizard's vehicle-type picker can ban more types than trucks.
Legal basis: MMDA truck-ban / truck-lane rules and LGU ordinances (to be confirmed for Zamboanga City).
"""
from engine.violations.banned_in_zone import BannedInZone


class TruckBan(BannedInZone):
    key = "truck_ban"
    zone_key = "truck_ban_zones"
    auto = True
    color = (0, 0, 200)
    banned_default = ("truck",)
