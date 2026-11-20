import asyncio
import base64
import json
import os
import random
import sys
import threading as _threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import store
from engine.camera_source import CameraSource, mask_url, parse_source
from engine.live_calibrator import LiveCalibrator, camera_key
from engine import live_run
from engine.playout import Playout
from engine.stage_timer import TIMER
from store import add_violation, MOCK_CLASSES, MOCK_USERS
from yolo_inference import get_inference

router = APIRouter(prefix="/ws", tags=["stream"])

# Video source: a file path, an rtsp:// / http:// address or a webcam number. The Live Monitor's
# "Camera input" sets it (routers/settings.py); engine/camera_source.py reads it.
DEFAULT_SOURCE = "test_video.mp4"


def saved_source(config_path: Path | None = None) -> str | int:
    """
    The camera the operator picked last time (camera_config.json: active_source), so a restart does not forget it.
    Falls back to the sample video when nothing was saved, the profile is gone, or a saved file no longer exists.
    """
    path = config_path or Path(__file__).resolve().parent.parent / "camera_config.json"
    try:
        cfg = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return DEFAULT_SOURCE
    active = cfg.get("active_source") or {}
    url = active.get("url")
    if active.get("profile"):
        url = next((p.get("url") for p in cfg.get("camera_profiles", []) if p.get("name") == active["profile"]), None)
    if not url:
        return DEFAULT_SOURCE
    try:
        if parse_source(url).kind == "file" and not Path(url).exists():
            return DEFAULT_SOURCE
    except ValueError:
        return DEFAULT_SOURCE
    return url


VIDEO_SOURCE: str | int = saved_source()
_active_source: CameraSource | None = None    # the source the live feed is reading right now

# The plate reading runs in a process of its own (engine/plate_service.py). While the live feed runs it reads on the CPU and holds no GPU.
from engine.plate_service import SERVICE as _plate_service  # noqa: E402
_plate_service.live_probe = lambda: _active_source is not None


def camera_status() -> dict:
    """What the live feed is reading and how it is doing (for the dashboard)."""
    if _active_source is not None:
        return _active_source.status()
    try:
        label = parse_source(VIDEO_SOURCE).label
    except ValueError:
        label = mask_url(str(VIDEO_SOURCE))
    return {"kind": "none", "label": label, "state": "idle"}

# Run heavy neural network inference every N frames (2 = every 3rd frame).
# Set to 0 to run inference on every single frame. This prevents ByteTrack from losing 
# track IDs (fragmentation) due to vehicles moving too far between skipped frames.
# Set to 1 or 2 to skip frames and massively increase video playback FPS.
INFER_EVERY_N_FRAMES = 2

# Stream output settings tuned for smooth dashboard rendering.
# 800px width matches the dashboard card width cleanly and reduces payload size by ~30%.
STREAM_WIDTH = 800
STREAM_JPEG_QUALITY = 55

# Cap frame height before any processing. YOLO rescales internally to 640px
# anyway, so detection quality is unchanged. Keeps CPU-bound ops (array copy,
# cv2 drawing, JPEG encode) fast regardless of source resolution.
MAX_PROCESSING_HEIGHT = 720

SNAPSHOTS_DIR = Path(__file__).parent.parent / "snapshots"

# Single-threaded executor: the IoU tracker and ONNX session are stateful and
# NOT thread-safe. Using max_workers=1 ensures frames are processed strictly
# sequentially — the asyncio event loop stays unblocked between frames, but no
# two frames ever race inside process_frame at the same time.
_PIPELINE_EXECUTOR = ThreadPoolExecutor(max_workers=1, thread_name_prefix="pipeline")

# Stage A of the live pipeline (the detector and the trackers: DecoupledPipeline.detect_stage) has its own single thread, so it can
# work on the NEXT picture while `_PIPELINE_EXECUTOR` (stage B: ledgers, learned flow, extra models, rules, and anything else that
# changes them) still works on the one before. Each stage handles the pictures strictly in order.
_DETECT_EXECUTOR = ThreadPoolExecutor(max_workers=1, thread_name_prefix="detect")
# HK_PIPELINE_OVERLAP=0 goes back to one picture at a time (both stages in one thread, the loop waits for each).
PIPELINE_OVERLAP = os.environ.get("HK_PIPELINE_OVERLAP", "1").strip() != "0"
# Python hands its lock to another thread every 5 ms by default. The live loop has one thread for the dashboard and several for the
# models, so every small step of the loop (shrink, send) waited several ms for the models' Python code (measured: send 17 ms, shrink 21 ms).
# 1 ms keeps the loop quick. HK_SWITCH_INTERVAL=0.005 gives the old value back.
sys.setswitchinterval(float(os.environ.get("HK_SWITCH_INTERVAL", "0.001")))

# The playback buffer (engine/playout.py): the backend keeps processing at full speed; the dashboard gets only pictures that are completely
# done, a few seconds late, at a steady pace (a video file plays in slow motion when the backend is slower than the video). Until enough is
# ready the dashboard shows "Processing... 60%". HK_PLAYOUT=0 shows every picture as soon as it is done, as before. The picture must travel
# in the message ("synced" mode): with HK_PICTURE_MODE=relay the buffer is off.
PLAYOUT = os.environ.get("HK_PLAYOUT", "1").strip() != "0"
PLAYOUT_START_S = float(os.environ.get("HK_PLAYOUT_START_S", "8"))             # a file: the gap - seconds of finished video kept ahead of the screen (and ready before it plays)
PLAYOUT_LIVE_START_S = float(os.environ.get("HK_PLAYOUT_LIVE_START_S", "6"))   # a live camera: how late its picture is
PLAYOUT_MAX_S = float(os.environ.get("HK_PLAYOUT_MAX_S", "16"))                # a file: the backend waits when this much is ready
# A video file in the Live Monitor: "buffered" (default) = every picture is processed, the screen is a fixed gap behind and plays in slow motion
# at the backend's own speed to keep that gap (the pipeline is the same as before). "continuous" = the file plays like a camera, always at
# its own speed, whatever the backend does; the backend works on the newest picture whenever it is free (pictures it skips get no boxes of
# their own) and its boxes are put on the right pictures when they are ready.
FILE_PLAYBACK = os.environ.get("HK_FILE_PLAYBACK", "buffered").strip().lower()
PLAYOUT_FILE_DELAY_S = float(os.environ.get("HK_PLAYOUT_FILE_DELAY_S", "3"))   # continuous: how far the picture is behind the backend
REPLAY_S = float(os.environ.get("HK_REPLAY_S", "120"))      # seconds of finished video the enforcer can go back over, and the backend may work ahead while the screen is paused
_playout_info: dict = {}                                                       # the buffer's state now (the Performance popup shows it)


def playout_status() -> dict:
    """{"state": filling | playing | done, "ahead_s", "speed", ...} of the running feed's playback buffer, or {} (none)."""
    return dict(_playout_info)

# ── Module-level singleton ────────────────────────────────────────────────────
CONFIG_PATH = Path(__file__).resolve().parent.parent / "camera_config.json"

