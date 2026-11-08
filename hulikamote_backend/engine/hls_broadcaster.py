"""
engine/hls_broadcaster.py
─────────────────────────
HLS Video Transport Layer (Phase B Architecture Upgrade).

Routes raw BGR frames from the AI pipeline → ffmpeg subprocess → MediaMTX RTSP ingest.
MediaMTX re-muxes the RTSP stream as HLS (.m3u8) which Flutter's video_player consumes
natively, eliminating the base64 JPEG WebSocket bottleneck entirely.

PREREQUISITES (one-time setup):
  1. Install ffmpeg:
     winget install ffmpeg
     OR download from https://ffmpeg.org/download.html and add to PATH.

  2. Download MediaMTX binary (no install needed):
     https://github.com/bluenviron/mediamtx/releases/latest
     → mediamtx_vX.X.X_windows_amd64.zip
     Extract to: hulikamote_backend/tools/mediamtx/mediamtx.exe

  3. Start MediaMTX before the backend:
     cd hulikamote_backend/tools/mediamtx
     ./mediamtx.exe mediamtx.yml

  4. Flutter: add to pubspec.yaml:
     dependencies:
       video_player: ^2.9.2

  5. Flutter: update video_feed_widget.dart to use VideoPlayer
     with URL: http://localhost:8888/live/index.m3u8

HLS stream URL:  http://localhost:8888/live/index.m3u8
RTSP ingest URL: rtsp://localhost:8554/live
"""

import logging
import queue
import shutil
import socket
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

log = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
MEDIAMTX_RTSP_URL = "rtsp://localhost:8554/live"
HLS_URL           = "http://localhost:8888/live/index.m3u8"
STREAM_WIDTH      = 1280
STREAM_HEIGHT     = 720
STREAM_FPS        = 25


MEDIAMTX_DIR = Path(__file__).resolve().parent.parent / "tools" / "mediamtx"
RTSP_PORT = 8554


