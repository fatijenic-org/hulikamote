"""
blocking_intersection - a vehicle that stops inside the junction box and blocks the cross traffic.

Shared stopped-in-a-zone rule (stopped_in_zone.py): the operator draws the junction box, and a vehicle
that stands still inside it for longer than the limit (default 5 s) is flagged. A car that is moving
through, or waiting BEFORE the box, is never flagged. Legal basis: local "anti-obstruction" rules (to be
confirmed with the LGU before it is quoted on a ticket).

No drawing needed: with no box drawn and no sign placed the junction is found by itself from the traffic flow (engine/intersection_finder.py:
cells where traffic goes two clearly different ways). Until it is found nothing is judged. A drawn box or a placed sign always wins.
"""
import cv2
import numpy as np

from engine import intersection_finder
from engine.violations.box_signs import BoxSigns
from engine.violations.stopped_in_zone import StoppedInZone


class BlockingIntersection(BoxSigns, StoppedInZone):
    sign_kind = "keep_clear"                       # the object placed for it (engine/overlay_objects.py)
    key = "blocking_intersection"
    zone_key = "intersection_zones"
    color = (180, 0, 180)
    default_limit_s = 5.0
    whole_frame = True        # nothing drawn: the junction is found from the traffic (whole_frame_zone below)
    needs_flow = True         # ... so the traffic flow is learned (a recorded clip is pre-scanned first)

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        """The junction found from the learned flow, or None while it is not clear (then nothing is judged)."""
        found = intersection_finder.find_junction(flow, *frame_size)
        if not found:
            return None
        zone = {"polygon": found, "time_limit": float(cfg.get("time_limit", self.default_limit_s)), "auto_junction": True}
        zone.update(self._zone_extra({"classes": cfg.get("banned_classes")}))
        return zone

    def draw_zone(self, pipe, frame, index, zone):
        super().draw_zone(pipe, frame, index, zone)
        if zone.get("auto_junction") and zone.get("polygon"):         # say it was found by itself
            x, y, _w, _h = cv2.boundingRect(np.array(zone["polygon"], dtype=np.int32))
            scale = max(0.5, frame.shape[0] / 1000)
            cv2.putText(frame, "JUNCTION (found by itself)", (x + 4, y + int(22 * scale)), cv2.FONT_HERSHEY_SIMPLEX, scale * 0.8,
                        self.color, max(1, frame.shape[0] // 500), cv2.LINE_AA)
