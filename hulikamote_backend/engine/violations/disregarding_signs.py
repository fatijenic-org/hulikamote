"""
disregarding_signs - breaking a traffic sign. One zone per sign; each sign type reuses a shared rule.

  no_entry    moving along the arrow (the prohibited direction) inside the zone (within 45 deg)
  no_turn     turning into the arrow direction (no left / right / U-turn), see geometry.turned_into
  no_stopping stopped in the zone longer than time_limit (default 5 s)
  vehicle_ban a banned vehicle type in the zone (e.g. "no trucks")
  stop        crossed the stop line without first coming to a full stop (under 25 px/s over 1 s)
"""
from engine import line_paint, overlay_objects
from engine.violations.base import Violation
from engine.violations.geometry import (
    STOP_SPEED, crossed_line, moving_along, point_in_polygon, recent_speed, stopped_too_long, turned_into_any, vectors_of,
)

SIGN_TYPES = ("no_entry", "no_turn", "no_stopping", "vehicle_ban", "stop")


class DisregardingSigns(Violation):
    key = "disregarding_signs"
    zone_key = "sign_zones"
    color = (200, 200, 0)

    MIN_PATH_POINTS = 4

    def parse_zone(self, raw):
        if not (raw.get("coordinates") and raw.get("sign")):
            return None
        vectors = vectors_of(raw) or [(0.0, 0.0)]
        return {
            "polygon": raw["coordinates"],
            "sign": raw["sign"],
            "vector": vectors[0],
            "vectors": vectors,
            "stop_line": raw.get("stop_line"),
            "time_limit": float(raw.get("time_limit", 5.0)),
            "banned_classes": raw.get("banned_classes", []),
        }

    def from_wizard(self, cfg):
        return [
            {
                "coordinates": z["polygon"],
                "sign": z["sign"],
                # Arrow signs (no entry / no turn) use the arrow; the stop sign uses its points as the stop line
                "prohibited_vector": z.get("vector"),
                **({"prohibited_vectors": z["vectors"]} if z.get("vectors") else {}),
                "stop_line": z.get("ui_vector") if z["sign"] == "stop" else None,
                "time_limit": float(cfg.get("time_limit", 5.0)),
                "banned_classes": cfg.get("banned_classes", []),
            }
            for z in cfg.get("rois", []) if z.get("polygon") and z.get("sign")
        ]

    # A stop zone is drawn like a real one: the stop line painted on the road (vehicles drive over it) and a stop sign beside its right end.
    # The paint and the sign are only pictures; the rule judges the line's points. Other sign types keep their outline and arrow.
    STOP_PAINT = {"style": "solid_white", "width": 2.4, "wear": 0.15, "taper": 0.5}

    def draw_zone(self, pipe, frame, index, zone):
        line = zone.get("stop_line") if zone.get("sign") == "stop" else None
        if line and len(line) >= 2:
            boxes = [d.bbox for d in getattr(pipe, "_draw_dets", ()) if getattr(d, "cls", None) in line_paint.OCCLUDES]
            line_paint.draw(frame, line, self.STOP_PAINT, True, occluders=boxes)
        super().draw_zone(pipe, frame, index, zone)
        if line and len(line) >= 2:
            end = max(line, key=lambda p: p[0])
            overlay_objects.draw_object(frame, (end[0] + 0.035 * frame.shape[1], end[1]), "stop_sign", {"scale": 1.2}, True)

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon", "sign", "vector"?, "stop_line"?, "time_limit"?, "banned_classes"?}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        _t, cx, cy, _w = ledger.path[-1]

        for i, zone in enumerate(zones):
            key, sign = ("sign", i), zone.get("sign")
            in_zone = point_in_polygon(cx, cy, zone["polygon"])
            if sign == "no_stopping":
                broken = stopped_too_long(ledger, key, in_zone, zone.get("time_limit") or 5.0)
            elif not in_zone:
                continue
            elif sign == "no_entry":
                broken = moving_along(ledger, zone.get("vector"))
            elif sign == "no_turn":
                broken = turned_into_any(ledger, key, zone.get("vectors") or [zone.get("vector")])
            elif sign == "vehicle_ban":
                broken = ledger.vclass in zone.get("banned_classes", [])
            elif sign == "stop":
                if recent_speed(ledger, 1.0) < STOP_SPEED:
                    ledger.made_stop.add(key)
                crossed = crossed_line(ledger, key, zone.get("stop_line"))
                broken = crossed and key not in ledger.made_stop
            else:
                continue
            if broken:
                ledger.violations.add(self.key)
                return True
        return False
