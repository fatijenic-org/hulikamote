"""
video_clock.py - what time of day was this video recorded? (rules that only apply at certain hours, e.g. the truck ban)

A violation that depends on the hour needs the real time of the footage. It is never guessed first: the time is taken from
the best source there is, and the source is kept next to the time so a ticket can say where it came from.

The ladder, best first (the first rung that gives a time wins):
  operator   the operator typed when the video started (also the way to SIMULATE an hour for a test or a demo)
  screen     the clock printed in the picture by the camera (OSD). Read with OCR at 3 moments of the video; it counts only
             when two readings agree with the time that really passed between them (a misread digit never passes)
  metadata   the container's own `creation_time` tag (ffprobe). Taken as UTC, shown as Philippine time (UTC+8)
  filename   a date and time in the file name (20261105_074000.mp4, 2026-11-05 07-40-00 ...)
  estimate   no clock anywhere: only "daytime / twilight / night" from how bright the picture is. This is NOT a time:
             `start` stays None, `confirmed` is False, and a rule that needs the hour flags for a human check instead.
If the screen clock and the file's own tag disagree by more than a few minutes the screen clock wins (cameras often write
local time into a field that should hold UTC) and the note says so.

Times are naive local Philippine time (the Philippines has no daylight saving). `start` is the time of the FIRST ANALYSED
frame (the trim start is already added), so `at(seconds)` takes seconds into the analysed part, as the pipeline counts them.
"""
from __future__ import annotations

import json
import logging
import re
import subprocess
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from datetime import time as dtime
from pathlib import Path

import cv2
import numpy as np

log = logging.getLogger("video_clock")

PH = timezone(timedelta(hours=8))          # Philippine time: UTC+8, no daylight saving
EARLIEST_YEAR = 2010                       # a camera with no battery for its clock writes 1970 / 2000: not a real time
SOURCE_LABELS = {
    "operator": "typed by the operator",
    "screen": "read from the clock in the picture",
    "metadata": "read from the video's own information",
    "filename": "read from the file name",
    "live": "this computer's clock",
    "estimate": "estimated from the picture (not a real time)",
    "none": "not found",
}
SCREEN_TOLERANCE_S = 3.0                   # two clock readings must differ from the real elapsed time by no more than this
SCREEN_TOLERANCE_NO_SECONDS_S = 70.0       # ... or this when the screen clock shows no seconds
DISAGREE_S = 300.0                         # screen clock and file tag further apart than this: they disagree


def now_ph() -> datetime:
    """The current Philippine time, naive."""
    return datetime.now(PH).replace(tzinfo=None)


# ─── the clock objects the pipeline reads (`clock.at(seconds)`) ─────────────────────────────────────────────

@dataclass
class ClockInfo:
    """The time of one analysed video. `start` is the time of its first analysed frame, or None when it is not known."""
    start: datetime | None
    source: str = "none"
    confirmed: bool = False          # True: a real time from a real source (not the picture estimate)
    note: str = ""                   # one plain sentence for the operator and the ticket
    daylight: str | None = None      # "day" | "twilight" | "night": from the picture, only when no real time was found

    def at(self, seconds: float) -> datetime | None:
        """The time `seconds` into the analysed part, or None when the start is not known."""
        return None if self.start is None else self.start + timedelta(seconds=float(seconds))

    def to_dict(self) -> dict:
        return {"start": self.start.isoformat(timespec="seconds") if self.start else None, "source": self.source,
                "label": SOURCE_LABELS.get(self.source, self.source), "confirmed": self.confirmed,
                "note": self.note, "daylight": self.daylight}

    @classmethod
    def from_dict(cls, d: dict | None) -> "ClockInfo | None":
        if not d:
            return None
        start = None
        if d.get("start"):
            try:
                start = datetime.fromisoformat(d["start"])
            except ValueError:
                start = None
        return cls(start=start, source=d.get("source") or "none", confirmed=bool(d.get("confirmed")),
                   note=d.get("note") or "", daylight=d.get("daylight"))


