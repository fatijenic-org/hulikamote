import asyncio
import shutil
import uuid
from fastapi import APIRouter, Body, Depends, HTTPException, UploadFile, File
from engine.frame_grabber import FrameGrabber
from engine.setup_scan import SetupScan
from engine.road_presets import PresetError, RoadPresets
from engine.hls_broadcaster import server_status
from engine.camera_source import mask_url, parse_source, restore_password, test_connection
from routers.trimmer import local_only
from store import delete_all_violations

router = APIRouter(prefix="/settings", tags=["settings"])


@router.delete("/violations")
async def delete_all_violations_endpoint():
    """Wipes all violation history. Useful for resetting the demo."""
    deleted = await delete_all_violations()
    return {"status": "success", "message": "All violations deleted", "deleted": deleted}

@router.post("/mock")
async def toggle_mock_mode(enabled: bool):
    """Toggles random violation mocking on/off during live video stream."""
    from store import set_mock_mode
    set_mock_mode(enabled)
    return {"message": f"Mock mode set to {enabled}"}


@router.get("/models")
async def get_available_models():
    """Expose ONNX model choices available for video analysis."""
    from yolo_inference import list_available_models
    return {"models": list_available_models()}


@router.post("/model")
async def set_active_model(name: str = "yolov8n.onnx"):
    """Switch the active object-detection model for the video analysis feed."""
    try:
        from yolo_inference import set_model_path
        resolved = set_model_path(name)
        return {"message": "Model updated", "model": resolved.name}
    except FileNotFoundError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


import json
from pathlib import Path

CONFIG_PATH = Path(__file__).parent.parent / "camera_config.json"

@router.get("/camera-config")
async def get_camera_config():
    if not CONFIG_PATH.exists():
        return {}
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)

@router.post("/camera-config")
async def save_camera_config(config: dict):
    existing = _read_config()
    for key in ("camera_profiles", "active_source"):           # saved by the Camera input, not by the zone editor
        if key not in config and key in existing:
            config[key] = existing[key]
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)
    await asyncio.to_thread(stream.reload_pipeline)               # loads models: not on the event loop (it would freeze the whole backend)
    return {"message": "Config saved successfully"}

import cv2
from fastapi.responses import Response
from routers import stream

@router.get("/video/info")
async def get_video_info(path: str):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return {"error": "Cannot open video"}
    w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0: fps = 30.0
    frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    duration = max(1.0, frame_count / fps)
    cap.release()
    aspect = (w / h) if (w > 0 and h > 0) else (16.0 / 9.0)
    return {
        "duration": round(duration, 2),
        "fps": round(fps, 2),
        "frames": int(frame_count),
        "width": int(w),
        "height": int(h),
        "aspect_ratio": round(aspect, 4),
    }

@router.get("/video/frame")
async def get_video_frame(path: str, second: float):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        return Response(status_code=404, content="Cannot open video")
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0: fps = 30
    frame_idx = int(fps * second)
    
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()
    cap.release()
    
    if not ret:
        return Response(status_code=404, content="Frame not found")
        
    # Resize for faster transmission over dashboard UI
    h, w = frame.shape[:2]
    frame = cv2.resize(frame, (800, int(h * (800 / w))))
    _, buffer = cv2.imencode(".jpg", frame)
    return Response(content=buffer.tobytes(), media_type="image/jpeg")

def _remember_source(path: str, profile: str | None = None) -> None:
    """
    Keep the chosen camera in camera_config.json so a backend restart does not forget it. A saved profile is kept by
    NAME; a plain address only when it carries no password (an address with one must be saved as a profile first).
    """
    config = _read_config()
    if profile:
        config["active_source"] = {"profile": profile}
    elif mask_url(path) == path:
        config["active_source"] = {"url": path}
    else:
        config.pop("active_source", None)
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")


def _apply_video_source(path: str):
    stream.VIDEO_SOURCE = path
    stream._stream_generation += 1
    stream.mark_pipeline_stale()          # the fresh pipeline is built when the feed starts (or "Apply" builds one): nothing to wait for now
    # Force broadcaster restart so the new stream gets correct resolution/fps
    broadcaster = stream._get_broadcaster()
    broadcaster.stop()


def _check_source(text: str):
    try:
        return parse_source(text)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/video/source")
