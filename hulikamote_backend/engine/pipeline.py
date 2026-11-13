"""
pipeline.py - Decoupled Cascading Pipeline

Handles one frame at a time:
  1. Primary anchor inference (vehicles and people, every frame) + tracking
  2. Ledger update (positions, stitching of broken tracks)
  3. Specialist looks every few frames (engine/specialist_jobs.py): helmet, plate, cabin
  4. Violation judging. Every violation is its own module (engine/violations/*.py); this file only
     calls their hooks and contains no violation logic.
  5. Evidence capture for flagged vehicles, plate attach, frame annotation
"""
import json
import logging
import time
from pathlib import Path

import cv2
import numpy as np

from engine import marks, privacy
from engine.flow_field import FlowField
from engine.video_clock import OffsetClock, WallClock, start_from_text
from engine.ledger import ActiveLedgerManager
from engine.registry import ModelRegistry
from engine.specialist_jobs import JOBS
from engine.violations import ALL as ALL_VIOLATIONS, ZONE_POINT_FIELDS, ZONE_RULES, ZONE_VIOLATIONS
from engine.violations.overloading import DEFAULT_MAX_RIDERS

log = logging.getLogger(__name__)

# Interval at which specialist models run (every N frames of inference).
# Lower value = more frequent plate/helmet checks per vehicle.
# With INFER_EVERY_N_FRAMES=2 in stream.py, inference runs every 3rd raw frame.
# SPECIALIST_INTERVAL=5 -> a specialist fires every ~15 raw frames (~0.5s at 30fps).
SPECIALIST_INTERVAL = 5

# Where proof-timeline frames are written. Served statically via the
# existing "/snapshots" mount in main.py (subfolders are included).
EVIDENCE_DIR = Path(__file__).resolve().parent.parent / "snapshots" / "evidence"

# The rules marked `whole_frame` (engine/violations/*.py) need no drawing: when one is on and nothing is drawn for it, it gets one
# implicit zone, the whole picture, built from its own wizard settings (Violation.whole_frame_zone)
WHOLE_FRAME_ZONE_KEYS = tuple(v.zone_key for v in ZONE_VIOLATIONS if v.whole_frame)


# ─── EasyOCR (lazy singleton) ─────────────────────────────────────────────────

_ocr_reader = None


_paddle_reader = None

def _get_ocr_reader(engine="easyocr"):
    global _ocr_reader, _paddle_reader
    
    if engine == "paddleocr":
        if _paddle_reader is None:
            try:
                from paddleocr import PaddleOCR
                import logging
                logging.getLogger("ppocr").setLevel(logging.ERROR)
                _paddle_reader = PaddleOCR(use_angle_cls=False, lang='en')
            except ImportError:
                log.warning("[OCR] paddleocr not installed.")
                return None
        return _paddle_reader
        
    # Default to easyocr
    if _ocr_reader is None:
        try:
            import easyocr
            _ocr_reader = easyocr.Reader(['en'], gpu=True, verbose=False)
        except ImportError:
            log.warning("[OCR] easyocr not installed.")
    return _ocr_reader



_sr_model = None
def _apply_super_resolution(image: np.ndarray) -> np.ndarray:
    """
    Applies LapSRN (Laplacian Pyramid Super-Resolution Network) to upscale 
    blurry dashcam crops by 8x using deep learning instead of mathematical interpolation.
    """
    global _sr_model
    import cv2
    from pathlib import Path
    
    if _sr_model is None:
        try:
            model_path = Path(__file__).parent.parent / "models" / "LapSRN_x8.pb"
            if model_path.exists():
                _sr_model = cv2.dnn_superres.DnnSuperResImpl_create()
                _sr_model.readModel(str(model_path))
                _sr_model.setModel("lapsrn", 8)
            else:
                _sr_model = "failed"
        except Exception as e:
            print(f"[Warning] SuperResolution disabled: {e}")
            _sr_model = "failed"
            
    if _sr_model and _sr_model != "failed":
        try:
            return _sr_model.upsample(image)
        except Exception as e:
            pass
            
    # Fallback to normal resize if model fails
    h, w = image.shape[:2]
    return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_CUBIC)


