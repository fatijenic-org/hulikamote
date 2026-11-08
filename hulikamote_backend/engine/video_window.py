"""
video_window.py - analyze only part of a video.

The dashboard's trim step sends `trim_start` and `trim_end` (seconds). The analysis then starts at that frame and stops at
that frame, and everything it reports (timestamps, evidence, the result video) counts from the start of the chosen part,
exactly as if the video had been cut there.
"""


def number_or_none(value) -> float | None:
    """A trim value from the config: a number, or None when it is missing or not a number."""
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number and number not in (float("inf"), float("-inf")) else None


def frame_window(fps: float, total_frames: int, trim_start=None, trim_end=None) -> tuple[int, int | None]:
    """(first frame to analyze, how many frames; None = until the video ends).

    No trim gives (0, None). A trim end before the start, or a part with no frame in it, is treated as no end:
    analyzing too much is safer than analyzing nothing."""
    fps = fps if fps and fps > 0 else 30.0
    start = number_or_none(trim_start)
    end = number_or_none(trim_end)
    first = max(0, round(start * fps)) if start and start > 0 else 0
    if end is None or end <= 0:
        return first, None
    last = round(end * fps)
    if total_frames > 0:
        last = min(last, total_frames)
    return (first, last - first) if last > first else (first, None)
