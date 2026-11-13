"""
base.py - the shape every violation module follows.

One violation = one small file in this folder. A violation declares what it needs and implements
only the hooks it uses; the pipeline (engine/pipeline.py) calls the hooks, it never contains
violation logic itself. To add a violation: write a module, add it to ALL in __init__.py, and
write its tests (the tests/engine/test_violation_*.py files show how).

Three families:
  - zone rules       zone_key + evaluate(): judged from the vehicle's path inside drawn zones
  - frame checks     check_frame(): judged from what is on screen right now (overloading)
  - model checks     job + judge(): judged from a specialist model's look at the vehicle
                     (helmet / plate / cabin, see engine/specialist_jobs.py), always by vote
"""
import cv2
import numpy as np

from engine.violations.geometry import point_in_polygon  # noqa: F401  (re-exported for rule modules)

# Classes treated as vehicles by the plate / cabin / indicator checks ("tricycle" comes from a
# PH fine-tuned detector; the stock COCO model never outputs it)
VEHICLE_CLASSES = ("car", "motorcycle", "bus", "jeepney", "truck", "tricycle")


class Violation:
    key: str = ""                          # name used in tickets and in camera_config's active_violations
    zone_key: str | None = None            # list name in camera_config's regions_of_interest (zone rules only)
    color: tuple = (255, 255, 255)         # BGR colour of the zone outline
    job: str | None = None                 # specialist job it is judged from: "helmet" | "plate" | "cabin"
    whole_frame: bool = False              # True: needs no drawing; with nothing drawn the whole picture is its zone
    needs_flow: bool = False               # True: that whole-picture zone also needs the learned traffic flow (counterflow direction,
                                           #   the "traffic keeps driving past" check of parking / loading)

    # ── zone setup ───────────────────────────────────────────────────────────
    def parse_zone(self, raw: dict) -> dict | None:
        """One zone from camera_config -> the zone dict the rule reads (None = unusable, skip it)."""
        coords = raw.get("coordinates")
        return {"polygon": coords} if coords else None

    def from_wizard(self, cfg: dict) -> list[dict]:
        """The dashboard wizard's settings for this violation ({"rois": [...], ...}) -> zones in camera_config
        format (what parse_zone reads). Keeps every wizard detail inside the violation that owns it."""
        return [{"coordinates": z["polygon"]} for z in cfg.get("rois", []) if z.get("polygon")]

    def whole_frame_zone(self, cfg: dict, polygon: list, frame_size: tuple, flow) -> dict:
        """The implicit zone of a rule that needs no drawing (nothing drawn): the whole picture. `cfg` is this violation's
        wizard settings (time limit, vehicle types, banned turns ...); `flow` is the FlowField learned from the traffic
        (only the rules with `needs_flow` read it)."""
        return {"polygon": polygon, "whole_frame": True, "field": flow, "frame_size": frame_size}

    def settings_from_wizard(self, cfg: dict) -> dict:
        """Top-level camera_config settings this violation takes from the wizard (e.g. max_riders)."""
        return {}

    # ── hooks (override what you need) ───────────────────────────────────────
    def prepare(self, pipe, frame: np.ndarray, detections: list, zones: list, t: float) -> None:
        """Once per frame, before the rules run, for violations that read the picture (light colour, indicators)."""

    def evaluate(self, mgr, track_id: int, zones: list) -> bool:
        """Zone rules: judge one tracked vehicle. Adds self.key to its ledger's violations and returns True when it flags."""
        return False

    def keep_detail(self, pipe, det, look, kind: str, label: str, boxes: list, confidence: float,
                    note: str | None = None) -> None:
        """Ask the pipeline to keep the picture the model looked at as extra evidence of this violation (a pipeline
        without that ability, e.g. a test double, simply skips it)."""
        keep = getattr(pipe, "keep_detail", None)
        if keep is not None:
            keep(det, look, kind, self.key, label, confidence, boxes, note)

    def check_frame(self, pipe, detections: list) -> None:
        """Frame checks: judge everything on screen right now."""

    def judge(self, pipe, det, look) -> None:
        """Model checks: judge one vehicle from a specialist look (specialist_jobs.Look)."""

    def decide_end(self, ledger) -> None:
        """When the vehicle leaves (or the video ends): turn a still-pending suspicion into a violation, or drop it."""

    # ── drawing ──────────────────────────────────────────────────────────────
    def line_colour(self, pipe, index: int) -> tuple:
        """Colour of this zone's stop line / light box."""
        return self.color

    def draw_extra(self, pipe, frame: np.ndarray, index: int, zone: dict) -> None:
        """Anything else this violation shows on the picture (e.g. the simulated traffic light)."""

    def draw_zone(self, pipe, frame: np.ndarray, index: int, zone: dict) -> None:
        if zone.get("whole_frame"):      # the implicit whole-picture zone: nothing to outline
            return
        cv2.polylines(frame, [np.array(zone["polygon"], dtype=np.int32)], isClosed=True, color=self.color, thickness=2)
        colour = self.line_colour(pipe, index)
        self.draw_extra(pipe, frame, index, zone)
        if zone.get("stop_line"):
            (ax, ay), (bx, by) = zone["stop_line"]
            cv2.line(frame, (int(ax), int(ay)), (int(bx), int(by)), colour, 4)
        if zone.get("light_box"):
            (ax, ay), (bx, by) = zone["light_box"]
            cv2.rectangle(frame, (int(ax), int(ay)), (int(bx), int(by)), colour, 2)
