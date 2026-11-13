"""
restricted_lane - a vehicle type that is not allowed in a lane (e.g. a car in a bus lane).

Heuristic: the vehicle's ground point is inside the zone and its class (the most common class
over its whole track, so one wrong frame cannot decide) is not in the zone's allowed_classes.
An empty allowed list closes the lane to everyone. A class that is still "unknown" is never judged.

A zone is optional. Drawn zones limit the rule to where they are. With none drawn the whole picture is the lane
(`whole_frame`: the pipeline gives the rule one implicit whole-picture zone, Violation.whole_frame_zone), so a camera that watches
only the restricted road needs no drawing.

Overlay signs (engine/lane_signs.py) say who may use a road: a sign inside a zone sets that zone's allowed vehicle types; with
no zone drawn each vehicle follows the nearest sign, or the tick boxes when there is no sign. Signs are drawn on the evidence
photos and the result video, and belong to the analysis only.
"""
from engine import lane_signs
from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon


class RestrictedLane(Violation):
    key = "restricted_lane"
    zone_key = "restricted_lane_zones"
    color = (0, 255, 255)
    whole_frame = True         # with no zone drawn, the whole picture is the lane (see pipeline._get_scaled_rois)

    def parse_zone(self, raw):
        coords = raw.get("coordinates")
        if not coords:
            return None
        zone = {"polygon": coords, "allowed_classes": raw.get("allowed_classes", ["bus"])}
        if raw.get("sign_points"):
            zone["sign_points"] = raw["sign_points"]
            zone["sign_types"] = raw.get("sign_types", [])
            zone["sign_looks"] = raw.get("sign_looks", [])                      # size / angle / tilt of each sign
            zone["sign_realistic"] = raw.get("sign_realistic", True)
        return zone

    def from_wizard(self, cfg):
        default = cfg.get("allowed_classes", ["bus"])
        signs = lane_signs.usable_signs(cfg.get("signs"))
        zones = []
        for z in cfg.get("rois", []):
            if not z.get("polygon"):
                continue
            inside = [s for s in signs if point_in_polygon(s["x"], s["y"], z["polygon"])]
            zone = {"coordinates": z["polygon"], "allowed_classes": lane_signs.allowed_by(s["type"] for s in inside) if inside else default}
            if inside:                                       # the signs on this lane: they set its rule and are drawn on it
                zone["sign_points"] = [[s["x"], s["y"]] for s in inside]
                zone["sign_types"] = [s["type"] for s in inside]
                zone["sign_looks"] = [lane_signs.look_with_stand(s) for s in inside]
                zone["sign_realistic"] = bool(cfg.get("signs_realistic", True))
            zones.append(zone)
        return zones

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        """The whole picture as one lane: the tick boxes, and the signs (placed in the wizard's 1920x1080 space) moved onto this frame."""
        zone = super().whole_frame_zone(cfg, polygon, frame_size, flow)
        fw, fh = frame_size
        zone["allowed_classes"] = cfg.get("allowed_classes", ["bus"])
        zone["signs"] = [{"type": s["type"], "at": (s["x"] * fw / lane_signs.REF[0], s["y"] * fh / lane_signs.REF[1]),
                          "allowed": lane_signs.SIGNS[s["type"]]["allowed"], "look": lane_signs.look_with_stand(s)}
                         for s in lane_signs.usable_signs(cfg.get("signs"))]
        zone["sign_realistic"] = bool(cfg.get("signs_realistic", True))
        return zone

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "allowed_classes": ["bus", ...]}; the implicit whole-picture zone also has "signs"."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < 2:
            return False

        cx, cy = ledger.history[-1][1], ledger.history[-1][2]
        for zone in zones:
            if point_in_polygon(cx, cy, zone["polygon"]):
                allowed = zone.get("allowed_classes", [])
                if zone.get("signs"):                        # no zone drawn: the nearest sign says who may be here
                    allowed = min(zone["signs"], key=lambda s: (s["at"][0] - cx) ** 2 + (s["at"][1] - cy) ** 2)["allowed"]
                if ledger.vclass != "unknown" and ledger.vclass not in allowed:
                    ledger.violations.add(self.key)
                    return True
        return False

    def draw_zone(self, pipe, frame, index, zone):
        """The zone outline when one was drawn, and every sign standing on the road."""
        super().draw_zone(pipe, frame, index, zone)                              # the implicit whole-picture zone draws nothing
        realistic = zone.get("sign_realistic", True)
        for sign in zone.get("signs", []):
            lane_signs.draw_sign(frame, sign["at"], sign["type"], **sign.get("look", {}), realistic=realistic)
        looks = zone.get("sign_looks", [])
        for i, (at, kind) in enumerate(zip(zone.get("sign_points", []), zone.get("sign_types", []))):
            lane_signs.draw_sign(frame, at, kind, **(looks[i] if i < len(looks) else {}), realistic=realistic)
