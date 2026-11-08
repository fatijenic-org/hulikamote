"""
make_ready_clips.py - turn the downloaded public material into ready-to-upload video clips.

    python tools/benchmark/make_ready_clips.py                 everything that is downloaded
    python tools/benchmark/make_ready_clips.py --only helmet   one group: helmet | ridesafe | wrongway | idiap
    python tools/benchmark/make_ready_clips.py --per-part 30   HELMET clips per part (the busiest ones plus the cleanest ones)

Output: benchmarks/public_clips/ready/<source>/ plus INDEX.csv (one row per clip) and a truth file next to every HELMET clip.
Needs ffmpeg on PATH and the backend's python (stdlib only). Skips clips that already exist. Evaluation material only.

What is turned into video: HELMET (Myanmar) comes as 100 jpg frames per 10 s at 10 fps, so it is rebuilt as a 10 fps
H.264 clip of exactly those frames (1280x720). No in-between frames are generated: motion interpolation made small moving
parts such as heads wobble. The Dhaka, InaTRC and Medellin sets are single pictures
from different times (not sequences) and the Cadiz set is 20-frame vehicle crops, so they cannot become scene video.
"""
from __future__ import annotations

import argparse
import collections
import csv
import io
import re
import shutil
import subprocess
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from ready_names import ready as R              # folder names under ready/: <origin>__<violations>

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "benchmarks" / "public_clips"
OUT = SRC / "ready"
POSITION = re.compile(r"(D|P\d)(NoHelmet|Helmet)")


def ffmpeg(args: list[str], data: bytes | None = None) -> None:
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], input=data, capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr.decode(errors="replace")[:400])


def helmet_truth(rows: list[dict]) -> tuple[list[str], int, int]:
    """Lines for the truth file, number of riders without a helmet, number of motorcycles with 3+ riders."""
    tracks = collections.defaultdict(list)
    for r in rows:
        tracks[r["track_id"]].append(r)
    lines, no_helmet, triple = [], 0, 0
    for rs in tracks.values():
        frames = [int(r["frame_id"]) for r in rs]
        label = collections.Counter(r["label"] for r in rs).most_common(1)[0][0]
        riders = POSITION.findall(label)
        bare = sum(1 for _, h in riders if h == "NoHelmet")
        no_helmet += bare
        triple += len(riders) >= 3
        lines.append(f"{min(frames) / 10:4.1f}s-{max(frames) / 10:4.1f}s  riders={len(riders)} no_helmet={bare}  {label}")
    return sorted(lines), no_helmet, triple