# Instantiated once at import time so reconnects do NOT wipe tracking state
# or leak VRAM by re-loading models.
def _build_pipeline():
    """Lazily build the pipeline to avoid import-time side-effects during tests."""
    from engine.pipeline import DecoupledPipeline
    pipeline = DecoupledPipeline(str(CONFIG_PATH))
    pipeline.show_paths = True          # live evidence photos of Crossing a solid line carry the path the vehicle drove
    return pipeline

_pipeline = None
_pipeline_source = None      # the camera the current pipeline was built for (a learned traffic flow only fits the same camera)
_pipeline_stale = False      # the source changed: a fresh pipeline is built the next time one is needed (see mark_pipeline_stale)

# The Live Monitor learns the painted road lines of its camera from the stream by itself (engine/live_calibrator.py) and
# remembers them per camera in camera_config.json. One for the whole app: a reconnect or a new pipeline keeps what is learned.
road = LiveCalibrator(config_path=CONFIG_PATH)


def road_status() -> dict:
    """What the road learner is doing (state, progress, what it found, refusal reason) for the dashboard."""
    return road.status()


def mark_pipeline_stale() -> None:
    """The video source changed. The pipeline for the new source (a fresh tracker, nothing remembered from the old video) is built the
    next time one is needed: when the feed starts, or when "Apply" builds one with new rules, whichever comes first. Not now, so
    choosing a file or a camera takes no time and the models load once."""
    global _pipeline_stale
    _pipeline_stale = True


# One pipeline build at a time. A build loads models (seconds): the preparing thread, "Apply" and a feed that starts must not each build one.
_build_lock = _threading.RLock()

# "Apply" is building the pipeline for the new rules: NOT set while it does. A feed that starts meanwhile (the old one was stopped, the dashboard
# reconnects) waits for it here: it must not start on the old rules and keep them.
_pipeline_ready = _threading.Event()
_pipeline_ready.set()
_rebuilds = 0                                     # Applies that are building now (two at once: the feed waits for both)
_rebuild_guard = _threading.Lock()


def begin_rebuild() -> None:
    """Apply starts building the pipeline for new rules (call it before the running feed is stopped). Pair with end_rebuild()."""
    global _rebuilds
    with _rebuild_guard:
        _rebuilds += 1
        _pipeline_ready.clear()


def end_rebuild() -> None:
    global _rebuilds
    with _rebuild_guard:
        _rebuilds = max(0, _rebuilds - 1)
        if _rebuilds == 0:
            _pipeline_ready.set()


def _get_pipeline():
    _pipeline_ready.wait(timeout=180)             # never longer than this, whatever happened to the build
    if _pipeline is None or _pipeline_stale:
        with _build_lock:                      # a build that is running now is waited for, not repeated
            if _pipeline is None or _pipeline_stale:
                return reload_pipeline()
    return _pipeline

def reload_pipeline():
    global _pipeline, _pipeline_source, _pipeline_stale
    with _build_lock:
        old, old_source = _pipeline, _pipeline_source
        _pipeline = _build_pipeline()
        _pipeline_source = VIDEO_SOURCE
        _pipeline_stale = False
        # New rules for the SAME camera keep what the traffic already taught (the learned flow): learning it again takes minutes.
        # Another camera starts from nothing.
        if old is not None and old_source == VIDEO_SOURCE and getattr(old, "flow", None) is not None:
            _pipeline.flow = old.flow
        return _pipeline


def warm_up_pipeline() -> None:
    """Run every model of the current pipeline once on an empty picture (the detector and the ReID networks were warmed when they were loaded).
    The first run of a CUDA model costs seconds; this pays it behind the setup, so the first live picture is not the slow one. Never raises."""
    pipeline = _pipeline
    registry = getattr(pipeline, "registry", None)
    warm = getattr(registry, "warm_up", None)
    if warm is None:
        return
    try:
        warm()
    except Exception as exc:
        print(f"[Stream] Warm-up skipped: {exc}")


# ── Preparing the models before they are needed ───────────────────────────────────
# Pressing Start (or "Set up violations") tells the backend the Live Monitor is about to run. The detector, the trackers' ReID networks and
# the models of the rules that are saved are loaded and warmed NOW, in a thread, while the operator goes through the setup - so "Apply" only
# finds them loaded and the first picture is not the slow one. Nothing is built that depends on the new rules.
_prepare_thread: "_threading.Thread | None" = None
_prepare_lock = _threading.Lock()


def _prepare_models() -> None:
    from engine.registry import ModelRegistry
    from engine.start_log import START

    # (while a feed runs, its own start-up timeline is not touched)
    mark = START.mark if _active_source is None else (lambda step: None)
    try:
        try:
            cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8")) if CONFIG_PATH.exists() else {}
        except (OSError, ValueError):
            cfg = {}
        mark("preparing")
        get_inference(tracker_type=cfg.get("tracker", "bytetrack"))        # loads + warms the detector and the trackers (when not loaded yet)
        mark("detector ready")
        registry = ModelRegistry(str(CONFIG_PATH))                         # the saved rules' models: loaded into the shared cache
        registry.warm_up()
        mark("rule models ready")
    except Exception as exc:
        print(f"[Stream] Preparing the models failed (they load when the feed starts instead): {exc}")


def prepare_feed() -> dict:
    """Start loading + warming the models in the background (once at a time). {"state": "started" | "running"}."""
    global _prepare_thread
    with _prepare_lock:
        if _prepare_thread is not None and _prepare_thread.is_alive():
            return {"state": "running"}
        from engine.start_log import START
        if _active_source is None:
            START.continue_or_begin("prepare")
        _prepare_thread = _threading.Thread(target=_prepare_models, daemon=True, name="live-prepare")
        _prepare_thread.start()
    return {"state": "started"}


# ── Traffic flow on the live picture ─────────────────────────────────────────────
# Counterflow (and the rules that need the traffic flow) learn which way traffic goes by watching the camera. The live picture
# can show the learned arrows, and Counterflow can be reversed for a demo: ordinary traffic is then flagged, so it can be shown
# without waiting for a real wrong-way car. Both only change what is shown / tested; the learned flow itself is kept.
_last_size = (0, 0)      # (width, height) of the processed picture the live loop works on


def _flow_state(pipeline) -> dict | None:
    """{"learning", "counterflow", "reversed", "cells"} for the controls of the live picture, or None when no rule uses the flow."""
    counterflow_on = "counterflow" in pipeline.registry.active_violations
    learning = bool(pipeline.learns_flow)
    if not counterflow_on and not learning:
        return None
    settings = (getattr(pipeline, "violation_cfg", None) or {}).get("counterflow") or {}
    width, height = _last_size
    return {
        "learning": learning,
        "counterflow": counterflow_on,
        "reversed": counterflow_on and bool(settings.get("invert_flow")),
        "cells": len(pipeline.flow.learned_cells(width, height)) if learning and width else 0,
    }


def flow_status() -> dict | None:
    """The flow state for the status endpoint (no arrows). Never raises: it is only a help for the dashboard."""
    try:
        return None if _pipeline is None else _flow_state(_pipeline)
    except Exception:
        return None


