"""
camera_source.py - one video input for the live monitor: a file, an RTSP / HTTP stream, or a webcam.

The rest of the system only sees a CameraSource, so a real CCTV / DVR channel, a phone camera app and
a second laptop playing a clip are all the same thing: an address. Only the address changes.

  - file     read in order, rewinds at the end (as before)
  - live     (rtsp / http / rtmp / udp / webcam) a reader thread always keeps the NEWEST frame and
             drops older ones, so lag cannot build up when the AI is slower than the camera.
             If the stream drops it reconnects by itself (1, 2, 4, 8 s, then every 8 s) and reports "offline".
"""
import os
import re
import threading
import time
from collections import namedtuple
from pathlib import Path

import cv2

OPEN_TIMEOUT_MS = 5000
READ_TIMEOUT_MS = 5000
RETRY_DELAYS_S = (1.0, 2.0, 4.0, 8.0)       # the last one repeats
# TCP: UDP drops packets on Wi-Fi (smeared frames). No-buffer / low-delay: show frames as they arrive.
FFMPEG_OPTIONS = "rtsp_transport;tcp|fflags;nobuffer|flags;low_delay"
STREAM_SCHEMES = ("rtsp", "rtsps", "http", "https", "rtmp", "udp")     # nothing else is handed to ffmpeg

Frame = namedtuple("Frame", "image captured_at")
SourceSpec = namedtuple("SourceSpec", "kind target label")

_ENV_LOCK = threading.Lock()


def mask_url(url: str) -> str:
    """rtsp://user:secret@host/x -> rtsp://user:***@host/x (never log or show a password)."""
    return re.sub(r"(://[^:/@\s]+):[^@/\s]+@", r"\1:***@", str(url))


def restore_password(masked_url: str, original_url: str) -> str:
    """The dashboard only ever sees masked addresses. When it sends one back ("user:***@host"), put the real
    password from the stored address back in. Anything else is returned unchanged."""
    if ":***@" not in masked_url:
        return masked_url
    found = re.search(r"://[^:/@\s]+:([^@/\s]+)@", original_url or "")
    return masked_url.replace(":***@", f":{found.group(1)}@", 1) if found else masked_url


def parse_source(source) -> SourceSpec:
    """Work out what an address is. Raises ValueError for anything that is not a file, webcam or allowed stream."""
    if isinstance(source, int) or (isinstance(source, str) and source.strip().isdigit()):
        return SourceSpec("webcam", int(source), f"webcam {int(source)}")
    text = str(source).strip()
    if not text:
        raise ValueError("Empty video source")
    match = re.match(r"^([a-zA-Z][a-zA-Z0-9+.-]*)://", text)
    if match:
        scheme = match.group(1).lower()
        if scheme not in STREAM_SCHEMES:
            raise ValueError(f"Unsupported source type '{scheme}://' (use rtsp, http, rtmp or udp)")
        kind = "rtsp" if scheme.startswith("rtsp") else "http" if scheme.startswith("http") else "stream"
        return SourceSpec(kind, text, mask_url(text))
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:(?![\\/])", text):      # concat:, pipe:, subfile: ... ffmpeg tricks
        raise ValueError("Unsupported video source")
    return SourceSpec("file", text, Path(text).name or text)


def _sane_fps(value, default: float) -> float:
    # RTSP often reports 0 or a 90000 time base
    return float(value) if value and 1.0 < float(value) <= 120.0 else default


