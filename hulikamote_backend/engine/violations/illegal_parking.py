"""
illegal_parking - a vehicle left standing inside a no-parking zone.

Heuristic: inside the zone and slower than 25 px/s (box jitter on a parked car stays below this,
a driving car is far above) for longer than the zone's own time limit (default 180 s).
Needs 5+ position updates so a new track is not judged on nothing.
Whole picture (nothing drawn, no sign): the whole picture is the zone and the vehicle must also be stopped while
other traffic keeps driving past it along the learned road (a red-light queue is not parking). The enforcer's time
limit applies. Ticking the rule means "no parking on this road".
A vehicle with a blinking indicator or hazard lights has not parked yet (it signals, so it is pulling in or out, or waiting
for a gap): the stopwatch is held while the lights blink and starts again when they stop (see indicators.py).
Overlay "NO PARKING" signs (engine/loading_signs.py, same as the no-loading signs): the operator places a sign on the picture and
resizes it; the sign's box is a no-parking area. It is drawn on the evidence photos and the result video only, never written into the
video, and belongs to the analysis. Drawn zones and signs can be mixed; the rule's time limit applies to both.
Each sign says WHY parking is banned there (engine/parking_reasons.py, RA 4136 Section 46): an official sign, within 4 m of a fire hydrant,
within 4 m of a fire station driveway, within 6 m of a corner, or in front of a private driveway. A flagged vehicle carries that reason as a
label on its evidence photos. Section 46 also bans parking in an intersection, on a crosswalk and beside a parked vehicle (double parking):
those are judged by the rules "Blocking the intersection", "Pedestrian lane blocked" and "Double parking".
"""
import math

from engine import loading_signs, marks, overlay_objects, parking_reasons
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, point_in_polygon
from engine.violations.indicators import is_signalling, sample_indicators
from engine.violations.scene import recently_flowing

BLINK_LOOKBACK_S = 5.0      # how much of the recent past is read for a blinking indicator
BLINK_MEMORY_S = 3.0        # a blink seen this recently still counts: a lamp is not read clearly in every frame


class IllegalParking(Violation):
    key = "illegal_parking"
    zone_key = "illegal_parking_zones"
    whole_frame = True
    needs_flow = True
    color = (255, 0, 0)

    MIN_UPDATES = 5

    def parse_zone(self, raw):
        coords = raw.get("coordinates")
        if not coords:
            return None
        zone = {"polygon": coords, "time_limit": float(raw.get("time_limit", 180.0))}
        if raw.get("sign"):
            zone["sign"] = True                      # drawn as a sign, not as a plain outline
            zone["reason"] = parking_reasons.kind_of({"kind": raw.get("reason")})
            zone.update(overlay_objects.parsed_fields(raw, coords, zone["reason"]))
        return zone

    def from_wizard(self, cfg):
        """Drawn zones, then one zone per sign (its box); all with the same time limit."""
        limit = float(cfg.get("time_limit", 10.0))
        zones = [{"coordinates": z["polygon"], "time_limit": limit} for z in cfg.get("rois", []) if z.get("polygon")]
        for sign in loading_signs.usable_signs(cfg.get("signs")):
            kind = parking_reasons.kind_of(sign)
            zones.append({"coordinates": loading_signs.polygon(sign), "time_limit": limit, "sign": True, "reason": kind,
                          **overlay_objects.zone_fields(sign, kind, cfg)})
        return zones

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("sign"):
            overlay_objects.draw_zone_object(frame, zone, parking_reasons.kind_of({"kind": zone.get("reason")}))
        else:
            super().draw_zone(pipe, frame, index, zone)

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        return {"polygon": polygon, "time_limit": float(cfg.get("time_limit", 10.0)),
                "whole_frame": True, "field": flow, "frame_size": frame_size}

    def prepare(self, pipe, frame, detections, zones, t):
        """Read the indicators of vehicles that stand still. A moving vehicle is never judged here, so it is not read."""
        sample_indicators(pipe, frame, detections, wanted=lambda ledger: ledger.get_speed() < STOP_SPEED)

    def signalling(self, ledger, t) -> bool:
        """A blinking indicator or hazard light, seen in the last few seconds."""
        memory = f"{self.key}:blink"
        if is_signalling(ledger, t, BLINK_LOOKBACK_S):
            ledger.stop_timers[memory] = t
        return t - ledger.stop_timers.get(memory, -math.inf) <= BLINK_MEMORY_S

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "time_limit": seconds}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES:
            return False

        t, cx, cy = ledger.history[-1][0], ledger.history[-1][1], ledger.history[-1][2]
        zone = None
        if ledger.get_speed() < STOP_SPEED:
            zone = next((z for z in zones if point_in_polygon(cx, cy, z["polygon"])), None)

        if zone is None:
            ledger.stationary_start_time = None
            marks.clear_timer(ledger, self.key)
            return False
        if self.signalling(ledger, t):
            ledger.stationary_start_time = None     # lights are blinking: not parked yet, the stopwatch starts again when they stop
            marks.clear_timer(ledger, self.key)
            return False
        if ledger.stationary_start_time is None:
            ledger.stationary_start_time = t
            return False
        flowing = recently_flowing(mgr, ledger, zone, self.key) if zone.get("whole_frame") else True
        limit = zone.get("time_limit", 180.0)
        elapsed = t - ledger.stationary_start_time
        if flowing:     # the stopwatch on the vehicle's box runs from the first still frame until it moves off or leaves
            marks.set_timer(ledger, self.key, f"PARKED {marks.clock(elapsed)} / {marks.clock(limit)}", elapsed >= limit, t)
        if elapsed >= limit and flowing:
            ledger.violations.add(self.key)
            if zone.get("reason"):                   # say why on the evidence photos: "Within 4 m of fire hydrant"
                box = ledger.history[-1][3]
                marks.set_marks(ledger, self.key, box, [(box, parking_reasons.mark_of(zone["reason"]), marks.RED)])
            return True
        return False