async def set_video_source(path: str):
    """Point the live monitor at a file, an rtsp:// / http:// address or a webcam number."""
    spec = _check_source(path)
    _remember_source(path)
    _apply_video_source(path)
    return {"message": f"Source updated to {spec.label}", "kind": spec.kind, "label": spec.label}


@router.get("/video-server")
def video_server():
    """Is the video relay (MediaMTX) up? Starts it when it is installed but not running (a plain `def`, so FastAPI
    runs it in a worker thread: starting it can take a few seconds)."""
    if stream.PICTURE_MODE != "relay":                  # synced pictures need no relay
        return {"ready": True, "message": "", "mode": stream.PICTURE_MODE}
    ready, message = server_status()
    return {"ready": ready, "message": message, "mode": "relay"}


@router.post("/video/test")
def test_video_source(path: str | None = None, name: str | None = None):
    """Try an address (or a saved profile) once: reports size, speed and time to first picture.
    A plain `def`, so FastAPI runs it in a worker thread: a dead address can take seconds."""
    return test_connection(path if path else _profile_url(name))


@router.get("/video/status")
async def video_status():
    """What the live feed is reading right now and how it is doing (state, fps, lag, reconnects), plus what the road learner
    is doing ("road": learning progress, what it learned, or why it could not), and the traffic flow ("flow": learning, counterflow,
    reversed, cells; null when no rule uses it)."""
    return {**stream.camera_status(), "road": stream.road_status(), "flow": stream.flow_status()}


@router.get("/video/road")
async def video_road():
    """The road learner on its own: state, progress, what it found for this camera."""
    return stream.road_status()


@router.post("/video/road/relearn")
async def relearn_road():
    """Forget what is known about the current view and learn it again from the live stream (needs traffic passing)."""
    return {"ok": stream.road.relearn(), "road": stream.road_status()}


@router.post("/video/road/forget")
async def forget_road():
    """Remove the learned road of the connected camera (also from camera_config.json) and stop using it."""
    return {"ok": stream.road.forget(), "road": stream.road_status()}


# ─── "Detect road": freeze a frame, read the road, show every step, then Apply or Discard ────────

@router.post("/video/road/detect")
async def detect_road():
    """The Live Monitor's Detect road button: freezes the newest picture and reads the road from the last ~40 s of the camera.
    Poll GET /video/road/detect for the steps; the frame and each step's picture have their own addresses."""
    return stream.road.begin_detect()


@router.get("/video/road/detect")
async def detect_road_status():
    """State (collecting / analysing / done / failed / none), progress, and every step with its state."""
    return stream.road.detect_status()