def _port_open(port: int = RTSP_PORT, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except OSError:
        return False


def server_status(wait_s: float = 6.0) -> tuple[bool, str]:
    """Is the video relay (MediaMTX) up? Starts it from tools/mediamtx when it is installed but not running.
    Returns (ready, what to tell the user). Without the relay ffmpeg cannot send frames anywhere, and a backend that
    keeps writing into it used to freeze completely."""
    if _port_open():
        return True, ""
    exe = MEDIAMTX_DIR / "mediamtx.exe"
    if not exe.exists():
        return False, "The video relay (MediaMTX) is not running and is not installed in hulikamote_backend/tools/mediamtx."
    try:
        subprocess.Popen(
            [str(exe), "mediamtx.yml"], cwd=str(MEDIAMTX_DIR), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except OSError as exc:
        return False, f"The video relay (MediaMTX) could not be started: {exc}"
    deadline = time.time() + wait_s
    while time.time() < deadline:
        if _port_open():
            return True, ""
        time.sleep(0.25)
    return False, "The video relay (MediaMTX) was started but is not answering. Check tools/mediamtx/mediamtx.yml."


class HLSBroadcaster:
    """
    Pipes raw BGR frames into an ffmpeg process that pushes an RTSP stream
    to MediaMTX, which re-muxes it as HLS for Flutter to consume natively.

    Usage:
        broadcaster = HLSBroadcaster()
        broadcaster.start(width=1280, height=720, fps=25)
        while True:
            frame = pipeline.get_frame()
            broadcaster.push(frame)
        broadcaster.stop()
    """

    def __init__(self):
        self._proc: Optional[subprocess.Popen] = None
        self._frames: Optional[queue.Queue] = None   # frames waiting for the writer thread
        self._writer: Optional[threading.Thread] = None
        self._started = False
        self._ffmpeg_available = shutil.which("ffmpeg") is not None

        if not self._ffmpeg_available:
            log.warning(
                "[HLS] ffmpeg not found on PATH. HLS transport disabled. "
                "The system will fall back to base64 JPEG WebSocket. "
                "Install ffmpeg: winget install ffmpeg"
            )

    @property
    def is_available(self) -> bool:
        # Forced HLS Transport! Base64 is dead.
        return True

    @property
    def hls_url(self) -> str:
        # Use RTSP instead of HLS. RTSP has zero buffer latency, ensuring 
        # the video stays perfectly synced with the WebSocket bounding boxes.
        return MEDIAMTX_RTSP_URL

    def start(self, width: int = STREAM_WIDTH, height: int = STREAM_HEIGHT, fps: int = STREAM_FPS):
        if self._started:
            return

        ready, why = server_status()
        if not ready:
            log.error("[HLS] %s Live video cannot be shown until it is.", why)
            return

        self._width = width
        self._height = height

        cmd = [
            "ffmpeg",
            "-y",
            "-f", "rawvideo",
            "-vcodec", "rawvideo",
            "-pix_fmt", "bgr24",
            "-s", f"{width}x{height}",
            "-use_wallclock_as_timestamps", "1", # Stamp frames with real time!
            "-thread_queue_size", "512",
            "-i", "pipe:0",                 # Read raw frames from stdin
            "-c:v", "h264_mf",              # Windows MediaFoundation Hardware Encoder
            "-b:v", "4M",                   # High bitrate to fix pixelation!
            "-g", "15",                     # Force keyframe every 15 frames (~1 second)
            "-bf", "0",                     # Disable B-frames for zero latency
            "-r", str(fps),                 # Force output stream to exactly 25 FPS
            "-pix_fmt", "yuv420p",
            "-rtsp_transport", "tcp",       # Force TCP to prevent UDP packet drops (blue smears)
            "-f", "rtsp",
            MEDIAMTX_RTSP_URL,
        ]

        try:
            self._ffmpeg_log = open("ffmpeg_debug.log", "w")
            self._proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=self._ffmpeg_log,
            )
            self._frames = queue.Queue(maxsize=3)
            self._writer = threading.Thread(target=self._write_loop, args=(self._proc, self._frames), daemon=True, name="hls-writer")
            self._writer.start()
            self._started = True
            log.info("[HLS] ffmpeg RTSP ingest started → %s", MEDIAMTX_RTSP_URL)
            log.info("[HLS] HLS playback URL: %s", HLS_URL)
        except FileNotFoundError:
            print("\n" + "="*80)
            print("CRITICAL ERROR: FFMPEG NOT FOUND!")
            print("You installed ffmpeg, but your VS Code / Terminal hasn't registered the system PATH update yet.")
            print("PLEASE RESTART VS CODE ENTIRELY, THEN START THE BACKEND AGAIN.")
            print("="*80 + "\n")
            self._started = False
        except Exception as e:
            log.error("[HLS] Failed to start ffmpeg: %s", e)
            self._started = False

    def push(self, frame: np.ndarray):
        """Push a single BGR frame into the ffmpeg pipe."""
        if not self._started or self._proc is None:
            return
        if self._proc.poll() is not None:
            log.warning("[HLS] ffmpeg process died. Restarting...")
            self._started = False
            h, w = frame.shape[:2]
            self.start(width=w, height=h)
            return

        # Resize frame to target resolution if needed
        h, w = frame.shape[:2]
        if w != self._width or h != self._height:
            frame = cv2.resize(frame, (self._width, self._height))

        try:
            self._frames.put_nowait(frame.tobytes())
        except queue.Full:
            pass                      # the encoder is behind: drop this frame, live video never waits for it

    def _write_loop(self, proc: subprocess.Popen, frames: queue.Queue):
        """Feeds frames to ffmpeg. Only this thread can ever block on the pipe, so a stuck encoder cannot freeze the rest."""
        while True:
            data = frames.get()
            if data is None:
                return
            try:
                proc.stdin.write(data)
            except (OSError, ValueError):
                self._started = False
                return

    def stop(self):
        """Stop ffmpeg. Never waits on a stuck encoder: it is killed first, because closing a pipe that nobody reads
        from would wait for ever (that froze the whole backend)."""
        proc, writer, frames = self._proc, self._writer, self._frames
        self._proc = self._writer = self._frames = None
        self._started = False
        if frames is not None:
            try:
                frames.put_nowait(None)              # wakes the writer if it is idle
            except queue.Full:
                pass
        if proc is not None:
            try:
                proc.kill()
            except OSError:
                pass
            try:
                proc.wait(timeout=2)
            except Exception:
                pass
            try:
                proc.stdin.close()
            except Exception:
                pass
        if writer is not None:
            writer.join(timeout=1)

        if hasattr(self, '_ffmpeg_log') and self._ffmpeg_log:
            try:
                self._ffmpeg_log.close()
            except Exception:
                pass

        log.info("[HLS] ffmpeg RTSP ingest stopped.")


# ── Module-level singleton ────────────────────────────────────────────────────
_broadcaster: Optional[HLSBroadcaster] = None


def get_broadcaster() -> HLSBroadcaster:
    global _broadcaster
    if _broadcaster is None:
        _broadcaster = HLSBroadcaster()
    return _broadcaster
