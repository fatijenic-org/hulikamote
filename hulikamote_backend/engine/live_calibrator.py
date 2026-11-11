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

"Detect road" (begin_detect): the operator freezes a frame, the road is read from the last ~40 s kept in a rolling buffer, and every
step of the finder is handed back as a picture (road_lines.WALKTHROUGH) for the dashboard to play one at a time. Apply makes what was found
the live rules; Discard drops it.

Needs what the finder needs: a fixed camera, some traffic in the first 30-40 s, a level camera, daylight.
Thread safety: feed() is called from the live loop; analysis runs in its own thread; every state change is under one lock.
"""
from __future__ import annotations

import bisect
import json
import logging
import os
import threading
import time
from collections import deque
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
ZONE_KINDS = ("crosswalk", "road", "sidewalk")                 # what the operator may correct after a detection
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

def crosswalk_verdict(c: dict, top_width: float) -> str | None:
    """None when a crosswalk is believed, else the reason it is ignored."""
    if not (c["stripes"] >= MIN_STRIPES or (c["stripes"] >= 4 and c["score"] >= STRONG_FOUR)):
        return "too few stripes"
    if c["top"]["u1"] - c["top"]["u0"] < MIN_CROSSWALK_WIDTH * top_width:
        return "too narrow to span the road"
    return None


def stop_line_ok(line: dict, top_width: float) -> bool:
    return line["length"] >= MIN_STOP_LENGTH * top_width


def solid_line_ok(line: dict, top_depth: float) -> bool:
    return (line["style"] == "solid" and line["coverage"] >= MIN_SOLID_COVERAGE
            and abs(line["top"]["v1"] - line["top"]["v0"]) >= MIN_SOLID_REACH * top_depth)


def accept(result: dict) -> tuple[dict, dict]:
    """(zones, counts) from a road_lines result: only the marks that are clear enough. Zones are in the wizard's shape and
    1920x1080 reference space; counts say what was found ({"crosswalks", "stop_lines", "solid_lines"}). Nothing guessed."""
    from engine.road_lines import reference_zones
    if not result.get("ok"):
        return {}, {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}
    tw, th = result["rectifier"]["top_size"]
    crosswalks = [c for c in result["crosswalks"] if crosswalk_verdict(c, tw) is None]
    stops = [s for s in result["stop_lines"] if stop_line_ok(s, tw)]
    solid = [ln for ln in result["lane_lines"] if solid_line_ok(ln, th)]
    trimmed = {**result, "crosswalks": crosswalks, "stop_lines": stops, "lane_lines": solid}
    zones = {key: value for key, value in reference_zones(trimmed).items() if key in LEARNABLE}
    return zones, {"crosswalks": len(crosswalks), "stop_lines": len(stops), "solid_lines": len(solid)}


def _make_detector():
    """A function frame -> [(class name, [x, y, w, h])] that only looks (the live tracking is left alone), or None when the detector is not
    available. It lets the road scan tell vehicles from people."""
    try:
        from yolo_inference import get_inference
        engine = get_inference()
        return lambda frame: [(d.cls, d.bbox) for d in engine.infer(frame, track=False)]
    except Exception:
        log.exception("Detect road: the detector is not available, so no road and sidewalk areas")
        return None


def editable_zones(result: dict, size: tuple[int, int]) -> list[dict]:
    """What the operator can correct, in the pixels of the frozen picture: the crosswalks that will be used, the road and the sidewalks."""
    vw, vh = result["video_size"]
    sx, sy = size[0] / vw, size[1] / vh
    tw = result["rectifier"]["top_size"][0]

    def pts(points):
        return [[round(x * sx, 1), round(y * sy, 1)] for x, y in points]
    out, n = [], 0
    for c in result["crosswalks"]:
        if len(c.get("polygon") or []) >= 3 and crosswalk_verdict(c, tw) is None:
            n += 1
            out.append({"id": f"crosswalk-{n}", "kind": "crosswalk", "polygon": pts(c["polygon"])})
    for k, region in enumerate(result.get("regions") or [], 1):
        out.append({"id": f"{region['kind']}-{k}", "kind": region["kind"], "polygon": pts(region["polygon"]),
                    **({"side": region["side"]} if region.get("side") else {})})
    return out


def clean_zones(zones, size: tuple[int, int]) -> list[dict] | None:
    """The operator's corrected areas, checked and kept inside the picture. None when something is not valid."""
    if not isinstance(zones, list) or len(zones) > 24:
        return None
    w, h = size
    out, seen = [], set()
    for i, z in enumerate(zones):
        if not isinstance(z, dict) or z.get("kind") not in ZONE_KINDS:
            return None
        points = z.get("polygon")
        if not isinstance(points, list) or not 3 <= len(points) <= 16:
            return None
        try:
            poly = [[round(min(max(float(x), 0.0), w - 1.0), 1), round(min(max(float(y), 0.0), h - 1.0), 1)] for x, y in points]
        except (TypeError, ValueError):
            return None
        zid = str(z.get("id") or f"{z['kind']}-{i + 1}")[:40]
        if zid in seen:
            zid = f"{zid}-{i + 1}"
        seen.add(zid)
        out.append({"id": zid, "kind": z["kind"], "polygon": poly, **({"side": z["side"]} if z.get("side") in ("left", "right") else {})})
    return out


