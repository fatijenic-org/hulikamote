"""
truck_ban - a truck on a road or lane that is closed to trucks (truck ban / truck lane).

Shared banned-type rule (banned_in_zone.py): the operator draws the closed road or lane; a truck that stays inside
for 1 s is flagged. The ban can have hours (`ban_windows`, e.g. 6-9 AM and 4-7 PM): then only the time inside them counts, judged by
the time of the video (engine/video_clock.py: typed by the operator, the clock in the picture, the file information, the file name);
with no time found the truck is still flagged but its ticket says "time not confirmed". With no hours set the ban holds all day.
The wizard's vehicle-type picker can ban more types than trucks.
Legal basis: MMDA truck-ban / truck-lane rules and LGU ordinances (to be confirmed for Zamboanga City).
"""
from engine.violations.banned_in_zone import BannedInZone


class TruckBan(BannedInZone):
    key = "truck_ban"
    zone_key = "truck_ban_zones"
    whole_frame = True
    color = (0, 0, 200)
    banned_default = ("truck",)
