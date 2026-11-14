"""
truck_ban - a truck on a road or lane that is closed to trucks (truck ban / truck lane).

Shared banned-type rule (banned_in_zone.py): the operator draws the closed road or lane; a truck that stays inside
for 1 s is flagged. The ban can have hours (`ban_windows`, e.g. 6-9 AM and 4-7 PM): then only the time inside them counts, judged by
the time of the video (engine/video_clock.py: typed by the operator, the clock in the picture, the file information, the file name);
with no time found the truck is still flagged but its ticket says "time not confirmed". With no hours set the ban holds all day.
The wizard's vehicle-type picker can ban more types than trucks.
Legal basis: MMDA truck-ban / truck-lane rules and LGU ordinances (to be confirmed for Zamboanga City).
"""
import cv2
import numpy as np

from engine import overlay_objects
from engine.violations.box_signs import BoxSigns
from engine.violations.banned_in_zone import BannedInZone

# Where the time of the video comes from, in words for the badge.
SHORT_SOURCE = {"operator": "typed time", "screen": "screen clock", "metadata": "file info", "filename": "file name",
                "live": "live clock", "estimate": "estimate only", "none": "time not found"}
IN_FORCE_TEXT = {True: "BAN IN FORCE", False: "outside ban hours", None: "ban hours unknown"}
IN_FORCE_BGR = {True: (80, 80, 255), False: (210, 210, 210), None: (0, 190, 255)}


def draw_time_badge(frame, info, below_lights: bool = False) -> None:
    """The time of the video in the upper right corner of the whole frame (a dark badge, big time, small line under it: where the
    time comes from and, when ban hours are set, whether the ban is in force). Changes `frame`."""
    if not info:
        return
    fh, fw = frame.shape[:2]
    k = max(0.5, fw / 1280.0)
    moment = info.get("moment")
    big = moment.strftime("%I:%M:%S %p").lstrip("0") if moment else "TIME UNKNOWN"
    hours = bool(info.get("hours"))
    bits = [SHORT_SOURCE.get(info.get("source"), "")] + ([IN_FORCE_TEXT[info.get("in_force")]] if hours else [])
    small = "  |  ".join(b for b in bits if b)
    colour = IN_FORCE_BGR[info.get("in_force")] if hours else (210, 210, 210)
    font = cv2.FONT_HERSHEY_SIMPLEX
    (w1, h1), _ = cv2.getTextSize(big, font, 0.9 * k, max(1, int(2 * k)))
    (w2, h2), _ = cv2.getTextSize(small, font, 0.5 * k, 1)
    pad, margin = max(4, int(8 * k)), max(6, fh // 80)
    shift = int(4.6 * overlay_objects.object_width(fw, "traffic_light_red", 1.0)) if below_lights else 0   # the simulated light hangs up there
    x2, y1 = fw - margin, margin + shift
    x1, y2 = max(0, x2 - max(w1, w2) - 2 * pad), min(fh, y1 + h1 + h2 + 3 * pad)
    if x2 <= x1 or y2 <= y1:
        return
    frame[y1:y2, x1:x2] = (frame[y1:y2, x1:x2] * 0.35).astype(np.uint8)
    cv2.putText(frame, big, (x1 + pad, y1 + pad + h1), font, 0.9 * k, (255, 255, 255), max(1, int(2 * k)), cv2.LINE_AA)
    if small:
        cv2.putText(frame, small, (x1 + pad, y1 + 2 * pad + h1 + h2), font, 0.5 * k, colour, max(1, int(k)), cv2.LINE_AA)


class TruckBan(BoxSigns, BannedInZone):
    sign_kind = "no_trucks"                       # the object placed for it (engine/overlay_objects.py)
    key = "truck_ban"
    zone_key = "truck_ban_zones"
    whole_frame = True
    color = (0, 0, 200)
    banned_default = ("truck",)

    def prepare(self, pipe, frame, detections, zones, t):
        """Also note the time of this frame for the badge (see draw_time_badge)."""
        super().prepare(pipe, frame, detections, zones, t)
        clock = getattr(pipe, "clock", None)
        flags = [z.get("ban_active") for z in zones if z.get("ban_windows")]
        pipe.truck_time = {"moment": clock.at(t) if clock is not None else None, "source": getattr(clock, "source", "none"),
                           "hours": bool(flags), "in_force": None if (not flags or None in flags) else any(flags)}

    def draw_zone(self, pipe, frame, index, zone):
        super().draw_zone(pipe, frame, index, zone)
        if index == 0:                                   # once per picture, however many zones or boxes there are
            lights = getattr(pipe, "_light_states", None) or {}
            draw_time_badge(frame, getattr(pipe, "truck_time", None), below_lights=any(left is not None for _s, left in lights.values()))
