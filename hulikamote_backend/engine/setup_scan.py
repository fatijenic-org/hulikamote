"""
setup_scan.py - the setup's "Find the road automatically": the walkthrough of "Detect road" (engine/live_calibrator.py, engine/road_lines.py)
on a few seconds collected from the setup's source, so the finder sees how traffic moves and not only one picture.

  a video file   SCAN_SECONDS of the video, from the picked picture on
  a live camera  the camera is opened for SCAN_SECONDS (the setup runs before the feed starts)
  the feed runs  a camera cannot be opened twice: the picture alone is read (the paint, no traffic)

It uses a private LiveCalibrator that is never attached to a camera and never saved: nothing of a scan reaches camera_config.json. The steps
and their pictures are read through the same status as Detect road, so the dashboard draws them the same way.
"""
import threading
import time

import cv2
import numpy as np

from engine import road_lines
from engine.camera_source import CameraSource, parse_source
from engine.frame_grabber import CAMERA_OPEN_WAIT_S
from engine.live_calibrator import LiveCalibrator

SCAN_SECONDS = 8.0           # how much footage the road is read from: enough to see traffic move, short enough to wait for
BACKGROUND_PICTURES = 20     # colour pictures the empty road is built from
STILL_PICTURES = 24          # a single picture is repeated this often (the finder wants a clip)


class ClipBuilder:
    """Collects the clip dict road_lines.analyse_clip reads: SAMPLE_FPS small grey pictures a second, and a few colour pictures spread over
    the time. `wants(t)` says whether the picture at time t (seconds) will be used, so a picture that is not needed is never converted."""

    def __init__(self, video_size: tuple[int, int]):
        self.video = video_size
        w, h = video_size
        self.colour_size = (road_lines.WORK_W, road_lines._even(h * road_lines.WORK_W / w))
        self.grey_size = (road_lines.FLOW_W, road_lines._even(h * road_lines.FLOW_W / w))
        self.greys: list[np.ndarray] = []
        self.colours: list[np.ndarray] = []
        self.colour_at: list[int] = []
        self._next: float | None = None
        self._next_colour = 0.0

    def wants(self, t: float) -> bool:
        return self._next is None or t >= self._next

    def add(self, t: float, bgr: np.ndarray) -> None:
        if not self.wants(t):
            return
        step = 1.0 / road_lines.SAMPLE_FPS
        self._next = t + step if self._next is None else max(self._next + step, t)    # catches up when pictures came late
        colour = cv2.resize(bgr, self.colour_size, interpolation=cv2.INTER_AREA)
        self.greys.append(cv2.cvtColor(cv2.resize(colour, self.grey_size, interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY))
        if len(self.colours) < BACKGROUND_PICTURES and t >= self._next_colour:
            self.colours.append(colour)
            self.colour_at.append(len(self.greys) - 1)
            self._next_colour = t + SCAN_SECONDS / BACKGROUND_PICTURES

    def clip(self) -> dict:
        if len(self.greys) < 16:
            raise ValueError("Too few pictures could be read to find the road.")
        return {"video": self.video, "fps": float(road_lines.SAMPLE_FPS), "seconds": len(self.greys) / road_lines.SAMPLE_FPS,
                "colours": self.colours, "colour_at": self.colour_at, "greys": self.greys,
                "grey_size": self.grey_size, "colour_size": self.colour_size}


class SetupScan:
    """One scan at a time: start() it, poll `road.detect_status()` (the same status as Detect road), cancel() it."""

    def __init__(self):
        self.road = LiveCalibrator(background=False)       # analyses in the scan's own thread
        self._token = 0
        self._lock = threading.Lock()

    def start(self, source, frame_jpeg: bytes, at_s: float | None, running_picture=None) -> dict:
        """`frame_jpeg`: the setup picture. `at_s`: its time in a video file (the footage is taken from there on), or None."""
        frame = cv2.imdecode(np.frombuffer(frame_jpeg, np.uint8), cv2.IMREAD_COLOR)
        if frame is None:
            return {"ok": False, "reason": "The setup picture could not be read."}
        with self._lock:
            self._token += 1
            token = self._token
        self.road.scan_begin(frame, SCAN_SECONDS)
        threading.Thread(target=self._run, args=(token, source, frame, at_s, running_picture), daemon=True, name="setup-scan").start()
        return {"ok": True, "detect": self.road.detect_status()}

    def cancel(self) -> None:
        with self._lock:
            self._token += 1                                # whatever runs notices and stops
        self.road.discard_detect()

    def _run(self, token: int, source, frame: np.ndarray, at_s: float | None, running_picture) -> None:
        def stopped() -> bool:
            return token != self._token
        h, w = frame.shape[:2]
        builder = ClipBuilder((w, h))
        try:
            if running_picture is not None:
                picture = running_picture()
                if picture is None:
                    raise ValueError("The live feed has no picture yet.")
                for i in range(STILL_PICTURES):
                    builder.add(i / road_lines.SAMPLE_FPS, picture)
            else:
                spec = parse_source(source)
                if spec.kind == "file":
                    self._from_file(spec.target, at_s or 0.0, builder, stopped)
                else:
                    self._from_camera(source, builder, stopped)
            if stopped():
                return
            self.road.scan_analyse(builder.clip())
        except Exception as exc:                             # the operator gets the reason, in words
            if not stopped():
                self.road.scan_fail(str(exc) or exc.__class__.__name__)

    def _from_file(self, path: str, start_s: float, builder: ClipBuilder, stopped) -> None:
        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            cap.release()
            raise ValueError("The video file could not be opened.")
        try:
            fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
            fps = fps if 1.0 < fps <= 120.0 else 25.0
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            if total > 0 and total / fps > SCAN_SECONDS:
                start_s = max(0.0, min(start_s, total / fps - SCAN_SECONDS))      # the footage must fit between the picture and the end
            else:
                start_s = 0.0
            cap.set(cv2.CAP_PROP_POS_MSEC, start_s * 1000.0)
            n = 0
            while not stopped():
                t = n / fps
                if t >= SCAN_SECONDS:
                    break
                if builder.wants(t):
                    ok, image = cap.read()
                    if ok and image is not None:
                        builder.add(t, image)
                else:
                    ok = cap.grab()                           # decoded but not converted: a picture that is not used is cheap
                if not ok:
                    break
                n += 1
                if n % 8 == 0:
                    self.road.scan_progress(t)
        finally:
            cap.release()

    def _from_camera(self, source, builder: ClipBuilder, stopped) -> None:
        camera = CameraSource(source)
        if not camera.start():
            raise ValueError("The camera could not be opened. Check the address and that the camera is on.")
        try:
            deadline = time.monotonic() + CAMERA_OPEN_WAIT_S + SCAN_SECONDS + 5.0
            first = None
            while not stopped() and time.monotonic() < deadline:
                item = camera.read(timeout=0.5)
                if item is None:
                    continue
                now = time.monotonic()
                first = now if first is None else first
                elapsed = now - first
                builder.add(elapsed, item.image)
                self.road.scan_progress(min(elapsed, SCAN_SECONDS))
                if elapsed >= SCAN_SECONDS:
                    break
            if first is None and not stopped():
                raise ValueError("No picture came from the camera. Check the address and that the camera is on.")
        finally:
            camera.stop()
