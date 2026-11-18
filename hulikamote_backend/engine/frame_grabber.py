"""
frame_grabber.py - a few pictures of the Live Monitor's source, for the setup's "pick a frame" step.

  a video file    pictures spread over the whole video (the first one is the first frame of the video), ready in a second or two
  a live camera   the camera is opened for a few seconds and a picture is kept every `spacing` seconds, so the operator can pick a
                  moment when the road is clear and the paint is easy to see (rtsp / http / webcam)

The pictures appear one by one while the grab runs, so the operator can pick the first and start at once. It never opens a camera the
live feed is already reading (a webcam cannot be opened twice): then the live feed's own newest picture is the only choice.
"""
import threading
import time

import cv2
import numpy as np

from engine.camera_source import CameraSource, parse_source

MAX_WIDTH = 1920            # the setup draws in a 1920x1080 space; a wider picture only costs time
JPEG_QUALITY = 88
CAMERA_OPEN_WAIT_S = 12.0   # a camera can take this long to show its first picture

_job_counter = 0
_job_lock = threading.Lock()


def _next_job() -> int:
    global _job_counter
    with _job_lock:
        _job_counter += 1
        return _job_counter


def _clock(seconds: float) -> str:
    """83.4 -> '1:23'."""
    seconds = max(0, int(round(seconds)))
    return f"{seconds // 60}:{seconds % 60:02d}"


class FrameGrabber:
    """One grab: start() it, poll status(), read a picture with jpeg(id). A new grab is a new object (new `job` number)."""

    def __init__(self, source, count: int = 8, spacing: float = 1.0, running_picture=None, camera_factory=CameraSource):
        self.source = source
        self.count = max(2, int(count))
        self.spacing = spacing
        self._running_picture = running_picture        # a function returning the live feed's newest picture (a numpy array) or None
        self._camera_factory = camera_factory
        self.job = _next_job()
        self.state = "idle"                            # idle | grabbing | done | failed
        self.kind = ""                                 # file | camera, known once the source is understood
        self.error = ""
        self.fps = 25.0
        self._frames: list[dict] = []                  # {"jpeg", "label", "width", "height"}
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    # ── use ──────────────────────────────────────────────────────────────────
    def start(self) -> None:
        self.state = "grabbing"
        self._thread = threading.Thread(target=self._run, name="frame-grabber", daemon=True)
        self._thread.start()

    def cancel(self) -> None:
        self._stop.set()

    def status(self) -> dict:
        with self._lock:
            frames = [{"id": i, "label": f["label"], "width": f["width"], "height": f["height"]} for i, f in enumerate(self._frames)]
        return {"job": self.job, "state": self.state, "kind": self.kind, "error": self.error, "expected": self.count,
                "fps": self.fps, "frames": frames}

    def jpeg(self, frame_id: int) -> bytes | None:
        with self._lock:
            if 0 <= frame_id < len(self._frames):
                return self._frames[frame_id]["jpeg"]
        return None

    def frame_at(self, frame_id: int) -> float | None:
        """The time (seconds) of a picture of a video file; None for a camera."""
        with self._lock:
            if 0 <= frame_id < len(self._frames):
                return self._frames[frame_id].get("at")
        return None

    def frame_size(self, frame_id: int) -> tuple[int, int] | None:
        with self._lock:
            if 0 <= frame_id < len(self._frames):
                f = self._frames[frame_id]
                return f["width"], f["height"]
        return None

    # ── the work ─────────────────────────────────────────────────────────────
    def _add(self, image: np.ndarray, label: str, at: float | None = None) -> None:
        h, w = image.shape[:2]
        if w > MAX_WIDTH:
            image = cv2.resize(image, (MAX_WIDTH, max(1, round(h * MAX_WIDTH / w))), interpolation=cv2.INTER_AREA)
            h, w = image.shape[:2]
        ok, buf = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        if not ok:
            return
        with self._lock:
            self._frames.append({"jpeg": buf.tobytes(), "label": label, "width": w, "height": h, "at": at})

    def _run(self) -> None:
        try:
            if self._running_picture is not None:
                self._from_running_feed()
            else:
                spec = parse_source(self.source)
                if spec.kind == "file":
                    self._from_file(spec.target)
                else:
                    self._from_camera()
            if not self._frames and not self._stop.is_set():
                raise ValueError("No picture could be read from the source.")
            self.state = "done"
        except Exception as exc:                     # the operator gets the reason, in words
            self.error = str(exc) or exc.__class__.__name__
            self.state = "failed"

    def _from_running_feed(self) -> None:
        self.kind = "camera"
        picture = self._running_picture()
        if picture is None:
            raise ValueError("The live feed has no picture yet. Wait a moment and try again.")
        self._add(picture.copy(), "now")

    def _from_file(self, path: str) -> None:
        self.kind = "file"
        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            cap.release()
            raise ValueError("The video file could not be opened.")
        try:
            fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
            self.fps = fps if 1.0 < fps <= 120.0 else 25.0
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            if total > self.count:
                # the first picture is the first frame; the last is a moment before the end (the very last frame can be empty)
                indexes = sorted({int(i) for i in np.linspace(0, max(0, total - 2), self.count)})
                for index in indexes:
                    if self._stop.is_set():
                        return
                    cap.set(cv2.CAP_PROP_POS_FRAMES, index)
                    ok, image = cap.read()
                    if ok and image is not None:
                        self._add(image, _clock(index / self.fps), index / self.fps)
            else:                                   # a very short clip, or a length the file does not tell: its first frames in order
                index = 0
                while len(self._frames) < self.count and not self._stop.is_set():
                    ok, image = cap.read()
                    if not ok or image is None:
                        break
                    self._add(image, _clock(index / self.fps))
                    index += max(1, int(self.fps))   # about one picture a second
                    cap.set(cv2.CAP_PROP_POS_FRAMES, index)
        finally:
            cap.release()

    def _from_camera(self) -> None:
        self.kind = "camera"
        camera = self._camera_factory(self.source)
        if not camera.start():
            raise ValueError("The camera could not be opened. Check the address and that the camera is on.")
        try:
            deadline = time.monotonic() + CAMERA_OPEN_WAIT_S + self.count * self.spacing + 5.0
            first_at = last_at = None
            while not self._stop.is_set() and len(self._frames) < self.count and time.monotonic() < deadline:
                item = camera.read(timeout=0.5)
                if item is None:
                    continue
                now = time.monotonic()
                if last_at is not None and now - last_at < self.spacing:
                    continue
                first_at = first_at or now
                last_at = now
                self.fps = float(getattr(camera, "source_fps", 25.0) or 25.0)
                self._add(item.image, f"{int(round(now - first_at))} s")
            if not self._frames and not self._stop.is_set():
                raise ValueError("No picture came from the camera. Check the address and that the camera is on.")
        finally:
            camera.stop()
