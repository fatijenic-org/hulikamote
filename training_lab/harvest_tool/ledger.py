"""
The labelled ledger: a memory of which pictures were already labelled for which model, kept APART from the inbox database.

Why: the inbox database (harvest_inbox/harvest.db) is a work area and may be cleaned. This ledger is a plain text file
(one JSON line per picture) that survives that. It is matched by the picture's CONTENT (sha1), not its path, so a picture
that was renamed or moved by hand is still recognised.

    training_lab/labelled_ledger/<model>.jsonl          the central ledger, written when a picture is finished and when it is exported
    <destination>/<model>/labelled_ledger.jsonl         a copy written by the export, so the mark travels with the dataset

A picture is "labelled" for ONE model only: labelling it for the plate model does not hide it from the helmet model.
To rebuild a lost central ledger, copy the ledger file(s) from the dataset folder(s) into training_lab/labelled_ledger/.
"""
from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

from .config import Paths

LEDGER_DIR = "labelled_ledger"
COPY_NAME = "labelled_ledger.jsonl"


def ledger_file(paths: Paths, model: str) -> Path:
    return paths.lab / LEDGER_DIR / f"{model}.jsonl"


def digest(path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _append(file: Path, entry: dict) -> None:
    file.parent.mkdir(parents=True, exist_ok=True)
    with open(file, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def record(paths: Paths, model: str, *, sha1: str, name: str, folder: str, size: int, labels: int, blur: int,
           status: str, moved_to: str | None = None, copies: tuple = ()) -> dict:
    """Write one line to the central ledger and to every file in [copies]. status: 'labelled' (finished) or 'exported'."""
    entry = {"model": model, "sha1": sha1, "name": name, "folder": folder, "size": size, "labels": labels, "blur": blur,
             "status": status, "moved_to": moved_to, "when": time.strftime("%Y-%m-%d %H:%M:%S")}
    _append(ledger_file(paths, model), entry)
    for extra in copies:
        _append(Path(extra), entry)
    return entry


def load(paths: Paths, model: str) -> dict[str, dict]:
    """sha1 -> the latest entry, for one model. A line that cannot be read is ignored."""
    file = ledger_file(paths, model)
    known: dict[str, dict] = {}
    if not file.is_file():
        return known
    with open(file, encoding="utf-8") as f:
        for line in f:
            try:
                entry = json.loads(line)
                known[entry["sha1"]] = entry
            except (ValueError, KeyError, TypeError):
                continue
    return known
