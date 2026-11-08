"""
engine/camera_source.py - what an address means, newest-frame reading, reconnecting, and the connection test,
all with a scripted fake camera (no network, no ffmpeg).
"""
import threading
import time

import cv2
import numpy as np
import pytest

from engine.camera_source import CameraSource, mask_url, parse_source, test_connection


class FakeCapture:
    """Scripted camera: `frames` pictures, then reads fail. `block` holds the reader until released."""

    def __init__(self, frames=3, opened=True, fps=25.0, size=(64, 48), block=None):
        self.frames, self.opened, self.fps, self.size, self.block = frames, opened, fps, size, block
        self.count, self.released = 0, False

    def isOpened(self):
        return self.opened

    def get(self, prop):
        return {cv2.CAP_PROP_FPS: self.fps, cv2.CAP_PROP_FRAME_WIDTH: self.size[0],
                cv2.CAP_PROP_FRAME_HEIGHT: self.size[1]}.get(prop, 0)

    def read(self):
        if self.block is not None:
            self.block.wait(2)
        if self.count >= self.frames:
            return False, None
        self.count += 1
        image = np.full((self.size[1], self.size[0], 3), self.count % 200, dtype=np.uint8)
        return True, image

    def set(self, *_):
        self.count = 0

    def release(self):
        self.released = True


def test_a_tap_sees_every_picture_of_a_live_camera_and_cannot_break_it():
    seen = []
    cam = CameraSource("rtsp://cam/1", capture_factory=factory_of(FakeCapture(frames=6)), retry_delays=(0.05,))
    cam.tap = lambda image, arrived: seen.append((image.shape, arrived))
    cam.start()
    assert wait_for(lambda: len(seen) == 6)                                      # all six, though nobody read() them
    cam.stop()
    assert all(shape == (48, 64, 3) for shape, _t in seen)

    cam = CameraSource("rtsp://cam/1", capture_factory=factory_of(FakeCapture(frames=4)), retry_delays=(0.05,))

    def broken(image, arrived):
        raise RuntimeError("the listener fell over")
    cam.tap = broken
    cam.start()
    frame = cam.read(timeout=2)
    cam.stop()
    assert frame is not None                                                     # the camera kept delivering


def factory_of(*captures):
    """A VideoCapture stand-in that hands out the given captures one after another (the last one repeats)."""
    queue, opened = list(captures), []

    def factory(target, *args):
        cap = queue.pop(0) if len(queue) > 1 else queue[0]
        opened.append((target, args))
        return cap
    factory.opened = opened
    return factory


def wait_for(condition, seconds=2.0):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.01)
    return False


# ─── what an address means ───────────────────────────────────────────────────

@pytest.mark.parametrize("text,kind", [
    ("rtsp://192.168.1.10:554/stream1", "rtsp"),
    ("rtsps://cam.local/live", "rtsp"),
    ("http://192.168.1.5:8080/video", "http"),
    ("rtmp://host/app", "stream"),
    ("0", "webcam"),
    (1, "webcam"),
    ("C:/clips/test.mp4", "file"),
    ("clip.mp4", "file"),
])
def test_parse_source_kinds(text, kind):
    assert parse_source(text).kind == kind


@pytest.mark.parametrize("text", ["", "   ", "file:///etc/passwd", "concat:a.mp4|b.mp4", "pipe:0", "ftp://host/x", "javascript://x"])
def test_parse_source_rejects_anything_that_is_not_a_file_webcam_or_allowed_stream(text):
    with pytest.raises(ValueError):
        parse_source(text)


def test_windows_paths_are_files_not_schemes():
    assert parse_source(r"C:\Users\me\clip.mp4").kind == "file"


def test_passwords_are_masked_in_labels():
    spec = parse_source("rtsp://admin:s3cret@192.168.1.10/ch1")
    assert "s3cret" not in spec.label and spec.label == "rtsp://admin:***@192.168.1.10/ch1"
    assert mask_url("rtsp://192.168.1.10/ch1") == "rtsp://192.168.1.10/ch1"      # nothing to hide
    assert spec.target.endswith("s3cret@192.168.1.10/ch1")                        # the real address is still used


# ─── files ───────────────────────────────────────────────────────────────────

def test_file_source_reads_in_order_and_rewinds_at_the_end():
    cam = CameraSource("clip.mp4", capture_factory=factory_of(FakeCapture(frames=2)))
    assert cam.start() and not cam.live
    values = [int(cam.read().image[0, 0, 0]) for _ in range(5)]
    assert values == [1, 2, 1, 2, 1]                                               # loops like before
    assert cam.source_fps == 25.0


def test_file_that_cannot_be_opened_reports_it():
    cam = CameraSource("missing.mp4", capture_factory=factory_of(FakeCapture(opened=False)))
    assert cam.start() is False and cam.state == "offline"


def test_stop_never_releases_a_file_while_a_read_is_in_progress():
    # cv2 captures are not thread-safe: releasing one mid-read corrupted the heap (random backend crash)
    entered, gate = threading.Event(), threading.Event()

    class SlowRead(FakeCapture):
        reading = released_while_reading = False

        def read(self):
            self.reading = True
            entered.set()
            gate.wait(2)
            self.reading = False
            return super().read()

        def release(self):
            self.released_while_reading = self.reading
            super().release()

    cap = SlowRead(frames=10)
    cam = CameraSource("clip.mp4", capture_factory=factory_of(cap))
    cam.start()
    reader = threading.Thread(target=cam.read)
    reader.start()
    assert entered.wait(1)                                         # the read is now in progress
    stopper = threading.Thread(target=cam.stop)
    stopper.start()
    time.sleep(0.1)                                                # give stop() the chance to jump in
    assert not cap.released                                        # it has to wait for the read
    gate.set()
    reader.join(2)
    stopper.join(2)
    assert cap.released and not cap.released_while_reading
    assert cam.read() is None                                      # after stop there is nothing left to read


