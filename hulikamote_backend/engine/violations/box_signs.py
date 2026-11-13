"""
box_signs.py - overlay boxes (engine/loading_signs.py + engine/overlay_objects.py) for any rule that works on drawn zones.

An operator places a real-looking object (a sign on a pole, a hydrant ...) on the picture and sizes the box around it: the box IS a zone of
the rule, made exactly like a zone the operator would have drawn there (same time limit, same vehicle types, same ban hours), so the rule
judges it with no new logic. The box is drawn as its object (and a faint patch for the area) on the evidence photos and the result video,
never written into the video, and belongs to the analysis. Drawn zones and boxes can be mixed.

Use: `class MyRule(BoxSigns, StoppedInZone): sign_kind = "double_parking"` (a key of overlay_objects.KINDS). Put BoxSigns first.
"""
from engine import loading_signs, overlay_objects


class BoxSigns:
    sign_kind = "sign"

    def parse_zone(self, raw):
        zone = super().parse_zone(raw)
        if zone is not None and raw.get("sign"):
            zone["sign"] = True                      # drawn as an object, not as a plain outline
            zone.update(overlay_objects.parsed_fields(raw, zone["polygon"], self.sign_kind))
        return zone

    def from_wizard(self, cfg):
        zones = super().from_wizard(cfg)
        for sign in loading_signs.usable_signs(cfg.get("signs")):
            drawn_like = {**cfg, "rois": [{"polygon": loading_signs.polygon(sign)}]}      # the box, as if it had been drawn
            for zone in super().from_wizard(drawn_like):
                zones.append({**zone, "sign": True, **overlay_objects.zone_fields(sign, self.sign_kind, cfg)})
        return zones

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("sign"):
            overlay_objects.draw_zone_object(frame, zone, self.sign_kind)
        else:
            super().draw_zone(pipe, frame, index, zone)
