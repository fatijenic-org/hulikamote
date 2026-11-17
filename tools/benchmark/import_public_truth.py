"""
import_public_truth.py - write the truth of the public helmet clips into benchmarks/registry.yaml.

Sources (evaluation material: never train on a clip that is listed here):
  Myanmar (HELMET dataset)   A:/huli-kamote/evaluation-testing-videos/to-evaluate/helmet-myanmar__no-helmet_overloading
  Dhaka (photo slideshow)    A:/huli-kamote/evaluation-testing-videos/to-train/dhaka-univ__no-helmet_overloading
Each clip has a <clip>_truth.txt next to it:
  Myanmar  " 0.9s- 6.9s  riders=1 no_helmet=1  DNoHelmet"                 one line per motorcycle (its time on screen)
  Dhaka    "00:01.5  17:37:26  Image0004  Bike x1, No_helmet x3, Trippling x1"   one line per photo
Events written: no_helmet (a rider without a helmet) and overloading (3 or more riders on one motorcycle).
The videos stay where they are (the registry keeps their full path); only registry.yaml and one settings file are written.

    python -m tools.benchmark.import_public_truth                    # 35 Myanmar + 5 Dhaka clips, the richest first
    python -m tools.benchmark.import_public_truth --picks picks.txt  # your own list: one clip path or file name per line
    python -m tools.benchmark.import_public_truth --dry-run          # show what would be written
Then:  python -m tools.benchmark validate   and   python -m tools.benchmark run --label public   (backend running)
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from . import registry

ROOT = Path("A:/huli-kamote/evaluation-testing-videos")
MYANMAR = ROOT / "to-evaluate" / "helmet-myanmar__no-helmet_overloading"
DHAKA = ROOT / "to-train" / "dhaka-univ__no-helmet_overloading"
SETTINGS_NAME = "settings/public_helmet.json"
MAX_RIDERS = 2

# The wizard settings every imported clip is analysed with: both rules watch the whole picture, DeepSORT (ByteTrack
# leaves most detections untracked), no slow plate enhancement.
SETTINGS = {
    "active_violations": ["no_helmet", "overloading"], "tracker": "deepsort", "plate_method": "smart",
    "plate_format": "ph_standard", "ocr_engine": "easyocr", "enhancement": "lanczos", "primary_model": "",
    "use_sahi": False, "flag_sensitivity": 5, "evidence_gap": 5, "keep_input_video": False, "blur_privacy": True,
    "flow_mode": "manual", "per_violation_configs": {"overloading": {"max_riders": MAX_RIDERS}}, "regions_of_interest": {},
}

_MYANMAR_LINE = re.compile(r"([\d.]+)s?\s*-\s*([\d.]+)s?\s+riders=(\d+)\s+no_helmet=(\d+)")
_DHAKA_LINE = re.compile(r"^(\d+):(\d+(?:\.\d+)?)\s+\S+\s+\S+\s+(.*)$")


def parse_myanmar(text: str) -> list[dict]:
    """One event per motorcycle line: no_helmet when a rider has none, overloading when it carries 3 or more."""
    events = []
    for line in text.splitlines():
        m = _MYANMAR_LINE.search(line)
        if not m:
            continue
        start, end, riders, bare = float(m[1]), float(m[2]), int(m[3]), int(m[4])
        if bare >= 1:
            events.append({"violation": "no_helmet", "start": round(start, 1), "end": round(end, 1)})
        if riders > MAX_RIDERS:
            events.append({"violation": "overloading", "start": round(start, 1), "end": round(end, 1)})
    return events


def parse_dhaka(text: str) -> list[dict]:
    """One event per photo that shows the violation; a photo stays on screen until the next one."""
    rows = []
    for line in text.splitlines():
        m = _DHAKA_LINE.match(line.strip())
        if m:
            rows.append((int(m[1]) * 60 + float(m[2]), m[3]))
    events = []
    for i, (t, labels) in enumerate(rows):
        end = rows[i + 1][0] if i + 1 < len(rows) else t + 1.5
        if "No_helmet" in labels:
            events.append({"violation": "no_helmet", "start": round(t, 1), "end": round(end, 1)})
        if "Trippling" in labels:
            events.append({"violation": "overloading", "start": round(t, 1), "end": round(end, 1)})
    return events


def read_clip(video: Path) -> dict | None:
    """Registry entry for one clip, or None when it has no truth file."""
    truth = video.with_name(video.stem + "_truth.txt")
    if not truth.exists():
        return None
    text = truth.read_text(encoding="utf-8", errors="replace")
    dhaka = "dhaka" in video.name.lower()
    events = parse_dhaka(text) if dhaka else parse_myanmar(text)
    entry = {"id": re.sub(r"[^a-z0-9]+", "_", video.stem.lower()).strip("_"), "file": video.as_posix(),
             "settings": SETTINGS_NAME, "clean": not events,
             "note": ("Dhaka photo slideshow (no motion between photos): spot check only" if dhaka
                      else "HELMET dataset, Myanmar, 10 fps") + "; truth from " + truth.name}
    if events:
        entry["events"] = events
    return entry


def richest(folder: Path, count: int) -> list[Path]:
    """The `count` clips of a folder with the most overloading events, then the most events (30 fps copies are skipped)."""
    scored = []
    for video in sorted(folder.glob("*.mp4")):
        if video.stem.endswith("_30fps"):
            continue
        entry = read_clip(video)
        if entry is None:
            continue
        events = entry.get("events", [])
        scored.append((-sum(e["violation"] == "overloading" for e in events), -len(events), video.name, video))
    return [row[3] for row in sorted(scored)[:count]]


def picked(list_file: Path) -> list[Path]:
    """Clips named in a picks file: a full path, or a file name looked up in the Myanmar and Dhaka folders."""
    out = []
    for line in list_file.read_text(encoding="utf-8").splitlines():
        name = line.strip().strip('"')
        if not name or name.startswith("#"):
            continue
        path = Path(name)
        if not path.is_absolute():
            name = name if name.lower().endswith(".mp4") else name + ".mp4"
            path = next((d / name for d in (MYANMAR, DHAKA) if (d / name).exists()), MYANMAR / name)
        out.append(path)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Write the truth of public helmet clips into benchmarks/registry.yaml")
    ap.add_argument("--picks", type=Path, help="text file: one clip path or file name per line (default: the richest clips)")
    ap.add_argument("--n-myanmar", type=int, default=35)
    ap.add_argument("--n-dhaka", type=int, default=5)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    videos = picked(args.picks) if args.picks else richest(MYANMAR, args.n_myanmar) + richest(DHAKA, args.n_dhaka)
    raw = registry.load_raw()
    clips = [c for c in raw.get("clips") or []]
    known = {c["id"]: i for i, c in enumerate(clips)}
    added = replaced = 0
    totals: dict[str, int] = {}
    for video in videos:
        entry = read_clip(video) if video.exists() else None
        if entry is None:
            print(f"  skipped (video or truth file missing): {video}")
            continue
        for e in entry.get("events", []):
            totals[e["violation"]] = totals.get(e["violation"], 0) + 1
        if entry["id"] in known:
            clips[known[entry["id"]]] = entry
            replaced += 1
        else:
            known[entry["id"]] = len(clips)
            clips.append(entry)
            added += 1
    print(f"{added} clips added, {replaced} replaced; real events: {totals or 'none'}")
    if args.dry_run:
        return 0
    settings = registry.BENCH / SETTINGS_NAME
    settings.parent.mkdir(parents=True, exist_ok=True)
    settings.write_text(json.dumps(SETTINGS, indent=2), encoding="utf-8")
    raw["clips"] = clips
    registry.save_raw(raw)
    print(f"written: {registry.BENCH / 'registry.yaml'} and {settings}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