# ─── live sources ────────────────────────────────────────────────────────────

def test_live_source_opens_with_tcp_and_timeouts():
    factory = factory_of(FakeCapture(frames=1))
    cam = CameraSource("rtsp://127.0.0.1:8554/cam1", capture_factory=factory)
    cam.start()
    assert cam.read(timeout=2) is not None
    cam.stop()
    target, args = factory.opened[0]
    assert target == "rtsp://127.0.0.1:8554/cam1" and args[0] == cv2.CAP_FFMPEG
    assert cv2.CAP_PROP_OPEN_TIMEOUT_MSEC in args[1] and cv2.CAP_PROP_READ_TIMEOUT_MSEC in args[1]


def test_live_read_returns_the_newest_frame_and_drops_the_stale_ones():
    gate = threading.Event()
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(FakeCapture(frames=5, block=gate)))
    cam.start()
    gate.set()                                       # the camera delivers all 5 frames while nobody is reading
    assert wait_for(lambda: cam.dropped >= 4)
    frame = cam.read(timeout=1)
    assert int(frame.image[0, 0, 0]) == 5            # the newest, not the oldest
    assert cam.read(timeout=0.05) is None            # nothing new since
    cam.stop()


def test_live_read_gives_up_after_the_timeout_when_the_camera_is_silent():
    gate = threading.Event()                         # never set: the camera sends nothing
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(FakeCapture(block=gate)))
    cam.start()
    started = time.time()
    assert cam.read(timeout=0.2) is None
    assert 0.15 < time.time() - started < 1.0
    gate.set()
    cam.stop()


def test_live_source_reconnects_after_the_stream_drops():
    first, second = FakeCapture(frames=2), FakeCapture(frames=10 ** 6)
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(first, second), retry_delays=(0.01,))
    cam.start()
    assert wait_for(lambda: cam.reconnects >= 1 and second.count > 0)               # dropped, then frames flow again
    assert first.released
    cam.stop()


def test_live_source_reports_offline_and_keeps_retrying_when_it_cannot_open():
    bad, good = FakeCapture(opened=False), FakeCapture(frames=10 ** 6)
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(bad, bad, good), retry_delays=(0.3,))   # long enough to observe "offline"
    cam.start()
    assert wait_for(lambda: cam.state == "offline")
    assert wait_for(lambda: cam.read(timeout=0.1) is not None)                       # third try works
    assert cam.status()["state"] == "live"
    cam.stop()


def test_status_reports_size_fps_and_lag():
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(FakeCapture(frames=20, fps=15.0, size=(320, 240))))
    cam.start()
    assert wait_for(lambda: cam.read(timeout=0.1) is not None)
    status = cam.status()
    assert (status["kind"], status["width"], status["height"], status["source_fps"]) == ("rtsp", 320, 240, 15.0)
    assert status["lag_ms"] >= 0 and status["state"] in ("live", "offline")
    cam.stop()


def test_a_nonsense_fps_from_the_stream_is_ignored():
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(FakeCapture(frames=1, fps=90000.0)))
    cam.start()
    assert wait_for(lambda: cam.read(timeout=0.1) is not None)
    assert cam.source_fps == 25.0
    cam.stop()


def test_stop_releases_the_camera():
    cap = FakeCapture(frames=1000)
    cam = CameraSource("rtsp://x/y", capture_factory=factory_of(cap))
    cam.start()
    assert wait_for(lambda: cam.read(timeout=0.1) is not None)
    cam.stop()
    assert cap.released and cam.state == "idle"


# ─── the Test button ─────────────────────────────────────────────────────────

def test_connection_test_reports_size_and_speed():
    result = test_connection("rtsp://x/y", capture_factory=factory_of(FakeCapture(frames=3, size=(640, 360), fps=20.0)), wait_s=2)
    assert result["ok"] and (result["width"], result["height"], result["fps"]) == (640, 360, 20.0)
    assert result["first_frame_ms"] >= 0 and "label" in result


def test_connection_test_explains_a_dead_address():
    result = test_connection("rtsp://x/y", capture_factory=factory_of(FakeCapture(opened=False)), wait_s=0.3)
    assert not result["ok"] and "No picture" in result["error"]


def test_connection_test_rejects_unsupported_addresses_without_touching_them():
    factory = factory_of(FakeCapture())
    result = test_connection("concat:a|b", capture_factory=factory)
    assert not result["ok"] and factory.opened == []


def test_connection_test_never_shows_the_password():
    result = test_connection("rtsp://admin:s3cret@cam/ch1", capture_factory=factory_of(FakeCapture(frames=1)), wait_s=2)
    assert "s3cret" not in str(result)


def test_a_masked_address_gets_its_password_back():
    from engine.camera_source import restore_password
    stored = "rtsp://admin:s3cret@10.0.0.5/ch1"
    assert restore_password("rtsp://admin:***@10.0.0.5/ch1", stored) == stored
    assert restore_password("rtsp://admin:new@10.0.0.5/ch1", stored) == "rtsp://admin:new@10.0.0.5/ch1"   # user typed a new one
    assert restore_password("rtsp://10.0.0.5/ch1", stored) == "rtsp://10.0.0.5/ch1"