_realesrgan_session = None
def _apply_realesrgan(image: np.ndarray) -> np.ndarray:
    global _realesrgan_session
    import onnxruntime as ort
    from pathlib import Path
    
    if _realesrgan_session is None:
        try:
            base_dir = Path(__file__).resolve().parent.parent / "models"
            model_path = base_dir / "realesrgan.onnx"
            if not model_path.exists():
                for p in base_dir.rglob("*.onnx"):
                    if p.name == "realesrgan.onnx":
                        model_path = p
                        break

            if model_path.exists():
                from inference.providers import make_session
                _realesrgan_session = make_session(str(model_path))
            else:
                _realesrgan_session = "failed"
        except Exception as e:
            _realesrgan_session = "failed"
            print(f"[Enhancement] Failed to load realesrgan: {e}")
            
    if _realesrgan_session == "failed" or _realesrgan_session is None:
        # Graceful fallback to Lanczos
        h, w = image.shape[:2]
        return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)
        
    try:
        input_name = _realesrgan_session.get_inputs()[0].name
        
        # Preprocess: BGR to RGB, normalize, NCHW format
        rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        input_tensor = rgb.astype(np.float32) / 255.0
        input_tensor = np.transpose(input_tensor, (2, 0, 1))
        input_tensor = np.expand_dims(input_tensor, axis=0)
        
        # Run GAN
        outputs = _realesrgan_session.run(None, {input_name: input_tensor})
        
        # Postprocess
        output_tensor = np.squeeze(outputs[0])
        output_tensor = np.clip(output_tensor, 0, 1)
        output_tensor = np.transpose(output_tensor, (1, 2, 0))
        output_bgr = cv2.cvtColor((output_tensor * 255.0).astype(np.uint8), cv2.COLOR_RGB2BGR)
        return output_bgr
    except Exception as e:
        print(f"[Enhancement] realesrgan Error during inference: {e}")
        h, w = image.shape[:2]
        return cv2.resize(image, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)

def _extract_plate_text(plate_crop: np.ndarray, plate_format: str = "raw", ocr_engine: str = "easyocr", enhancement: str = "lanczos") -> tuple[str, str, np.ndarray, np.ndarray, float]:
    """
    Run EasyOCR or PaddleOCR on a plate crop.
    Returns (raw_text, corrected_text, raw_crop, enhanced_crop).
    raw_crop is the original unmodified image.
    enhanced_crop is after GAN/SR/Lanczos upscaling (may be identical to raw_crop if no enhancement ran).
    """
    reader = _get_ocr_reader(ocr_engine)
    if reader is None:
        return "unidentified", "unidentified", plate_crop, plate_crop, 0.0
        
    h, w = plate_crop.shape[:2]
    if h == 0 or w == 0:
        return "unidentified", "unidentified", plate_crop, plate_crop, 0.0

    # Save original before enhancement so we can return both
    raw_crop = plate_crop.copy()

    # All enhancers are unconditional — always upscale for better OCR readability
    if enhancement == "realesrgan":
        plate_crop = _apply_realesrgan(plate_crop)
    elif enhancement == "lapsrn":
        plate_crop = _apply_super_resolution(plate_crop)
    elif enhancement == "lanczos":
        plate_crop = cv2.resize(plate_crop, (w * 4, h * 4), interpolation=cv2.INTER_LANCZOS4)

    sr_crop = plate_crop  # enhanced copy (always different from raw_crop now)

    # PaddleOCR performs best on color images (BGR). EasyOCR can use grayscale.
    gray = cv2.cvtColor(plate_crop, cv2.COLOR_BGR2GRAY)
    
    try:
        raw = ""
        confidence = 0.0
        
        if ocr_engine == "paddleocr":
            # PaddleOCR returns a nested list structure. Pass the color BGR image!
            try:
                results = reader.ocr(plate_crop)
            except TypeError:
                results = reader.ocr(plate_crop, cls=False)
                
            if results and results[0]:
                raw = "".join([res[1][0] for res in results[0]]).strip().upper().replace(" ", "")
                # Average the confidences
                confidences = [res[1][1] for res in results[0]]
                if confidences:
                    confidence = sum(confidences) / len(confidences)
                import re
                raw = re.sub(r'[^0-9A-Z]', '', raw)
        else:
            # EasyOCR detail=1 returns [(bbox, text, prob)]
            results = reader.readtext(gray, detail=1, paragraph=False, allowlist='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ')
            if results:
                raw = "".join([res[1] for res in results]).strip().upper().replace(" ", "")
                confidences = [res[2] for res in results]
                if confidences:
                    confidence = sum(confidences) / len(confidences)
                
        if raw:
            
            if plate_format == "raw":
                return raw, raw, raw_crop, sr_crop, confidence
                
            dict_char_to_int = {'O': '0', 'I': '1', 'J': '3', 'A': '4', 'G': '6', 'S': '5', 'B': '8', 'Z': '2', 'Q': '0', 'D': '0', 'T': '7', 'U': '0', 'Y': '7', 'P': '0', 'F': '5', 'L': '4'}
            dict_int_to_char = {'0': 'O', '1': 'I', '3': 'J', '4': 'A', '6': 'G', '5': 'S', '8': 'B', '2': 'Z', '7': 'T', '9': 'P'}
            
            cleaned = ""
            mapping = {}
            if plate_format == "ph_standard":
                mapping = {0: dict_int_to_char, 1: dict_int_to_char, 2: dict_int_to_char, 
                           3: dict_char_to_int, 4: dict_char_to_int, 5: dict_char_to_int, 6: dict_char_to_int}
            elif plate_format == "uk_standard":
                mapping = {0: dict_int_to_char, 1: dict_int_to_char, 
                           2: dict_char_to_int, 3: dict_char_to_int,
                           4: dict_int_to_char, 5: dict_int_to_char, 6: dict_int_to_char}
            
            if mapping:
                for i in range(len(raw)):
                    if i in mapping:
                        if raw[i] in mapping[i]:
                            cleaned += mapping[i][raw[i]]
                        else:
                            cleaned += raw[i]
                    else:
                        cleaned += raw[i]
                return raw, cleaned, raw_crop, sr_crop, confidence
                
            return raw, raw, raw_crop, sr_crop, confidence

    except Exception as e:
        print(f"OCR Error: {e}")
        
    return "unidentified", "unidentified", raw_crop, sr_crop, 0.0


