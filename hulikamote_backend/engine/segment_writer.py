"""
segment_writer.py - write the raw replay video in short pieces.

An MP4 only opens once its writer is closed (the index is written at the end). One big file therefore
loses EVERYTHING if the run dies or the backend restarts (a 15-minute 4K run lost 7 GB that way).
This writer closes a piece every SEGMENT_SECONDS of video, so a crash loses at most the open piece.
At the end ffmpeg joins the pieces while it makes the web video (see ffmpeg_input()).

The frames are the same frames in the same order, so the result (tickets, photos, video) does not change.
"""
from pathlib import Path
from typing import Callable

import cv2

SEGMENT_SECONDS = 30.0


class SegmentedVideoWriter:
    def __init__(self, folder: Path, fps: float, size: tuple[int, int], seconds: float = SEGMENT_SECONDS,
                 name: str = "evidence_raw", on_part_closed: Callable[[int, int, int], None] | None = None):
        self.folder, self.fps, self.size, self.name = Path(folder), fps, size, name
        self.frames_per_part = max(1, round(fps * seconds))
        self.on_part_closed = on_part_closed          # (part number, first frame, last frame) of the piece just closed
        self.parts: list[Path] = []
        self._writer = None
        self._in_part = 0
        self._written = 0

    def _open(self) -> None:
        path = self.folder / f"{self.name}_part{len(self.parts) + 1:04d}.mp4"
        self._writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), self.fps, self.size)
        self.parts.append(path)
        self._in_part = 0

    def _close(self) -> None:
        if self._writer is None:
            return
        self._writer.release()
        self._writer = None
        if self.on_part_closed and self._in_part:
            self.on_part_closed(len(self.parts), self._written - self._in_part + 1, self._written)

    def write(self, frame) -> None:
        if self._writer is None:
            self._open()
        self._writer.write(frame)
        self._in_part += 1
        self._written += 1
        if self._in_part >= self.frames_per_part:
            self._close()

    def release(self) -> None:
        """Close the open piece (call once, when the video ends or the run stops)."""
        self._close()

    def ffmpeg_input(self) -> list[str]:
        """ffmpeg arguments that read every piece as one video (no copy of the data is made)."""
        listing = self.folder / f"{self.name}_parts.txt"
        listing.write_text("".join(f"file '{p.name}'\n" for p in self.parts), encoding="utf-8")
        return ["-f", "concat", "-safe", "0", "-i", str(listing)]

    def remove_parts(self) -> None:
        for p in self.parts:
            p.unlink(missing_ok=True)
        (self.folder / f"{self.name}_parts.txt").unlink(missing_ok=True)
