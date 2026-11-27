import asyncio
import shutil
import uuid
from fastapi import APIRouter, Body, Depends, HTTPException, UploadFile, File
from engine.frame_grabber import FrameGrabber
from engine.setup_scan import SetupScan
from engine.road_presets import PresetError, RoadPresets
from engine.setup_presets import PresetError as SetupPresetError, SetupPresets
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
    stream.reset_rules()                                          # a new setup: every rule of it is on
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
    from engine import live_run, replay_run
    replay_run.deactivate()                 # a real source is chosen: a saved run is not replayed any more
    live_run.CONTINUE["folder"] = None      # ... and no saved monitoring waits to go on
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
    "quality_mode", "judge_incoming_two_wheelers",
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
setup_presets = SetupPresets()


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
async def list_road_presets(hash: str | None = None):
    """The saved roads; with the fingerprint of the video in use ("hash"), the roads saved for it come first and carry match: true."""
    return {"presets": road_presets.list(hash)}


@router.get("/road-presets/{preset_id}")
async def get_road_preset(preset_id: str):
    return _preset_or_404(road_presets.get(preset_id))


@router.post("/road-presets")
async def save_road_preset(payload: dict = Body(...)):
    """{"name", "markings": [...]} -> the saved road (with its id)."""
    return _preset_call(road_presets.create, payload.get("name"), payload.get("markings"), payload.get("video_hash") or "", payload.get("video_name") or "")


@router.put("/road-presets/{preset_id}")
async def update_road_preset(preset_id: str, payload: dict = Body(...)):
    """Any of {"name", "markings"}: only what is sent changes."""
    return _preset_or_404(_preset_call(road_presets.update, preset_id, payload.get("name"), payload.get("markings"),
                                       payload.get("video_hash"), payload.get("video_name")))


@router.post("/road-presets/{preset_id}/duplicate")
async def duplicate_road_preset(preset_id: str):
    return _preset_or_404(_preset_call(road_presets.duplicate, preset_id))


@router.delete("/road-presets/{preset_id}")
async def delete_road_preset(preset_id: str):
    if not road_presets.delete(preset_id):
        raise HTTPException(status_code=404, detail="There is no such saved road")
    return {"ok": True}


# ─── Saved violation setups, and the fingerprint of the video they belong to ───────────────────────────────────────

@router.get("/video/hash")
async def current_video_hash():
    """The fingerprint of the video file the Live Monitor uses now ({hash, name, size}; hash is null for a camera or an address)."""
    from engine import video_fingerprint
    found = await asyncio.to_thread(video_fingerprint.of_source, stream.VIDEO_SOURCE)
    return found or {"hash": None, "name": "", "size": 0}


def _setup_call(fn, *args):
    try:
        return fn(*args)
    except SetupPresetError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/setup-presets")
async def list_setup_presets(hash: str | None = None):
    return {"presets": setup_presets.list(hash)}


@router.get("/setup-presets/{preset_id}")
async def get_setup_preset(preset_id: str):
    found = setup_presets.get(preset_id)
    if found is None:
        raise HTTPException(status_code=404, detail="There is no such saved setup")
    return found


@router.post("/setup-presets")
async def save_setup_preset(payload: dict = Body(...)):
    """{"name", "config": {active_violations, per_violation_configs, ...}, "video_hash", "video_name"} -> the saved setup."""
    return _setup_call(setup_presets.create, payload.get("name"), payload.get("config"), payload.get("video_hash") or "", payload.get("video_name") or "")


@router.put("/setup-presets/{preset_id}")
async def update_setup_preset(preset_id: str, payload: dict = Body(...)):
    found = _setup_call(setup_presets.update, preset_id, payload.get("name"), payload.get("config"), payload.get("video_hash"), payload.get("video_name"))
    if found is None:
        raise HTTPException(status_code=404, detail="There is no such saved setup")
    return found


@router.delete("/setup-presets/{preset_id}")
async def delete_setup_preset(preset_id: str):
    if not setup_presets.delete(preset_id):
        raise HTTPException(status_code=404, detail="There is no such saved setup")
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


@router.get("/live/rules")
async def get_live_rules():
    """The live switch: {ready, setup: [rules of the setup], active: [rules on], cost_ms: {rule: average ms per picture}, needs: {rule: what it needs}}."""
    return stream.rules_state()


@router.post("/live/stabilizer")
async def set_live_stabilizer(body: dict):
    """The box stabilizer: {"on": bool, "hold_s": seconds a lost box stays on the screen (0 to 5), "keep_conf": the lowest score a tracked
    vehicle keeps its box at (0 = off)}. Only what is sent changes."""
    try:
        return stream.set_stabilizer(body.get("on"), body.get("hold_s"), body.get("keep_conf"))
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="The hold time and the score must be numbers.") from exc