class WallClock:
    """Live monitoring: it is "now". The seconds the pipeline passes are ignored."""
    source, confirmed, daylight, note = "live", True, None, "This computer's clock."

    def at(self, seconds: float) -> datetime:
        return now_ph()


class OffsetClock(WallClock):
    """A pretend clock for a live demo: it starts at `start` when it is made and then runs at the speed of real time."""
    source, note = "operator", "A pretend start time was set for this run."

    def __init__(self, start: datetime):
        self._start, self._made = start, now_ph()

    def at(self, seconds: float) -> datetime:
        return self._start + (now_ph() - self._made)


# ─── ban hours: "06:00-09:00", "4 PM-7 PM" ... ─────────────────────────────────────────────────────────────

_HHMM = re.compile(r"^\s*(\d{1,2})(?:\s*[:.]\s*(\d{2}))?\s*([AaPp][Mm])?\s*$")


def parse_minutes(text) -> int | None:
    """"06:00", "6", "6:30 pm", "18.15" -> minutes after midnight; None when it is not a time of day."""
    m = _HHMM.match(str(text)) if text is not None else None
    if not m:
        return None
    hour, minute, ampm = int(m.group(1)), int(m.group(2) or 0), (m.group(3) or "").lower()
    if minute > 59:
        return None
    if ampm:
        if not 1 <= hour <= 12:
            return None
        hour = hour % 12 + (12 if ampm == "pm" else 0)
    if hour > 24 or (hour == 24 and minute):
        return None
    return hour * 60 + minute


def parse_windows(raw) -> list[tuple[int, int]]:
    """[["06:00", "09:00"], ["16:00", "19:00"]] -> [(360, 540), (960, 1140)]. Pairs that do not parse, or whose two ends are
    the same minute, are dropped. A pair whose start is after its end wraps past midnight (22:00-05:00)."""
    out = []
    for pair in raw or []:
        try:
            a, b = parse_minutes(pair[0]), parse_minutes(pair[1])
        except (TypeError, IndexError, KeyError):
            continue
        if a is not None and b is not None and a != b:
            out.append((a, b))
    return out


def in_windows(moment: datetime, windows: list[tuple[int, int]]) -> bool:
    """True when the time of day of `moment` is inside any window (start included, end excluded)."""
    minute = moment.hour * 60 + moment.minute
    for a, b in windows:
        if (a <= minute < b) if a < b else (minute >= a or minute < b):
            return True
    return False


def describe_windows(raw) -> str:
    """"6:00 AM-9:00 AM and 4:00 PM-7:00 PM", or "" when none."""
    def fmt(minutes: int) -> str:
        h, m = divmod(minutes % 1440, 60)
        return f"{(h % 12) or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"
    return " and ".join(f"{fmt(a)}-{fmt(b)}" for a, b in parse_windows(raw))


# ─── reading a time from text ──────────────────────────────────────────────────────────────────────────

_STAMP = re.compile(
    r"(?P<y>20\d{2})\D{0,2}(?P<mo>\d{2})\D{0,2}(?P<d>\d{2})\D{0,3}(?P<h>\d{2})\D{0,2}(?P<mi>\d{2})\D{0,2}(?P<s>\d{2})")
_TIME_HM = re.compile(r"(?<!\d)(\d{1,2})\s*[:;.,]\s*(\d{2})")
_TIME_TAIL = re.compile(r"\s*[:;.,]?\s*(\d{2,4})(?!\d)")        # what follows HH:MM: the seconds, maybe with a misread colon glued on
_AMPM = re.compile(r"\s*([AaPp][Mm])")
_DATE_YMD = re.compile(r"(20\d{2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,2})")
_DATE_DMY = re.compile(r"(?<!\d)(\d{1,2})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(20\d{2})")


def _make(y, mo, d, h, mi, s) -> datetime | None:
    try:
        return datetime(int(y), int(mo), int(d), int(h), int(mi), int(s))
    except ValueError:
        return None