def _flow_message(pipeline, w: int, h: int) -> dict | None:
    """The flow state plus the learned arrows (pixels of the w x h picture) for one live frame."""
    try:
        state = _flow_state(pipeline)
        if state is None:
            return None
        arrows = pipeline.flow.arrows(w, h, invert=state["reversed"]) if state["learning"] else []
        return {**state, "arrows": [{k: round(v, 1) for k, v in arrow.items()} for arrow in arrows]}
    except Exception:
        return None


def set_flow_reversed(on: bool) -> dict:
    """Demo of Counterflow: the opposite of the legal direction counts as legal (on), or normal again (off). Takes effect on the
    next frame. Temporary: a new pipeline (other rules saved from the setup, another camera) starts normal."""
    pipeline = _pipeline
    if pipeline is None or "counterflow" not in pipeline.registry.active_violations:
        return {"ok": False, "reason": "Counterflow is not switched on. Press Set up violations and pick Counterflow first."}
    from engine.violations import ALL
    next(v for v in ALL if v.key == "counterflow").set_test_reversed(pipeline, bool(on))
    return {"ok": True, "reversed": bool(on)}


def relearn_flow() -> dict:
    """Forget the learned traffic flow and learn it again from the traffic (e.g. the camera was moved)."""
    pipeline = _pipeline
    if pipeline is None:
        return {"ok": False, "reason": "The live monitor has not been started yet."}
    from engine.flow_field import FlowField
    pipeline.flow = FlowField()
    return {"ok": True}


# ── HLS Broadcaster (Phase B) ─────────────────────────────────────────────────
# Pipes raw frames to ffmpeg → MediaMTX RTSP → HLS for Flutter's video_player.
# Falls back to base64 JPEG WebSocket if ffmpeg is not installed.
from engine.hls_broadcaster import get_broadcaster as _get_broadcaster

# How the picture reaches the dashboard:
#   synced (default)  the picture is a JPEG inside the SAME message as the boxes, so the boxes sit exactly on the vehicles.
#                     No encoder and no video relay are needed.
#   relay             the picture goes through ffmpeg and MediaMTX: smoother and lighter, but it arrives later than the boxes.
PICTURE_MODE = os.environ.get("HK_PICTURE_MODE", "synced").strip().lower()
PICTURE_MAX_WIDTH = 960
PICTURE_JPEG_QUALITY = 72


# The violations whose overlay objects (signs, painted crosswalks and lines) are NOT drawn on the live picture: the Live Monitor's
# "Layers" checklist. A set shared by every pipeline: changing it takes effect on the next picture.
_hidden_overlays: set[str] = set()


def set_hidden_overlays(keys) -> list[str]:
    """Replace the hidden set (violation keys). Returns it, sorted."""
    _hidden_overlays.clear()
    _hidden_overlays.update(str(k) for k in keys or ())
    return sorted(_hidden_overlays)


def hidden_overlays() -> list[str]:
    return sorted(_hidden_overlays)


def _with_overlays(frame, pipeline, detections):
    """The picture with the overlay objects of the switched-on violations painted on it (a copy), or `frame` itself when there are none.
    Never raises: the overlays are only a help. The vehicles of the last judged picture are the ones the paint goes under."""
    if pipeline is None:
        return frame
    try:
        h, w = frame.shape[:2]
        items = pipeline.live_overlay_zones(w, h, _hidden_overlays)
        if not items:
            return frame
        out = frame.copy()
        pipeline.draw_live_overlays(out, items, detections or ())
        return out
    except Exception:
        return frame


TURN_ARROWS_LAYER = "illegal_turn:arrows"          # the Layers switch of the banned-turn arrows
PATHS_LAYER = "crossing_solid_line:paths"          # the Layers switch of the light line behind every vehicle (Crossing a solid line)


def _layered(items: list) -> list:
    """The drawn zones for the dashboard, without the banned-turn arrows when Layers has them switched off."""
    if TURN_ARROWS_LAYER not in _hidden_overlays:
        return items
    return [{k: v for k, v in item.items() if k != "arrows"} for item in items]


def _picture_b64_timed(frame, pipeline=None, detections=()) -> str:
    """_picture_b64 with its time kept (it runs in a worker thread, started as soon as the picture is read). With a `pipeline` the overlay
    objects of the set-up violations are painted on the picture first."""
    t0 = time.perf_counter()
    out = _picture_b64(_with_overlays(frame, pipeline, detections))
    TIMER.add("encode", time.perf_counter() - t0)
    return out


def _picture_b64(frame) -> str:
    """The frame as a small JPEG (same shape, at most PICTURE_MAX_WIDTH wide) in base64, for the 'synced' mode."""
    h, w = frame.shape[:2]
    if w > PICTURE_MAX_WIDTH:
        frame = cv2.resize(frame, (PICTURE_MAX_WIDTH, max(1, round(h * PICTURE_MAX_WIDTH / w))), interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, PICTURE_JPEG_QUALITY])
    return base64.b64encode(buf.tobytes()).decode("ascii") if ok else ""


def _encode_stream_frame(annotated: cv2.Mat, width: int, quality: int) -> str:
    """Run in thread pool: downscale and JPEG-encode display frame (fallback path)."""
    h, w = annotated.shape[:2]
    dh = int(h * (width / w))
    disp = cv2.resize(annotated, (width, dh), interpolation=cv2.INTER_LINEAR)
    from yolo_inference import get_inference
    return get_inference().encode_frame(disp, quality)
# ─────────────────────────────────────────────────────────────────────────────


@router.websocket("/video-feed")
async def video_feed(websocket: WebSocket):
    await websocket.accept()
    try:
        start = max(0.0, float(websocket.query_params.get("start") or 0.0))   # a video file: where to go on from (Refresh / Resume)
    except ValueError:
        start = 0.0
    await _real_loop(websocket, start)


def _log_stream_error(text: str) -> None:
    """The live feed stopped on an error: keep it in stream_errors.log (the console of the backend is not always read)."""
    try:
        with open(Path(__file__).resolve().parent.parent / "stream_errors.log", "a", encoding="utf-8") as f:
            f.write(f"--- {datetime.now().isoformat(timespec='seconds')}\n{text}\n")
    except OSError:
        pass


async def _process_ocr_background(violation_id: str, snap_path: str, plate_bbox: list):
    try:
        import cv2
        import os
        from engine.slicer import NumpySlicer
        from yolo_inference import _extract_plate_text

        # 1. Load the saved image from disk
        abs_path = os.path.join(os.path.dirname(__file__), "..", snap_path)
        frame = cv2.imread(abs_path)
        if frame is None:
            return

        # 2. Crop the plate region
        plate_crop = NumpySlicer.crop_box(frame, plate_bbox)
        if plate_crop.size == 0:
            return

        # 3. Run EasyOCR in a thread pool so we absolutely don't block asyncio
        plate_text = await asyncio.get_event_loop().run_in_executor(None, _extract_plate_text, plate_crop)

        # 4. Map the extracted text to a user in the database
        if plate_text != "unidentified":
            resolved_user = await store.get_user_by_plate(plate_text)
            if resolved_user:
                # 5. Update the violation record transparently in the background
                await store.update_violation_user(violation_id, resolved_user["id"])

    except Exception as e:
        print(f"[Background OCR] Failed to process plate: {e}")