@router.post("/live/rules")
async def set_live_rules(body: dict):
    """Switch the rules of the running monitoring ({"active": [keys]}): the backend judges only those from the next picture on, and runs only the
    models they need. A rule that is not in the setup cannot be switched on here."""
    active = body.get("active")
    if not isinstance(active, list):
        raise HTTPException(status_code=400, detail="Send the rules that should be on as a list.")
    try:
        return await asyncio.to_thread(stream.set_rules, [str(k) for k in active])
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


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


# ─── Replay of a saved run (engine/replay_run.py) ───────────────────────────────────────────────────────────────

@router.get("/replay/runs")
async def list_replay_runs():
    """The saved runs (folders with pictures + index.jsonl) in the folder chosen for saving and in the default one, newest first."""
    from engine import replay_run
    active = replay_run.active()
    return {"runs": await asyncio.to_thread(replay_run.list_runs), "active": active.name if active else None,
            "roots": [str(r) for r in replay_run.roots()]}


@router.post("/replay/open")
async def open_replay_run(body: dict):
    """Make a saved run the Live Monitor's source ({"run": folder name}). The dashboard opens the feed after this; it plays the run, with no models."""
    from engine import replay_run
    folder = replay_run.find(str(body.get("run") or ""))
    if folder is None:
        raise HTTPException(status_code=404, detail="That saved run was not found.")
    replay_run.activate(folder)
    return {"ok": True, "run": folder.name}


@router.post("/live/session/save")
async def save_live_session(body: dict):
    """"Save and pause": everything needed to go on with this monitoring later goes into the run folder (session.json): the setup, the
    learned road, the source and where on the video the picture is ({"pos_s"}). The run must be a saved one ("Save this run")."""
    from datetime import datetime
    from engine import live_run
    run = live_run.CURRENT.get("run")
    if run is None or not run.keep_all:
        raise HTTPException(status_code=409, detail="This run is not being saved. Turn on \"Save this run\" in the last setup step, then start monitoring.")
    config = _read_config()
    keep = {k: config[k] for k in LIVE_SETUP_KEYS if k in config}
    if "learned_road" in config:
        keep["learned_road"] = config["learned_road"]
    source = str(stream.VIDEO_SOURCE)
    masked = mask_url(source) == source                      # an address with a password is never written down
    run.save_session({
        "status": "paused", "saved_at": datetime.now().isoformat(timespec="seconds"), "pos_s": float(body.get("pos_s") or 0.0),
        "source": source if masked else None, "source_name": source.replace("\\", "/").split("/")[-1] if masked else "",
        "config": keep, "hidden_overlays": stream.hidden_overlays(), "rules_off": sorted(stream._rules_off),
    })
    return {"ok": True, "folder": str(run.folder)}


async def apply_session(folder: Path, restore_tickets: bool = True) -> dict:
    """Bring a saved monitoring back: its setup and learned road, its source, its overlays; its tickets become the live tickets again (not when
    they are on screen already: the replay shows them); the pictures that follow are written after the ones already saved. Returns
    {"pos_s", "source_name", "tickets"}. Raises HTTPException (404, 400) in words."""
    from engine import live_run, replay_run
    session_file = folder / "session.json"
    if not session_file.is_file():
        raise HTTPException(status_code=404, detail="That monitoring was not saved with \"Save and pause\".")
    session = json.loads(session_file.read_text(encoding="utf-8"))
    source = session.get("source")
    if source and not source.startswith(("rtsp://", "http://", "https://")) and not source.isdigit() and not Path(source).exists():
        raise HTTPException(status_code=400, detail=f"The video of this monitoring is not there any more: {source}")
    config = _read_config()
    config.update(session.get("config") or {})
    learned = (session.get("config") or {}).get("learned_road")
    if learned:
        config["learned_road"] = {**(config.get("learned_road") or {}), **learned}
    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")
    if source:
        _check_source(source)
        _remember_source(source)
        _apply_video_source(source)
    stream.set_hidden_overlays(session.get("hidden_overlays") or [])
    stream.reset_rules()
    stream._rules_off = set(session.get("rules_off") or [])            # the rules that were off stay off
    stream.mark_pipeline_stale()
    tickets = await replay_run.put_back_all(folder) if restore_tickets else -1
    live_run.CONTINUE["folder"] = folder
    return {"ok": True, "pos_s": float(session.get("pos_s") or 0.0), "source_name": session.get("source_name") or "", "tickets": tickets}


@router.post("/live/session/continue")
async def continue_live_session(body: dict):
    """Go on with a saved monitoring ({"run": folder name}); the dashboard then opens the feed at {"pos_s"}. See apply_session."""
    from engine import replay_run
    folder = replay_run.find(str(body.get("run") or ""))
    if folder is None:
        raise HTTPException(status_code=404, detail="That monitoring was not saved with \"Save and pause\".")
    return await apply_session(folder)


