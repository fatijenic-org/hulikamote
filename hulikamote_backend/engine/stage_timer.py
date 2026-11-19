"""
stage_timer.py - how long each step of the live pipeline takes, so a slow step is seen and not guessed.

Every step adds its time with TIMER.add(name, seconds) (or `with TIMER.time(name):`). The last WINDOW samples of each step are kept:
snapshot() gives the average and the worst of them, line() the same as one line for the log, rate() how many times a second something
happened (pictures sent, pictures judged). Cheap enough to leave on: two clock reads and a lock per sample.

Steps, in the order of a picture (the names the pipeline uses):
  wait      the loop waits for the next picture (a live camera: this is idle time, not work)
  decode    a video file: reading the next picture (runs ahead of the loop, in its own thread)
  prep      copy + shrink the picture
  A         stage A in total: the detector and the trackers (engine/pipeline.py detect_stage)
    detect    the model run (all tiles of "small people" mode too)
    nms       cutoffs, NMS, the box objects
    trackV    the vehicle tracker
    trackP    the people tracker (runs beside the vehicle tracker when both have boxes)
    roi       the picture-wide zone filter
  B         stage B in total: history, extra models, rules (judge_stage)
    history   ledger update and the learned flow
    models    helmet / plate / cabin models (only when a violation needs them)
    rules     the violation rules
    evidence  evidence photos and the plate text
  overlay   the boxes and labels for the dashboard
  encode    the JPEG (or the push to the video relay); starts as soon as the picture is read
  send      the websocket message
"""
import threading
import time
from collections import deque
from contextlib import contextmanager

WINDOW = 150                      # samples kept per step
ORDER = ("wait", "decode", "prep", "A", "detect", "nms", "trackV", "trackP", "roi",
         "B", "history", "models", "rules", "evidence", "overlay", "encode", "send")
SPANS_KEPT = 1500                 # recent steps kept with their start time, for the popup's timeline

# What each step is, for the popup: the row it is drawn in, and whether it works on the GPU. "A" and "B" are the totals of their rows.
STEP_INFO = {
    "wait":     {"lane": "loop",    "res": "cpu", "label": "Wait for picture"},
    "decode":   {"lane": "reader",  "res": "cpu", "label": "Decode video"},
    "prep":     {"lane": "reader",  "res": "cpu", "label": "Shrink picture"},
    "detect":   {"lane": "A",       "res": "gpu", "label": "Detector (YOLO)"},
    "nms":      {"lane": "A",       "res": "cpu", "label": "Boxes + NMS"},
    "roi":      {"lane": "A",       "res": "cpu", "label": "Zone filter"},
    "trackV":   {"lane": "V",       "res": "gpu", "label": "Track vehicles"},
    "trackP":   {"lane": "P",       "res": "gpu", "label": "Track people"},
    "history":  {"lane": "B",       "res": "cpu", "label": "History + flow"},
    "models":   {"lane": "B",       "res": "gpu", "label": "Helmet/plate/cabin models"},
    "rules":    {"lane": "B",       "res": "cpu", "label": "Rules"},
    "evidence": {"lane": "B",       "res": "cpu", "label": "Evidence photos"},
    "overlay":  {"lane": "loop",    "res": "cpu", "label": "Boxes for dashboard"},
    "encode":   {"lane": "encode",  "res": "cpu", "label": "JPEG encode"},
    "send":     {"lane": "loop",    "res": "cpu", "label": "Send to dashboard"},
}
LANES = (("reader", "Reader"), ("A", "A: detect"), ("V", "Track vehicles"), ("P", "Track people"),
         ("B", "B: history, models, rules"), ("encode", "JPEG"), ("loop", "Loop: send"))


class StageTimer:
    def __init__(self, window: int = WINDOW):
        self._lock = threading.Lock()
        self._window = window
        self._samples: dict[str, deque] = {}
        self._events: dict[str, deque] = {}        # name -> times (monotonic) of the last events, for rates
        self._spans: deque = deque(maxlen=SPANS_KEPT)   # (end time monotonic, seconds, name)
        self._last_report = time.monotonic()

    def add(self, name: str, seconds: float) -> None:
        end = time.monotonic()
        with self._lock:
            self._samples.setdefault(name, deque(maxlen=self._window)).append(seconds)
            self._spans.append((end, seconds, name))

    @contextmanager
    def time(self, name: str):
        t0 = time.perf_counter()
        try:
            yield
        finally:
            self.add(name, time.perf_counter() - t0)

    def mark(self, name: str) -> None:
        """One event happened (a picture was sent, a picture was judged)."""
        with self._lock:
            self._events.setdefault(name, deque(maxlen=400)).append(time.monotonic())

    def rate(self, name: str, seconds: float = 5.0) -> float:
        """Events a second over the last `seconds` (0 when there were none)."""
        now = time.monotonic()
        with self._lock:
            recent = [t for t in self._events.get(name, ()) if now - t <= seconds]
        if len(recent) < 2 or recent[-1] <= recent[0]:
            return 0.0
        return (len(recent) - 1) / (recent[-1] - recent[0])

    def snapshot(self) -> dict:
        """{"steps": {name: {"avg_ms", "max_ms", "n"}}, "rates": {"pictures" shown, "judged", "produced" (finished by the backend)}} - steps in picture order."""
        with self._lock:
            names = [n for n in ORDER if n in self._samples] + [n for n in self._samples if n not in ORDER]
            steps = {n: {"avg_ms": round(1000 * sum(self._samples[n]) / len(self._samples[n]), 2),
                         "max_ms": round(1000 * max(self._samples[n]), 2), "n": len(self._samples[n])} for n in names if self._samples[n]}
        return {"steps": steps, "rates": {"pictures": round(self.rate("pictures"), 1), "judged": round(self.rate("judged"), 1),
                                                                                    "produced": round(self.rate("produced"), 1)}}

    def spans(self, window_s: float = 2.5) -> list[dict]:
        """The steps of the last `window_s` seconds, for a timeline: [{"name", "start" (s from the start of the window), "dur_ms"}].
        The totals "A" and "B" are left out (their steps are in the list)."""
        now = time.monotonic()
        first = now - window_s
        with self._lock:
            recent = [x for x in self._spans if x[0] >= first and x[2] not in ("A", "B")]
        return [{"name": name, "start": round(max(0.0, end - sec - first), 4), "dur_ms": round(sec * 1000, 2)} for end, sec, name in recent]

    def line(self) -> str:
        snap = self.snapshot()
        parts = [f"{n} {v['avg_ms']:.1f}" for n, v in snap["steps"].items()]
        return (f"[Timing ms avg] {' | '.join(parts)} || pictures {snap['rates']['pictures']}/s, judged {snap['rates']['judged']}/s")

    def report_every(self, seconds: float = 5.0) -> str | None:
        """The log line when `seconds` have passed since the last one, else None."""
        now = time.monotonic()
        with self._lock:
            if now - self._last_report < seconds:
                return None
            self._last_report = now
        return self.line()

    def reset(self) -> None:
        with self._lock:
            self._samples.clear()
            self._events.clear()
            self._spans.clear()


TIMER = StageTimer()