@dataclass(frozen=True)
class ClockReading:
    """One clock read off a picture: the time of day, and the date when the picture showed one."""
    seconds: int                   # seconds after midnight
    has_seconds: bool
    day: date | None = None


def read_clock_text(text: str, loose: bool = False) -> ClockReading | None:
    """A time (and date) found in `text` (what an OCR read off the screen), or None.
    An OCR often reads one separator as another (07:40.06), drops the one in the date (2026-11 05) or turns the last colon into
    a digit (07:402112); all of that is forgiven, because only two readings that agree with the time that passed are believed.
    A time that is not a real time of day (25:70) is refused. A bare "2:11" with no seconds and no date is not a clock but a torn
    piece of one, so it is refused, unless `loose` (what a person typed)."""
    text = text.replace("O", "0").replace("o", "0")          # the digit zero is the letter O to an OCR
    day = None
    rest = text
    m = _DATE_YMD.search(text)
    if m:
        year, month, dom = int(m.group(1)), int(m.group(2)), int(m.group(3))
    else:
        m = _DATE_DMY.search(text)
        if m:
            a, b, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
            # 25/11/2026 can only be day first. 05/11/2026 is ambiguous: month first (how most DVRs print it). Only the
            # time of day matters for a ban hour, so a swapped day and month changes the date shown and nothing else.
            month, dom = (b, a) if a > 12 else (a, b)
    if m:
        try:
            day = date(year, month, dom)
        except ValueError:
            day = None
        rest = text[:m.start()] + " " + text[m.end():]       # the date's own dots and dashes must not read as a time
    hm = _TIME_HM.search(rest)
    if not hm:
        return None
    hour, minute = int(hm.group(1)), int(hm.group(2))
    seconds = None
    after = rest[hm.end():]
    tail = _TIME_TAIL.match(after)
    if tail:
        seconds = int(tail.group(1)[-2:])                    # two digits: the seconds. Three or four: the extra one is a misread colon
        after = after[tail.end():]
    ampm = _AMPM.match(after)
    if not (loose or seconds is not None or day is not None):
        return None
    if ampm:
        if not 1 <= hour <= 12:
            return None
        hour = hour % 12 + (12 if ampm.group(1).lower() == "pm" else 0)
    if hour > 23 or minute > 59 or (seconds is not None and seconds > 59):
        return None
    return ClockReading(seconds=hour * 3600 + minute * 60 + (seconds or 0), has_seconds=seconds is not None, day=day)


def parse_clock_text(text: str, today: datetime | None = None, loose: bool = False) -> tuple[datetime, bool] | None:
    """The same as `read_clock_text`, as a moment: (datetime, has_seconds). A missing date is today's."""
    reading = read_clock_text(text, loose=loose)
    if reading is None:
        return None
    day = reading.day or (today or now_ph()).date()
    return datetime.combine(day, dtime.min) + timedelta(seconds=reading.seconds), reading.has_seconds


def start_from_text(text: str | None, today: datetime | None = None) -> datetime | None:
    """What the operator typed ("7:40", "7:40 AM", "2026-11-05 07:40", "2026-11-05T07:40:00") -> a moment, or None."""
    if not text or not str(text).strip():
        return None
    text = str(text).strip()
    try:
        iso = datetime.fromisoformat(text)
        return iso.astimezone(PH).replace(tzinfo=None) if iso.tzinfo else iso
    except ValueError:
        pass
    found = parse_clock_text(text, today, loose=True)
    return found[0] if found else None


def start_from_filename(name: str | None) -> datetime | None:
    """A date and time inside a file name: 20261105_074000, 2026-11-05 07-40-00, REC_20261105-074000 ..."""
    if not name:
        return None
    m = _STAMP.search(Path(name).stem)
    if not m:
        return None
    moment = _make(m["y"], m["mo"], m["d"], m["h"], m["mi"], m["s"])
    return moment if moment and EARLIEST_YEAR <= moment.year <= now_ph().year + 1 else None