def _label(img: np.ndarray, text: str, at: tuple[int, int], colour: tuple) -> None:
    (tw, th), base = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
    x, y = max(4, at[0]), max(th + 8, at[1])
    cv2.rectangle(img, (x - 4, y - th - 6), (x + tw + 4, y + base), (0, 0, 0, 200), -1)
    cv2.putText(img, text, (x, y - 2), cv2.FONT_HERSHEY_SIMPLEX, 0.8, colour, 2, cv2.LINE_AA)


def marks_overlay(result: dict, colour_size: tuple[int, int], lines_are_rules: bool) -> tuple[np.ndarray, list[dict]]:
    """The finished picture of a detection, BGRA at the colour-frame size: crosswalks that will be used (cyan, filled), marks that were
    found but are ignored (red outline, with the reason), stop and solid lines (amber: a rule, or "hint" when they are not rules).
    Also a plain list of what was drawn, for the dashboard."""
    cw, ch = colour_size
    vw, vh = result["video_size"]
    sx, sy = cw / vw, ch / vh
    tw, th = result["rectifier"]["top_size"]
    out = np.zeros((ch, cw, 4), np.uint8)
    marks: list[dict] = []

    def pts(points):
        return np.array([[x * sx, y * sy] for x, y in points], np.int32)
    cyan, amber, red, grey = (255, 255, 0, 255), (0, 170, 255, 255), (70, 70, 255, 255), (190, 190, 190, 255)
    blue, green = (255, 140, 30, 255), (60, 220, 60, 255)
    for region in result.get("regions") or []:                          # the road and the sidewalks, under everything else
        if len(region.get("polygon") or []) < 3:
            continue
        poly, colour = pts(region["polygon"]), (blue if region["kind"] == "road" else green)
        cv2.fillPoly(out, [poly], colour[:3] + (60,))
        cv2.polylines(out, [poly], True, colour, 4, cv2.LINE_AA)
        _label(out, "Road" if region["kind"] == "road" else "Sidewalk", (int(poly[:, 0].min()) + 8, int(poly[:, 1].min()) + 34), colour)
        marks.append({"kind": region["kind"], "status": "draft"})
    for c in result["crosswalks"]:
        if len(c.get("polygon") or []) < 3:
            continue                                                  # no outline to draw
        poly, why = pts(c["polygon"]), crosswalk_verdict(c, tw)
        top_left = (int(poly[:, 0].min()), int(poly[:, 1].min()) - 4)
        if why is None:
            cv2.fillPoly(out, [poly], (255, 255, 0, 90))
            cv2.polylines(out, [poly], True, cyan, 4, cv2.LINE_AA)
            _label(out, "Crosswalk", top_left, cyan)
            marks.append({"kind": "crosswalk", "status": "rule", "stripes": c["stripes"]})
        else:
            cv2.polylines(out, [poly], True, red, 3, cv2.LINE_AA)
            _label(out, f"Ignored: {why}", top_left, red)
            marks.append({"kind": "crosswalk", "status": "ignored", "why": why, "stripes": c["stripes"]})
    kind = "rule" if lines_are_rules else "hint"
    for line in result["stop_lines"]:
        if not stop_line_ok(line, tw):
            continue
        a, b = (tuple(int(v) for v in pts([line["p0"], line["p1"]])[i]) for i in (0, 1))
        cv2.line(out, a, b, amber, 6, cv2.LINE_AA)
        _label(out, f"Stop line ({kind})", (min(a[0], b[0]), min(a[1], b[1]) - 6), amber)
        marks.append({"kind": "stop_line", "status": kind})
    for line in result["lane_lines"]:
        a, b = (tuple(int(v) for v in pts([line["p0"], line["p1"]])[i]) for i in (0, 1))
        if solid_line_ok(line, th):
            cv2.line(out, a, b, amber, 6, cv2.LINE_AA)
            _label(out, f"Solid line ({kind})", (min(a[0], b[0]), min(a[1], b[1]) - 6), amber)
            marks.append({"kind": "solid_line", "status": kind})
        else:
            cv2.line(out, a, b, grey, 2, cv2.LINE_AA)
            marks.append({"kind": "lane_line", "status": "ignored", "why": line["style"] if line["style"] != "solid" else "faint"})
    return out, marks