def _redetect_source(folder: Path):
    """(source file, setup config, the rules in it) of a saved run: from the session saved with Save and pause, else the run's own record and
    the setup that is applied now."""
    session = {}
    try:
        session = json.loads((folder / "session.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    meta = {}
    try:
        meta = json.loads((folder / "run.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    config = session.get("config") or {k: _read_config()[k] for k in LIVE_SETUP_KEYS if k in _read_config()}
    source = session.get("source") or meta.get("source")
    return source, config


@router.get("/replay/{run_id}/info")
async def redetect_info(run_id: str):
    """What "Re-detect a part" needs to know about a saved run: its length, the rules of its setup, and whether its video can be read."""
    from engine import replay_run
    folder = replay_run.find(run_id)
    if folder is None:
        raise HTTPException(status_code=404, detail="That saved run was not found.")
    source, config = _redetect_source(folder)
    ok = bool(source) and Path(str(source)).is_file()
    return {"duration": await asyncio.to_thread(replay_run.quick_duration, folder), "rules": list(config.get("active_violations") or []),
            "source": Path(str(source)).name if source else "", "can": ok,
            "why": "" if ok else "The video of this run is not on this computer any more, so it cannot be analyzed again."}


@router.post("/replay/redetect")
async def start_redetect(body: dict):
    """Run the detection again on a stretch of a saved run's video ({"run", "start_s", "end_s", "rules": [...]}; seconds on the run's timeline).
    It is a Forensic analysis of that stretch with the saved setup and the chosen rules: its result (the evidence video with boxes, the
    tickets, the plates) is in the Forensic Library, and the original video file is never touched. Needs the live feed stopped (the analysis
    uses the same detector). Returns {"task_id"}; the progress is /api/forensic/status/{task_id}."""
    import copy
    import threading
    import uuid
    from engine import replay_run
    from engine.pipeline import EVIDENCE_DIR
    from routers import forensic

    folder = replay_run.find(str(body.get("run") or ""))
    if folder is None:
        raise HTTPException(status_code=404, detail="That saved run was not found.")
    if stream._active_source is not None:
        raise HTTPException(status_code=409, detail="Stop the live monitoring first (Save and pause), then analyze again: both use the same detector.")
    source, config = _redetect_source(folder)
    if not source or not Path(str(source)).is_file():
        raise HTTPException(status_code=400, detail="The video of this run is not on this computer any more.")
    config = copy.deepcopy(config)
    in_setup = list(config.get("active_violations") or [])
    rules = [str(r) for r in (body.get("rules") or []) if str(r) in in_setup] or in_setup
    if not rules:
        raise HTTPException(status_code=400, detail="This run has no rules to analyze again.")
    try:
        start_s, end_s = float(body.get("start_s")), float(body.get("end_s"))
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Give the start and the end of the part, in seconds.")
    if end_s - start_s < 1.0:
        raise HTTPException(status_code=400, detail="The part must be at least one second long.")
    v_start, v_end = replay_run.video_time(folder, start_s), replay_run.video_time(folder, end_s)
    config.update({
        "active_violations": rules, "trim_start": max(0.0, v_start), "trim_end": max(v_start + 1.0, v_end),
        "keep_input_video": True,                     # the video file of the run is the operator's: it must never be deleted
        "video_name": Path(str(source)).name, "redetect_of": folder.name,
    })
    task_id = str(uuid.uuid4())
    task_dir = EVIDENCE_DIR / "forensic" / task_id
    output_dir = task_dir / "output"
    output_dir.mkdir(parents=True, exist_ok=True)
    forensic.forensic_tasks[task_id] = {"status": "processing", "progress": 0.0, "result_video": None, "tickets": [], "ticket_count": 0,
                                         "video_done": False, "message": ""}
    forensic._main_loop = asyncio.get_running_loop()            # the analysis thread posts its report and database work here
    threading.Thread(target=forensic.forensic_processing_task, args=(task_id, Path(str(source)), output_dir, config),
                     name=f"redetect-{task_id[:8]}", daemon=True).start()
    try:                                                         # the run remembers which parts were analyzed again
        record = folder / "redetects.json"
        items = json.loads(record.read_text(encoding="utf-8")) if record.exists() else []
        items.append({"task_id": task_id, "start_s": start_s, "end_s": end_s, "rules": rules})
        record.write_text(json.dumps(items, indent=2), encoding="utf-8")
    except (OSError, ValueError):
        pass
    return {"ok": True, "task_id": task_id, "rules": rules, "video_start_s": v_start, "video_end_s": v_end}


@router.post("/replay/close")
async def close_replay_run():
    from engine import replay_run
    replay_run.deactivate()
    return {"ok": True}


@router.post("/replay/adopt")
async def adopt_live_tickets(body: dict):
    """A saved run that has no tickets of its own yet (made before runs kept them): take the tickets that are in the Live Monitor now."""
    from engine import replay_run
    folder = replay_run.find(str(body.get("run") or ""))
    if folder is None:
        raise HTTPException(status_code=404, detail="That saved run was not found.")
    await replay_run.Syncer(folder).once(force=True)
    return {"ok": True, "tickets": len(replay_run.Run(folder).saved_tickets())}


@router.get("/demo")
async def get_demo():
    """The Demo replay switch and the demos made so far (each belongs to a video file, by name)."""
    from engine import demo_replay
    return {"on": demo_replay.is_on(), "demos": demo_replay.list_demos()}


@router.post("/demo")
async def set_demo(body: dict):
    """Turn the Demo replay on or off: {"on": bool}. On: a video file that has a demo plays the recorded run in the Live Monitor."""
    from engine import demo_replay
    return {"on": demo_replay.set_on(bool(body.get("on"))), "demos": demo_replay.list_demos()}


@router.post("/demo/create")
async def create_demo(body: dict):
    """Make a demo from a saved live run and the live tickets as they are now (after the review): {"title", "video" (file name; default: the
    run's own video), "run_dir" (default: the newest saved run)}."""
    import asyncio
    from engine import demo_replay, live_run
    from routers import forensic

    title = str(body.get("title") or "").strip() or "Demo"
    run_dir = Path(str(body["run_dir"])) if body.get("run_dir") else None
    if run_dir is None:
        saved = live_run.read_settings().get("dir") or str(Path(__file__).resolve().parent.parent / "snapshots" / "live_runs_saved")
        run_dir = demo_replay.last_saved_run(Path(saved))
    if run_dir is None or not (run_dir / "index.jsonl").exists():
        raise HTTPException(status_code=400, detail="There is no saved run. Run the Live Monitor once with 'Save this run' on.")
    video = str(body.get("video") or "").strip()
    if not video:
        try:
            video = str(json.loads((run_dir / "run.json").read_text(encoding="utf-8")).get("source") or "")
        except (OSError, ValueError):
            video = ""
    if not video:
        raise HTTPException(status_code=400, detail="Tell me the name of the video file this run belongs to.")
    out = forensic.live_output_dir()
    async with forensic._report_lock:
        tickets = await asyncio.to_thread(forensic._load_tickets, out / "report.json")
    try:
        config = json.loads((out / "forensic_config.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        config = {}
    try:
        return await asyncio.to_thread(demo_replay.create, run_dir, [video], title, tickets, config, lambda t: forensic._live_photo_files([t]))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.delete("/demo/{demo_id}")
async def delete_demo(demo_id: str):
    from engine import demo_replay
    return {"deleted": demo_replay.delete_demo(demo_id)}


def _demo_folder(demo_id: str) -> Path:
    from engine import demo_replay
    folder = demo_replay.DEMO_ROOT / Path(demo_id).name
    if not (folder / "demo.json").exists():
        raise HTTPException(status_code=404, detail="That demo does not exist.")
    return folder


@router.get("/demo/{demo_id}/tracks")
async def get_demo_tracks(demo_id: str):
    """The vehicles of a demo, for the demo editor: [{track_id, kind, plate, violation, frames, first_s, last_s, tickets}], with the choices."""
    from engine import demo_replay
    folder = _demo_folder(demo_id)
    return {"tracks": await asyncio.to_thread(demo_replay.tracks, folder), "kinds": list(demo_replay.VEHICLE_KINDS),
            "violations": demo_replay.violation_keys()}


@router.get("/demo/{demo_id}/track-picture/{track_id}")
async def get_demo_track_picture(demo_id: str, track_id: int):
    """One vehicle of a demo, cut out of its biggest picture (to see which one is being edited)."""
    from engine import demo_replay
    folder = _demo_folder(demo_id)
    jpeg = await asyncio.to_thread(demo_replay.track_crop_jpeg, folder, track_id)
    if jpeg is None:
        raise HTTPException(status_code=404, detail="No picture of that vehicle.")
    return Response(content=jpeg, media_type="image/jpeg")


@router.post("/demo/{demo_id}/edit")
async def edit_demo_track(demo_id: str, body: dict):
    """Correct one vehicle of a demo in every picture and ticket: {"track_id", "kind"?, "plate"?, "violation"? ("" = none), "delete"?}."""
    from engine import demo_replay
    folder = _demo_folder(demo_id)
    if not isinstance(body.get("track_id"), int):
        raise HTTPException(status_code=400, detail="track_id is needed.")
    try:
        return await asyncio.to_thread(
            demo_replay.edit_track, folder, int(body["track_id"]), body.get("kind"), body.get("plate"), body.get("violation"), bool(body.get("delete")))
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
    stream.reset_rules()                         # a new setup starts with all its rules on
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
