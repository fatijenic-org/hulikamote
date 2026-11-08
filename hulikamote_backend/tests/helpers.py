"""Shared helpers for the scripted-car tests: a stand-in detection and a driver that feeds a path to a rule."""


FPS = 10.0          # the pipeline infers on every 3rd frame of 30 fps video

W, H = 100, 80      # car box size

BIG_ZONE = [[0, 0], [2000, 0], [2000, 2000], [0, 2000]]


class Det:
    """Minimal stand-in for YoloDetection."""

    def __init__(self, track_id, bbox, cls="car"):
        self.track_id = track_id
        self.bbox = bbox
        self.cls = cls


def drive(mgr, points, evaluate, tid=1, cls="car"):
    """Feed (x, y) bottom-centre points one frame apart; return True if `evaluate` ever flagged."""
    flagged = False
    for i, (x, y) in enumerate(points):
        mgr.update([Det(tid, [int(x - W / 2), int(y - H), W, H], cls)], i / FPS)
        flagged = evaluate(tid) or flagged
    return flagged


def go_up_then(dx, frames_up=20, frames_turn=20, start=(1000, 1500), speed=9):
    """Drive up the image, then head sideways (dx=-1 left, +1 right, 0 straight on)."""
    x, y = start
    pts = []
    for _ in range(frames_up):
        y -= speed
        pts.append((x, y))
    for _ in range(frames_turn):
        if dx:
            x += dx * speed
        else:
            y -= speed
        pts.append((x, y))
    return pts


STOP_LINE = [[800, 1000], [1200, 1000]]


class FakeSMTP:
    """Stands in for smtplib.SMTP: remembers what it was asked to do."""
    calls: list = []

    def __init__(self, host, port, timeout=None):
        FakeSMTP.calls = [("connect", host, port, timeout)]

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def starttls(self):
        FakeSMTP.calls.append(("starttls",))

    def login(self, user, password):
        FakeSMTP.calls.append(("login", user, password))

    def send_message(self, msg):
        FakeSMTP.calls.append(("send", msg["To"]))
