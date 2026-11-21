"""
playout.py - the Live Monitor's playback buffer: the backend keeps processing at full speed, the screen shows only pictures that are
completely done, a little later, at a steady pace.

Like a video stream that buffers: pictures (with their boxes) are pushed in as they are finished, each with its time on the video
(`t`, seconds). A playhead runs over that timeline.

  filling   nothing is shown yet. The playhead waits until `start_s` seconds of video are ready ("Processing...").
  playing   the playhead moves and the pictures that it passes are shown.
            A video FILE keeps a constant gap: `start_s` seconds of finished video stay between the backend and the screen. The speed
            is the backend's own speed (seconds of video it finishes per second of real time, over the last few seconds), nudged up or
            down in proportion to how far the gap is from `start_s`: backend at 0.45 of the video's speed = steady slow motion at 0.45,
            gap unchanged; backend faster than the video = normal speed, and the backend pauses when `max_s` seconds are ready.
            A stall of the backend only slows the picture (the nudge), it can never empty the gap, so the picture never has to stop
            and load again.
            A LIVE camera keeps the speed at 1.0 (it cannot be slowed: the camera goes on), so the picture is about `start_s`
            seconds late; when the backend stalls, the picture freezes for the stall and goes on.
  filling   again only if the buffer runs dry anyway: it waits for `rebuffer_s` seconds of video.
  done      the source is over (`finish()`) and everything was shown.

Pure logic: no threads, no I/O, a clock that can be replaced.
"""
import os
import time
from collections import deque

RATE_WINDOW_S = 4.0       # the backend's speed is read over this much real time
# A file that has far more in hand than the gap (after the viewer went back, or paused for long) is played at most this fast while it catches up
# (HK_PLAYOUT_MAX_SPEED; 1.0 = no limit): it stays a steady slow motion instead of jumping to normal speed. A backend that is itself faster than
# this plays at its own speed (up to 1.0); the cap only limits the catch-up.
MAX_CATCHUP_SPEED = min(1.0, max(0.1, float(os.environ.get("HK_PLAYOUT_MAX_SPEED", "0.8"))))
SPEED_SMOOTH_S = 1.0      # the playing speed moves to its new value over about this long (no jerks)


