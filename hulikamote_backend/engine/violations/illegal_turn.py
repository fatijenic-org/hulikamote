"""
illegal_turn - turning into a prohibited direction inside a zone.

Heuristic: the operator draws a zone and an arrow for the forbidden turn (an arrow pointing left =
"no left turn"). A vehicle is flagged when, inside the zone, its heading has swung by 45 deg or more
since it entered, now points along the arrow (within 45 deg), and did NOT already point that way on
entry (driving straight along the arrow is not a turn). Headings need half a box width (at least
15 px) of travel, so a stopped car's box jitter never counts. See geometry.turned_into.

Whole picture (nothing drawn): the whole picture is the zone and the enforcer sets which turns are
banned at this camera (banned_turns: "left" and / or "right", default left). A vehicle is flagged when its heading
swings 45 to 150 deg (wider is a U-turn) toward a banned side since it first appeared. See geometry.turned_side.
"""
from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon, turned_into, turned_side


class IllegalTurn(Violation):
    key = "illegal_turn"
    zone_key = "illegal_turn_zones"
    color = (0, 128, 255)
    whole_frame = True

    MIN_PATH_POINTS = 4

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        banned = [s for s in (cfg.get("banned_turns") or ["left"]) if s in ("left", "right")]
        return {"polygon": polygon, "whole_frame": True, "banned_turns": banned or ["left"]}

    def parse_zone(self, raw):
        if not raw.get("coordinates"):
            return None
        vec = raw.get("prohibited_vector", {})
        return {"polygon": raw["coordinates"], "vector": (float(vec.get("x_dir", 0.0)), float(vec.get("y_dir", 0.0)))}

    def from_wizard(self, cfg):
        # The arrow is the PROHIBITED turn direction; zones without one are skipped
        return [{"coordinates": z["polygon"], "prohibited_vector": z["vector"]}
                for z in cfg.get("rois", []) if z.get("polygon") and z.get("vector")]

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "vector": (x, y)} - the arrow of the forbidden turn (automatic: "banned_turns")."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        _t, cx, cy, _w = ledger.path[-1]
        for i, zone in enumerate(zones):
            if not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            key = (self.key, i)
            if zone.get("whole_frame"):
                hit = turned_side(ledger, key) in zone["banned_turns"]
            else:
                hit = turned_into(ledger, key, zone.get("vector"))
            if hit:
                ledger.violations.add(self.key)
                return True
        return False
