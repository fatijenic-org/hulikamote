"""
illegal_loading - a bus, jeepney, tricycle or truck stopping to load or unload where it is not allowed.

Shared stopped-in-a-zone rule (stopped_in_zone.py), judged only for the vehicle types that load in the road
(default: bus, jeepney, tricycle and truck). The operator draws the no-loading
area (a closed bus stop, a busy corner); one of those vehicles standing still inside it for longer than the
limit (default 8 s) is flagged. Vehicles outside the zone, other types, and a car left standing (that is
illegal_parking) are never flagged here.

Overlay signs (engine/loading_signs.py) work as zones that can be placed anywhere on the picture and resized: the sign's box is a
no-loading area. They are drawn on the evidence photos and the result video, and belong to the analysis only. Drawn zones and signs
can be mixed. With nothing drawn and no sign, the whole picture is watched.
Legal basis: MMDA / LGU loading-and-unloading rules (to be confirmed with the Zamboanga City ordinance
before it is quoted on a ticket).
"""
from engine import loading_signs, overlay_objects
from engine.violations.stopped_in_zone import StoppedInZone


class IllegalLoading(StoppedInZone):
    key = "illegal_loading"
    zone_key = "loading_zones"
    whole_frame = True
    needs_flow = True
    color = (0, 140, 255)
    default_limit_s = 8.0
    default_classes = ("bus", "jeepney", "tricycle", "truck")

    def parse_zone(self, raw):
        zone = super().parse_zone(raw)
        if zone and raw.get("sign"):
            zone["sign"] = True                      # drawn as an object, not as a plain outline
            zone.update(overlay_objects.parsed_fields(raw, zone["polygon"], "no_loading"))
        return zone

    def from_wizard(self, cfg):
        """Drawn zones, then one zone per sign (its box), all with the same time limit and vehicle types."""
        zones = super().from_wizard(cfg)
        limit = float(cfg.get("time_limit", self.default_limit_s))
        extra = self._zone_extra({"classes": cfg.get("banned_classes")})
        for sign in loading_signs.usable_signs(cfg.get("signs")):
            zones.append({"coordinates": loading_signs.polygon(sign), "time_limit": limit, **extra, "sign": True,
                          **overlay_objects.zone_fields(sign, "no_loading", cfg)})
        return zones

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("sign"):
            overlay_objects.draw_zone_object(frame, zone, "no_loading")
        else:
            super().draw_zone(pipe, frame, index, zone)
