"""
reid.py - Public vehicle-identity pictures for the ReID ("is it the same car?") model.

Layout (same shape as datasets/reid, which holds YOUR reviewed Zamboanga cars):
    datasets/reid_public/images/<source id>/<identity>/<picture>.jpg
Public identities are kept in their own folder so a new model's held-out score is still measured on real cars.
A few pictures per identity are taken from different cameras, straight out of the remote zip (no 2 GB download).
"""
from __future__ import annotations

import json
import re
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path

from .common import DATASETS, inspect_image

NAME = re.compile(r"^(?P<identity>\d+)_(?P<camera>[^_]+)_")


def pick(names: list[str], per_identity: int) -> dict[str, list[str]]:
    """
    Up to `per_identity` file names per identity, taken round-robin over cameras (so one car is seen from
    different places), in a fixed order so a re-run picks the same pictures.
    names look like  images/train/0001_c010_000560.jpg  ->  identity 0001, camera c010.
    """
    by_id: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for full in sorted(names):
        m = NAME.match(full.rsplit("/", 1)[-1])
        if m:
            by_id[m["identity"]][m["camera"]].append(full)
    chosen: dict[str, list[str]] = {}
    for identity, cams in sorted(by_id.items()):
        lists = [cams[c] for c in sorted(cams)]
        out: list[str] = []
        i = 0
        while len(out) < per_identity and any(lists):
            lst = lists[i % len(lists)]
            if lst:
                out.append(lst.pop(len(lst) // 2))      # the middle one: not the first / last (often a blurry frame)
            i += 1
        chosen[identity] = out
    return chosen


def fetch(src: dict, log=print) -> Path:
    """Needs: record (Zenodo id), file (zip name), per_identity. Optional: min_side."""
    from remotezip import RemoteZip
    from .sources import _json
    out = DATASETS / "reid_public" / "images" / src["id"]
    if (out / "SOURCE.json").exists():
        return out
    rec = _json(f"https://zenodo.org/api/records/{src['record']}")
    entry = next(f for f in rec["files"] if f["key"] == src["file"])
    url = entry["links"]["self"]
    for attempt in range(5):
        try:
            with RemoteZip(url) as z:
                names = [i.filename for i in z.infolist() if i.filename.lower().endswith((".jpg", ".jpeg", ".png"))]
            break
        except Exception:
            if attempt == 4:
                raise
            time.sleep(4 * (attempt + 1))
    chosen = pick(names, int(src.get("per_identity", 12)))
    todo = [(identity, full) for identity, files in chosen.items() for full in files]
    log(f"    {len(chosen)} identities, {len(todo)} pictures to fetch from {src['file']} (partial download)")
    min_side = int(src.get("min_side", 40))
    local = threading.local()
    lock = threading.Lock()
    stats = {"saved": 0, "too_small": 0, "unreadable": 0, "network_failed": 0}

    def job(item: tuple[str, str]) -> None:
        identity, full = item
        dst = out / identity / full.rsplit("/", 1)[-1]
        if dst.exists():
            return
        data = None
        for attempt in range(5):                       # a dropped connection or DNS hiccup: new connection, try again
            try:
                if not hasattr(local, "zip"):
                    local.zip = RemoteZip(url)
                data = local.zip.read(full)
                break
            except Exception:
                if hasattr(local, "zip"):
                    del local.zip
                time.sleep(2 * (attempt + 1))
        if data is None:
            with lock:
                stats["network_failed"] += 1
            return
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
        info = inspect_image(dst)
        with lock:
            if info is None:
                stats["unreadable"] += 1
                dst.unlink()
            elif min(info["w"], info["h"]) < min_side:
                stats["too_small"] += 1
                dst.unlink()
            else:
                stats["saved"] += 1

    with ThreadPoolExecutor(max_workers=int(src.get("workers", 8))) as pool:
        for n, _ in enumerate(pool.map(job, todo), 1):
            if n % 1000 == 0:
                log(f"      {n:,} / {len(todo):,}")
    keep = {(identity, full.rsplit("/", 1)[-1]) for identity, full in todo}
    for d in [d for d in out.iterdir() if d.is_dir()]:                  # surplus pictures of an earlier run with a bigger sample
        for f in d.glob("*.*"):
            if (d.name, f.name) not in keep:
                f.unlink()
                stats["trimmed"] = stats.get("trimmed", 0) + 1
    identities = sum(1 for d in out.iterdir() if d.is_dir() and any(d.iterdir()))
    pictures = sum(1 for _ in out.rglob("*.jpg"))
    if stats["network_failed"]:
        raise RuntimeError(f"{stats['network_failed']} pictures could not be fetched (network): run again to resume")
    (out / "SOURCE.json").write_text(json.dumps({
        "id": src["id"], "retrieved": date.today().isoformat(), "host": "zenodo", "url": f"https://zenodo.org/records/{src['record']}",
        "doi": rec.get("doi"), "license": src.get("license"), "trust": src.get("trust"), "notes": src.get("notes"),
        "citation": src.get("citation"), "identities": identities, "pictures": pictures, "stats": stats,
        "per_identity": src.get("per_identity", 12)}, indent=2, ensure_ascii=False), encoding="utf-8")
    return out