def helmet_pick(ann: zipfile.ZipFile, clips: list[str], per_part: int) -> list[str]:
    """The busiest clips (most riders without helmet) plus the cleanest ones, so false alarms can be seen too."""
    scored = []
    for c in clips:
        rows = list(csv.DictReader(io.StringIO(ann.read(f"annotation/{c}.csv").decode())))
        scored.append((helmet_truth(rows)[1], c))
    scored.sort(key=lambda t: (-t[0], t[1]))
    if len(scored) <= per_part:
        return [c for _, c in scored]
    clean = max(per_part // 3, 1)
    return [c for _, c in scored[: per_part - clean]] + [c for _, c in scored[-clean:]]


def helmet_clip(zip_path: Path, ann_path: Path, part: str, clip: str, index: list[dict]) -> None:
    dest = OUT / R("helmet_myanmar") / f"{clip}.mp4"
    with zipfile.ZipFile(zip_path) as z, zipfile.ZipFile(ann_path) as ann:
        rows = list(csv.DictReader(io.StringIO(ann.read(f"annotation/{clip}.csv").decode())))
        lines, no_helmet, triple = helmet_truth(rows)
        (dest.parent / f"{clip}_truth.txt").write_text(
            "time (s)      riders / riders without helmet / label (D = driver, P1 P2 = passengers)\n" + "\n".join(lines) + "\n")
        if not dest.exists():
            names = {int(Path(n).stem): n for n in z.namelist() if n.startswith(f"{part}/{clip}/") and n.endswith(".jpg")}
            data = b"".join(z.read(names[i]) for i in sorted(names))
            ffmpeg(["-f", "image2pipe", "-framerate", "10", "-vcodec", "mjpeg", "-i", "-",
                    "-vf", "scale=1280:720",
                    "-c:v", "libx264", "-crf", "21", "-pix_fmt", "yuv420p", "-threads", "3", str(dest)], data)
    index.append({"source": "helmet_myanmar", "file": f"{R('helmet_myanmar')}/{clip}.mp4", "seconds": 10, "fps": 10,
                  "violations": "no_helmet, overloading", "truth": f"{R('helmet_myanmar')}/{clip}_truth.txt",
                  "note": f"{no_helmet} riders without helmet, {triple} motorcycles with 3+ riders"})
    print("clip", clip, flush=True)


def do_helmet(per_part: int, workers: int, index: list[dict], parts: set[str] | None = None) -> None:
    root = SRC / "helmet_myanmar" / "HELMET_DATASET"
    ann_path = root / "annotation.zip"
    jobs = []
    (OUT / R("helmet_myanmar")).mkdir(parents=True, exist_ok=True)
    for zp in sorted((root / "image").glob("part_*.zip")):
        if parts and zp.stem not in parts:
            continue
        if (zp.parent / (zp.name + ".part")).exists() or not zipfile.is_zipfile(zp):
            print("skip (not finished downloading):", zp.name)
            continue
        with zipfile.ZipFile(zp) as z, zipfile.ZipFile(ann_path) as ann:
            part = zp.stem
            clips = sorted({n.split("/")[1] for n in z.namelist() if n.endswith(".jpg")})
            for clip in helmet_pick(ann, clips, per_part):
                jobs.append((zp, part, clip))
    with ThreadPoolExecutor(workers) as ex:
        for done in [ex.submit(helmet_clip, zp, ann_path, part, clip, index) for zp, part, clip in jobs]:
            done.result()                                   # raise the first ffmpeg error instead of hiding it


def do_ridesafe(index: list[dict]) -> None:
    ridesafe_zip(SRC / "ridesafe_400" / "videoset1_videos_part1.zip", index)


def ridesafe_zip(zp: Path, index: list[dict]) -> None:
    dest = OUT / R("ridesafe_400")
    dest.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(SRC).free < 12e9:
        sys.exit("Less than 12 GB free: not unpacking RideSafe.")
    with zipfile.ZipFile(zp) as z:
        for n in z.namelist():
            if n.endswith(".mp4"):
                target = dest / Path(n).name
                if not target.exists():
                    with z.open(n) as s, open(target, "wb") as d:
                        shutil.copyfileobj(s, d, 1 << 20)
                index.append({"source": "ridesafe_400", "file": f"{R('ridesafe_400')}/{target.name}", "seconds": 60, "fps": "",
                              "violations": "no_helmet, overloading, no_plate", "truth": "annotations in ridesafe_400/*.zip",
                              "note": "dashcam (moving camera), not a fixed view"})
    print("ridesafe unpacked", flush=True)


def do_reencode(zp: Path, group: str, violations: str, note: str, index: list[dict]) -> None:
    dest = OUT / R(group)
    dest.mkdir(parents=True, exist_ok=True)
    items = []                                              # (source file, finished mp4, unpacked temp copy?)
    if zp.suffix == ".zip":
        with zipfile.ZipFile(zp) as z:
            for n in z.namelist():
                if n.lower().endswith((".mov", ".mp4", ".avi")):
                    out = dest / (Path(n).stem + ".mp4")
                    target = dest / (Path(n).stem + ".src" + Path(n).suffix)
                    if not out.exists():
                        with z.open(n) as s, open(target, "wb") as d:
                            shutil.copyfileobj(s, d, 1 << 20)
                    items.append((target, out, True))
    else:
        items.append((zp, dest / (zp.stem + ".mp4"), False))
    for src, out, temp in items:
        if not out.exists():
            ffmpeg(["-i", str(src), "-an", "-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p", str(out)])
        if temp and src.exists():
            src.unlink()
        index.append({"source": group, "file": f"{R(group)}/{out.name}", "seconds": "", "fps": "", "violations": violations,
                      "truth": "none yet: write it in benchmarks/registry.yaml", "note": note})
        print("reencoded", out.name, flush=True)


def write_index(index: list[dict]) -> None:
    """Merge the new rows into ready/INDEX.csv (keyed by file path)."""
    path = OUT / "INDEX.csv"
    old = list(csv.DictReader(path.open(encoding="utf-8"))) if path.exists() else []
    merged = {r["file"]: r for r in old + index}
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["source", "file", "seconds", "fps", "violations", "truth", "note"])
        w.writeheader()
        w.writerows(sorted(merged.values(), key=lambda r: r["file"]))
    print(f"INDEX.csv: {len(merged)} clips")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["helmet", "ridesafe", "wrongway", "idiap"])
    ap.add_argument("--per-part", type=int, default=30)
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()
    index: list[dict] = []
    OUT.mkdir(parents=True, exist_ok=True)
    if args.only in (None, "helmet"):
        do_helmet(args.per_part, args.workers, index)
    if args.only in (None, "wrongway"):
        do_reencode(SRC / "wrong_way_cycling" / "final_validation.zip", "wrong_way_cycling", "counterflow",
                    "fixed CCTV, bicycles going the wrong way", index)
    if args.only in (None, "idiap"):
        do_reencode(SRC / "idiap_traffic_junction" / "traffic-junction.avi", "idiap_traffic_junction",
                    "red_light, pedestrian_lane, blocking_intersection", "fixed camera at a junction", index)
    if args.only in (None, "ridesafe"):
        do_ridesafe(index)
    write_index(index)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