def _png(overlay: np.ndarray | None) -> bytes | None:
    if overlay is None:
        return None
    ok, data = cv2.imencode(".png", overlay, [cv2.IMWRITE_PNG_COMPRESSION, 3])
    return data.tobytes() if ok else None


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
        self._ring_g: deque = deque()                      # (t, small grey picture): the last learn_seconds of the camera
        self._ring_c: deque = deque()                      # (t, colour picture at the finder's working width)
        self._ring_last_g: float | None = None
        self._ring_last_c: float | None = None
        self._ring_size: tuple[int, int] | None = None
        self._last_frame: np.ndarray | None = None         # the newest full picture (a reference, not a copy)
        self._detect: dict | None = None                   # the "Detect road" session, see begin_detect
        self._detect_n = 0
        self._reset_state()

    # ── state ──
    def _reset_state(self) -> None:
        self.state = "off"                                 # off | learning | analysing | ready | empty | refused | error
        self.message = ""
        self.note = ""                                     # why a learning window (re)started
        self.attempt = 0
        self.zones: dict[str, list[dict]] = {}             # everything accepted (installed ones and hints)
        self.found = {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}
        self.regions: list[dict] = []                      # road and sidewalks (drawn only, in the 1920x1080 reference space)
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
            self._ring_clear()
            self._detect = None
            saved = load_saved(key, self.config_path)
            if saved is not None:
                self._set_zones(dict(saved["zones"]))
                self.regions = [r for r in (saved.get("regions") or []) if isinstance(r, dict) and r.get("polygon")]
                self.found = dict(saved.get("found") or self.found)
                self.saved, self.learned_at = True, saved.get("learned_at")
                self._view_hash = saved.get("view_hash")
                self.state = "ready" if (self.zones or self.regions) else "empty"
                self.message = (f"Road loaded (saved for this camera): {self._summary()}" if (self.zones or self.regions)
                                else "Saved for this camera: no clear crosswalk or line was found")
                self._verify = [] if self._view_hash else None
            else:
                self._start_learning(1)

    def detach(self) -> None:
        """The camera disconnected: stop collecting. What is learned stays (it is the same camera when it comes back)."""
        with self._lock:
            self._clear_buffers()
            self._ring_clear()
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
        if frame is None or self.key is None:
            return
        t = time.monotonic() if t is None else float(t)
        with self._lock:
            self._last_frame = frame
            self._ring_add(frame, t)
            if self._detect is not None and self._detect["state"] == "collecting":
                self._detect_check(t)
            if self.state not in ("learning", "ready", "empty"):
                return
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

    def region_overlay(self, frame_w: int, frame_h: int) -> list[dict]:
        """The saved road and sidewalks, on the processed frame, for the live picture (drawn only: no rule uses them yet)."""
        with self._lock:
            regions = list(self.regions)
        sx, sy = frame_w / REFERENCE[0], frame_h / REFERENCE[1]
        return [{"violation": r["kind"], "polygon": [[int(x * sx), int(y * sy)] for x, y in r["polygon"]], "line": None,
                 "best_effort": False, "hint": False} for r in regions]

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

    # ── the rolling buffer: the last learn_seconds of the camera, for "Detect road" ──
    def _ring_clear(self) -> None:
        self._ring_g.clear()
        self._ring_c.clear()
        self._ring_last_g = self._ring_last_c = self._ring_size = None
        self._last_frame = None

    def _ring_add(self, frame: np.ndarray, t: float) -> None:
        from engine.road_lines import WORK_W, _even
        h, w = frame.shape[:2]
        if self._ring_size is not None and self._ring_size != (w, h):    # the stream changed size: nothing mixes
            self._ring_g.clear()
            self._ring_c.clear()
            self._ring_last_g = self._ring_last_c = None
        self._ring_size = (w, h)
        if self._ring_last_g is not None and t - self._ring_last_g < PICTURE_GAP:
            return
        self._ring_last_g = t
        self._ring_g.append((t, self._small_grey(frame)))
        if self._ring_last_c is None or t - self._ring_last_c >= self.learn_seconds / COLOUR_PICTURES:
            self._ring_last_c = t
            self._ring_c.append((t, cv2.resize(frame, (WORK_W, _even(h * WORK_W / w)), interpolation=cv2.INTER_AREA)))
        horizon = t - self.learn_seconds
        while self._ring_g and self._ring_g[0][0] < horizon:
            self._ring_g.popleft()
        while self._ring_c and self._ring_c[0][0] < horizon:
            self._ring_c.popleft()

    def _ring_span(self) -> float:
        return (self._ring_g[-1][0] - self._ring_g[0][0]) if len(self._ring_g) > 1 else 0.0

    def _ring_ready(self) -> bool:
        return len(self._ring_g) >= 16 and bool(self._ring_c) and self._ring_span() >= 0.9 * self.learn_seconds

    def _ring_clip(self) -> dict:
        """The buffer as the clip dict road_lines.analyse_clip reads."""
        times = [t for t, _g in self._ring_g]
        greys = [g for _t, g in self._ring_g]
        colours = [c for _t, c in self._ring_c]
        colour_at = [min(bisect.bisect_left(times, t), len(times) - 1) for t, _c in self._ring_c]
        return {"video": self._ring_size, "fps": 8.0, "seconds": len(greys) / 8.0, "colours": colours, "colour_at": colour_at,
                "greys": greys, "grey_size": (greys[0].shape[1], greys[0].shape[0]),
                "colour_size": (colours[0].shape[1], colours[0].shape[0])}

    # ── "Detect road": freeze a frame, read the road, show every step ──
    def begin_detect(self) -> dict:
        """The operator pressed Detect road. The newest picture is frozen (it is what the walkthrough is drawn on); the road is read from the
        last learn_seconds of the camera, once that much has been seen. Steps and their pictures appear in detect_status() as they finish."""
        from engine.road_lines import WALKTHROUGH
        with self._lock:
            if self.key is None or self._last_frame is None:
                return {"ok": False, "reason": "There is no picture from the camera yet."}
            if self._detect is not None and self._detect["state"] in ("collecting", "analysing"):
                return {"ok": False, "reason": "The road is already being read."}
            frame = self._last_frame
            h, w = frame.shape[:2]
            if w > 1280:
                frame, (w, h) = cv2.resize(frame, (1280, int(round(h * 1280 / w))), interpolation=cv2.INTER_AREA), (1280, int(round(h * 1280 / w)))
            ok, jpg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 88])
            self._detect_n += 1
            self._detect = {
                "id": self._detect_n, "state": "collecting", "frame": jpg.tobytes() if ok else b"", "size": [w, h], "reason": None,
                "steps": {sid: {"id": sid, "title": title, "about": about, "state": "waiting", "overlay": None, "info": {}}
                          for sid, title, about in WALKTHROUGH},
                "found": {"crosswalks": 0, "stop_lines": 0, "solid_lines": 0}, "zones": {}, "rules": [], "hints": [],
                "editable": [], "edited": False, "background": None, "applied": False, "started": self._ring_last_g if self._ring_last_g is not None else 0.0}
            self._detect_check(self._ring_last_g if self._ring_last_g is not None else 0.0)
            return {"ok": True, "detect": self._detect_status()}

    def _detect_check(self, t: float) -> None:
        d = self._detect
        if d is None or d["state"] != "collecting":
            return
        if self._ring_ready():
            clip, did = self._ring_clip(), d["id"]
            d["state"] = "analysing"
            if self._background:
                threading.Thread(target=self._detect_run, args=(clip, did), daemon=True, name="road-detect").start()
            else:
                self._detect_run(clip, did)
        elif t - d["started"] >= MAX_LEARN_SECONDS:
            d["state"] = "failed"
            d["reason"] = "The camera gave too few pictures to read the road."
            for step in d["steps"].values():
                step["state"] = "skipped"

    def _detect_run(self, clip: dict, did: int) -> None:
        def trace(step: str, phase: str, overlay, info: dict) -> None:
            with self._lock:
                d = self._detect
                state = None if d is None or d["id"] != did else d["steps"].get(step)
                if state is None:
                    return
                if phase == "start":
                    state["state"] = "running"
                else:
                    state.update(state="done", info=info, overlay=_png(overlay))
        error = None
        try:
            analyse, extra = self._analyse, {}
            if analyse is None:
                from engine.road_lines import analyse_clip as analyse
                extra["detector"] = _make_detector()
            result, background = analyse(clip, trace=trace, **extra)
        except Exception as exc:
            log.exception("Detect road failed")
            result, background, error = None, None, f"Could not read the road ({exc})"
        with self._lock:
            d = self._detect
            if d is None or d["id"] != did:
                return                                          # discarded, or replaced by a newer detection
            if error is not None or result is None or not result.get("ok"):
                d["state"] = "failed"
                d["reason"] = error or (result or {}).get("reason") or "The road could not be read."
                for step in d["steps"].values():
                    if step["state"] in ("waiting", "running"):
                        step["state"] = "skipped"
                return
            try:
                zones, found = accept(result)
                lines_are_rules = self._lines_are_rules()
                overlay, marks = marks_overlay(result, clip["colour_size"], lines_are_rules)
                d["steps"]["marks"].update(state="done", overlay=_png(overlay), info={"marks": marks})
                rules = [k for k in zones if k not in BEST_EFFORT or lines_are_rules]
                d.update(state="done", zones=zones, found=found, rules=sorted(rules), hints=sorted(set(zones) - set(rules)),
                         background=background, editable=editable_zones(result, tuple(d["size"])), edited=False)
            except Exception as exc:                                   # never leave a detection stuck on "analysing"
                log.exception("Detect road: drawing the result failed")
                d["state"] = "failed"
                d["reason"] = f"Could not draw the result ({exc})"
                d["steps"]["marks"]["state"] = "skipped"

    def _detect_status(self) -> dict:
        d = self._detect
        if d is None:
            return {"state": "none"}
        return {"id": d["id"], "state": d["state"], "size": d["size"], "reason": d["reason"], "found": dict(d["found"]),
                "rules": list(d["rules"]), "hints": list(d["hints"]), "applied": d["applied"],
                "zones": [dict(z) for z in d["editable"]], "edited": d["edited"],
                "progress_s": round(min(self.learn_seconds, self._ring_span()), 1), "need_s": self.learn_seconds,
                "steps": [{"id": st["id"], "title": st["title"], "about": st["about"], "state": st["state"],
                           "has_overlay": st["overlay"] is not None, "info": st["info"]} for st in d["steps"].values()]}

    def detect_status(self) -> dict:
        with self._lock:
            return self._detect_status()

    def detect_frame(self) -> bytes | None:
        with self._lock:
            return self._detect["frame"] if self._detect else None

    def detect_overlay(self, step: str) -> bytes | None:
        with self._lock:
            st = self._detect["steps"].get(step) if self._detect else None
            return st["overlay"] if st else None

    def discard_detect(self) -> bool:
        with self._lock:
            had = self._detect is not None
            self._detect = None
            return had

    def set_detect_zones(self, zones) -> dict:
        """The operator corrected the draft (moved corners, deleted or relabelled an area). Apply uses these from now on."""
        with self._lock:
            d = self._detect
            if d is None or d["state"] != "done":
                return {"ok": False, "reason": "There is no finished detection to correct."}
            clean = clean_zones(zones, tuple(d["size"]))
            if clean is None:
                return {"ok": False, "reason": "Those areas are not valid: each needs a kind (crosswalk, road or sidewalk) and 3 to 16 corners."}
            d["editable"], d["edited"] = clean, True
            return {"ok": True, "zones": [dict(z) for z in clean]}

    def _apply_set(self, d: dict) -> tuple[dict, list[dict], dict]:
        """(rule zones, road and sidewalk areas, counts) of a detection, with the operator's corrections in, in the 1920x1080 reference space."""
        w, h = d["size"]
        sx, sy = REFERENCE[0] / w, REFERENCE[1] / h

        def ref(poly):
            return [[round(x * sx, 1), round(y * sy, 1)] for x, y in poly]
        zones, found = dict(d["zones"]), dict(d["found"])
        if d["edited"]:
            zones.pop("pedestrian_lane", None)
            walks = [z for z in d["editable"] if z["kind"] == "crosswalk"]
            if walks:
                zones["pedestrian_lane"] = [{"polygon": ref(z["polygon"])} for z in walks]
            found["crosswalks"] = len(walks)
        regions = [{"kind": z["kind"], "polygon": ref(z["polygon"]), **({"side": z["side"]} if z.get("side") else {})}
                   for z in d["editable"] if z["kind"] in ("road", "sidewalk")]
        return zones, regions, found

    def apply_detect(self) -> dict:
        """Make what the detection found (with the operator's corrections) the camera's road: saved for this camera and used by the live rules
        (crosswalk -> Pedestrian lane; lines stay hints unless learned_lines_as_rules is set). The road and sidewalks are saved and drawn.
        The caller switches the matching violations on."""
        with self._lock:
            d = self._detect
            if d is None or d["state"] != "done":
                return {"ok": False, "reason": "There is no finished detection to apply."}
            zones, regions, found = self._apply_set(d)
            if not zones and not regions:
                return {"ok": False, "reason": "No clear crosswalk, line, road or sidewalk is left, so there is nothing to apply."}
            self._epoch += 1                                          # an automatic reading under way is now out of date
            self._clear_buffers()
            self.found = found
            self.regions = regions
            self.learned_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
            self.saved = False
            if d["background"] is not None:
                self._view_hash = view_hash(_grey(d["background"]))
            self._set_zones(zones)
            self.state = "ready"
            self.message = f"Road applied: {self._summary()}" if zones else f"Road applied: {len(regions)} road and sidewalk area(s)"
            if self.key:
                try:
                    save_road(self.key, {"zones": self.zones, "regions": regions, "edited": bool(d["edited"]), "found": self.found,
                                         "learned_at": self.learned_at, "frame_size": list(self._ring_size or []), "view_hash": self._view_hash},
                              self.config_path)
                except OSError:
                    log.exception("Live road: could not save the applied road")
            d["applied"] = True
            return {"ok": True, "zones": sorted(self._split()[0])}
