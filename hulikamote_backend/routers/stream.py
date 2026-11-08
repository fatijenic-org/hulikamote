import asyncio
import json
import random
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import cv2
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import store
from engine.camera_source import CameraSource, mask_url, parse_source
from engine.live_calibrator import LiveCalibrator, camera_key
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

# ── Module-level singleton ────────────────────────────────────────────────────
CONFIG_PATH = Path(__file__).resolve().parent.parent / "camera_config.json"

# Instantiated once at import time so reconnects do NOT wipe tracking state
# or leak VRAM by re-loading models.
def _build_pipeline():
    """Lazily build the pipeline to avoid import-time side-effects during tests."""
    from engine.pipeline import DecoupledPipeline
    return DecoupledPipeline(str(CONFIG_PATH))

_pipeline = None

# The Live Monitor learns the painted road lines of its camera from the stream by itself (engine/live_calibrator.py) and
# remembers them per camera in camera_config.json. One for the whole app: a reconnect or a new pipeline keeps what is learned.
road = LiveCalibrator(config_path=CONFIG_PATH)


def road_status() -> dict:
    """What the road learner is doing (state, progress, what it found, refusal reason) for the dashboard."""
    return road.status()


def _get_pipeline():
    global _pipeline
    if _pipeline is None:
        _pipeline = _build_pipeline()
    return _pipeline

def reload_pipeline():
    global _pipeline
    _pipeline = _build_pipeline()
    return _pipeline


# ── HLS Broadcaster (Phase B) ─────────────────────────────────────────────────
# Pipes raw frames to ffmpeg → MediaMTX RTSP → HLS for Flutter's video_player.
# Falls back to base64 JPEG WebSocket if ffmpeg is not installed.
from engine.hls_broadcaster import get_broadcaster as _get_broadcaster


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
    await _real_loop(websocket)


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