_stream_generation = 0
_current_ws_id = None

# ── Setup picture ─────────────────────────────────────────────────────────────
# The Live Monitor's "Set up violations" is drawn on ONE frozen picture of the running camera. The loop keeps a copy of the
# camera's newest picture once a second; capture_reference() freezes it (full size, at most 1920 wide) for the dashboard.
_latest_picture = None
_latest_picture_at = 0.0
_reference: dict | None = None
REFERENCE_MAX_WIDTH = 1920


def capture_reference() -> dict:
    """Freeze the newest picture of the running camera. {"ok": True, "version", "width", "height", "fps"} or {"ok": False, "reason"}."""
    picture = _latest_picture
    if picture is None or time.time() - _latest_picture_at > 5.0:
        return {"ok": False, "reason": "No picture from the camera yet. Wait for the live picture, then try again."}
    h, w = picture.shape[:2]
    if w > REFERENCE_MAX_WIDTH:
        picture = cv2.resize(picture, (REFERENCE_MAX_WIDTH, max(1, round(h * REFERENCE_MAX_WIDTH / w))), interpolation=cv2.INTER_AREA)
        h, w = picture.shape[:2]
    ok, buf = cv2.imencode(".jpg", picture, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        return {"ok": False, "reason": "The picture could not be saved. Try again."}
    return set_reference(buf.tobytes(), w, h)


def set_reference(jpeg: bytes, width: int, height: int, at: float | None = None) -> dict:
    """Make this picture (a JPEG) the one the violations are set up on. `at` = its time in a video file (None: a camera picture).
    {"ok": True, "version", "width", "height", "fps"}."""
    global _reference
    version = _reference["version"] + 1 if _reference else 1
    _reference = {"jpeg": jpeg, "width": width, "height": height, "version": version, "at": at}
    fps = round(_active_source.source_fps, 1) if _active_source is not None else 25.0
    return {"ok": True, "version": version, "width": width, "height": height, "fps": fps}


def start_clean() -> None:
    """The Live Monitor was opened: forget the old road (saved and learned) and the learned traffic flow, so everything starts from nothing.
    Skipped while a feed is running (it would pull the rules out from under it)."""
    global _pipeline
    if _active_source is not None:
        return
    road.reset_all()
    _pipeline = None                      # a new pipeline is built when the feed starts: no learned flow comes along


def clear_reference() -> None:
    """Forget the setup picture (the Live Monitor starts empty)."""
    global _reference
    _reference = None


def reference_at() -> float | None:
    """The time of the setup picture in its video file (seconds), or None."""
    return _reference.get("at") if _reference else None


def reference_jpeg() -> bytes | None:
    """The frozen setup picture (JPEG), or None before the first capture."""
    return _reference["jpeg"] if _reference else None


# The zones the operator set up, for the live picture ("what did I set up?"). Rebuilt only when the pipeline or the picture size changes.
_setup_overlay_cache: tuple = (None, 0, 0, [])


def _setup_overlay(pipeline, w: int, h: int) -> list:
    """The DRAWN zones of the switched-on violations on the processed frame: [{"violation", "polygon", "line", "drawn": True}].
    A rule that watches the whole picture has nothing drawn and so nothing here. Never raises: the overlay is only a help."""
    global _setup_overlay_cache
    cached_pipeline, cached_w, cached_h, items = _setup_overlay_cache
    if cached_pipeline is pipeline and (cached_w, cached_h) == (w, h):
        return items
    items = []
    try:
        from engine.violations import ZONE_VIOLATIONS
        active = set(pipeline.registry.active_violations)
        for violation in ZONE_VIOLATIONS:
            if violation.key not in active:
                continue
            for zone in pipeline.rois.get(violation.zone_key) or []:
                if violation.key == "pedestrian_lane" and zone.get("overlay"):
                    continue                                                  # a painted zebra is on the picture itself: no outline over it
                polygon = pipeline._scale_polygon(zone.get("polygon") or [], w, h)
                line = pipeline._scale_polygon(zone["stop_line"], w, h) if zone.get("stop_line") else []
                if len(polygon) >= 3 or len(line) >= 2:
                    item = {"violation": violation.key, "polygon": polygon, "line": line, "best_effort": False, "drawn": True}
                    if zone.get("flow_path"):                       # Counterflow: the legal way, bent where the road bends
                        item["arrow"] = pipeline._scale_polygon(zone["flow_path"], w, h)
                    arrows = [pipeline._scale_polygon(zone[f], w, h) for f in ("turn_arrow_left", "turn_arrow_right") if zone.get(f)]
                    if arrows:
                        item["arrows"] = arrows                     # Illegal turn: the banned turns of a marked road (Layers can hide them)
                    items.append(item)
    except Exception:
        items = []
    try:
        items.extend(_marking_arrows(pipeline, w, h, items))
    except Exception:
        pass                                                          # the arrows are only a help
    _setup_overlay_cache = (pipeline, w, h, items)
    return items


def _marking_arrows(pipeline, w: int, h: int, shown: list) -> list:
    """The roads and lanes of the setup's road markings that have a direction (Road step): the road and its arrow, bent as it was marked.
    A road whose arrow a Counterflow zone already shows is not drawn twice."""
    try:
        markings = json.loads(CONFIG_PATH.read_text(encoding="utf-8")).get("road_markings") or []
    except (OSError, ValueError):
        return []

    def same(a: list, b: list) -> bool:
        return len(a) == len(b) and all(abs(p[0] - q[0]) <= 4 and abs(p[1] - q[1]) <= 4 for p, q in zip(a, b))
    out = []
    for m in markings:
        if not isinstance(m, dict) or m.get("kind") not in ("road", "lane") or m.get("flow") not in ("in", "out"):
            continue
        arrow = pipeline._scale_polygon(m.get("arrow") or [], w, h)
        polygon = pipeline._scale_polygon(m.get("polygon") or [], w, h)
        if len(arrow) < 2 or len(polygon) < 3 or any(same(arrow, it.get("arrow") or []) for it in shown):
            continue
        out.append({"violation": "road", "polygon": polygon, "line": None, "best_effort": False, "hint": False, "flow": m["flow"], "arrow": arrow})
    return out


async def _real_loop(websocket: WebSocket, start_s: float = 0.0):
    global _current_ws_id, _stream_generation, _active_source, _latest_picture, _latest_picture_at, _last_size
    import uuid
    my_ws_id = str(uuid.uuid4())
    _current_ws_id = my_ws_id
    my_gen = _stream_generation

    from engine.start_log import START
    START.continue_or_begin("connect")                         # (the Apply that just happened, or a start of its own)
    START.mark("feed connected")
    start_loop = asyncio.get_running_loop()

    class DashboardGone(Exception):
        pass

    async def start_up(job):
        """Run a start-up job in a thread and wait for it, telling the dashboard the feed is alive (at once, then every 2 s): its
        "Processing" view shows from the first moment, its "no picture yet" warning and its watchdog stay quiet however long the models take.
        An error of the job itself is raised as it always was; only a dashboard that has gone away ends the start quietly."""
        fut = start_loop.run_in_executor(None, job)
        while True:
            try:
                await websocket.send_json({"type": "buffer", "state": "filling", "percent": 0.0, "ahead_s": 0.0, "speed": 1.0, "need_s": 0.0, "live": False})
            except (WebSocketDisconnect, RuntimeError):
                raise DashboardGone() from None
            done, _ = await asyncio.wait({fut}, timeout=2.0)
            if done:
                return fut.result()

    try:
        # The pipeline is built here only when nothing was built since the source changed, and either way OFF the event loop: a build loads
        # models for seconds and would freeze every other request of the backend (and the messages of this feed). A build that is running
        # now (Apply) is waited for, not repeated.
        pipeline = await start_up(_get_pipeline)
        engine = await start_up(get_inference)                 # needed for encode_frame / save_snapshot
        START.mark("pipeline ready")
        await start_up(warm_up_pipeline)                       # (instant when Apply / the preparing thread did it: a model that ran once is skipped)
        START.mark("models warm")
    except DashboardGone:
        return                                                 # the dashboard left while the models were loading

    try:
        source = CameraSource(VIDEO_SOURCE)
    except ValueError as exc:
        print(f"[Stream] Unusable video source: {exc}")
        await websocket.close()
        return
    if not await start_loop.run_in_executor(None, source.start):    # (a file opens now; a camera connects in the background)
        await websocket.close()
        return
    if start_s > 0 and not source.live:
        source.seek(start_s)                                   # go on where the picture was (Refresh / Resume)
    START.mark("source open")
    _active_source = source
    source_fps = source.source_fps
    # The road learner watches the camera itself (every picture, from the reader thread), so it keeps its pace when the
    # detector is slow. A file has no reader thread: the loop below feeds it.
    source.tap = road.feed if source.live else None
    road.attach(camera_key(VIDEO_SOURCE, CONFIG_PATH))        # a saved road for this camera is used at once, else it starts learning
    pipeline.set_learned_zones(road.active_zones())
    road_version = road.version

    frame_idx = 0
    last_yolo_results: list = []

    # track_id -> (violation_type, assigned_user) for mock mode
    flagged_tracks: dict = {}

    loop = asyncio.get_event_loop()
    print(f"[Stream] Pipeline overlap: {'on' if PIPELINE_OVERLAP else 'off (HK_PIPELINE_OVERLAP=0)'}")
    # Overlap mode: the detector and the trackers (stage A, its own thread) work on the NEXT inference picture while the rules thread
    # (stage B) and the sender finish the one before, so the loop does not wait for the models one picture after the other.
    # `pending` = the newest inference picture that is not shown yet: {"fut": its stage A, "frames": the pictures that are shown with its
    # boxes}. Boxes and pictures still go out together, as before; the picture is a little later (about one inference interval at most).
    pending = None
    next_due = None          # overlap mode, files: when the next picture is due (a steady pace that catches up after a slow one)
    ahead = None             # overlap mode, files: the read of the next picture, started before this one is judged and sent
    n_read = 0               # files: how many pictures were read (a picture's time on the video is n_read / fps)

    def fetch():
        """Read the next picture and shrink it: (item, small picture, its time on the video in seconds), or (None, None, None) when nothing
        came. A live camera's time is the moment the camera delivered it. Runs in a worker thread: for a
        video file it works one picture ahead of the loop, so decoding (55 ms measured on a 4K file) and shrinking are off the loop's path."""
        t0 = time.perf_counter()
        got = source.read(1.0)
        TIMER.add("decode", time.perf_counter() - t0)
        if got is None:
            return None, None, None
        START.mark("first picture read")
        nonlocal n_read
        if source.live:
            when = got.captured_at or time.time()
        else:
            when = n_read / float(source_fps)
            n_read += 1
        t0 = time.perf_counter()
        big = got.image
        # The road learner gets the camera's own picture, before the cap below: thin paint and pavement tiles are told
        # apart far better at 1080p than at 720p (at 720p a tiled pavement strip can pass for a crosswalk).
        # Cheap: most calls only check the clock; the reading runs in its own thread.
        if not source.live:
            road.feed(big, time.time())
        # ── Resolution cap ─────────────────────────────────────────────
        # Downscale tall frames (e.g. 1080p → 720p) before any processing.
        # YOLO always rescales to 640px internally, so detection accuracy is
        # unchanged. All other operations (frame.copy, cv2 drawing, JPEG
        # encode) become significantly faster on the smaller array.
        fh, fw = big.shape[:2]
        small = big
        if fh > MAX_PROCESSING_HEIGHT:
            scale_down = MAX_PROCESSING_HEIGHT / fh
            small = cv2.resize(big, (int(fw * scale_down), MAX_PROCESSING_HEIGHT), interpolation=cv2.INTER_LINEAR)
        TIMER.add("prep", time.perf_counter() - t0)
        return got, small, when

    publishing: set = set()             # the tasks that save tickets in the background (kept here so they are not collected half done)

    async def publish_tickets(tickets: list) -> None:
        from routers import forensic as forensic_router          # imported here: the forensic router imports this module
        for ticket in tickets:
            try:
                await forensic_router.publish_live_ticket(ticket, pipeline.config, add_violation)
            except Exception as exc:                              # one bad ticket must not stop the feed
                import traceback
                print(f"[Stream] A live ticket could not be saved: {exc!r}")
                _log_stream_error(traceback.format_exc())

    async def save_tickets(tickets: list) -> None:
        """Real pipeline tickets -> the "live" run (report + Inbox rows). The plate is NOT read here: the live feed keeps no plate, it is
        read from the ticket's evidence photos when the reviewer opens the ticket (routers/forensic.py publish_live_ticket).
        The saving runs in the background (the tickets one after the other): the pictures never wait for the report file and the database."""
        if not tickets:
            return
        task = asyncio.create_task(publish_tickets(tickets))
        publishing.add(task)
        task.add_done_callback(publishing.discard)

    async def mock_violations(frame) -> None:
        """Mock-mode violations (testing only), made on the newest results."""
        if not store.USE_MOCK:
            return
        for d in last_yolo_results:
            if d.track_id in flagged_tracks:
                viol_type, assigned_user = flagged_tracks[d.track_id]
                d.is_violator = True
                d.violation_type = viol_type
                d.assigned_user_id = assigned_user["id"]
                d.assigned_user_name = assigned_user["name"]

            elif random.random() < 0.03:
                if d.cls in ["car", "motorcycle", "bus", "truck"]:
                    viol_type = random.choice(MOCK_CLASSES)
                    assigned_user = random.choice(MOCK_USERS)
                    flagged_tracks[d.track_id] = (viol_type, assigned_user)
                    d.is_violator = True
                    d.violation_type = viol_type

                    snap_frame = engine.draw_detections(frame.copy(), [d])
                    snap_path = engine.save_snapshot(snap_frame, SNAPSHOTS_DIR)

                    await add_violation(
                        d.violation_type,
                        d.confidence,
                        user_id=assigned_user["id"],
                        image_path=snap_path,
                    )
                    d.assigned_user_id = assigned_user["id"]
                    d.assigned_user_name = assigned_user["name"]

    send_lock = asyncio.Lock()          # the finished pictures and the status messages go out over the same socket, one at a time
    playout = None                      # the playback buffer (None: every picture is shown as soon as it is done)
    player_task = None
    continuous = False                  # a video file played like a camera (see FILE_PLAYBACK)
    worker_task = None                  # continuous: works on the newest picture whenever it is free, and puts its boxes on the pictures
    offer: dict = {}                    # continuous: the newest picture that waits for the backend
    offer_event = asyncio.Event()
    carry: dict = {"display": [], "specs": None}   # continuous: the boxes of the newest finished picture, given to each picture that is read after it
    if PLAYOUT and PICTURE_MODE != "relay":
        if not source.live and FILE_PLAYBACK == "continuous":
            continuous = True
            playout = Playout(live=True, start_s=PLAYOUT_FILE_DELAY_S, max_s=PLAYOUT_MAX_S, keep_all=True)
        else:
            gap_s = PLAYOUT_LIVE_START_S if source.live else PLAYOUT_START_S       # (start_s stays where on the video this run began)
            playout = Playout(live=source.live, start_s=gap_s, max_s=PLAYOUT_MAX_S, history_s=REPLAY_S, hold_max_s=REPLAY_S)
        _playout_info.clear()
    print(f"[Stream] Playback buffer: {'on' if playout is not None else 'off'}{' (video file played continuously)' if continuous else ''}")
    # The pictures of this run go to disk as they are finished (engine/live_run.py): the screen may be far behind the backend (the enforcer
    # paused, or looks at a ticket) and may go back and forth over what is done, and the memory does not grow with it.
    run = None
    preview: dict = {"b64": None}        # the newest finished picture, kept in memory for the "Processing" view only
    run_t0: list = [None]                # video time of the first finished picture: the timeline counts from there
    feed_started = time.monotonic()      # the video's own clock for the timeline: seconds since this run began
    control_task = None
    if playout is not None and not continuous:
        run = live_run.start()
        if run is not None:
            playout.on_drop = lambda payload: run.drop(payload.get("file"))

    def boxes_of(results: list):
        """(the detections for the dashboard, the Forensic Analyzer's box specs) of the results of one picture."""
        with TIMER.time("overlay"):
            # Send ALL detections to Flutter so the frontend can draw the boxes dynamically
            display_results = [
                {
                    "class": getattr(d, "violation_type", getattr(d, "cls", "unknown")),
                    "is_violator": getattr(d, "is_violator", False),
                    "confidence": round(d.confidence, 3),
                    "track_id": getattr(d, "track_id", -1),
                    "bbox": [
                        int(d.bbox[0]),
                        int(d.bbox[1]),
                        int(d.bbox[2]),
                        int(d.bbox[3]),
                    ],
                    "user_id": getattr(d, "assigned_user_id", None),
                    "user_name": getattr(d, "plate_text", None) if getattr(d, "plate_text", "unidentified") != "unidentified" else getattr(d, "assigned_user_name", None),
                    "marks": getattr(d, "marks", []),   # boxes showing why it was flagged (engine/marks.py)
                }
                for d in results
            ]

            try:                                                    # the Forensic Analyzer's own boxes (label, colours, plate, why-marks, stopwatch)
                box_specs = pipeline.box_specs(results)
                if PATHS_LAYER in _hidden_overlays:                 # Layers: "Crossing a solid line: vehicle paths" switched off
                    box_specs = [s for s in box_specs if "trail" not in s]
            except Exception:
                box_specs = None                                    # the dashboard then draws plain boxes from `detections`

        return display_results, box_specs

    async def package(picture_frame, encoding, t: float) -> dict:
        """A finished picture with its boxes, ready to be shown. In "synced" mode only the JPEG is kept (the raw picture is let go, so a
        buffer of seconds stays small). (JSON Overlay Architecture: the boxes are not burned into the picture; Flutter draws them on top.)
        `encoding` = the JPEG job that was started when the picture was read (or None)."""
        h, w = picture_frame.shape[:2]
        display_results, box_specs = boxes_of(last_yolo_results)

        picture = None
        file = None
        if PICTURE_MODE != "relay":
            # ── synced: the picture rides in the same message as the boxes ──
            picture = await (encoding if encoding is not None else loop.run_in_executor(None, _picture_b64_timed, picture_frame, pipeline, last_yolo_results))
            if run is not None and picture:
                preview["b64"] = picture
                try:
                    file = await loop.run_in_executor(None, run.store, picture)        # on disk: the picture leaves the memory
                    picture = None
                except Exception:
                    file = None                                                         # the disk failed: the picture stays in memory, as before
                if run.keep_all:
                    run.note(file, t, w, h, display_results, box_specs)
        return {"t": t, "w": w, "h": h, "picture": picture, "file": file, "frame": picture_frame if PICTURE_MODE == "relay" else None,
                "detections": display_results, "boxes": box_specs}

    def make_packet(picture_frame, encoding, t: float) -> dict:
        """Continuous playback: a picture goes into the buffer the moment it is read, with the boxes of the newest finished picture (its own
        boxes replace them when they are ready). Only the JPEG is kept: the raw picture is let go as soon as it is encoded."""
        h, w = picture_frame.shape[:2]
        packet = {"t": t, "w": w, "h": h, "picture": None, "encoding": encoding, "frame": picture_frame,
                  "detections": carry["display"], "boxes": carry["specs"]}

        def encoded(fut) -> None:
            if not fut.cancelled() and fut.exception() is None:
                packet["picture"] = fut.result()
                packet["frame"] = None
        encoding.add_done_callback(encoded)
        return packet

    async def judge_and_bind(job, o: dict) -> None:
        """Stage B of a picture, then its boxes go onto the waiting pictures from its time on (later pictures get them as they are read)."""
        nonlocal last_yolo_results
        _picture, last_yolo_results = await loop.run_in_executor(_PIPELINE_EXECUTOR, pipeline.judge_stage, job)
        START.mark("first picture judged")
        await save_tickets(pipeline.ledger_manager.drain_tickets())   # stage B is idle now, so the ledgers are read safely here
        await mock_violations(o["frame"])
        display, specs = boxes_of(last_yolo_results)
        carry["display"], carry["specs"] = display, specs
        playout.patch(o["t"], lambda p: p.update(detections=display, boxes=specs))

    async def inference_worker() -> None:
        """Continuous playback: whenever the backend is free it takes the NEWEST picture (the ones in between are skipped) and works on it.
        Stage A of one picture overlaps stage B of the one before."""
        prev = None
        try:
            while True:
                await offer_event.wait()
                offer_event.clear()
                o = dict(offer)
                a_fut = loop.run_in_executor(_DETECT_EXECUTOR, pipeline.detect_stage, o["frame"], o["idx"], o["time"])
                if prev is not None:
                    await prev
                job = await a_fut
                prev = asyncio.create_task(judge_and_bind(job, o))
        finally:
            if prev is not None:
                prev.cancel()

    async def transmit(packet: dict, buffer_info: dict | None) -> None:
        """One finished picture and its boxes to the dashboard. `buffer_info` = the playback buffer's state (None: no buffer)."""
        relay = PICTURE_MODE == "relay"
        if relay:
            # ── video relay: ffmpeg -> MediaMTX (the picture arrives later than the boxes) ──
            broadcaster = _get_broadcaster()
            with TIMER.time("encode"):
                if not broadcaster._started:
                    h_fr, w_fr = packet["frame"].shape[:2]
                    print(f"[Stream] Starting broadcaster with {w_fr}x{h_fr}")
                    broadcaster.start(width=w_fr, height=h_fr)
                # the overlay objects (signs, painted crosswalks and lines) go on the relayed picture too, as on the synced one
                await loop.run_in_executor(None, lambda: broadcaster.push(_with_overlays(packet["frame"], pipeline, last_yolo_results)))
        w, h = packet["w"], packet["h"]
        picture = packet["picture"]
        if picture is None and packet.get("file") and run is not None:
            picture = await loop.run_in_executor(None, run.load_b64, packet["file"])
        if picture is None and packet.get("encoding") is not None:
            picture = await packet["encoding"]               # (continuous playback: nearly always done long before it is shown)
        with TIMER.time("send"):
            async with send_lock:
                await websocket.send_json({
                    "type": "frame",
                    "transport": "hls" if relay else "jpeg",
                    "hls_url": _get_broadcaster().hls_url if relay else None,
                    "frame_width": w,
                    "frame_height": h,
                    "mock": store.USE_MOCK,
                    "frame_base64": picture,   # synced mode: the picture itself; relay mode: None
                    "detections": packet["detections"],
                    "boxes": packet["boxes"],                           # same data the replay's boxes.json holds, per frame
                    "camera": source.status(),
                    "road": road.status(),                              # learning progress / what was learned / why it could not
                    "road_zones": _layered(_setup_overlay(pipeline, w, h)) + pipeline.learned_overlay(w, h) + road.hint_overlay(w, h) + road.region_overlay(w, h),   # set-up zones + learned zones in use + line hints
                    "flow": _flow_message(pipeline, w, h),              # the learned traffic-flow arrows + whether the demo reversal is on (None: no rule uses the flow)
                    "buffer": buffer_info,                              # the playback buffer: state, how much is ready, the playing speed
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })
        TIMER.mark("pictures")
        line = TIMER.report_every(5.0)
        if line:
            print(line)

    async def emit(picture_frame, encoding, t: float) -> None:
        """A picture is done: into the playback buffer, or (no buffer) straight to the dashboard."""
        packet = await package(picture_frame, encoding, t)
        if run_t0[0] is None:
            run_t0[0] = t
        TIMER.mark("produced")
        START.mark("first picture finished")
        if playout is None:
            await transmit(packet, None)
        else:
            playout.push(t, packet)

    async def player() -> None:
        """The screen side of the playback buffer: shows the finished pictures at the video's own pace, a few seconds late. While the
        buffer fills (at the start, or after it ran dry) it tells the dashboard how far it is ("Processing... 60%")."""
        last_note = 0.0
        last_hold = 0.0
        last_pause_note = 0.0
        while True:
            if _plate_service.focusing():
                # a plate is being read: the screen is paused too. A quiet "status" every second keeps the dashboard from thinking the feed died.
                playout.hold()
                if time.monotonic() - last_hold >= 1.0:
                    last_hold = time.monotonic()
                    async with send_lock:
                        await websocket.send_json({"type": "status", "camera": source.status(), "paused": True})
                await asyncio.sleep(0.05)
                continue
            shown = playout.tick()
            info = playout.info()
            if not source.live:
                info["pos_s"] = round(start_s + (playout.play_t or 0.0), 2)   # where on the video the screen is (Refresh / Resume go on from here)
            t0 = run_t0[0] or 0.0                                             # the timeline: seconds from the start of this run
            for key in ("first_s", "play_s", "proc_s"):
                if info.get(key) is not None:
                    info[key] = round(info[key] - t0, 2)
            info["video_s"] = round(time.monotonic() - feed_started, 2)       # where the video itself would be, played at its own speed
            if playout.paused and time.monotonic() - last_pause_note >= 0.5:
                last_pause_note = time.monotonic()
                async with send_lock:
                    await websocket.send_json({"type": "buffer", **info})     # paused: no pictures go out, so the timeline is told here
            _playout_info.clear()
            _playout_info.update(info)
            if info["state"] == "playing":
                START.mark("playing")
            if info["state"] == "filling" and time.monotonic() - last_note >= 0.5:
                last_note = time.monotonic()
                note = {"type": "buffer", **info}
                newest = playout.newest()
                shot = (newest.get("picture") if newest is not None else None) or preview["b64"]
                if newest is not None and shot:                    # the newest finished picture, for the "Processing" view (it is not played)
                    note["preview"] = {"picture": shot, "w": newest["w"], "h": newest["h"],
                                       "boxes": [d["bbox"] for d in newest["detections"]]}
                async with send_lock:
                    await websocket.send_json(note)
            for packet in shown:
                await transmit(packet, info)
            if info["state"] == "done":
                return
            await asyncio.sleep(playout.next_delay())

    async def finish(group: dict) -> None:
        """Overlap mode: the pending inference picture is detected: judge it (stage B), save its tickets, and show it and the
        pictures that waited for its boxes."""
        nonlocal last_yolo_results
        job = await group["fut"]                                   # stage A: ready by now, or the loop waits for it
        _picture, last_yolo_results = await loop.run_in_executor(_PIPELINE_EXECUTOR, pipeline.judge_stage, job)
        START.mark("first picture judged")
        await save_tickets(pipeline.ledger_manager.drain_tickets())   # stage B is idle now, so the ledgers are read safely here
        await mock_violations(group["frames"][0][0])
        for picture_frame, encoding, t in group["frames"]:
            await emit(picture_frame, encoding, t)

    async def control() -> None:
        """The dashboard's timeline: pause, play, go to a time (seconds from the start of this run; never beyond what is finished)."""
        while True:
            try:
                text = await websocket.receive_text()
            except Exception:
                return                                             # the socket is gone: the loop notices it by itself
            try:
                msg = json.loads(text)
                cmd = msg.get("cmd")
                if cmd == "pause":
                    playout.pause()
                elif cmd == "play":
                    playout.resume()
                elif cmd == "seek":
                    playout.seek((run_t0[0] or 0.0) + float(msg.get("t", 0.0)))
            except Exception:
                continue

    if playout is not None:
        player_task = asyncio.create_task(player())
        control_task = asyncio.create_task(control())
    if continuous:
        worker_task = asyncio.create_task(inference_worker())

    try:
        while True:
            if player_task is not None and player_task.done():
                player_task.result()                               # the screen side failed (the dashboard left): its error ends the loop here
            if worker_task is not None and worker_task.done():
                worker_task.result()                               # the backend side failed: its error ends the loop here
            # If a new websocket has connected, OR the video source changed (new generation), this loop is obsolete.
            if _current_ws_id != my_ws_id or my_gen != _stream_generation:
                print(f"[Stream] Obsolete loop detected (ws_changed={_current_ws_id != my_ws_id}, gen_changed={my_gen != _stream_generation}). Shutting down.")
                # Close the socket so the dashboard knows the source changed and reconnects.
                try:
                    await websocket.close()
                except Exception:
                    pass
                break

            if _plate_service.focusing():
                # A plate is being read for a ticket: the whole machine goes to it. The live monitor waits (a file goes on from the same
                # picture afterwards, a camera shows its newest one).
                last_beat = 0.0
                while _plate_service.focusing() and _current_ws_id == my_ws_id and my_gen == _stream_generation:
                    if player_task is not None and player_task.done():
                        break
                    if player_task is None and time.monotonic() - last_beat >= 1.0:       # (no playback buffer: nobody else sends the keep-alive)
                        last_beat = time.monotonic()
                        async with send_lock:
                            await websocket.send_json({"type": "status", "camera": source.status(), "paused": True})
                    await asyncio.sleep(0.05)
                continue

            if playout is not None:
                # A video file: when enough is ready the backend waits for the screen (a live camera never waits).
                while playout.full() and _current_ws_id == my_ws_id and my_gen == _stream_generation:
                    if player_task.done():
                        player_task.result()
                        break
                    await asyncio.sleep(0.02)

            start_time = time.time()
            # Live sources: the newest frame (older ones are dropped, so lag cannot build up).
            # None = nothing arrived for a second: tell the dashboard the camera is offline and keep waiting.
            if ahead is None:
                ahead = loop.run_in_executor(None, fetch)
            with TIMER.time("wait"):
                item, frame, t_pic = await ahead
            ahead = None
            if item is None:
                if not source.live:
                    if pending is not None:                        # the file is over: its last pictures still go out
                        await finish(pending)
                        pending = None
                    if playout is not None:
                        playout.finish()
                        await player_task                          # what is still in the buffer is shown (a few seconds)
                    break
                async with send_lock:
                    await websocket.send_json({"type": "status", "camera": source.status()})
                continue
            if (PIPELINE_OVERLAP or continuous) and not source.live:
                ahead = loop.run_in_executor(None, fetch)          # the next picture is decoded while this one is judged and sent
            frame_time = item.captured_at if (source.live or continuous) else None   # live: when the camera delivered it (continuous file: when it was read)
            if start_time - _latest_picture_at >= 1.0:               # for "Set up violations": a copy, as the frame is worked on below
                _latest_picture, _latest_picture_at = item.image.copy(), start_time

            _last_size = (frame.shape[1], frame.shape[0])          # the size the pipeline (and its flow cells) works in

            if road.version != road_version:                       # learned, forgotten or the view changed: swap the zones
                road_version = road.version
                pipeline.set_learned_zones(road.active_zones())
            # The JPEG starts now, in a worker thread, so it is ready (or nearly) when the picture is shown.
            encoding = None if PICTURE_MODE == "relay" else loop.run_in_executor(None, _picture_b64_timed, frame, pipeline, last_yolo_results)

            frame_idx += 1
            run_inference = True if INFER_EVERY_N_FRAMES == 0 else (frame_idx % (INFER_EVERY_N_FRAMES + 1) == 0)

            if continuous:
                # The picture goes on at its own speed whatever the backend does: it is in the buffer at once, and is offered to the backend,
                # which takes the newest offer whenever it is free (see inference_worker).
                playout.push(t_pic, make_packet(frame, encoding, t_pic))
                TIMER.mark("produced")
                offer.update(frame=frame, idx=frame_idx, time=frame_time, t=t_pic)
                offer_event.set()
            elif not PIPELINE_OVERLAP:
                # One picture at a time, as before: both stages in one thread, the loop waits for them.
                # (The IoU tracker and ONNX session are NOT thread-safe: max_workers=1 prevents concurrent frame processing races.)
                if run_inference:
                    _picture, last_yolo_results = await loop.run_in_executor(
                        _PIPELINE_EXECUTOR, pipeline.process_frame, frame, frame_idx, frame_time
                    )
                    await save_tickets(pipeline.ledger_manager.drain_tickets())
                    await mock_violations(frame)
                await emit(frame, encoding, t_pic)
            elif run_inference:
                # Stage A of this picture starts now, in its own thread; meanwhile the picture before it is finished here.
                fut = loop.run_in_executor(_DETECT_EXECUTOR, pipeline.detect_stage, frame, frame_idx, frame_time)
                if pending is not None:
                    await finish(pending)
                pending = {"fut": fut, "frames": [(frame, encoding, t_pic)]}
            elif pending is None:
                await emit(frame, encoding, t_pic)                 # no inference picture waits for its boxes: it is done as it is
            else:
                pending["frames"].append((frame, encoding, t_pic))   # done with the boxes of the inference picture before it
                if pending["fut"].done():                          # stage A is ready: do not hold the pictures any longer
                    await finish(pending)
                    pending = None

            if source.live:
                await asyncio.sleep(0)   # the camera sets the pace; the next read waits for its next frame
            elif playout is not None and not continuous:
                await asyncio.sleep(0)   # a file with the slow-motion buffer: the buffer sets the pace (the backend waits when it is full)
            elif PIPELINE_OVERLAP or continuous:
                # Files: a steady pace. A slow picture is made up for by the quick ones after it (the pictures of one group are
                # read quickly and shown together), so the video keeps its real speed when the models are fast enough on average.
                period = 1.0 / float(source_fps)
                next_due = (start_time if next_due is None else next_due) + period
                wait = next_due - time.time()
                if wait > 0:
                    await asyncio.sleep(wait)
                else:
                    if wait < -6 * period:
                        next_due = time.time()                     # far behind: do not try to catch up
                    await asyncio.sleep(0)
            else:
                elapsed = time.time() - start_time
                await asyncio.sleep(max(0.001, 1.0 / float(source_fps) - elapsed))

    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[Stream] CRITICAL ERROR in _real_loop: {e}")
        import traceback
        traceback.print_exc()
        _log_stream_error(traceback.format_exc())
    finally:
        if pending is not None:
            pending["fut"].cancel()
        if ahead is not None:
            ahead.cancel()
        if player_task is not None:
            player_task.cancel()
        if worker_task is not None:
            worker_task.cancel()
        if control_task is not None:
            control_task.cancel()
        if run is not None:
            run.close({"source": str(mask_url(str(VIDEO_SOURCE)))})
        _playout_info.clear()
        source.stop()
        if _active_source is source:
            _active_source = None
            _latest_picture = None                                 # a picture of a camera that is gone must not become the setup picture
        if _current_ws_id == my_ws_id:
            road.detach()                                          # (a newer loop for the same camera keeps its own buffers)
            broadcaster = _get_broadcaster()
            broadcaster.stop()