# ─── Pipeline ─────────────────────────────────────────────────────────────────

class DecoupledPipeline:
    # Zones the Live Monitor learned from the camera picture by itself (engine/live_calibrator.py): {zone_key: [zone, ...]} in
    # the wizard's 1920x1080 reference space. Replaced as a whole (never edited in place), so the frame loop can read it while
    # another thread swaps it. A drawn zone for the same rule always wins; see _get_scaled_rois.
    learned_rois: dict = {}
    LEARNED_REF = (1920, 1080)

    # TEMPORARY switch (wizard: "Blur faces and other plates in saved photos"). On = the thesis' mandatory anonymization.
    # Off only for the team's own training videos: the saved photos then show faces, so never confirm or send those tickets.
    blur_privacy = True

    def __init__(self, config_path: str):
        self.registry = ModelRegistry(config_path)
        self.ledger_manager = ActiveLedgerManager()
        self.rois = self._parse_rois(config_path)
        try:
            with open(config_path) as fc:
                self.config = json.load(fc)      # settings the violations read (e.g. bed_passengers_allowed)
        except Exception:
            self.config = {}
        self._light_readers: dict = {}   # red-light zone index -> LightReader (camera mode)
        # red-light zone index -> (state, seconds left or None); seconds left = simulated (timer) light
        self._light_states: dict = {}
        # Native video dimensions (width × height) that the ROI polygon coords
        # were drawn at. Used to scale polygons to match the actual processed
        # frame size (which may be smaller due to MAX_PROCESSING_HEIGHT cap).
        self.native_w, self.native_h = self._parse_native_dims(config_path)
        
        # Parse global plate format (default PH)
        self.plate_format = "ph_standard"
        try:
            import json
            with open(config_path) as ff:
                cfg = json.load(ff)
                self.plate_format = cfg.get("plate_format", "ph_standard")
        except:
            pass
        
        # Evidence photo gap: save one evidence frame every N frames of a flagged car (default 5)
        self.evidence_gap = 5
        try:
            with open(config_path) as fg:
                self.evidence_gap = max(1, int(json.load(fg).get("evidence_gap", 5)))
        except Exception:
            pass

        try:
            with open(config_path) as fb:
                self.blur_privacy = bool(json.load(fb).get("blur_privacy", True))
        except Exception:
            self.blur_privacy = True
        if not self.blur_privacy:
            log.warning("PRIVACY BLUR IS OFF for this run: saved photos show faces and every plate.")

        # Overloading: most people allowed on one motorcycle
        self.max_riders = DEFAULT_MAX_RIDERS
        try:
            with open(config_path) as fm:
                self.max_riders = max(1, int(json.load(fm).get("max_riders", DEFAULT_MAX_RIDERS)))
        except Exception:
            pass

        # Read tracker type and flow mode from config and initialize YOLO inference immediately
        self.tracker_type = "bytetrack"
        self.flow_mode = "zones"        # "auto": always learn the traffic flow; "zones": only when a rule needs it (see learns_flow)
        self.violation_cfg: dict = {}   # the wizard's per-violation settings (an automatic rule reads its own: time limit, banned turns ...)
        # What time is it in the picture? Live: this computer's clock. An analysis sets the time found in its video (forensic.py).
        # `clock_start` ("7:30") in the config pretends a start time, e.g. to show a ban hour in a live demo.
        self.clock = WallClock()
        try:
            with open(config_path) as f:
                cfg = json.load(f)
                pretend = start_from_text(cfg.get("clock_start"))
                if pretend is not None:
                    self.clock = OffsetClock(pretend)
                self.tracker_type = cfg.get("tracker", "bytetrack")
                self.flow_mode = "auto" if cfg.get("flow_mode") == "auto" else "zones"
                self.violation_cfg = cfg.get("per_violation_configs") or {}
        except Exception:
            pass
        self.flow = FlowField()          # what the traffic taught us (auto mode); filled while frames are processed
        self.learn_only = False          # True during a pre-scan: track and learn the flow, judge nothing

        # Force reload to apply new tracker strategy immediately
        from yolo_inference import get_inference
        get_inference(force_reload=True, tracker_type=self.tracker_type)

    @staticmethod
    def _parse_native_dims(config_path: str) -> tuple[int, int]:
        """Read video_native_width/height from config. Falls back to 0,0 (no scaling)."""
        try:
            path = Path(config_path)
            if not path.is_absolute() and not path.exists():
                backend_path = Path(__file__).resolve().parent.parent / config_path
                if backend_path.exists():
                    path = backend_path
            with open(path) as f:
                cfg = json.load(f)
            return int(cfg.get("video_native_width", 0)), int(cfg.get("video_native_height", 0))
        except Exception:
            return 0, 0

    @property
    def learns_flow(self) -> bool:
        """True when the traffic flow must be learned from the video: the config says so (flow_mode "auto"), or a rule that needs the
        flow (Violation.needs_flow: counterflow, parking, loading) is on and has nothing drawn, so it watches the whole picture."""
        if getattr(self, "flow_mode", "zones") == "auto":
            return True
        active = getattr(getattr(self, "registry", None), "active_violations", None) or []
        return any(v.needs_flow and v.key in active and not self.rois.get(v.zone_key) for v in ZONE_VIOLATIONS)

    def _scale_polygon(self, polygon: list, frame_w: int, frame_h: int) -> list:
        """
        Scale ROI polygon coordinates from the native video resolution that the
        user drew them at, down to the actual processed frame resolution.

        If native dims are unknown (0,0) or already match the frame, returns
        the polygon unchanged so legacy configs still work correctly.
        """
        if not self.native_w or not self.native_h:
            return polygon
        if self.native_w == frame_w and self.native_h == frame_h:
            return polygon
        sx = frame_w / self.native_w
        sy = frame_h / self.native_h
        return [[int(pt[0] * sx), int(pt[1] * sy)] for pt in polygon]

    def _get_scaled_rois(self, frame_w: int, frame_h: int) -> dict:
        """Returns self.rois with all polygons (and stop lines / light boxes) scaled to the
        current frame. Every other zone field (vector, time_limit, ...) is carried over as-is."""
        def scale(z: dict) -> dict:
            out = {**z, "polygon": self._scale_polygon(z["polygon"], frame_w, frame_h)}
            for field in ZONE_POINT_FIELDS:
                if z.get(field):
                    out[field] = self._scale_polygon(z[field], frame_w, frame_h)
            return out

        scaled = {key: [scale(z) for z in self.rois.get(key, [])] for key in ZONE_RULES.values()}
        # A rule that needs no drawing (`whole_frame`) that is on, with nothing drawn (and no sign placed): the whole picture is its zone.
        active = getattr(getattr(self, "registry", None), "active_violations", None)
        if active:
            whole = [[0, 0], [frame_w, 0], [frame_w, frame_h], [0, frame_h]]
            settings = getattr(self, "violation_cfg", None) or {}
            for violation in ZONE_VIOLATIONS:
                if violation.whole_frame and violation.key in active and not scaled[violation.zone_key]:
                    zone = violation.whole_frame_zone(settings.get(violation.key) or {}, whole, (frame_w, frame_h), getattr(self, "flow", None))
                    scaled[violation.zone_key] = [zone] if zone else []       # None: nothing to judge yet (the junction is not found)
        for violation in self._learned_in_use():
            scaled[violation.zone_key] = [self._scale_learned(z, frame_w, frame_h) for z in self.learned_rois[violation.zone_key]]
        return scaled

    # ── zones learned from the live picture ──────────────────────────────────

    def set_learned_zones(self, zones: dict) -> None:
        """Install what the live calibrator learned. `zones` = {violation key: [wizard-shaped zone, ...]} in the 1920x1080
        reference space; each violation turns them into its own zone format. Only the violations the live config switched on
        use them, and only where nothing was drawn. An empty dict removes them all. Never raises: a zone that does not parse
        is skipped, so a bad learn cannot stop the live view."""
        parsed: dict = {}
        settings = getattr(self, "violation_cfg", None) or {}
        for violation in ZONE_VIOLATIONS:
            raw = (zones or {}).get(violation.key)
            if not raw:
                continue
            wizard = {**(settings.get(violation.key) or {}), "rois": raw}
            if violation.key == "red_light" and not settings.get("red_light"):
                wizard.update({"light_mode": "timer", "red_start": 0.0, "red": 30.0, "green": 30.0, "yellow": 3.0})
            try:
                for z in violation.from_wizard(wizard):
                    zone = violation.parse_zone(z)
                    if zone:
                        parsed.setdefault(violation.zone_key, []).append({**zone, "learned": True})
            except Exception:
                log.exception("A learned %s zone could not be used and was skipped", violation.key)
        self.learned_rois = parsed

    def _learned_in_use(self) -> list:
        """The violations whose learned zones are used right now: switched on, learned, and with no drawn zone."""
        learned = self.learned_rois
        if not learned:
            return []
        active = set(getattr(getattr(self, "registry", None), "active_violations", None) or [])
        rois = getattr(self, "rois", None) or {}
        return [v for v in ZONE_VIOLATIONS if v.key in active and learned.get(v.zone_key) and not rois.get(v.zone_key)]

    def _scale_learned(self, zone: dict, frame_w: int, frame_h: int) -> dict:
        """A learned zone from the 1920x1080 reference space onto the processed frame (independent of video_native_*)."""
        sx, sy = frame_w / self.LEARNED_REF[0], frame_h / self.LEARNED_REF[1]

        def pts(points):
            return [[int(x * sx), int(y * sy)] for x, y in points]
        out = {**zone, "polygon": pts(zone["polygon"])}
        for field in ZONE_POINT_FIELDS:
            if zone.get(field):
                out[field] = pts(zone[field])
        return out

    def learned_overlay(self, frame_w: int, frame_h: int) -> list:
        """The learned zones in use, on the processed frame, for the live picture:
        [{"violation", "polygon", "line" (stop / solid line or None), "best_effort"}]."""
        from engine.live_calibrator import BEST_EFFORT
        out = []
        for violation in self._learned_in_use():
            for zone in self.learned_rois[violation.zone_key]:
                z = self._scale_learned(zone, frame_w, frame_h)
                out.append({"violation": violation.key, "polygon": z["polygon"], "line": z.get("stop_line"),
                            "best_effort": violation.key in BEST_EFFORT})
        return out

    def _draw_rois(self, frame: np.ndarray) -> np.ndarray:
        fh, fw = frame.shape[:2]
        scaled_rois = self._get_scaled_rois(fw, fh)
        for violation in ZONE_VIOLATIONS:
            if violation.key not in self.registry.active_violations:
                continue
            for i, zone in enumerate(scaled_rois.get(violation.zone_key, [])):
                violation.draw_zone(self, frame, i, zone)
        return frame

    def _capture_evidence_frame(self, frame: np.ndarray, det, track_id: int, detections=()) -> None:
        """
        Save one proof-timeline frame for a flagged track.
        Guarded to avoid redundant disk I/O: checks capacity first and throttles
        to at most one snapshot every 200ms per violating vehicle.

        Everything saved here (the photo and both crops) is cut from a blurred copy of the frame: faces and other
        vehicles' plates are hidden, the violator's plate is not. If the blur fails, nothing is saved.
        """
        ledger = self.ledger_manager.ledgers.get(track_id)
        if ledger is None or len(ledger.evidence_paths) >= ledger.MAX_EVIDENCE_FRAMES:
            return

        ledger._evidence_counter = getattr(ledger, "_evidence_counter", 0) + 1
        # Throttle: Always save on Frame 1 (guaranteed evidence), then 1 out of every `evidence_gap` frames
        if ledger._evidence_counter != 1 and ledger._evidence_counter % self.evidence_gap != 0:
            return

        from yolo_inference import get_inference, YoloInference
        yolo = get_inference()
        
        try:
            safe = (privacy.anonymize(frame, detections, self.ledger_manager.ledgers, keep_track_id=track_id)
                    if self.blur_privacy else frame.copy())
        except Exception:
            log.exception("Blurring failed for track %s: its evidence photo was not saved", track_id)
            return

        # Burn ALL active ROIs onto the frame first so the evidence shows the full crime scene context
        self._draw_dets = detections                 # rules that paint on the road (overlay crosswalk) keep vehicles on top
        base_frame = self._draw_rois(safe.copy())
        
        # Burn the vehicle bounding box
        annotated = yolo.draw_detections(base_frame, [det])
        marks.draw_marks(annotated, ledger, det.bbox)
        
        path = YoloInference.save_snapshot(annotated, EVIDENCE_DIR)

        # Clean vehicle crop (taken from the raw frame, no drawn boxes/zones) for ReID training data
        car_crop = None
        try:
            cx, cy, cw, ch = (int(v) for v in det.bbox)
            crop = safe[max(0, cy):max(0, cy) + ch, max(0, cx):max(0, cx) + cw]
            if crop.size:
                car_crop = Path(YoloInference.save_snapshot(crop, EVIDENCE_DIR)).name
        except Exception:
            pass

        # Training material for the harvest tool (training_lab/harvest_tool/sources.py reads "clean",
        # "clean_box" and "vclass"): a clean, wider crop (riders' heads, mirrors and plate included)
        # with its place in the frame.
        clean, clean_box = None, None
        try:
            fh, fw = safe.shape[:2]
            vx, vy, vw, vh = (int(v) for v in det.bbox)
            x1, y1 = max(0, vx - vw // 6), max(0, vy - int(vh * 0.6))
            x2, y2 = min(fw, vx + vw + vw // 6), min(fh, vy + vh + vh // 6)
            if x2 > x1 and y2 > y1:
                clean = Path(YoloInference.save_snapshot(safe[y1:y2, x1:x2], EVIDENCE_DIR)).name
                clean_box = [x1, y1, x2 - x1, y2 - y1]
        except Exception:
            pass

        ledger.add_evidence_frame(path, bbox=det.bbox, t=ledger.history[-1][0] if ledger.history else None,
                                  car_crop=car_crop)
        ledger.evidence_meta[-1].update({
            "clean": clean,
            "clean_box": clean_box,
            "vclass": ledger.vclass,
            "marks": [{"bbox": b, "label": label} for b, label, _ in marks.current_marks(ledger, det.bbox) if b],
        })

    def annotate_frame_fast(self, frame: np.ndarray, detections: list, boxes: bool = True) -> np.ndarray:
        """
        Fast frame annotation for skipped frames: burns last known detections
        and active ROI polygons onto the current video frame without running
        costly neural network inference. Takes ~2-3ms instead of ~90ms.
        `boxes=False` burns only the zones: the replay video keeps its boxes in a separate file (see box_specs),
        so the dashboard can draw them thin when the video is zoomed.
        """
        from yolo_inference import get_inference
        out_frame = frame
        if boxes:
            out_frame = get_inference().draw_detections(frame, detections)
            for det in detections:   # boxes showing why each flagged vehicle was flagged
                ledger = self.ledger_manager.ledgers.get(getattr(det, "track_id", -1))
                if ledger is not None:
                    marks.draw_marks(out_frame, ledger, det.bbox)
        self._draw_dets = detections
        return self._draw_rois(out_frame)

    def box_specs(self, detections: list) -> list[dict]:
        """What annotate_frame_fast would draw as boxes, as plain data with RGB colours (the replay's box file)."""
        from yolo_inference import box_specs
        specs = box_specs(detections)
        for det in detections:
            ledger = self.ledger_manager.ledgers.get(getattr(det, "track_id", -1))
            if ledger is not None:
                specs += marks.mark_specs(ledger, det.bbox)
        for spec in specs:
            if "color" in spec:
                spec["color"] = spec["color"][::-1]     # BGR (OpenCV) -> RGB
        return specs

    # ── ROI parsing ──────────────────────────────────────────────────────────

    def _parse_rois(self, config_path: str) -> dict:
        """
        Parse ROIs from camera_config.json written by the ROI Canvas Tool.
        Falls back to sensible defaults so the pipeline never hard-crashes.

        Supports multiple zones per violation type:
          rois = {
              "counterflow_zones":     [{"polygon": [...], "vector": (x, y)}, ...],
              "illegal_parking_zones": [{"polygon": [...], "time_limit": 180.0}, ...],
          }
        Also understands the older single-zone config shape (still written by
        the Live Camera wizard) as a fallback.
        """
        defaults = {key: [] for key in ZONE_RULES.values()}
        path = Path(config_path)
        if not path.is_absolute() and not path.exists():
            backend_path = Path(__file__).resolve().parent.parent / config_path
            if backend_path.exists():
                path = backend_path

        if not path.exists():
            log.warning(f"[Pipeline] {config_path} not found. Using default ROIs.")
            return defaults

        try:
            with open(path) as f:
                cfg = json.load(f)

            regions = cfg.get("regions_of_interest", {})
            rois = {key: [] for key in ZONE_RULES.values()}

            # ── Current multi-zone format: each violation parses its own zones ──
            for violation in ZONE_VIOLATIONS:
                for raw in regions.get(violation.zone_key, []) or []:
                    zone = violation.parse_zone(raw)
                    if zone:
                        rois[violation.zone_key].append(zone)

            # ── Legacy single-zone format (older configs / Live Camera wizard) ──
            if not rois["counterflow_zones"] and not rois["illegal_parking_zones"]:
                legacy_parking = None
                legacy_counterflow = None
                legacy_vector = (1.0, 0.0)

                for key, value in regions.items():
                    if not isinstance(value, dict) or "coordinates" not in value:
                        continue
                    coords = value["coordinates"]
                    if not coords:
                        continue
                    lower_key = str(key).lower()
                    if "parking" in lower_key:
                        legacy_parking = coords
                    if "counterflow" in lower_key or "lane" in lower_key:
                        legacy_counterflow = coords

                if legacy_parking is None or legacy_counterflow is None:
                    for key, value in regions.items():
                        if not isinstance(value, dict) or "coordinates" not in value:
                            continue
                        coords = value["coordinates"]
                        if not coords:
                            continue
                        if "zone" in str(key).lower():
                            if legacy_parking is None:
                                legacy_parking = coords
                            if legacy_counterflow is None:
                                legacy_counterflow = coords
                            break

                if "legal_flow_vector" in regions:
                    v = regions["legal_flow_vector"]
                    legacy_vector = (float(v.get("x_dir", 1.0)), float(v.get("y_dir", 0.0)))

                if legacy_parking:
                    rois["illegal_parking_zones"].append({"polygon": legacy_parking, "time_limit": 180.0})
                if legacy_counterflow:
                    rois["counterflow_zones"].append({"polygon": legacy_counterflow, "vector": legacy_vector})

            return rois

        except Exception as e:
            log.warning(f"[Pipeline] Failed to parse {config_path}: {e}. Using defaults.")
            return defaults

    # ── Detection gating ──────────────────────────────────────────────────

    def _filter_to_roi(self, detections: list, scaled_rois: dict) -> list:
        """
        Gate detections to configured ROI zones using sv.PolygonZone.
        Any vehicle outside all active zones is dropped before tracking.
        """
        import supervision as sv

        active_zones = [
            z
            for violation, key in ZONE_RULES.items()
            if violation in self.registry.active_violations
            for z in scaled_rois.get(key, [])
        ]
        polygons = [z["polygon"] for z in active_zones if z.get("polygon")]
        if len(polygons) < len(active_zones):
            return detections           # a zone without a road section (a solid line alone) is the whole picture: nothing is cut away

        if not polygons or not detections:
            return detections

        # Build sv.Detections for zone triggering (xyxy format)
        xyxy = np.array([
            [d.bbox[0], d.bbox[1], d.bbox[0] + d.bbox[2], d.bbox[1] + d.bbox[3]]
            for d in detections
        ], dtype=np.float32)
        sv_dets = sv.Detections(xyxy=xyxy)

        # Keep a detection if its centroid falls inside ANY polygon zone
        keep_mask = np.zeros(len(detections), dtype=bool)
        for poly in polygons:
            zone = sv.PolygonZone(polygon=np.array(poly, dtype=np.int32))
            triggered = zone.trigger(sv_dets)
            keep_mask |= triggered

        return [d for d, keep in zip(detections, keep_mask) if keep]

    # ── Frame processing ─────────────────────────────────────────────────────

    def process_frame(self, frame: np.ndarray, frame_count: int, timestamp: float | None = None) -> tuple[np.ndarray, list]:
        from yolo_inference import get_inference
        yolo = get_inference()

        fh, fw = frame.shape[:2]
        scaled_rois = self._get_scaled_rois(fw, fh)

        detections = self._filter_to_roi(yolo.infer(frame), scaled_rois)
        self.ledger_manager.update(detections, timestamp, frame)

        if self.learns_flow:
            self.flow.observe_frame(self.ledger_manager, detections, fw, fh)
            if self.learn_only:                  # pre-scan: learn the flow, judge nothing, keep no evidence
                return frame, detections

        active = self.registry.active_violations
        self._run_specialists(frame, frame_count, detections, active)
        self._judge(frame, detections, scaled_rois, active, timestamp if timestamp is not None else time.time())

        # ── Capture evidence for any flagged violators ───────────────────────
        for det in detections:
            tid = getattr(det, "track_id", -1)
            if tid != -1:
                # Sync violator state from ledger to ensure it persists across frames
                ledger = self.ledger_manager.ledgers.get(tid)
                if ledger and (ledger.violations or ledger.pending):
                    det.is_violator = True
                    # Unified evidence: all concurrent violations on the box label; "?" = decided when it leaves
                    det.violation_type = "+".join(sorted(ledger.violations) + [f"{v}?" for v in sorted(ledger.pending)])

                if getattr(det, "is_violator", False):
                    self._capture_evidence_frame(frame, det, tid, detections)

        # ── Attach cached plate identification ───────────────────────────────
        # The plate specialist only runs every SPECIALIST_INTERVAL frames, so
        # pull its last known result off the ledger for every frame in between.
        for det in detections:
            tid = getattr(det, "track_id", -1)
            if tid == -1 or tid not in self.ledger_manager.ledgers:
                continue
            ledger = self.ledger_manager.ledgers[tid]
            if ledger.plate_text != "unidentified":
                det.plate_text = ledger.plate_text
            det.plate_bbox = ledger.plate_bbox
            det.marks = [{"bbox": b, "label": label} for b, label, _ in marks.current_marks(ledger, det.bbox) if b]

        # The clean frame goes back to the streamer: boxes and zones are drawn from the JSON overlay by the dashboard.
        return frame, detections

    def reset_tracking(self) -> None:
        """Forget every tracked vehicle and restart the tracker, but keep the learned flow (after a pre-scan)."""
        from yolo_inference import get_inference
        self.ledger_manager = ActiveLedgerManager()
        get_inference().reset_tracker()

    def keep_detail(self, det, look, kind: str, violation: str, label: str, confidence: float, boxes: list,
                    note: str | None = None) -> None:
        """
        Keep the picture a specialist model looked at (the helmet crop, the cabin crop ...) with its boxes drawn on it, as
        extra evidence of `violation`. Called by a violation for a look that voted FOR it. Only the most confident few per
        kind are kept (TrackLedger.DETAIL_CAP); when the vehicle leaves, the ledger ties the ones that held to the nearest
        evidence photo and deletes the rest. Cut from a blurred copy of the frame like every evidence photo (heads hidden).
        `boxes` are (box in FRAME pixels, label, colour); `note` is optional text along the top of the picture.
        Never raises: a failed close-up must not stop the analysis.
        """
        ledger = self.ledger_manager.ledgers.get(det.track_id)
        crop, frame = getattr(look, "crop", None), getattr(self, "_look_frame", None)
        if ledger is None or crop is None or frame is None or not getattr(crop, "size", 0):
            return
        t = ledger.path[-1][0] if ledger.path else None
        if not ledger.accepts_detail(kind, violation, confidence, t):
            return
        try:
            from yolo_inference import YoloInference
            safe = (privacy.anonymize(frame, getattr(self, "_look_dets", []), self.ledger_manager.ledgers,
                                      keep_track_id=det.track_id) if self.blur_privacy else frame.copy())
            ox, oy = look.origin
            h, w = crop.shape[:2]
            piece = safe[oy:oy + h, ox:ox + w].copy()
            if piece.size == 0:
                return
            marks.draw_boxes(piece, [([b[0] - ox, b[1] - oy, b[2], b[3]], text, colour) for b, text, colour in boxes if b],
                             note=note or (label if not boxes else None))
            path = YoloInference.save_snapshot(piece, EVIDENCE_DIR, prefix=f"detail_{kind}_")
        except Exception:
            log.exception("Could not keep the %s close-up of track %s", kind, det.track_id)
            return
        pushed = ledger.add_detail({"kind": kind, "violation": violation, "label": label, "confidence": round(float(confidence), 2),
                                    "t": t, "path": str(EVIDENCE_DIR / Path(path).name), "file": Path(path).name})
        for old in pushed:
            Path(old["path"]).unlink(missing_ok=True)

    def _run_specialists(self, frame: np.ndarray, frame_count: int, detections: list, active: list) -> None:
        """Every few frames, let each specialist model look at the vehicles it applies to; the violations judge the look."""
        self._look_frame, self._look_dets = frame, detections      # what keep_detail() cuts the close-ups from
        for i, det in enumerate(detections):
            if det.track_id == -1:
                continue

            # Round-robin distribution: instead of running the specialists on ALL vehicles on the
            # exact same frame (which causes a massive FPS pause), offset the check by the vehicle's index.
            if (frame_count + i) % SPECIALIST_INTERVAL != 0:
                continue

            for job in JOBS:
                if not job.wanted(active, det):
                    continue
                look = job.look(self, frame, det, detections)
                if look is None:
                    continue
                for violation in ALL_VIOLATIONS:
                    if violation.job == job.name and violation.key in active:
                        violation.judge(self, det, look)

            ledger = self.ledger_manager.ledgers.get(det.track_id)
            if ledger is not None:
                ledger.violations.update(getattr(det, "violations", set()))

    def _judge(self, frame: np.ndarray, detections: list, scaled_rois: dict, active: list, t: float) -> None:
        """Zone rules on every tracked vehicle, then the checks that read the whole frame."""
        # People (riders, pedestrians) are skipped: every zone rule is about vehicles.
        rules = []
        for violation in ZONE_VIOLATIONS:
            zones = scaled_rois.get(violation.zone_key)
            if violation.key in active and zones:
                violation.prepare(self, frame, detections, zones, t)
                rules.append((violation, zones))
        for tid, ledger in list(self.ledger_manager.ledgers.items()):
            if "person" in (ledger.vclass, ledger.latest_class):   # latest_class: a new track has no settled class yet
                continue
            for violation, zones in rules:
                violation.evaluate(self.ledger_manager, tid, zones)

        for violation in ALL_VIOLATIONS:
            if violation.key in active:
                violation.check_frame(self, detections)


# ─── Local test entry point ───────────────────────────────────────────────────

def main():
    """Main execution loop for testing the pipeline locally."""
    import sys
    video_path = sys.argv[1] if len(sys.argv) > 1 else "test_video.mp4"
    if not Path(video_path).exists():
        print(f"Error: {video_path} not found.")
        return

    cap = cv2.VideoCapture(video_path)
    pipeline = DecoupledPipeline("camera_config.json")
    frame_count = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1
        out_frame, _ = pipeline.process_frame(frame, frame_count)

        cv2.imshow("HULI-KAMOTE AI Engine (Decoupled)", out_frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
