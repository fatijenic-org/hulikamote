"""
video_fingerprint.py - a quick fingerprint of a video FILE, so a saved setup (violations, road) can be offered again when the same video is used.

The fingerprint is made of the size of the file and three pieces of it (start, middle, end), not of its name or place: the same video under another
name or in another folder gives the same fingerprint. It reads about 3 MB, so it is instant even for a big file. Only local files have one.
"""
import hashlib
import os
from pathlib import Path

CHUNK = 1024 * 1024


def fingerprint(path) -> dict | None:
    """{"hash", "name", "size"} of the video file at `path`; None when it is not a readable local file."""
    try:
        p = Path(str(path))
        if not p.is_file():
            return None
        size = p.stat().st_size
        digest = hashlib.sha1(str(size).encode("ascii"))
        with open(p, "rb") as fh:
            for offset in (0, max(0, size // 2 - CHUNK // 2), max(0, size - CHUNK)):
                fh.seek(offset)
                digest.update(fh.read(CHUNK))
        return {"hash": digest.hexdigest()[:20], "name": p.name, "size": size}
    except (OSError, ValueError):
        return None


def of_source(source) -> dict | None:
    """The fingerprint of the Live Monitor's source (None for a camera, an address or a webcam number)."""
    text = str(source or "")
    if text.startswith(("rtsp://", "http://", "https://")) or text.isdigit() or not os.path.exists(text):
        return None
    return fingerprint(text)