@router.get("/video/road/detect/frame")
async def detect_road_frame():
    """The frozen picture the walkthrough is drawn on (JPEG)."""
    data = stream.road.detect_frame()
    if not data:
        raise HTTPException(status_code=404, detail="There is no detection in progress")
    return Response(content=data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.get("/video/road/detect/step/{step}")
async def detect_road_step(step: str):
    """One step's picture (PNG with see-through parts) to lay over the frozen picture, once that step has finished."""
    data = stream.road.detect_overlay(step)
    if not data:
        raise HTTPException(status_code=404, detail="That step has no picture (yet)")
    return Response(content=data, media_type="image/png", headers={"Cache-Control": "no-store"})


@router.post("/video/road/detect/zones")
async def correct_detected_road(body: dict):
    """The operator's corrections to the draft: {"zones": [{"id", "kind": crosswalk|road|sidewalk, "polygon": [[x, y], ...]}]} in the pixels
    of the frozen picture. Apply then saves these instead of what the scan found."""
    return stream.road.set_detect_zones(body.get("zones"))


@router.post("/video/road/detect/discard")
async def discard_detected_road():
    return {"ok": stream.road.discard_detect()}


@router.post("/video/road/detect/apply")
def apply_detected_road(counterflow: bool = False):
    """Use what the detection found: the camera's road is saved and the matching violations (Pedestrian lane for a crosswalk) are switched
    on in the live configuration. When one had to be switched on, the live view restarts once with it.
    `?counterflow=true` also makes the incoming / outgoing sides of the road Counterflow zones (traffic against the arrow is flagged)."""
    result = stream.road.apply_detect(counterflow=counterflow)
    if not result.get("ok"):
        return result
    config = _read_config()
    active = list(config.get("active_violations", []))
    added = [key for key in result["zones"] if key not in active]
    if added:
        config["active_violations"] = active + added
        CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
        stream.reload_pipeline()
        stream._stream_generation += 1
    return {**result, "switched_on": added, "road": stream.road_status()}


# ─── Set up violations on the live picture (the Live Monitor's "Set up violations") ────────────

# What the setup shows again when it is opened a second time. The camera addresses (with passwords) are NOT part of it.
LIVE_SETUP_KEYS = (
    "active_violations", "per_violation_configs", "tracker", "plate_model", "plate_method", "plate_format",
    "ocr_engine", "enhancement", "primary_model", "use_sahi", "flag_sensitivity", "evidence_gap", "blur_privacy", "road_markings",
)


@router.post("/video/reference")
async def capture_reference_picture():
    """Freezes the newest picture of the running camera. The violations are set up on it; the live video goes on.
    {"ok": True, "version", "width", "height", "fps"} or {"ok": False, "reason"} (no picture yet)."""
    return stream.capture_reference()


@router.get("/video/reference/frame")
async def reference_frame():
    """The frozen setup picture (JPEG)."""
    data = stream.reference_jpeg()
    if not data:
        raise HTTPException(status_code=404, detail="No setup picture has been taken yet")
    return Response(content=data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


# The setup's "Find the road automatically": the walkthrough of Detect road on a few seconds collected from the current source, from the setup
# picture on. The status, the frame and the step pictures have the same shape as Detect road's, so the dashboard shows them the same way.
scan = SetupScan()


@router.post("/video/scan")
async def start_road_scan():
    """Start the scan. {"ok": True, "detect": status} or {"ok": False, "reason"}. Poll GET /video/scan."""
    jpeg = stream.reference_jpeg()
    if not jpeg:
        return {"ok": False, "reason": "There is no setup picture yet."}
    feed_running = stream._active_source is not None            # a camera cannot be opened twice: the feed's own picture is read instead
    return scan.start(stream.VIDEO_SOURCE, jpeg, stream.reference_at(),
                      running_picture=(lambda: stream._latest_picture) if feed_running else None)


@router.get("/video/scan")
async def road_scan_status():
    return scan.road.detect_status()


@router.get("/video/scan/frame")
async def road_scan_frame():
    data = scan.road.detect_frame()
    if not data:
        raise HTTPException(status_code=404, detail="There is no scan in progress")
    return Response(content=data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.get("/video/scan/step/{step}")
async def road_scan_step(step: str):
    data = scan.road.detect_overlay(step)
    if not data:
        raise HTTPException(status_code=404, detail="That step has no picture (yet)")
    return Response(content=data, media_type="image/png", headers={"Cache-Control": "no-store"})


@router.post("/video/scan/discard")
async def discard_road_scan():
    scan.cancel()
    return {"ok": True}


# Saved road configurations (the road markings of the setup, under a name): use again, duplicate, edit later.
road_presets = RoadPresets()


def _preset_or_404(preset: dict | None) -> dict:
    if preset is None:
        raise HTTPException(status_code=404, detail="There is no such saved road")
    return preset


def _preset_call(fn, *args):
    try:
        return fn(*args)
    except PresetError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/road-presets")
async def list_road_presets():
    return {"presets": road_presets.list()}


@router.get("/road-presets/{preset_id}")
async def get_road_preset(preset_id: str):
    return _preset_or_404(road_presets.get(preset_id))


@router.post("/road-presets")
async def save_road_preset(payload: dict = Body(...)):
    """{"name", "markings": [...]} -> the saved road (with its id)."""
    return _preset_call(road_presets.create, payload.get("name"), payload.get("markings"))


@router.put("/road-presets/{preset_id}")
async def update_road_preset(preset_id: str, payload: dict = Body(...)):
    """Any of {"name", "markings"}: only what is sent changes."""
    return _preset_or_404(_preset_call(road_presets.update, preset_id, payload.get("name"), payload.get("markings")))


@router.post("/road-presets/{preset_id}/duplicate")
async def duplicate_road_preset(preset_id: str):
    return _preset_or_404(_preset_call(road_presets.duplicate, preset_id))


@router.delete("/road-presets/{preset_id}")
async def delete_road_preset(preset_id: str):
    if not road_presets.delete(preset_id):
        raise HTTPException(status_code=404, detail="There is no such saved road")
    return {"ok": True}


# The setup's "pick a frame" step: a few pictures of the CURRENT source (a file: spread over the video; a camera: one a second for a few
# seconds). They arrive one by one; the operator picks one and it becomes the setup picture (/video/reference/frame).
_grab: FrameGrabber | None = None


@router.post("/video/frames/start")
async def start_frame_grab(count: int = 8):
    """Start collecting pictures of the current source (a new call throws the old pictures away). Poll GET /video/frames."""
    global _grab
    if _grab is not None:
        _grab.cancel()
    feed_running = stream._active_source is not None            # never open a camera the live feed is reading: use its picture
    _grab = FrameGrabber(stream.VIDEO_SOURCE, count=max(2, min(count, 12)),
                         running_picture=(lambda: stream._latest_picture) if feed_running else None)
    _grab.start()
    return _grab.status()


@router.get("/video/frames")
async def frame_grab_status():
    """{job, state: idle|grabbing|done|failed, kind: file|camera, error, expected, fps, frames: [{id, label, width, height}]}"""
    if _grab is None:
        return {"job": 0, "state": "idle", "kind": "", "error": "", "expected": 0, "fps": 25.0, "frames": []}
    return _grab.status()


@router.get("/video/frames/{frame_id}")
async def frame_grab_picture(frame_id: int):
    """One collected picture (JPEG)."""
    data = _grab.jpeg(frame_id) if _grab is not None else None
    if not data:
        raise HTTPException(status_code=404, detail="That picture is not there (yet)")
    return Response(content=data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.post("/video/frames/{frame_id}/use")
async def use_grabbed_frame(frame_id: int):
    """Make a collected picture the one the violations are set up on. {"ok": True, "version", "width", "height", "fps"}."""
    data = _grab.jpeg(frame_id) if _grab is not None else None
    size = _grab.frame_size(frame_id) if _grab is not None else None
    if not data or not size:
        return {"ok": False, "reason": "That picture is not there any more. Get new pictures and pick again."}
    return {**stream.set_reference(data, size[0], size[1], at=_grab.frame_at(frame_id)), "fps": round(_grab.fps, 1)}


@router.post("/live/flow/reverse")
async def reverse_live_flow(on: bool):
    """Demo of Counterflow on the live camera: on = the OPPOSITE of the learned (or drawn) direction counts as legal, so ordinary
    traffic is flagged; off = normal again. Takes effect on the next frame and keeps what was learned. Tickets made while it is on
    are tests (the photos carry a TEST label). Runs on the pipeline's own thread, so it never races a frame."""
    import asyncio
    return await asyncio.get_running_loop().run_in_executor(stream._PIPELINE_EXECUTOR, stream.set_flow_reversed, on)


@router.post("/live/flow/relearn")
async def relearn_live_flow():
    """Forget the learned traffic flow and learn it again (the camera was moved, or a wrong flow was learned)."""
    import asyncio
    return await asyncio.get_running_loop().run_in_executor(stream._PIPELINE_EXECUTOR, stream.relearn_flow)


@router.get("/live/timing")
async def live_timing():
    """How long each step of the live pipeline takes (average and worst of the last ~150 pictures, in ms) and how many pictures a second
    are sent and judged. The same numbers go to the log every 5 seconds. "overlap" says whether the detector and the rules work on
    different pictures at the same time (HK_PIPELINE_OVERLAP=0 turns that off)."""
    from engine.stage_timer import TIMER
    return {**TIMER.snapshot(), "overlap": stream.PIPELINE_OVERLAP}


@router.get("/live/perf")
async def live_perf(window: float = 2.5):
    """Everything the Live Monitor's Performance popup shows, in one call: the step times (as /live/timing), the steps of the last `window`
    seconds with their start times (a timeline), CPU / RAM / GPU load now and for the last 90 s, and the device each model runs on."""
    import yolo_inference
    from engine.plate_service import SERVICE as PLATE_SERVICE
    from engine.stage_timer import LANES, STEP_INFO, TIMER
    from engine.start_log import START
    from engine.system_stats import STATS
    window = min(max(window, 0.5), 10.0)
    models = []
    detector = getattr(yolo_inference, "_inference", None)
    if detector is not None:
        models.append({"name": "detector", "provider": detector._session.get_providers()[0]})
    registry = getattr(getattr(stream, "_pipeline", None), "registry", None)
    for name, session in (getattr(registry, "models", None) or {}).items():
        try:
            models.append({"name": name, "provider": session.get_providers()[0]})
        except Exception:
            pass
    return {**TIMER.snapshot(), "overlap": stream.PIPELINE_OVERLAP, "infer_every": stream.INFER_EVERY_N_FRAMES + 1, "window_s": window,
            "spans": TIMER.spans(window), "step_info": STEP_INFO, "lanes": [{"id": i, "label": label} for i, label in LANES],
            "system": STATS.snapshot(), "models": models, "playout": stream.playout_status(),
            "plate_process": PLATE_SERVICE.status(), "startup": START.snapshot()}


@router.post("/live/prepare")
async def prepare_live():
    """The Live Monitor is about to start (Start, or Set up violations, was pressed): load and warm the models NOW, in the background,
    while the operator goes through the setup. Apply then finds them loaded and the first picture is not the slow one. Safe to call often."""
    return stream.prepare_feed()


@router.get("/live/record")
async def get_live_record():
    """Whether the next live run is saved (every picture and its boxes, to replay later like a forensic run) and where."""
    from engine import live_run
    return {**live_run.read_settings(), "default_dir": str(Path(__file__).resolve().parent.parent / "snapshots" / "live_runs_saved")}


@router.post("/live/record")
async def set_live_record(body: dict):
    """Choose to save the next live runs, and the folder (made when it does not exist). {"save": bool, "dir": str}"""
    from engine import live_run
    try:
        return live_run.write_settings(bool(body.get("save")), str(body.get("dir") or ""))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/live/setup")
async def get_live_setup():
    """The violations and settings the Live Monitor uses now, in the wizard's own shape (empty when none were set up)."""
    config = _read_config()
    return {key: config[key] for key in LIVE_SETUP_KEYS if key in config}


@router.get("/live/overlays")
async def get_live_overlays():
    """The violations whose overlay objects (signs, painted crosswalks and lines) are hidden on the live picture."""
    return {"hidden": stream.hidden_overlays()}


@router.put("/live/overlays")
async def put_live_overlays(payload: dict = Body(...)):
    """{"hidden": ["restricted_lane", ...]}: those violations draw no overlay objects on the live picture (the rules still judge them)."""
    hidden = payload.get("hidden")
    if not isinstance(hidden, list):
        raise HTTPException(status_code=400, detail="Send the violations to hide as a list")
    return {"hidden": stream.set_hidden_overlays(hidden)}


@router.delete("/live/tickets")
async def clear_live_tickets_endpoint():
    """Clear every ticket the Live Monitor made before (database rows, report, evidence photos). Forensic analyses are not touched."""
    from routers import forensic as forensic_router
    return {"ok": True, **await forensic_router.clear_live_tickets()}


@router.post("/live/reset")
async def reset_live_setup():
    """The Live Monitor starts empty each time it is opened: no violations, no zones, no road markings, no setup picture, no saved or learned
    road, no learned traffic flow. The camera, the saved camera addresses, the saved roads (road_presets.json) and the pipeline settings are kept."""
    config = _read_config()
    config["active_violations"] = []
    for key in ("per_violation_configs", "road_markings"):
        config.pop(key, None)
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
    scan.cancel()
    stream.set_hidden_overlays(())               # a new setup shows all its overlays
    stream.clear_reference()
    stream.mark_pipeline_stale()                 # the next feed is built without the old rules
    stream.start_clean()                         # no saved or learned road, no learned traffic flow
    return {"ok": True}


# ─── Camera profiles: named addresses (CCTV / DVR, phone camera, another laptop, a file) ────────

def _read_config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8")) if CONFIG_PATH.exists() else {}


def _profiles() -> list[dict]:
    return [p for p in _read_config().get("camera_profiles", []) if isinstance(p, dict) and p.get("name") and p.get("url")]


def _profile_url(name: str | None) -> str:
    for profile in _profiles():
        if profile["name"] == name:
            return profile["url"]
    raise HTTPException(status_code=404, detail=f"No camera profile named '{name}'")


@router.get("/camera-profiles")
async def list_camera_profiles():
    """Saved camera addresses. Passwords are never sent back: they show as ***."""
    out = []
    for profile in _profiles():
        try:
            kind = parse_source(profile["url"]).kind
        except ValueError:
            kind = "invalid"
        out.append({"name": profile["name"], "url": mask_url(profile["url"]), "kind": kind})
    return {"profiles": out}


@router.put("/camera-profiles")
async def save_camera_profiles(body: dict):
    """Replace the saved profiles. An address that still has *** for its password keeps the stored password."""
    old = {p["name"]: p["url"] for p in _profiles()}
    saved = []
    for item in body.get("profiles", []):
        name, url = str(item.get("name", "")).strip(), str(item.get("url", "")).strip()
        if not name or not url:
            raise HTTPException(status_code=400, detail="Every profile needs a name and an address")
        url = restore_password(url, old.get(name, ""))
        _check_source(url)
        saved.append({"name": name, "url": url})
    config = _read_config()
    config["camera_profiles"] = saved
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return {"message": "Camera profiles saved", "count": len(saved)}


@router.post("/camera-profiles/use")
async def use_camera_profile(name: str):
    """Make a saved profile the live monitor's source."""
    url = _profile_url(name)
    spec = _check_source(url)
    _remember_source(url, profile=name)
    _apply_video_source(url)
    return {"message": f"Source updated to {spec.label}", "kind": spec.kind, "label": spec.label}


PHONE_PROFILE = "Phone"


@router.post("/phone/connect")
async def connect_phone():
    """The Live Monitor's "Connect phone": finds the HULI-KAMOTE Camera app on the phone by itself (USB cable, USB tethering,
    the phone's hotspot or the same Wi-Fi: engine/phone_link.py), saves it as the camera "Phone" and makes it the live source.
    Always answers 200: {"ok": False, "message", "steps"} says what to do when no phone was found."""
    import asyncio
    from engine import phone_link
    result = await asyncio.get_running_loop().run_in_executor(None, phone_link.connect)
    if not result["ok"]:
        return result
    url = result["url"]
    config = _read_config()
    config["camera_profiles"] = [p for p in _profiles() if p["name"] != PHONE_PROFILE] + [{"name": PHONE_PROFILE, "url": url}]
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
    _remember_source(url, profile=PHONE_PROFILE)
    _apply_video_source(url)
    return {**result, "label": parse_source(url).label}


UPLOAD_DIR =Path(__file__).parent.parent / "snapshots" / "live_uploads"
_ALLOWED_VIDEO_EXT = {".mp4", ".avi", ".mov", ".mkv", ".webm"}


def _video_info(path: Path) -> dict | None:
    """What a video file is (width, height, fps, frames, duration in seconds, size_mb), or None when it cannot be opened."""
    cap = cv2.VideoCapture(str(path))
    try:
        if not cap.isOpened():
            return None
        fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
        frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        return {
            "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0),
            "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0),
            "fps": round(fps, 2),
            "frames": frames,
            "duration": round(frames / fps, 1) if fps > 1.0 and frames > 0 else 0.0,
            "size_mb": round(path.stat().st_size / 1048576, 1),
        }
    finally:
        cap.release()


@router.post("/video/use-file", dependencies=[Depends(local_only)])
async def use_video_file(path: str):
    """Use a video file WHERE IT IS as the live monitor source: no copy, nothing to wait for (the backend and the dashboard are on
    the same PC). 404 when this PC cannot see the file (then the dashboard uploads a copy instead)."""
    file = Path(path)
    if not file.is_file():
        raise HTTPException(status_code=404, detail="That file is not on the backend PC.")
    if file.suffix.lower() not in _ALLOWED_VIDEO_EXT:
        raise HTTPException(status_code=400, detail=f"Unsupported video type '{file.suffix.lower()}'")
    video = _video_info(file)
    if video is None:
        raise HTTPException(status_code=400, detail="Cannot open that video")
    _remember_source(str(file))
    _apply_video_source(str(file))
    return {"message": "Live source updated", "path": str(file), "video": video}


@router.post("/video/upload")
async def upload_video_source(file: UploadFile = File(...)):
    """Save an uploaded video and make it the live monitor source."""
    ext = Path(file.filename or "").suffix.lower()
    if ext not in _ALLOWED_VIDEO_EXT:
        raise HTTPException(status_code=400, detail=f"Unsupported video type '{ext}'")
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    dest = UPLOAD_DIR / f"{uuid.uuid4().hex}{ext}"
    with open(dest, "wb") as out:
        shutil.copyfileobj(file.file, out)
    video = _video_info(dest)                           # also what the dashboard's "ready" card shows
    if video is None:
        dest.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Cannot open uploaded video")
    _remember_source(str(dest))
    _apply_video_source(str(dest))
    # Keep only the current upload; older ones are no longer the live source.
    for old in UPLOAD_DIR.iterdir():
        if old != dest and old.is_file():
            try:
                old.unlink()
            except OSError:
                pass  # still open by the stream; it will be removed on the next upload
    return {"message": "Live source updated", "path": str(dest), "video": video}
