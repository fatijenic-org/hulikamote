"""
live_calibrator.py - the Live Monitor learns the painted road lines of its camera BY ITSELF, nobody draws anything.

It watches the live stream for a while (LEARN_SECONDS), then reads the paint with engine/road_lines.py in a background
thread (the stream never waits for it) and turns what it found into zones for the rules that need them. What it learned is
remembered per camera, so the next connection has the zones at once; it learns again only when asked ("Re-learn") or when
the view clearly changed.

What it is allowed to do, and what it is not:
  - pedestrian_lane  from a crosswalk that spans the road and has 5 or more stripes (or 4 very clear ones)
  - red_light / crossing_solid_line  from a stop line / a solid lane line: BEST EFFORT. The finder is weaker there (on the
    user's own clips it took curbs for solid lines), so by default they are only HINTS: drawn in the live picture, labelled,
    but never turned into rules. camera_config.json {"learned_lines_as_rules": true} makes them rules.
  - a refused or failed learn leaves nothing installed: the live view keeps running with the rules that need no zone, and
    no zone is ever guessed.
  - drawn zones (the wizard's "Use for Live Monitor") always win over learned ones (see DecoupledPipeline._get_scaled_rois).

Needs what the finder needs: a fixed camera, some traffic in the first 30-40 s, a level camera, daylight.
Thread safety: feed() is called from the live loop; analysis runs in its own thread; every state change is under one lock.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

import cv2
import numpy as np

log = logging.getLogger(__name__)

LEARN_SECONDS = 40.0          # how much footage is read before the paint is analysed
MAX_LEARN_SECONDS = 90.0      # a slow stream is given this long to collect enough pictures
MIN_PICTURES = 160            # at least 20 s worth at 8 pictures a second, or the road direction cannot be trusted
MAX_ATTEMPTS = 3              # learning windows tried in a row before it gives up and waits for "Re-learn"
PICTURE_GAP = 1.0 / 8.0       # seconds between the small grey pictures (road_lines.SAMPLE_FPS)
COLOUR_PICTURES = 30          # colour pictures spread over the window: the empty road is built from them
VERIFY_PICTURES = 40          # a known road is checked against ~5 s of the live view ...
VERIFY_EVERY = 300.0          # ... when the camera connects, and again this many seconds apart while it stays connected
CHANGED_DISTANCE = 20         # of 64 bits: a saved view this far from the live one is a different view
MIN_STRIPES = 5               # a crosswalk needs this many stripes ...
STRONG_FOUR = 0.85            # ... or 4 stripes that are all very clear (road_lines "score")
MIN_CROSSWALK_WIDTH = 0.40    # ... and must span the road: this share of the top view's width (measured: real crosswalks 0.59-0.95,
                              # a tiled pavement strip that looked like one 0.32)
MIN_STOP_LENGTH = 0.30        # a stop line must be at least this share of the top view's width
MIN_SOLID_COVERAGE = 0.90     # a solid lane line must be painted along at least this share of its length
MIN_SOLID_REACH = 0.30        # ... and reach at least this share of the top view's depth
REFERENCE = (1920, 1080)      # the wizard's zone space (engine/road_lines.reference_zones)
LEARNABLE = ("pedestrian_lane", "red_light", "crossing_solid_line")
BEST_EFFORT = ("red_light", "crossing_solid_line")        # hints only unless camera_config.json says "learned_lines_as_rules": true
RULE_FLAG = "learned_lines_as_rules"
FLAG_REFRESH = 5.0            # seconds the setting is remembered before camera_config.json is read again
DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "camera_config.json"
CONFIG_KEY = "learned_road"                       # camera_config.json: {camera: {zones, found, view_hash, ...}}

_FILE_LOCK = threading.Lock()


# ───────────────────────────── a name per camera, and the view's fingerprint ─────────────────────────────

def camera_key(source, config_path: Path | None = None) -> str:
    """The saved-road key of a camera: the name of the saved profile that has this address, else the address with its
    password masked. Never contains a password."""
    from engine.camera_source import mask_url
    text = str(source)
    try:
        cfg = json.loads((config_path or DEFAULT_CONFIG).read_text(encoding="utf-8"))
        for profile in cfg.get("camera_profiles", []):
            if isinstance(profile, dict) and profile.get("url") == text and profile.get("name"):
                return f"profile:{profile['name']}"
    except (OSError, ValueError):
        pass
    return mask_url(text)


def view_hash(grey: np.ndarray) -> str:
    """64-bit fingerprint of a picture (which side of each neighbouring pair is brighter, on a 9x8 version). The same view
    with other traffic on it stays close; a different view does not."""
    small = cv2.resize(grey, (9, 8), interpolation=cv2.INTER_AREA).astype(np.int16)
    bits = (small[:, 1:] > small[:, :-1]).flatten()
    return f"{int(''.join('1' if b else '0' for b in bits), 2):016x}"


def hash_distance(a: str, b: str) -> int:
    return bin(int(a, 16) ^ int(b, 16)).count("1")


def _grey(image: np.ndarray) -> np.ndarray:
    return image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


# ───────────────────────────── what is remembered per camera ─────────────────────────────

def _read(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _write_atomic(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def load_saved(key: str, path: Path | None = None) -> dict | None:
    entry = (_read(path or DEFAULT_CONFIG).get(CONFIG_KEY) or {}).get(key)
    return entry if isinstance(entry, dict) and isinstance(entry.get("zones"), dict) else None


def save_road(key: str, entry: dict, path: Path | None = None) -> None:
    path = path or DEFAULT_CONFIG
    with _FILE_LOCK:
        config = _read(path)
        config.setdefault(CONFIG_KEY, {})[key] = entry
        _write_atomic(path, config)


def forget_road(key: str, path: Path | None = None) -> bool:
    path = path or DEFAULT_CONFIG
    with _FILE_LOCK:
        config = _read(path)
        saved = config.get(CONFIG_KEY) or {}
        if key not in saved:
            return False
        del saved[key]
        if not saved:
            config.pop(CONFIG_KEY, None)
        _write_atomic(path, config)
        return True


# ───────────────────────────── what is believed ─────────────────────────────

def accept(result: dict) -> tuple[dict, dict]:
    """(zones, counts) from a road_lines result: only the marks that are clear enough. Zones are in the wizard's shape and
    1920x1080 reference space; counts say what was found ({"crosswalks", "stop_lines", "solid_lines"}). Nothing guessed."""
    from engine.road_lines import reference_zones
    if not result.get("ok"):
        return {}, {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}
    tw, th = result["rectifier"]["top_size"]
    crosswalks = [c for c in result["crosswalks"]
                  if (c["stripes"] >= MIN_STRIPES or (c["stripes"] >= 4 and c["score"] >= STRONG_FOUR))
                  and c["top"]["u1"] - c["top"]["u0"] >= MIN_CROSSWALK_WIDTH * tw]
    stops = [s for s in result["stop_lines"] if s["length"] >= MIN_STOP_LENGTH * tw]
    solid = [ln for ln in result["lane_lines"]
             if ln["style"] == "solid" and ln["coverage"] >= MIN_SOLID_COVERAGE
             and abs(ln["top"]["v1"] - ln["top"]["v0"]) >= MIN_SOLID_REACH * th]
    trimmed = {**result, "crosswalks": crosswalks, "stop_lines": stops, "lane_lines": solid}
    zones = {key: value for key, value in reference_zones(trimmed).items() if key in LEARNABLE}
    return zones, {"crosswalks": len(crosswalks), "stop_lines": len(stops), "solid_lines": len(solid)}


def _describe(found: dict) -> str:
    parts = [f"{n} {name}{'' if n == 1 else 's'}" for n, name in
             ((found["crosswalks"], "crosswalk"), (found["stop_lines"], "stop line"), (found["solid_lines"], "solid line")) if n]
    return ", ".join(parts)


# ───────────────────────────── the calibrator ─────────────────────────────

class LiveCalibrator:
    """One per Live Monitor. attach() when a camera connects, feed() with every processed frame, and read active_zones() /
    status(). `analyse` is road_lines.analyse_clip unless a test gives another one."""

    def __init__(self, config_path: Path | None = None, learn_seconds: float = LEARN_SECONDS,
                 analyse: Callable | None = None, min_pictures: int = MIN_PICTURES, background: bool = True):
        self.config_path = config_path or DEFAULT_CONFIG
        self.learn_seconds = float(learn_seconds)
        self.min_pictures = int(min_pictures)
        self._analyse = analyse
        self._background = background                      # False: analyse in the caller's thread (tests)
        self._lock = threading.RLock()
        self.key: str | None = None
        self.version = 0                                   # +1 every time the zones in use change
        self._epoch = 0                                    # +1 whenever the plan changes: an analysis from an older plan is dropped
        self._flag: tuple[bool, float] | None = None       # (learned_lines_as_rules, when it was read)
        self._reset_state()

    # ── state ──
    def _reset_state(self) -> None:
        self.state = "off"                                 # off | learning | analysing | ready | empty | refused | error
        self.message = ""
        self.note = ""                                     # why a learning window (re)started
        self.attempt = 0
        self.zones: dict[str, list[dict]] = {}             # everything accepted (installed ones and hints)
        self.found = {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}
        self.saved = False                                 # these zones were loaded from disk
        self.learned_at: str | None = None
        self._view_hash: str | None = None
        self._verify: list[np.ndarray] | None = None       # pictures of the live view, to compare with the known road
        self._next_check: float | None = None              # frame time of the next re-check of the view
        self._clear_buffers()

    def _clear_buffers(self) -> None:
        self._greys: list[np.ndarray] = []
        self._colours: list[np.ndarray] = []
        self._colour_at: list[int] = []
        self._first_t: float | None = None
        self._last_grey_t: float | None = None
        self._last_colour_t: float | None = None
        self._size: tuple[int, int] | None = None

    def _set_zones(self, zones: dict) -> None:
        self.zones = zones
        self.version += 1

    def _lines_are_rules(self) -> bool:
        """The operator's setting, read from camera_config.json at most every FLAG_REFRESH seconds (status and the overlay
        ask on every frame message)."""
        now = time.monotonic()
        if self._flag is None or now - self._flag[1] >= FLAG_REFRESH:
            self._flag = (bool(_read(self.config_path).get(RULE_FLAG, False)), now)
        return self._flag[0]

    def _split(self) -> tuple[dict, dict]:
        """(installed as rules, hints only). Crosswalks are rules; stop and solid lines are hints unless the flag says so."""
        rules_for_lines = self._lines_are_rules()
        rules = {k: v for k, v in self.zones.items() if k not in BEST_EFFORT or rules_for_lines}
        return rules, {k: v for k, v in self.zones.items() if k not in rules}

    # ── connecting ──
    def attach(self, key: str) -> None:
        """A camera connected. The same camera as before keeps what it knows; another one loads its own saved road (at once)
        or starts learning. A saved road is checked against the live view in the background (view changed -> learns again)."""
        with self._lock:
            if key == self.key and self.state != "off":
                if self.state in ("ready", "empty") and self._view_hash:      # same address, maybe another picture: look again
                    self._verify, self._last_grey_t = [], None
                return
            self.key = key
            self._epoch += 1
            self._set_zones({})
            self._reset_state()
            saved = load_saved(key, self.config_path)
            if saved is not None:
                self._set_zones(dict(saved["zones"]))
                self.found = dict(saved.get("found") or self.found)
                self.saved, self.learned_at = True, saved.get("learned_at")
                self._view_hash = saved.get("view_hash")
                self.state = "ready" if self.zones else "empty"
                self.message = (f"Road loaded (saved for this camera): {self._summary()}" if self.zones
                                else "Saved for this camera: no clear crosswalk or line was found")
                self._verify = [] if self._view_hash else None
            else:
                self._start_learning(1)

    def detach(self) -> None:
        """The camera disconnected: stop collecting. What is learned stays (it is the same camera when it comes back)."""
        with self._lock:
            self._clear_buffers()
            self._verify = None
            self._epoch += 1
            if self.state in ("learning", "analysing"):
                self.state = "off"
                self.message = ""
                self.attempt = 0

    def _start_learning(self, attempt: int, note: str = "") -> None:
        self._clear_buffers()
        self._next_check = None
        self._epoch += 1
        self.attempt = attempt
        self.state = "learning"
        self.note = note
        self.message = ""

    # ── feeding ──
    def feed(self, frame: np.ndarray, t: float | None = None) -> None:
        """One processed live frame (BGR). Cheap: most calls only check the clock."""
        if frame is None or self.state not in ("learning", "ready", "empty") or self.key is None:
            return
        t = time.monotonic() if t is None else float(t)
        with self._lock:
            if self.state == "learning":
                self._feed_learning(frame, t)
                return
            if self._view_hash and self._verify is None:                   # a known road: re-check the view now and then
                if self._next_check is None:
                    self._next_check = t + VERIFY_EVERY
                elif t >= self._next_check:
                    self._verify, self._last_grey_t = [], None
            if self._verify is not None:
                self._feed_verify(frame, t)

    def _small_grey(self, frame: np.ndarray) -> np.ndarray:
        from engine.road_lines import FLOW_W, _even
        h, w = frame.shape[:2]
        return cv2.cvtColor(cv2.resize(frame, (FLOW_W, _even(h * FLOW_W / w)), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)

    def _feed_learning(self, frame: np.ndarray, t: float) -> None:
        from engine.road_lines import WORK_W, _even
        h, w = frame.shape[:2]
        if self._size is not None and self._size != (w, h):          # the stream changed size: start over, nothing mixes
            self._clear_buffers()
        self._size = (w, h)
        if self._first_t is None:
            self._first_t = t
        if self._last_grey_t is not None and t - self._last_grey_t < PICTURE_GAP:
            return
        self._last_grey_t = t
        self._greys.append(self._small_grey(frame))
        spread = self.learn_seconds / COLOUR_PICTURES
        if len(self._colours) < COLOUR_PICTURES and (self._last_colour_t is None or t - self._last_colour_t >= spread):
            self._last_colour_t = t
            self._colours.append(cv2.resize(frame, (WORK_W, _even(h * WORK_W / w)), interpolation=cv2.INTER_AREA))
            self._colour_at.append(len(self._greys) - 1)
        elapsed = t - self._first_t
        enough = len(self._greys) >= self.min_pictures
        if (elapsed >= self.learn_seconds and enough) or elapsed >= MAX_LEARN_SECONDS:
            self._begin_analysis()

    def _feed_verify(self, frame: np.ndarray, t: float) -> None:
        if self._last_grey_t is not None and t - self._last_grey_t < PICTURE_GAP:
            return
        self._last_grey_t = t
        self._verify.append(self._small_grey(frame))
        if len(self._verify) < VERIFY_PICTURES:
            return
        live = view_hash(np.median(np.stack(self._verify), axis=0).astype(np.uint8))
        self._verify = None
        self._last_grey_t = None
        self._next_check = t + VERIFY_EVERY
        distance = hash_distance(live, self._view_hash)
        if distance >= CHANGED_DISTANCE:
            log.warning("Live road: the view of %s changed (distance %s): learning it again", self.key, distance)
            self._set_zones({})
            self.saved = False
            self._start_learning(1, "The camera view changed: learning the road again")

    # ── analysing ──
    def _begin_analysis(self) -> None:
        pictures = len(self._greys)
        if pictures < 16 or not self._colours:
            self._finish(None, None, "The stream gave too few pictures to read the road.")
            return
        clip = {"video": self._size, "fps": 8.0, "seconds": pictures / 8.0, "colours": self._colours, "colour_at": self._colour_at,
                "greys": self._greys, "grey_size": (self._greys[0].shape[1], self._greys[0].shape[0]),
                "colour_size": (self._colours[0].shape[1], self._colours[0].shape[0])}
        self.state = "analysing"
        self.message = "Reading the road paint..."
        self._epoch += 1
        epoch = self._epoch
        self._clear_buffers()
        if self._background:
            threading.Thread(target=self._run, args=(clip, epoch), daemon=True, name="road-learner").start()
        else:
            self._run(clip, epoch)

    def _run(self, clip: dict, epoch: int) -> None:
        try:
            analyse = self._analyse
            if analyse is None:
                from engine.road_lines import analyse_clip as analyse
            result, background = analyse(clip)
            error = None
        except Exception as exc:                                    # a bad read must never reach the live loop
            log.exception("Live road: reading the road failed")
            result, background, error = None, None, f"Could not read the road ({exc})"
        with self._lock:
            if epoch != self._epoch or self.state != "analysing":
                return                                              # a Re-learn / Forget / other camera came meanwhile
            self._finish(result, background, error)

    def _finish(self, result: dict | None, background, error: str | None = None) -> None:
        if error is not None or result is None or not result.get("ok"):
            reason = error or (result or {}).get("reason") or "The road could not be read"
            if self.attempt < MAX_ATTEMPTS:
                self._start_learning(self.attempt + 1, f"Last try: {reason}")
            else:
                self.state = "error" if error is not None else "refused"
                self.message = f"{reason} Press Re-learn to try again; the live view runs without learned zones."
            return
        zones, found = accept(result)
        self.found = found
        entry_hash = view_hash(_grey(background)) if background is not None else None
        self._view_hash = entry_hash
        self.learned_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.saved = False
        self._set_zones(zones)
        self.state = "ready" if zones else "empty"
        self.message = (f"Road learned: {self._summary()}" if zones
                        else "Road read, but no clear crosswalk or line was found: no zones are used")
        if self.key and (zones or self.attempt == 1):        # "nothing clear" after refused reads is doubtful: ask again next time
            try:
                save_road(self.key, {"zones": zones, "found": found, "learned_at": self.learned_at,
                                     "frame_size": list(result.get("video_size") or []), "view_hash": entry_hash},
                          self.config_path)
            except OSError:
                log.exception("Live road: could not save what was learned")

    def _summary(self) -> str:
        text = _describe(self.found)
        hints = sum(len(v) for v in self._split()[1].values())
        return text + (f" (the line{'s' if hints != 1 else ''} shown as hints only, not used as rules)" if hints else "")

    # ── asking and acting ──
    def active_zones(self) -> dict[str, list[dict]]:
        """The zones the pipeline may use as rules."""
        with self._lock:
            return {key: list(value) for key, value in self._split()[0].items()}

    def hint_overlay(self, frame_w: int, frame_h: int) -> list[dict]:
        """The zones that are only hints, on the processed frame, for the live picture."""
        with self._lock:
            hints = self._split()[1]
        sx, sy = frame_w / REFERENCE[0], frame_h / REFERENCE[1]

        def pts(points):
            return [[int(x * sx), int(y * sy)] for x, y in points]
        return [{"violation": key, "polygon": pts(z["polygon"]), "line": pts(z["ui_vector"]) if z.get("ui_vector") else None,
                 "best_effort": True, "hint": True} for key, zones in hints.items() for z in zones]

    def relearn(self) -> bool:
        """Throw away what is known for this camera's current view and learn again from the live stream."""
        with self._lock:
            if self.key is None:
                return False
            self._epoch += 1
            self._set_zones({})
            self.saved = False
            self.found = {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}
            self._verify = None
            self._start_learning(1)
            return True

    def forget(self) -> bool:
        """Remove what is saved for this camera and stop using it. It learns again the next time the camera connects, or on Re-learn."""
        with self._lock:
            if self.key is None:
                return False
            forget_road(self.key, self.config_path)
            self._epoch += 1
            self._set_zones({})
            self._reset_state()
            self.state = "off"
            self.message = "Forgotten. It learns again when the camera reconnects, or press Re-learn."
            return True

    def status(self) -> dict:
        with self._lock:
            progress = 0.0
            if self.state == "learning" and self._first_t is not None and self._last_grey_t is not None:
                progress = min(self.learn_seconds, max(0.0, self._last_grey_t - self._first_t))
            rules, hints = self._split()
            message = self.message
            if self.state == "learning":
                message = f"Learning the road {int(progress)}/{int(self.learn_seconds)} s"
                if self.attempt > 1:
                    message += f" (try {self.attempt} of {MAX_ATTEMPTS})"
                if self.note:
                    message += f". {self.note}"
            return {"state": self.state, "message": message, "progress_s": round(progress, 1), "need_s": self.learn_seconds,
                    "attempt": self.attempt, "max_attempts": MAX_ATTEMPTS, "found": dict(self.found), "saved": self.saved,
                    "learned_at": self.learned_at, "zones": sorted(rules), "hints": sorted(hints),
                    "best_effort": [k for k in self.zones if k in BEST_EFFORT], "camera": self.key or ""}
