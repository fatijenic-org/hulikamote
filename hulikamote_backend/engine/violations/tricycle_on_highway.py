"""
tricycle_on_highway - a tricycle on a national highway where tricycles are not allowed.

Shared banned-type rule (banned_in_zone.py): the operator draws the highway section; a tricycle that stays inside
for 1 s is flagged. Needs a vehicle detector that knows "tricycle" (the stock COCO model does not: use the
6-class Philippine vehicle model).
Legal basis: DILG MC 2020-036, reinforced by MC 2023-195 (LTO rules behind them). LGUs may allow tricycles on
some highway sections, so draw the zone only where the ban applies (to be confirmed for Zamboanga City).
"""
from engine.violations.banned_in_zone import BannedInZone


class TricycleOnHighway(BannedInZone):
    key = "tricycle_on_highway"
    zone_key = "highway_zones"
    auto = True
    color = (200, 200, 0)
    banned_default = ("tricycle",)
