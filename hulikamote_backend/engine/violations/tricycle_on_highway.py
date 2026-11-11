"""
tricycle_on_highway - a tricycle on a national highway where tricycles are not allowed.

Shared banned-type rule (banned_in_zone.py): a tricycle that stays inside the zone for 1 s is flagged. Needs a vehicle
detector that knows "tricycle" (the stock COCO model does not: use the 6-class Philippine vehicle model).

A zone is optional (`zoneless`: the pipeline gives the rule one implicit whole-picture zone, Violation.auto_zone). The video cannot
show whether a road is a national highway, or whether the city exempts a section of it, so the operator states it: ticking the
rule for a camera says "the whole view is a road where tricycles are banned". Draw a zone only to limit the rule to the banned
part, for example when the same view also shows a side street or an exempted section that tricycles may use.

Legal basis: DILG MC 2020-036 (17 Feb 2020) bans tricycles and pedicabs from national highways; MC 2023-195 (6 Dec 2023) reinforces it.
Each LGU lists its national highways, and the portions tricycles may use where there is no alternative route, in its Tricycle Route
Plan, and may allow those by ordinance. So whether a given road is banned is a local fact to confirm for Zamboanga City.
"""
from engine.violations.banned_in_zone import BannedInZone


class TricycleOnHighway(BannedInZone):
    key = "tricycle_on_highway"
    zone_key = "highway_zones"
    auto = True
    zoneless = True            # with no zone drawn, the whole picture is the banned road (see pipeline._get_scaled_rois)
    color = (200, 200, 0)
    banned_default = ("tricycle",)