# ─── the video's own information ─────────────────────────────────────────────────────────────────────────

def start_from_metadata(path: Path) -> datetime | None:
    """The `creation_time` tag of the container, in Philippine time (it is stored in UTC), or None."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_entries",
             "format_tags=creation_time:stream_tags=creation_time", str(path)],
            capture_output=True, text=True, timeout=15, check=False).stdout
        info = json.loads(out or "{}")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    tags = [(info.get("format") or {}).get("tags", {}).get("creation_time")]
    tags += [(s.get("tags") or {}).get("creation_time") for s in info.get("streams") or []]
    for raw in tags:
        if not raw:
            continue
        try:
            moment = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        except ValueError:
            continue
        if moment.tzinfo is None:
            moment = moment.replace(tzinfo=timezone.utc)
        local = moment.astimezone(PH).replace(tzinfo=None)
        if EARLIEST_YEAR <= local.year and local <= now_ph() + timedelta(days=1):
            return local
    return None


# ─── the clock printed in the picture ────────────────────────────────────────────────────────────────────

def _regions(frame: np.ndarray) -> list[np.ndarray]:
    """The four corner strips of the picture, where a camera prints its clock, scaled so the OCR sees the text at a good size
    (enlarging a big picture only blurs it and slows the OCR down)."""
    h, w = frame.shape[:2]
    strip_h, strip_w = max(int(h * 0.16), 24), int(w * 0.62)
    crops = [frame[:strip_h, :strip_w], frame[:strip_h, w - strip_w:],
             frame[h - strip_h:, :strip_w], frame[h - strip_h:, w - strip_w:]]
    out = []
    for crop in crops:
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if crop.ndim == 3 else crop
        scale = min(max(1200.0 / max(gray.shape[1], 1), 1.0), 3.0)
        out.append(gray if scale == 1.0 else cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC))
    return out


def _ocr_reader():
    from yolo_inference import get_easyocr_reader          # the plate reader's own EasyOCR, loaded once
    return get_easyocr_reader()


def read_clock_in_frame(frame: np.ndarray, reader) -> list[ClockReading]:
    """Every date-and-time the OCR can read in the corners of one picture."""
    found = []
    for crop in _regions(frame):
        try:
            # width_ths: the date and the time are one line, not two pieces
            text = " ".join(reader.readtext(crop, detail=0, allowlist="0123456789:;.,/-AaPpMm ", width_ths=3.0))
        except Exception as exc:                      # an OCR hiccup on one strip must not stop the others
            log.debug("OCR of a corner failed: %s", exc)
            continue
        reading = read_clock_text(text)
        if reading:
            found.append(reading)
    return found


MAX_SCREEN_LOOKS = 8


def _sample_times(duration: float) -> list[float]:
    """Seconds into the file where the clock is looked at, in the order to try them: the start, the middle, near the end, then
    the quarters and eighths (at least 2 s apart). A real OCR misreads a clock in some pictures, so there are up to 8 chances
    to find two readings that agree."""
    if duration < 3:
        return []
    last = duration - 1.0
    wanted = [0.5, duration * 0.5, last, duration * 0.25, duration * 0.75, duration * 0.125, duration * 0.625, duration * 0.875]
    out: list[float] = []
    for t in wanted:
        t = min(max(t, 0.5), last)
        if all(abs(t - u) >= 2.0 for u in out):
            out.append(t)
    return out[:MAX_SCREEN_LOOKS]


def _agree(a: ClockReading, ta: float, b: ClockReading, tb: float) -> bool:
    """Do two readings fit the time that really passed between their pictures? (the time of day only: the date is often misread)"""
    tolerance = SCREEN_TOLERANCE_S if (a.has_seconds and b.has_seconds) else SCREEN_TOLERANCE_NO_SECONDS_S
    gap = ((a.seconds - ta) - (b.seconds - tb)) % 86400
    return min(gap, 86400 - gap) <= tolerance


def start_from_screen(path: Path, reader=None, today: datetime | None = None) -> tuple[datetime, str] | None:
    """The time at the FIRST FRAME of the file, from the clock the camera printed in the picture, or None.
    Two readings count only when the time between them is what really passed in the video (a misread digit, or a text that is
    not a clock, cannot agree twice). Looks at up to 8 moments and stops at the first agreeing pair. Returns (file start, note)."""
    cap = cv2.VideoCapture(str(path))
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 0
        count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
        if fps <= 0 or count <= 0:
            return None
        reader = reader or _ocr_reader()
        if reader is None:
            return None
        readings: list[tuple[float, ClockReading]] = []      # (seconds into the file, what the clock showed)
        for seconds in _sample_times(count / fps):
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(seconds * fps))
            ok, frame = cap.read()
            if not ok:
                continue
            for reading in read_clock_in_frame(frame, reader):
                for earlier_t, earlier in readings:
                    if earlier_t != seconds and _agree(earlier, earlier_t, reading, seconds):
                        anchor_t, anchor = (earlier_t, earlier) if earlier.day else (seconds, reading)
                        day = anchor.day or (today or now_ph()).date()
                        # a clock shows whole seconds (or minutes): the real moment is half a step later on average
                        rounding = 0.5 if anchor.has_seconds else 30.0
                        start = datetime.combine(day, dtime.min) + timedelta(seconds=anchor.seconds - anchor_t + rounding)
                        return start, "Two readings of the clock in the picture agree with the time that passed."
                readings.append((seconds, reading))
    finally:
        cap.release()
    return None


# ─── no clock at all: how bright is it? ─────────────────────────────────────────────────────────────────

def estimate_daylight(path: Path, samples: int = 5) -> str | None:
    """"day", "twilight" or "night" from the brightness of a few pictures, or None when the video cannot be read.
    This is only a hint for the operator. It cannot tell 8 AM from 10 AM, so it is never used as a time."""
    cap = cv2.VideoCapture(str(path))
    try:
        count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        levels = []
        for i in range(samples):
            if count > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, int(count * (i + 0.5) / samples))
            ok, frame = cap.read()
            if not ok:
                continue
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            top = gray[: max(gray.shape[0] // 3, 1)]               # the sky and the far road
            levels.append(0.5 * float(gray.mean()) + 0.5 * float(top.mean()))
    finally:
        cap.release()
    if not levels:
        return None
    level = float(np.median(levels))
    return "night" if level < 55 else "twilight" if level < 90 else "day"


# ─── putting it together ─────────────────────────────────────────────────────────────────────────────────

def _at(moment: datetime) -> str:
    return moment.strftime("%I:%M %p").lstrip("0")


def resolve_clock(video_path: str | Path, *, start_text: str | None = None, name: str | None = None,
                  trim_start: float = 0.0, reader=None, use_screen: bool = True) -> ClockInfo:
    """The time of the analysed part of a video, from the best source there is (see the ladder at the top of this file).
    `name` is the file's real name when `video_path` is a renamed copy (an upload). Never raises."""
    path = Path(video_path)
    shift = timedelta(seconds=max(float(trim_start or 0.0), 0.0))

    def made(source: str, file_start: datetime, note: str) -> ClockInfo:
        start = file_start + shift
        return ClockInfo(start=start, source=source, confirmed=True,
                         note=f"{_at(start)} at the start of the analysed part, {SOURCE_LABELS[source]}. {note}".strip())

    try:
        typed = start_from_text(start_text)
        if typed is not None:
            return made("operator", typed, "")
        if start_text and str(start_text).strip():
            log.warning("The start time %r could not be read; looking in the video instead.", start_text)

        screen = start_from_screen(path, reader) if use_screen else None
        meta = start_from_metadata(path)
        if screen is not None:
            note = screen[1]
            if meta is not None and abs((meta - screen[0]).total_seconds()) > DISAGREE_S:
                note += (f" The video's own information says {_at(meta)}, so it was not used (cameras often write local "
                         "time where UTC belongs).")
            elif meta is not None:
                note += " It matches the video's own information."
            return made("screen", screen[0], note)
        if meta is not None:
            return made("metadata", meta, "The file information is taken as UTC and shown as Philippine time.")
        named = start_from_filename(name or path.name)
        if named is not None:
            return made("filename", named, "")
    except Exception:
        log.exception("Reading the time of %s failed", path)

    daylight = None
    try:
        daylight = estimate_daylight(path)
    except Exception:
        log.exception("Estimating the daylight of %s failed", path)
    seen = {"day": " The picture looks like daytime.", "twilight": " The picture looks like dawn or dusk.",
            "night": " The picture looks like night."}.get(daylight or "", "")
    return ClockInfo(start=None, source="estimate" if daylight else "none", confirmed=False, daylight=daylight,
                     note="No time was found in the video." + seen)