class CameraSource:
    def __init__(self, source, capture_factory=None, now=time.time, retry_delays=RETRY_DELAYS_S):
        self.spec = parse_source(source)
        self._factory = capture_factory or cv2.VideoCapture
        self._now = now
        self._retry_delays = retry_delays
        self._cap = None                       # file sources
        self._file_lock = threading.Lock()     # a cv2 capture must not be read and released at the same moment
        self._cond = threading.Condition()
        self._stop = threading.Event()
        self._thread = None
        self._latest: Frame | None = None
        self._seq = self._delivered = 0
        self.state = "idle"
        self.width = self.height = 0
        self.source_fps = 30.0 if self.spec.kind == "file" else 25.0
        self.reconnects = self.dropped = 0
        self.input_fps = 0.0
        self.lag_ms = 0.0
        self._last_arrival = None
        # Live sources only: called as tap(image, arrived) from the reader thread for EVERY picture the camera delivers, not
        # only the ones the processing loop gets round to reading. Must be quick. An error in it never stops the camera.
        self.tap = None

    @property
    def live(self) -> bool:
        return self.spec.kind != "file"

    # ── opening ──────────────────────────────────────────────────────────────
    def _open(self):
        kind, target = self.spec.kind, self.spec.target
        if kind in ("rtsp", "http", "stream"):
            params = [cv2.CAP_PROP_OPEN_TIMEOUT_MSEC, OPEN_TIMEOUT_MS, cv2.CAP_PROP_READ_TIMEOUT_MSEC, READ_TIMEOUT_MS]
            with _ENV_LOCK:                    # ffmpeg reads this variable while opening
                previous = os.environ.get("OPENCV_FFMPEG_CAPTURE_OPTIONS")
                os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = FFMPEG_OPTIONS
                try:
                    cap = self._factory(target, cv2.CAP_FFMPEG, params)
                finally:
                    if previous is None:
                        os.environ.pop("OPENCV_FFMPEG_CAPTURE_OPTIONS", None)
                    else:
                        os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = previous
        else:
            cap = self._factory(target)
        if not cap.isOpened():
            cap.release()
            return None
        self.width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or self.width)
        self.height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or self.height)
        self.source_fps = _sane_fps(cap.get(cv2.CAP_PROP_FPS), self.source_fps)
        return cap

    def start(self) -> bool:
        """Files open now (False if they cannot be read). Live sources connect in the background (always True)."""
        if not self.live:
            self._cap = self._open()
            self.state = "file" if self._cap else "offline"
            return self._cap is not None
        self.state = "connecting"
        self._thread = threading.Thread(target=self._run, name="camera-reader", daemon=True)
        self._thread.start()
        return True

    # ── live reader thread ───────────────────────────────────────────────────
    def _run(self) -> None:
        attempt = 0
        while not self._stop.is_set():
            cap = self._open()
            if cap is None:
                self.state = "offline"
                self._stop.wait(self._retry_delays[min(attempt, len(self._retry_delays) - 1)])
                attempt += 1
                continue
            attempt = 0
            self.state = "live"
            self._last_arrival = None
            while not self._stop.is_set():
                ok, image = cap.read()
                if not ok or image is None:
                    break
                self._publish(image)
            cap.release()
            if not self._stop.is_set():
                self.state = "offline"
                self.reconnects += 1
                self._stop.wait(self._retry_delays[0])

    def _publish(self, image) -> None:
        arrived = self._now()
        with self._cond:
            if self._latest is not None and self._seq != self._delivered:
                self.dropped += 1              # nobody took the previous frame: it is stale now
            self._latest = Frame(image, arrived)
            self._seq += 1
            if self._last_arrival is not None and arrived > self._last_arrival:
                instant = 1.0 / (arrived - self._last_arrival)
                self.input_fps = instant if self.input_fps == 0 else 0.9 * self.input_fps + 0.1 * instant
            self._last_arrival = arrived
            if not self.width:
                self.height, self.width = image.shape[:2]
            self._cond.notify_all()
        tap = self.tap
        if tap is not None:
            try:
                tap(image, arrived)
            except Exception:
                pass

    # ── reading ──────────────────────────────────────────────────────────────
    def read(self, timeout: float = 1.0) -> Frame | None:
        """The next frame. Files: the next one in order (rewinds at the end). Live: the newest frame not yet
        delivered, or None if none arrived within `timeout` seconds (camera slow or offline)."""
        if not self.live:
            return self._read_file()
        with self._cond:
            self._cond.wait_for(lambda: self._seq != self._delivered or self._stop.is_set(), timeout)
            if self._seq == self._delivered:
                return None
            self._delivered = self._seq
            frame = self._latest
        self.lag_ms = max(0.0, (self._now() - frame.captured_at) * 1000.0)
        return frame

    def _read_file(self) -> Frame | None:
        with self._file_lock:                  # stop() waits here, so it never frees the capture mid-read
            if self._cap is None:
                return None
            ok, image = self._cap.read()
            if not ok:
                self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ok, image = self._cap.read()
                if not ok:
                    return None
            return Frame(image, self._now())

    # ── status / stop ────────────────────────────────────────────────────────
    def status(self) -> dict:
        return {
            "kind": self.spec.kind, "label": self.spec.label, "state": self.state,
            "width": self.width, "height": self.height, "source_fps": round(self.source_fps, 1),
            "input_fps": round(self.input_fps, 1), "lag_ms": round(self.lag_ms),
            "reconnects": self.reconnects, "dropped": self.dropped,
        }

    def stop(self) -> None:
        self._stop.set()
        with self._cond:
            self._cond.notify_all()
        if self._thread is not None:
            self._thread.join(timeout=3)
        with self._file_lock:
            if self._cap is not None:
                self._cap.release()
                self._cap = None
        self.state = "idle"


def test_connection(source, capture_factory=None, wait_s: float = 8.0) -> dict:
    """Try a source once (for the dashboard's Test button): opens it, reads one frame, reports what it found."""
    try:
        spec = parse_source(source)
    except ValueError as exc:
        return {"ok": False, "error": str(exc)}
    cam = CameraSource(source, capture_factory=capture_factory, retry_delays=(0.2,))
    started = time.time()
    try:
        cam.start()
        frame = cam.read(timeout=wait_s)
        if frame is None:
            return {"ok": False, "kind": spec.kind, "label": spec.label,
                    "error": "No picture received (wrong address, camera off, or blocked by a firewall)"}
        h, w = frame.image.shape[:2]
        return {"ok": True, "kind": spec.kind, "label": spec.label, "width": w, "height": h,
                "fps": round(cam.source_fps, 1), "first_frame_ms": round((time.time() - started) * 1000)}
    finally:
        cam.stop()


test_connection.__test__ = False       # not a pytest test