class Playout:
    def __init__(self, live: bool, start_s: float = 8.0, max_s: float = 16.0, min_speed: float = 0.05,
                 rebuffer_s: float | None = None, keep_all: bool = False, clock=time.monotonic,
                 history_s: float = 120.0, hold_max_s: float = 120.0, on_drop=None):
        self.live = live
        self.keep_all = keep_all             # live only: show every picture that came due, not only the newest of them
        self.start_s = start_s               # the gap: seconds of finished video kept between the backend and the screen
        self.max_s = max(max_s, start_s + 1.0)
        self.min_speed = min_speed
        self.rebuffer_s = start_s if rebuffer_s is None else rebuffer_s
        self._clock = clock
        self._items: deque = deque()          # (t, payload), in order of t
        self._marks: deque = deque()          # (clock, t) of the latest pushes: the backend's speed
        self.state = "filling"                # filling | playing | done
        self.play_t: float | None = None      # the playhead: where on the video's timeline the screen is
        self.speed = 1.0
        self.finished = False
        self._last: float | None = None       # clock reading of the last tick
        self._need = start_s                  # seconds of video that must be ready before playing (again)
        # Replay: what was shown stays for `history_s` seconds behind the playhead, so the enforcer can go back. While paused the backend may
        # work on up to `hold_max_s` seconds beyond the playhead (not only `max_s`). `on_drop(payload)` is told when a picture leaves for good.
        self.history_s = history_s
        self.hold_max_s = max(hold_max_s, self.max_s)
        self.on_drop = on_drop
        self._played: deque = deque()         # (t, payload) already shown, oldest first
        self._show_once: list = []            # pictures to show now although the screen is paused (the one a seek lands on)
        self.paused = False

    # ── the backend side ──
    def push(self, t: float, payload) -> None:
        """A finished picture. Times never go back (a live clock can jitter)."""
        if self._items and t < self._items[-1][0]:
            t = self._items[-1][0]
        self._items.append((t, payload))
        self._marks.append((self._clock(), t))
        if self.live:                         # a camera goes on: what is far too old to be shown goes to the history (replay)
            limit = self._items[-1][0] - (self.hold_max_s if self.paused else self.max_s + self.start_s)
            while len(self._items) > 1 and self._items[0][0] < limit:
                self._played.append(self._items.popleft())
            self._trim_history()

    def finish(self) -> None:
        """No more pictures will come: what is ready is shown at normal speed, then the state is "done"."""
        self.finished = True

    def ahead_s(self) -> float:
        """Seconds of video that are ready beyond the playhead."""
        if not self._items:
            return 0.0
        base = self.play_t if self.play_t is not None else self._items[0][0]
        return max(0.0, self._items[-1][0] - base)

    def patch(self, t_from: float, change) -> None:
        """Change the payloads of the waiting pictures from time `t_from` on, newest first (their boxes arrived late): change(payload)."""
        for t, payload in reversed(self._items):
            if t < t_from:
                break
            change(payload)

    def newest(self):
        """The payload of the newest finished picture that is waiting, or None (for the preview while the buffer fills)."""
        return self._items[-1][1] if self._items else None

    def full(self) -> bool:
        """The backend should wait (a video file only): enough is ready (more while the screen is paused)."""
        return (not self.live) and not self.finished and self.ahead_s() >= (self.hold_max_s if self.paused else self.max_s)

    # ── replay: pause, go back, go forward (never beyond what is finished) ──
    def first_t(self) -> float | None:
        if self._played:
            return self._played[0][0]
        return self._items[0][0] if self._items else None

    def last_t(self) -> float | None:
        if self._items:
            return self._items[-1][0]
        return self._played[-1][0] if self._played else None

    def _trim_history(self) -> None:
        if not self._played:
            return
        anchor = self.play_t if self.play_t is not None else self._played[-1][0]
        limit = anchor - self.history_s
        while self._played and self._played[0][0] < limit:
            _t, payload = self._played.popleft()
            if self.on_drop is not None:
                self.on_drop(payload)

    def _rewind_to(self, t: float) -> None:
        """Pictures at or after t that were already moved to the history come back to the queue."""
        while self._played and self._played[-1][0] >= t:
            self._items.appendleft(self._played.pop())

    def pause(self) -> None:
        self.paused = True
        self._last = None

    def resume(self) -> None:
        """Go on from where the screen is, however far behind the backend that is (it then plays a bit faster, until the gap is back)."""
        if self.play_t is not None:
            self._rewind_to(self.play_t)
        self.paused = False
        self._last = None

    def seek(self, t: float) -> None:
        """Put the screen at video time t (kept inside what is finished). The picture there is shown at once, also while paused."""
        first, last = self.first_t(), self.last_t()
        if first is None or last is None:
            return
        t = min(max(t, first), last)
        self._rewind_to(t)
        while len(self._items) > 1 and self._items[0][0] < t:
            self._played.append(self._items.popleft())
        if self._items:
            when, payload = self._items.popleft()
            self._played.append((when, payload))
            self._show_once.append(payload)
            self.play_t = when
        else:
            self.play_t = t
        self._last = None
        if self.state in ("filling", "done") and (self._items or self._show_once):
            self.state = "playing"
        self._trim_history()

    def backend_speed(self) -> float:
        """Seconds of video the backend finishes per second of real time, over the last RATE_WINDOW_S (1.0 until there is enough to tell,
        and after a pause long enough for every reading to be old)."""
        now = self._clock()
        while self._marks and now - self._marks[0][0] > RATE_WINDOW_S:
            self._marks.popleft()
        if len(self._marks) < 2:
            return 1.0
        (c0, t0), (c1, t1) = self._marks[0], self._marks[-1]
        return max(0.0, (t1 - t0) / (c1 - c0)) if c1 > c0 else 1.0

    # ── the screen side ──
    def tick(self) -> list:
        """Move the playhead by the real time since the last call. Returns the payloads to show now, in order (a live camera shows only
        the newest of the pictures that came due together, unless it is behind: then every one)."""
        now = self._clock()
        shown, self._show_once = self._show_once, []
        if self.paused:
            self._last = None
            return shown
        if self.state == "filling":
            if self._items and (self.finished or self.ahead_s() >= self._need):
                if self.play_t is None or self.play_t < self._items[0][0]:
                    self.play_t = self._items[0][0]        # (after a stall of a live camera the gap is skipped)
                self.state = "playing"
                self._last = now
                self.speed = 1.0 if self.live else min(1.0, max(self.min_speed, self.backend_speed()))      # a file starts at the backend's own speed
            elif self.finished and not self._items:
                self.state = "done"
                return shown
            else:
                return shown
        if self.state != "playing":
            return shown
        dt = max(0.0, now - (self._last if self._last is not None else now))
        self._last = now
        gap_error = (self.ahead_s() - self.start_s) / self.start_s        # > 0: more in hand than the gap, < 0: less
        if self.finished:
            # the last pictures at normal speed; but a large amount in hand (the viewer went back) is still played in the steady slow motion
            self.speed = 1.0 if self.ahead_s() <= self.start_s else (self.speed if self.speed <= MAX_CATCHUP_SPEED else MAX_CATCHUP_SPEED)
            if self.speed < MAX_CATCHUP_SPEED and self.ahead_s() > self.start_s:
                self.speed += (MAX_CATCHUP_SPEED - self.speed) * min(1.0, dt / SPEED_SMOOTH_S)
        elif self.live:
            target = 1.0 + min(0.25, max(0.0, gap_error) * 0.25)          # a camera cannot be slowed; with more in hand than the gap: a bit faster
            self.speed += (target - self.speed) * min(1.0, dt / SPEED_SMOOTH_S)
        else:
            backend = self.backend_speed()
            raw = backend * (1.0 + gap_error)
            if gap_error > 0:
                raw = min(raw, max(backend, MAX_CATCHUP_SPEED))      # catching up a big gap: never faster than the steady slow motion
            target = min(1.0, max(self.min_speed, raw))
            self.speed += (target - self.speed) * min(1.0, dt / SPEED_SMOOTH_S)
        self.play_t += dt * self.speed
        if self.live and self._items and self._items[0][0] - self.play_t > 1.5:
            self.play_t = self._items[0][0]          # a hole in a camera's timeline (the monitor was paused for a plate read): skip it, do not wait
        due = []
        while self._items and self._items[0][0] <= self.play_t:
            item = self._items.popleft()
            self._played.append(item)
            due.append(item[1])
        self._trim_history()
        if not self._items:
            if self.finished:
                self.state = "done"
            else:
                self.state, self._need = "filling", self.rebuffer_s     # ran dry: wait for a little more
        behind = self.live and gap_error > 0.25
        return shown + (due if (self.keep_all or not self.live or behind) else due[-1:])

    def hold(self) -> None:
        """The screen is paused (a plate is being read): the playhead must not run on by the time that passes. Call it while paused."""
        self._last = None

    def next_delay(self) -> float:
        """Seconds until the next picture is due (for the screen side to sleep), between 2 and 50 ms."""
        if self.state == "playing" and self._items and self.play_t is not None:
            return max(0.002, min(0.05, (self._items[0][0] - self.play_t) / max(self.speed, 0.05)))
        return 0.05

    def info(self) -> dict:
        """For the dashboard: {"state", "percent" (while filling), "ahead_s", "speed", "need_s"}."""
        ahead = self.ahead_s()
        return {"state": self.state, "percent": round(min(1.0, ahead / self._need), 2) if self._need > 0 and self.state == "filling" else 1.0,
                "ahead_s": round(ahead, 2), "speed": round(self.speed, 2), "need_s": round(self._need, 1), "live": self.live,
                "paused": self.paused, "first_s": self.first_t(), "play_s": self.play_t, "proc_s": self.last_t()}