def clock_wanted(config: dict) -> bool:
    """Does this run need the time of its video? Yes when the operator typed a start time, or a switched-on rule has ban hours."""
    if str(config.get("video_start") or "").strip():
        return True
    per_rule = config.get("per_violation_configs") or {}
    return any(parse_windows((per_rule.get(key) or {}).get("ban_windows")) for key in config.get("active_violations") or [])


def hours_matter(config: dict, violations) -> bool:
    """Is any of these violations one that has ban hours in this run? Then its ticket depends on the time of day."""
    per_rule = config.get("per_violation_configs") or {}
    return any(parse_windows((per_rule.get(key) or {}).get("ban_windows")) for key in violations or [])


def _first_t(ticket: dict) -> float | None:
    times = [m["t"] for m in ticket.get("evidence_meta", []) if m.get("t") is not None]
    return min(times) if times else None


def ticket_time(clock: dict | None, seconds: float | None, hours_matter: bool = False) -> dict | None:
    """The `time` entry of a ticket whose first evidence photo is `seconds` into the analysed part:
    {"at": ISO local time, "source", "label", "confirmed", "start": the clock's start} when the time is known.
    When it is NOT known and the ticket depends on the hour (`hours_matter`) it is {"at": None, ..., "needs_check": True,
    "note"} so a human checks it; otherwise None."""
    info = ClockInfo.from_dict(clock)
    if info is None:
        return None
    moment = info.at(seconds) if seconds is not None else None
    base = {"source": info.source, "label": SOURCE_LABELS.get(info.source, info.source), "confirmed": info.confirmed,
            "start": info.start.isoformat(timespec="seconds") if info.start else None}
    if moment is None:
        if not hours_matter:
            return None
        return {"at": None, **base, "confirmed": False, "needs_check": True, "note": info.note}
    return {"at": moment.isoformat(timespec="seconds"), **base}


def retime(ticket: dict) -> None:
    """After tickets were joined or split: the time of a ticket is the time of its first photo (in place; nothing to do for a
    ticket that has no known clock start)."""
    time = ticket.get("time")
    first = _first_t(ticket)
    if not time or not time.get("start") or first is None:
        return
    try:
        at = (datetime.fromisoformat(time["start"]) + timedelta(seconds=first)).isoformat(timespec="seconds")
    except ValueError:
        return
    ticket["time"] = {**time, "at": at}      # a new dict: a split leaves two tickets sharing the old one


def earlier_time(a: dict | None, b: dict | None) -> dict | None:
    """Of two ticket times (a merge) the one that is known and earlier; a human check on either one stays."""
    known = [t for t in (a, b) if t and t.get("at")]
    pick = min(known, key=lambda t: t["at"]) if known else (a or b)
    if pick is None:
        return None
    out = dict(pick)
    if (a or {}).get("needs_check") or (b or {}).get("needs_check"):
        out["needs_check"] = True
        out["note"] = (a or {}).get("note") or (b or {}).get("note") or ""
    return out
