"""
red_light - crossing the stop line while the light is red.

Heuristic: judged at the moment of crossing. The vehicle's ground point must pass the stop line
(clearly: 30% of its box width, at least 10 px), coming from the side it was first seen on, while
the zone's light is "red". A car that crossed on green / yellow and is still in the junction when
the light turns red is not flagged; an unknown light never tickets.

The light comes from the camera (the colour inside a box the operator drew around the light) or a
SIMULATED timer cycle for recorded footage (engine/traffic_light.py). prepare() reads it once per
frame into zone["light"]; the simulated light and a countdown are drawn on every frame.
"""
from engine import overlay_objects
from engine.traffic_light import LightReader, timer_phase
from engine.violations.base import Violation
from engine.violations.geometry import crossed_line, point_in_polygon

LIGHT_BGR = {"red": (0, 0, 255), "yellow": (0, 255, 255), "green": (0, 255, 0), "unknown": (160, 160, 160)}


class RedLight(Violation):
    key = "red_light"
    zone_key = "red_light_zones"
    color = (0, 0, 200)

    def parse_zone(self, raw):
        if not (raw.get("coordinates") and raw.get("stop_line")):
            return None
        return {
            "polygon": raw["coordinates"],
            "stop_line": raw["stop_line"],
            "light_box": raw.get("light_box"),
            "light": raw.get("light", {"mode": "camera"}),
        }

    def from_wizard(self, cfg):
        light = (
            {"mode": "timer", **{k: float(cfg.get(k, 0)) for k in ("red_start", "red", "green", "yellow")}}
            if cfg.get("light_mode") == "timer" else {"mode": "camera"}
        )
        # ui_vector = the stop line's two points; ui_light_box = two corners around the light
        return [{"coordinates": z["polygon"], "stop_line": z["ui_vector"], "light_box": z.get("ui_light_box"), "light": light}
                for z in cfg.get("rois", []) if z.get("polygon") and z.get("ui_vector")]

    def prepare(self, pipe, frame, detections, zones, t):
        """Fill zone["light"] for every red-light zone: camera colour or timer."""
        fh, fw = frame.shape[:2]
        for i, zone in enumerate(zones):
            light_cfg = zone.get("light") if isinstance(zone.get("light"), dict) else {}
            seconds_left = None
            if light_cfg.get("mode") == "timer":
                state, seconds_left = timer_phase(t, light_cfg)
            elif zone.get("light_box"):
                (x1, y1), (x2, y2) = zone["light_box"]
                xa, xb = sorted((max(0, int(x1)), min(fw, int(x2))))
                ya, yb = sorted((max(0, int(y1)), min(fh, int(y2))))
                state = pipe._light_readers.setdefault(i, LightReader()).update(frame[ya:yb, xa:xb])
            else:
                state = "unknown"
            zone["light"] = state
            pipe._light_states[i] = (state, seconds_left)

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "stop_line": [[x1,y1],[x2,y2]], "light": state}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < 2:
            return False
        _t, cx, cy, _w = ledger.path[-1]
        for i, zone in enumerate(zones):
            if not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            crossed = crossed_line(ledger, (self.key, i), zone.get("stop_line"))
            if crossed and zone.get("light") == "red":
                ledger.violations.add(self.key)
                return True
        return False

    # The stop line is drawn in the light's current colour, so evidence shows the light at crossing time
    def line_colour(self, pipe, index):
        state, _left = pipe._light_states.get(index, ("unknown", None))
        return LIGHT_BGR[state]

    def draw_extra(self, pipe, frame, index, zone):
        state, seconds_left = pipe._light_states.get(index, ("unknown", None))
        if seconds_left is not None:   # simulated light: draw it on the frame
            overlay_objects.draw_traffic_light(frame, state, seconds_left, slot=index, box=zone.get("light_box"), realistic=zone.get("realistic", True))
