"""
pedestrian_lane - a vehicle stopped on a crosswalk (blocking pedestrians).

Shared stopped-in-a-zone rule (stopped_in_zone.py) with a 3 s default limit on the crosswalk zone.

Overlay crosswalks (engine/crosswalk_overlay.py) are for testing: the operator places a painted zebra crossing on the picture and it IS a crosswalk
zone (drawn zones and overlay crosswalks can be mixed). They are drawn on the evidence photos and the result video, never written into the video.
"""
from engine import crosswalk_overlay
from engine.violations.stopped_in_zone import StoppedInZone


OCCLUDES = ("car", "motorcycle", "bus", "truck", "tricycle", "bicycle", "person")


class PedestrianLane(StoppedInZone):
    key = "pedestrian_lane"
    zone_key = "pedestrian_lane_zones"
    color = (255, 255, 255)
    default_limit_s = 3.0

    def parse_zone(self, raw):
        zone = super().parse_zone(raw)
        if zone is not None and raw.get("overlay"):                    # a painted crosswalk: how it looks travels with the zone
            zone["overlay"] = raw["overlay"]
            zone["realistic"] = bool(raw.get("realistic", True))
        return zone

    def from_wizard(self, cfg):
        zones = super().from_wizard(cfg)
        limit = float(cfg.get("time_limit", self.default_limit_s))
        realistic = bool(cfg.get("crosswalks_realistic", True))
        extra = self._zone_extra({"classes": cfg.get("banned_classes")})          # same vehicle filter as a drawn zone
        for crosswalk in crosswalk_overlay.usable(cfg.get("crosswalks")):
            zones.append({"coordinates": crosswalk_overlay.polygon(crosswalk), "time_limit": limit,
                          "overlay": {"stripes": crosswalk["stripes"], "wear": crosswalk["wear"]}, "realistic": realistic, **extra})
        return zones

    def draw_zone(self, pipe, frame, index, zone):
        if zone.get("overlay"):                                        # painted on the road: no outline, just the zebra
            boxes = [d.bbox for d in getattr(pipe, "_draw_dets", ()) if getattr(d, "cls", None) in OCCLUDES]    # vehicles drive over the paint
            crosswalk_overlay.draw(frame, zone["polygon"], zone["overlay"], zone.get("realistic", True), occluders=boxes)
            return
        super().draw_zone(pipe, frame, index, zone)
