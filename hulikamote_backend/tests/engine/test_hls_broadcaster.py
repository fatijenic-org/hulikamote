"""engine/hls_broadcaster.py - a stuck encoder or a missing video relay (MediaMTX) must never freeze the backend."""
import threading
import time

import numpy as np
import pytest

from engine import hls_broadcaster as hb


class StuckStdin:
    """A pipe nobody reads from: a write waits until the process is killed, like ffmpeg with no relay to send to."""

    def __init__(self, proc):
        self.proc = proc

    def write(self, data):
        self.proc.killed.wait(10)
        raise OSError("pipe closed")

    def close(self):
        pass


class StuckEncoder:
    def __init__(self, *args, **kwargs):
        self.killed = threading.Event()
        self.stdin = StuckStdin(self)

    def poll(self):
        return None

    def kill(self):
        self.killed.set()

    def wait(self, timeout=None):
        return 0


FRAME = np.zeros((48, 64, 3), dtype=np.uint8)


def test_a_stuck_encoder_never_blocks_pushing_frames_or_stopping(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(hb, "server_status", lambda: (True, ""))
    encoders = []
    monkeypatch.setattr(hb.subprocess, "Popen", lambda *a, **k: encoders.append(StuckEncoder()) or encoders[-1])
    broadcaster = hb.HLSBroadcaster()
    broadcaster.start(width=64, height=48)

    started = time.time()
    for _ in range(60):
        broadcaster.push(FRAME)                                    # the encoder never reads: frames are dropped, not waited for
    assert time.time() - started < 1.0

    started = time.time()
    broadcaster.stop()                                             # used to wait for ever on the stuck pipe
    assert time.time() - started < 3.0
    assert encoders[0].killed.is_set()


def test_without_the_relay_no_encoder_is_started(monkeypatch, tmp_path):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(hb, "server_status", lambda: (False, "not running"))
    monkeypatch.setattr(hb.subprocess, "Popen", lambda *a, **k: pytest.fail("ffmpeg must not start without the relay"))
    broadcaster = hb.HLSBroadcaster()
    broadcaster.start(width=64, height=48)
    broadcaster.push(FRAME)                                        # harmless
    assert not broadcaster._started


def test_stopping_something_never_started_is_fine():
    hb.HLSBroadcaster().stop()


# ─── the relay ───────────────────────────────────────────────────────────────

def test_a_relay_that_is_already_up_is_left_alone(monkeypatch):
    monkeypatch.setattr(hb, "_port_open", lambda *a, **k: True)
    monkeypatch.setattr(hb.subprocess, "Popen", lambda *a, **k: pytest.fail("must not start a second relay"))
    assert hb.server_status() == (True, "")


def test_a_relay_that_is_installed_but_off_is_started(monkeypatch, tmp_path):
    (tmp_path / "mediamtx.exe").write_bytes(b"")
    monkeypatch.setattr(hb, "MEDIAMTX_DIR", tmp_path)
    answers = iter([False, False, True])                           # off, still starting, up
    monkeypatch.setattr(hb, "_port_open", lambda *a, **k: next(answers, True))
    started = []
    monkeypatch.setattr(hb.subprocess, "Popen", lambda cmd, **k: started.append((cmd, k["cwd"])))
    assert hb.server_status(wait_s=3) == (True, "")
    assert started == [([str(tmp_path / "mediamtx.exe"), "mediamtx.yml"], str(tmp_path))]


def test_a_relay_that_is_not_installed_says_where_it_belongs(monkeypatch, tmp_path):
    monkeypatch.setattr(hb, "MEDIAMTX_DIR", tmp_path)
    monkeypatch.setattr(hb, "_port_open", lambda *a, **k: False)
    ready, message = hb.server_status()
    assert not ready and "not installed" in message and "tools/mediamtx" in message


def test_a_relay_that_starts_but_never_answers_is_reported(monkeypatch, tmp_path):
    (tmp_path / "mediamtx.exe").write_bytes(b"")
    monkeypatch.setattr(hb, "MEDIAMTX_DIR", tmp_path)
    monkeypatch.setattr(hb, "_port_open", lambda *a, **k: False)
    monkeypatch.setattr(hb.subprocess, "Popen", lambda *a, **k: None)
    ready, message = hb.server_status(wait_s=0.3)
    assert not ready and "not answering" in message
