"""
banned_in_zone.py - the shared rule behind "this type of vehicle must not be here":
truck_ban (a banned road or lane), tricycle_on_highway (a national highway) and sidewalk_driving (the sidewalk).

Heuristic: the vehicle's class (the most common class over its whole track, so one wrong frame cannot decide;
a class still "unknown" is never judged) is in the zone's banned list AND its ground point stays inside the
zone for `sustain_s` seconds (a vehicle only clipping a corner is ignored). moving_only rules (the sidewalk) also
need the vehicle to be moving, so a car left standing there is illegal_parking, not "driving on the sidewalk".
The banned list comes from the wizard's vehicle-type picker; when it is empty the rule's own default is used.
This is the mirror image of restricted_lane, which lists the types that ARE allowed.
Whole-picture mode (truck_ban, tricycle_on_highway): with nothing drawn the whole picture is the banned area; ticking the rule means
"these types are banned on this road".

Ban hours (optional, `ban_windows`: [["06:00", "09:00"], ["16:00", "19:00"]]): when set, the ban only holds inside those hours.
The time of every frame comes from the pipeline's clock (engine/video_clock.py: the camera's own time for live, the time found in
the video - or typed by the operator - for an analysis). Three outcomes per frame, kept in the zone as `ban_active`:
  True   no hours were set, or the time is inside a window: the ban holds
  False  the time is known and outside every window: nothing is flagged
  None   the time is NOT known: the vehicle is flagged anyway, and the ticket says "time not confirmed" for a human to check
"""
from engine.video_clock import in_windows, parse_windows
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, point_in_polygon


class BannedInZone(Violation):
    banned_default: tuple = ()
    sustain_s = 1.0
    moving_only = False
    MIN_UPDATES = 5

    def _banned(self, source: dict) -> list:
        return list(source.get("banned_classes") or self.banned_default)

    def parse_zone(self, raw):
        if not raw.get("coordinates"):
            return None
        return {"polygon": raw["coordinates"], "banned_classes": self._banned(raw), "ban_windows": raw.get("ban_windows") or []}

    def from_wizard(self, cfg):
        banned = self._banned(cfg)
        hours = cfg.get("ban_windows") or []
        return [{"coordinates": z["polygon"], "banned_classes": banned, "ban_windows": hours}
                for z in cfg.get("rois", []) if z.get("polygon")]

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        return {"polygon": polygon, "banned_classes": self._banned(cfg), "whole_frame": True, "ban_windows": cfg.get("ban_windows") or []}

    def prepare(self, pipe, frame, detections, zones, t):
        """Once per frame: is the ban in force right now? (see "Ban hours" at the top of this file)"""
        clock = getattr(pipe, "clock", None)
        moment = None
        for zone in zones:
            windows = parse_windows(zone.get("ban_windows"))
            if not windows:
                zone["ban_active"] = True                    # no hours: banned all day, as before
                continue
            if moment is None and clock is not None:
                moment = clock.at(t)
            zone["ban_active"] = None if moment is None else in_windows(moment, windows)

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "banned_classes": ["truck", ...], "ban_active": True | False | None}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False
        t, cx, cy = ledger.history[-1][0], ledger.history[-1][1], ledger.history[-1][2]
        timer = f"{self.key}:inside"                      # own timer, never shared with the stop timers
        inside = ledger.vclass != "unknown" and any(
            ledger.vclass in z.get("banned_classes", []) and z.get("ban_active", True) is not False
            and point_in_polygon(cx, cy, z["polygon"]) for z in zones
        )
        if not inside or (self.moving_only and ledger.get_speed() < STOP_SPEED):
            ledger.stop_timers.pop(timer, None)
            return False
        if t - ledger.stop_timers.setdefault(timer, t) >= self.sustain_s:
            ledger.violations.add(self.key)
            return True
        return False
