"""
start_log.py - when each step of "Apply -> first picture" happened.

The Live Monitor's start is a chain: the rules arrive, the models are loaded and warmed, the feed connects, the source opens, the first
picture is read, detected and finished, and the playback buffer starts. Each step marks itself here (seconds since the Apply), so a slow
start can be read off instead of guessed: `GET /settings/live/perf` -> "startup". Nothing here changes how anything runs.
"""
import threading
import time
from datetime import datetime, timezone


class StartLog:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._t0: float | None = None
        self._label = ""
        self._since = ""
        self._steps: list[tuple[str, float]] = []
        self._playing = False

    def begin(self, label: str) -> None:
        """A new start: the Apply (or a plain connect). Forgets the one before."""
        with self._lock:
            self._t0 = time.monotonic()
            self._label = label
            self._since = datetime.now(timezone.utc).isoformat(timespec="seconds")
            self._steps = []
            self._playing = False

    def continue_or_begin(self, label: str, within_s: float = 300.0) -> None:
        """The feed connected: it belongs to the Apply that just happened (still starting), else it is a start of its own."""
        with self._lock:
            fresh = self._t0 is not None and not self._playing and time.monotonic() - self._t0 < within_s
        if not fresh:
            self.begin(label)

    def mark(self, step: str) -> None:
        """A step is done. Only the first time counts for each step of a start."""
        with self._lock:
            if self._t0 is None or any(name == step for name, _ in self._steps):
                return
            at = round(time.monotonic() - self._t0, 2)
            self._steps.append((step, at))
            if step == "playing":
                self._playing = True
        print(f"[Startup] {step}: {at:.2f} s")

    def snapshot(self) -> dict:
        with self._lock:
            steps, previous = [], 0.0
            for name, at in self._steps:
                steps.append({"step": name, "at_s": at, "took_s": round(at - previous, 2)})
                previous = at
            return {"label": self._label, "since": self._since, "steps": steps, "done": self._playing}


START = StartLog()