async def _real_loop(websocket: WebSocket):
    global _current_ws_id, _stream_generation, _active_source
    import uuid
    my_ws_id = str(uuid.uuid4())
    _current_ws_id = my_ws_id
    my_gen = _stream_generation

    pipeline = _get_pipeline()
    engine = get_inference()  # needed for encode_frame / save_snapshot

    try:
        source = CameraSource(VIDEO_SOURCE)
    except ValueError as exc:
        print(f"[Stream] Unusable video source: {exc}")
        await websocket.close()
        return
    if not source.start():
        await websocket.close()
        return
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
    annotated_high_res = None

    # track_id -> (violation_type, assigned_user) for mock mode
    flagged_tracks: dict = {}

    try:
        while True:
            # If a new websocket has connected, OR the video source changed (new generation), this loop is obsolete.
            if _current_ws_id != my_ws_id or my_gen != _stream_generation:
                print(f"[Stream] Obsolete loop detected (ws_changed={_current_ws_id != my_ws_id}, gen_changed={my_gen != _stream_generation}). Shutting down.")
                # Close the socket so the dashboard knows the source changed and reconnects.
                try:
                    await websocket.close()
                except Exception:
                    pass
                break

            start_time = time.time()
            # Live sources: the newest frame (older ones are dropped, so lag cannot build up).
            # None = nothing arrived for a second: tell the dashboard the camera is offline and keep waiting.
            item = await asyncio.get_event_loop().run_in_executor(None, source.read, 1.0)
            if item is None:
                if not source.live:
                    break
                await websocket.send_json({"type": "status", "camera": source.status()})
                continue
            frame = item.image
            frame_time = item.captured_at if source.live else None   # live: when the camera delivered it

            # The road learner gets the camera's own picture, before the cap below: thin paint and pavement tiles are told
            # apart far better at 1080p than at 720p (at 720p a tiled pavement strip can pass for a crosswalk).
            # Cheap: most calls only check the clock; the reading runs in its own thread.
            if not source.live:
                road.feed(frame, time.time())

            # ── Resolution cap ─────────────────────────────────────────────
            # Downscale tall frames (e.g. 1080p → 720p) before any processing.
            # YOLO always rescales to 640px internally, so detection accuracy is
            # unchanged. All other operations (frame.copy, cv2 drawing, JPEG
            # encode) become significantly faster on the smaller array.
            fh, fw = frame.shape[:2]
            if fh > MAX_PROCESSING_HEIGHT:
                scale_down = MAX_PROCESSING_HEIGHT / fh
                frame = cv2.resize(
                    frame,
                    (int(fw * scale_down), MAX_PROCESSING_HEIGHT),
                    interpolation=cv2.INTER_LINEAR,
                )

            if road.version != road_version:                       # learned, forgotten or the view changed: swap the zones
                road_version = road.version
                pipeline.set_learned_zones(road.active_zones())

            frame_idx += 1
            run_inference = True if INFER_EVERY_N_FRAMES == 0 else (frame_idx % (INFER_EVERY_N_FRAMES + 1) == 0)

            t0 = time.time()
            if run_inference:
                # Run pipeline in the dedicated single-threaded executor.
                # The IoU tracker and ONNX session are NOT thread-safe — using
                # max_workers=1 prevents concurrent frame processing races.
                annotated_high_res, last_yolo_results = (
                    await asyncio.get_event_loop().run_in_executor(
                        _PIPELINE_EXECUTOR, pipeline.process_frame, frame, frame_idx, frame_time
                    )
                )

                # ── Drain real pipeline tickets → DB ─────────────────────
                for ticket in pipeline.ledger_manager.drain_tickets():
                    # We save the ticket immediately with 'scanning'.
                    # This guarantees the live video NEVER freezes.
                    evidence_paths = ticket.get("evidence_paths") or []
                    snap_path = evidence_paths[0] if evidence_paths else ""

                    v_record = await add_violation(
                        cls=", ".join(ticket["violations"]),
                        confidence=1.0,
                        user_id="scanning",
                        image_path=snap_path,
                        notify=False,
                        evidence_paths=evidence_paths,
                        track_id=ticket.get("track_id", -1),
                    )
                    
                    # Automatically trigger background OCR so the user doesn't have to click
                    from routers.violations import run_plate_extraction
                    asyncio.create_task(run_plate_extraction(v_record["id"]))

                # ── Mock-mode violations (testing only) ──────────────────
                if store.USE_MOCK:
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
            else:
                # Fast path: JSON Overlay Architecture
                # We no longer burn tracking boxes into the video in Python!
                # We just pass the raw frame, and let Flutter draw the JSON coordinates on top.
                annotated_high_res = frame
            t1 = time.time()

            # ── Frame rendering ───────────────────────────────────────────
            if annotated_high_res is None:
                annotated_high_res = frame

            h, w = frame.shape[:2]

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
                for d in last_yolo_results
            ]

            broadcaster = _get_broadcaster()

            # ── Phase B: HLS Transport (Forced) ────────────────────────────────
            if not broadcaster._started:
                h_fr, w_fr = annotated_high_res.shape[:2]
                print(f"[Stream] Starting broadcaster with {w_fr}x{h_fr}")
                broadcaster.start(width=w_fr, height=h_fr)
            
            t2 = time.time()
            # Push clean raw frame to ffmpeg pipe (non-blocking)
            await asyncio.get_event_loop().run_in_executor(
                None, broadcaster.push, annotated_high_res
            )
            t3 = time.time()
            
            if frame_idx % 30 == 0:
                print(f"[Profiler] AI: {(t1-t0)*1000:.1f}ms | FFmpeg Push: {(t3-t2)*1000:.1f}ms")
            
            await websocket.send_json({
                "type": "frame",
                "transport": "hls",
                "hls_url": broadcaster.hls_url,
                "frame_width": w,
                "frame_height": h,
                "mock": store.USE_MOCK,
                "frame_base64": None,   # Stripped completely
                "detections": display_results,
                "camera": source.status(),
                "road": road.status(),                              # learning progress / what was learned / why it could not
                "road_zones": pipeline.learned_overlay(w, h) + road.hint_overlay(w, h),   # learned zones in use + line hints
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

            if source.live:
                await asyncio.sleep(0)   # the camera sets the pace; the next read waits for its next frame
            else:
                elapsed = time.time() - start_time
                await asyncio.sleep(max(0.001, 1.0 / float(source_fps) - elapsed))

    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[Stream] CRITICAL ERROR in _real_loop: {e}")
        import traceback
        traceback.print_exc()
    finally:
        source.stop()
        if _active_source is source:
            _active_source = None
        if _current_ws_id == my_ws_id:
            road.detach()                                          # (a newer loop for the same camera keeps its own buffers)
            broadcaster = _get_broadcaster()
            broadcaster.stop()
