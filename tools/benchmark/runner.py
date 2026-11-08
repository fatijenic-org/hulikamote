"""
runner.py - Run one clip through the backend's forensic analysis (the same code the dashboard wizard uses) and
return its tickets. Talks to a RUNNING backend over HTTP, so the models and settings are exactly the live ones.
"benchmark": true makes the backend skip the Inbox database: scoring runs leave no tickets to review.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

from .registry import Clip

DEFAULT_URL = "http://127.0.0.1:8000"


class RunError(RuntimeError):
    pass


def probe(video: Path) -> dict:
    """Length, size and fps of a clip (None when OpenCV is not available)."""
    try:
        import cv2
        cap = cv2.VideoCapture(str(video))
        fps = cap.get(cv2.CAP_PROP_FPS) or 0
        frames = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
        out = {"seconds": (frames / fps) if fps and frames else None, "fps": fps or None,
               "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or None, "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or None}
        cap.release()
        return out
    except Exception:
        return {"seconds": None, "fps": None, "width": None, "height": None}


def check_backend(base_url: str, client) -> None:
    try:
        r = client.get(f"{base_url}/status", timeout=10)
        r.raise_for_status()
    except Exception as e:
        raise RunError(f"The backend is not answering at {base_url} ({e}). Start it first "
                       f"(hulikamote_backend: uvicorn main:app --port 8000).") from None


def run_clip(clip: Clip, base_url: str = DEFAULT_URL, overrides: dict | None = None, client=None,
             poll_s: float = 2.0, timeout_s: float = 7200.0, log=print) -> dict:
    """Upload the clip with its saved wizard settings, wait for the analysis, return {task_id, tickets, wall_s}."""
    if client is None:
        import requests as client
    if not clip.file.exists():
        raise RunError(f"{clip.id}: video not found: {clip.file}")
    if not clip.settings:
        raise RunError(f"{clip.id}: no settings (save the wizard's forensic_config.json at {clip.settings_file})")
    config = {**clip.settings, **(overrides or {}), "benchmark": True, "keep_input_video": False}
    t0 = time.time()
    with open(clip.file, "rb") as f:
        r = client.post(f"{base_url}/api/forensic/upload", files={"file": (clip.file.name, f, "video/mp4")},
                        data={"config_json": json.dumps(config)}, timeout=600)
    r.raise_for_status()
    task_id = r.json()["task_id"]
    last = -1
    while True:
        s = client.get(f"{base_url}/api/forensic/status/{task_id}", timeout=30).json()
        if s.get("status") == "completed":
            return {"task_id": task_id, "tickets": s.get("tickets", []), "wall_s": round(time.time() - t0, 1)}
        if s.get("status") == "failed":
            raise RunError(f"{clip.id}: the analysis failed: {s.get('error')}")
        if int(s.get("progress", 0)) // 10 != last:
            last = int(s.get("progress", 0)) // 10
            log(f"    {clip.id}: {s.get('progress', 0):.0f}% {s.get('message', '')}")
        if time.time() - t0 > timeout_s:
            raise RunError(f"{clip.id}: still running after {timeout_s:.0f} s (task {task_id})")
        time.sleep(poll_s)
