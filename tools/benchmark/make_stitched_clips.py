"""
make_stitched_clips.py - stitch the downloaded photo sets (and the vehicle-crop sequences) into video clips.

    python tools/benchmark/make_stitched_clips.py                  every set
    python tools/benchmark/make_stitched_clips.py --only dhaka     one set: dhaka | inatrc | medellin | cadiz
    python tools/benchmark/make_stitched_clips.py --chunk 200      photos per clip (default 200 = 5 min)

Output: benchmarks/public_clips/ready/<source>/ plus rows in ready/INDEX.csv and a <clip>_truth.txt next to every clip.
Needs ffmpeg on PATH, numpy and Pillow (the backend's python). Skips clips that exist. Evaluation material only.

Dhaka, InaTRC and Medellin are single photos from a fixed camera taken seconds to months apart, so there is no motion to
interpolate (it would only warp the vehicles). They are ordered by their real timestamp, each photo is held 1 s and
dissolved into the next over half a second. Every photo is a separate spot check: tracking and counting do not carry over from one
photo to the next. Cadiz is a real sequence of 20 frames per vehicle (cropped), kept at its own 6 fps (interpolation warped small parts).
"""
from __future__ import annotations

import argparse
import collections
import csv
import io
import json
import re
import subprocess
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import PurePosixPath, Path

import numpy as np
from PIL import Image, ImageOps
from ready_names import ready as R              # folder names under ready/: <origin>__<violations>

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "benchmarks" / "public_clips"
OUT = SRC / "ready"
FPS, PIPE_FPS, HOLD_N, FADE_N = 30, 15, 15, 8        # piped at 15 fps, ffmpeg doubles each frame to 30 fps
STILL = (HOLD_N + FADE_N) / PIPE_FPS                  # seconds per photo (1.53)
POOL = ThreadPoolExecutor(3)
JOBS: list = []


def run_ffmpeg(args: list[str], data: bytes | None = None) -> None:
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], input=data, capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr.decode(errors="replace")[:400])


def timelapse(photos: list[tuple[bytes, str]], dest: Path, size: tuple[int, int]) -> None:
    """Hold each photo, dissolve into the next, pipe raw frames to ffmpeg. photos = [(jpeg bytes, truth text)]."""
    w, h = size
    proc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(PIPE_FPS),
         "-i", "-", "-vf", f"fps={FPS}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "24", "-pix_fmt", "yuv420p", str(dest)],
        stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    def load(b: bytes) -> np.ndarray:
        return np.asarray(ImageOps.pad(Image.open(io.BytesIO(b)).convert("RGB"), size, Image.BICUBIC))

    cur = load(photos[0][0])
    for i in range(len(photos)):
        still = cur.tobytes()
        for _ in range(HOLD_N):
            proc.stdin.write(still)
        if i + 1 < len(photos):
            nxt = load(photos[i + 1][0])
            for k in range(1, FADE_N + 1):
                t = k / (FADE_N + 1)
                proc.stdin.write(((1 - t) * cur + t * nxt).astype(np.uint8).tobytes())
            cur = nxt
    proc.stdin.close()
    err = proc.stderr.read().decode(errors="replace")
    if proc.wait():
        raise RuntimeError(err[:400])


def stamp(t: float) -> str:
    return f"{int(t // 60):02d}:{t % 60:04.1f}"


def write_clip(group: str, name: str, photos: list[tuple[bytes, str]], size: tuple[int, int], head: str,
               violations: str, note: str, index: list[dict]) -> None:
    dest = OUT / R(group) / f"{name}.mp4"
    dest.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{stamp(i * STILL)}  {txt}" for i, (_, txt) in enumerate(photos)]
    (dest.parent / f"{name}_truth.txt").write_text(head + "\n" + "\n".join(lines) + "\n", encoding="utf-8")
    if not dest.exists():
        JOBS.append(POOL.submit(timelapse, photos, dest, size))
    index.append({"source": group, "file": f"{R(group)}/{name}.mp4", "seconds": round(len(photos) * STILL), "fps": FPS,
                  "violations": violations, "truth": f"{R(group)}/{name}_truth.txt", "note": note})
    print("queued", group, name, len(photos), "photos", flush=True)


def chunks(items: list, n: int) -> list[list]:
    """Equal-sized pieces of at most n (no tiny leftover clip)."""
    parts = -(-len(items) // n)
    size = -(-len(items) // parts)
    return [items[i:i + size] for i in range(0, len(items), size)]


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


# ---- Dhaka (Mendeley ycv2mbph4b): raw photos with real date, time and place in a csv, COCO labels ----
def do_dhaka(chunk: int, index: list[dict]) -> None:
    z = zipfile.ZipFile(SRC / "dhaka_helmet_triple" / "ycv2mbph4b_v1.zip")
    names = {i.filename: i for i in z.infolist()}
    csv_name = next(n for n in names if n.endswith("dataset_metadata.csv"))
    meta = {r["Image_Name"]: r for r in csv.DictReader(io.StringIO(z.read(csv_name).decode("utf-8-sig")))}
    labels: dict[str, collections.Counter] = {}
    for n in names:
        if "Raw_Dataset" in n and n.endswith("_annotations.coco.json"):
            j = json.loads(z.read(n))
            cat = {c["id"]: c["name"] for c in j["categories"] if c["id"]}
            by_id = {im["id"]: im["file_name"] for im in j["images"]}
            for im in j["images"]:
                labels[im["file_name"]] = collections.Counter()
            for a in j["annotations"]:
                labels[by_id[a["image_id"]]][cat.get(a["category_id"], "?")] += 1
    rows = []
    for n in names:
        if "Raw_Dataset" in n and n.endswith(".jpg"):
            base = PurePosixPath(n).name
            m = meta.get(base.split("_jpg")[0] + ".jpg")
            if m:
                rows.append((m["Date"], m["Time"], m["Location"], n, labels.get(base, collections.Counter())))
    rows.sort(key=lambda r: (r[0], r[2], r[1]))
    sessions: dict[tuple[str, str], list] = collections.defaultdict(list)
    for r in rows:
        sessions[(r[0], r[2])].append(r)
    for (date, place), items in sessions.items():
        for k, part in enumerate(chunks(items, chunk), 1):
            photos = [(z.read(r[3]), f"{r[1]}  {PurePosixPath(r[3]).name.split('_jpg')[0]}  " +
                       (", ".join(f"{c} x{v}" for c, v in sorted(r[4].items())) or "no labels")) for r in part]
            write_clip("dhaka_helmet_triple", f"dhaka_{date}_{slug(place)}_{k:02d}", photos, (768, 768),
                       f"Dhaka {place}, {date}. Fixed camera, photos seconds apart (time of day, photo, annotated objects). "
                       "Bike/Rider/Helmet_On/No_helmet/Trippling = rider count on a bike; Trippling = 3 riders.",
                       "no_helmet, overloading", "photo slideshow of a fixed camera: spot checks, no tracking across photos", index)


# ---- InaTRC (Mendeley kddgphck3b): toll-road CCTV frames, time burned into the picture, YOLO labels ----
INA = {0: "non-truck", 1: "truck 2 axles", 2: "truck 3 axles", 3: "truck 4 axles", 4: "truck 5+ axles"}


def do_inatrc(chunk: int, index: list[dict]) -> None:
    z = zipfile.ZipFile(SRC / "inatrc_toll_trucks" / "kddgphck3b_v1.zip")
    pics = {}
    for i in z.infolist():
        if i.filename.endswith(".jpg") and "/images/" in i.filename:
            pics[PurePosixPath(i.filename).stem] = i.filename            # number is the capture order across all splits
    order = sorted(pics)
    for k, part in enumerate(chunks(order, chunk), 1):
        photos = []
        for stem in part:
            lab = pics[stem].replace("/images/", "/labels/")[:-4] + ".txt"
            c = collections.Counter(INA.get(int(l.split()[0]), "?") for l in z.read(lab).decode().splitlines() if l.strip())
            photos.append((z.read(pics[stem]), f"{stem}  " + (", ".join(f"{n} x{v}" for n, v in sorted(c.items())) or "no vehicles")))
        write_clip("inatrc_toll_trucks", f"inatrc_{k:02d}", photos, (1056, 720),
                   "InaTRC toll road, one fixed camera. Photos 2-5 s apart in capture order (the clock is in the picture).",
                   "truck_ban", "photo slideshow of a fixed camera: spot checks, no tracking across photos", index)


# ---- Medellin (Zenodo 7935298): CCTV photos named imagen<camera>_<date>_<time>, YOLO labels ----
MED = {0: "MMNAP", 1: "MMAP", 2: "MNAP", 3: "PCP"}


def do_medellin(chunk: int, index: list[dict]) -> None:
    z = zipfile.ZipFile(SRC / "medellin_pedestrian_cctv" / "PedestrianDataSet.zip")
    cams: dict[str, list] = collections.defaultdict(list)
    for i in z.infolist():
        m = re.match(r"images/imagen(\d+)_(\d{8})_(\d{6})\.jpg$", i.filename)
        if m:
            cams[m.group(1)].append((m.group(2) + m.group(3), i.filename))
    small = []
    for cam, items in sorted(cams.items(), key=lambda kv: int(kv[0])):
        items.sort()
        if len(items) < 10:
            small += [(cam, *it) for it in items]
            continue
        for k, part in enumerate(chunks(items, chunk), 1):
            medellin_clip(z, f"medellin_cam{cam}_{k:02d}", [(cam, *it) for it in part], f"camera {cam}", index)
    for k, part in enumerate(chunks(sorted(small, key=lambda t: (t[0], t[1])), chunk) if small else [], 1):
        medellin_clip(z, f"medellin_other_cameras_{k:02d}", part, "cameras with few photos (scene changes at every cut)", index)


def medellin_clip(z: zipfile.ZipFile, name: str, items: list, what: str, index: list[dict]) -> None:
    photos = []
    for cam, ts, path in items:
        lab = "etiquetas/" + PurePosixPath(path).stem + ".txt"
        c = collections.Counter(MED.get(int(l.split()[0]), "?") for l in z.read(lab).decode(errors="replace").splitlines()
                                if l.split() and l.split()[0].isdigit())
        photos.append((z.read(path), f"cam{cam} {ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[8:10]}:{ts[10:12]}  " +
                       (", ".join(f"{n} x{v}" for n, v in sorted(c.items())) or "no labels")))
    write_clip("medellin_pedestrian_cctv", name, photos, (1280, 720),
               f"Medellin pedestrian area, {what}, ordered by capture time (days to months apart). Classes as the dataset names them: "
               "MMNAP, MMAP, MNAP, PCP (MM = motorcyclist; P in the code = pedestrian area).",
               "sidewalk_driving, pedestrian_lane", "photo slideshow of a fixed camera: spot checks, no tracking across photos", index)


# ---- Cadiz (Zenodo): 20 real frames per tracked vehicle (cropped), interpolated up to 30 fps ----
def cadiz_vehicle(frames: list[bytes], dest: Path) -> None:
    """The crop grows as the vehicle comes closer, so every frame is fitted to one canvas before interpolating."""
    size = (832, 588)
    raw = b"".join(ImageOps.pad(Image.open(io.BytesIO(f)).convert("RGB"), size, Image.BICUBIC).tobytes() for f in frames)
    run_ffmpeg(["-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "832x588", "-framerate", "6", "-i", "-",
                "-c:v", "libx264", "-crf", "22", "-pix_fmt", "yuv420p", "-threads", "2", str(dest)], raw)


def do_cadiz(chunk: int, index: list[dict]) -> None:
    z = zipfile.ZipFile(SRC / "zigzag_cadiz" / "driving_behaviour_vehicle_sequences_v1.0.zip")
    csv_name = next(i.filename for i in z.infolist() if i.filename.endswith(".csv"))
    rows = list(csv.DictReader(io.StringIO(z.read(csv_name).decode("utf-8-sig")), delimiter=";"))
    seq: dict[tuple[str, str], list[str]] = collections.defaultdict(list)
    for i in z.infolist():
        p = PurePosixPath(i.filename)
        if i.filename.endswith(".jpg") and len(p.parts) >= 4:
            seq[(p.parts[1], p.parts[2])].append(i.filename)
    by_class: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)
    for r in rows:
        if (r["video_id"], r["vehicle_id"]) in seq:
            by_class[r["clase"]].append((r["video_id"], r["vehicle_id"]))
    tmp = OUT / R("zigzag_cadiz") / "_tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    jobs, plan = [], []
    for cls, vehicles in by_class.items():
        for k, part in enumerate(chunks(sorted(vehicles), 60 if cls == "normal" else 100), 1):
            name = f"cadiz_{cls}_{k:02d}"
            dest = OUT / R("zigzag_cadiz") / f"{name}.mp4"
            parts = []
            for v in part:
                t = tmp / f"{v[0]}__{v[1]}.mp4"
                if not t.exists() and not dest.exists():
                    jobs.append((sorted(seq[v]), t))
                parts.append((v, t))
            plan.append((cls, name, dest, parts))
    with ThreadPoolExecutor(4) as ex:
        for f in [ex.submit(lambda fs, t: cadiz_vehicle([z.read(n) for n in fs], t), fs, t) for fs, t in jobs]:
            f.result()
    real = []
    for cls, name, dest, parts in plan:
        if not dest.exists():
            lst = tmp / f"{name}.txt"
            lst.write_text("".join(f"file '{t.as_posix()}'\n" for _, t in parts))
            run_ffmpeg(["-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(dest)])
            lst.unlink()
        secs = len(parts) * 20 / 6
        lines = [f"{stamp(i * 20 / 6)}  {v[0]} {v[1]}  class={cls}" for i, (v, _) in enumerate(parts)]
        (dest.parent / f"{name}_truth.txt").write_text(
            f"Cadiz vehicle sequences, behaviour '{cls}'. One tracked vehicle at a time (cropped), each about 3.3 s, hard cut between vehicles.\n"
            + "\n".join(lines) + "\n", encoding="utf-8")
        real.append({"source": "zigzag_cadiz", "file": f"{R('zigzag_cadiz')}/{name}.mp4", "seconds": round(secs), "fps": 30,
                     "violations": "swerving" if cls != "normal" else "(normal driving: false-alarm check)",
                     "truth": f"{R('zigzag_cadiz')}/{name}_truth.txt",
                     "note": f"{len(parts)} vehicles, class {cls}; frames 6 fps in the source, no frames generated"})
        print("clip", name, len(parts), "vehicles", flush=True)
    index.extend(real)
    for f in tmp.glob("*.mp4"):
        f.unlink()
    for f in tmp.glob("*.txt"):
        f.unlink()
    tmp.rmdir()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["dhaka", "inatrc", "medellin", "cadiz"])
    ap.add_argument("--chunk", type=int, default=200)
    args = ap.parse_args()
    index: list[dict] = []
    for key, fn in (("dhaka", do_dhaka), ("inatrc", do_inatrc), ("medellin", do_medellin), ("cadiz", do_cadiz)):
        if args.only in (None, key):
            fn(args.chunk, index)
    for j in JOBS:
        j.result()                                          # raise the first ffmpeg error instead of hiding it
    path = OUT / "INDEX.csv"
    old = list(csv.DictReader(path.open(encoding="utf-8"))) if path.exists() else []
    merged = {r["file"]: r for r in old + index}
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["source", "file", "seconds", "fps", "violations", "truth", "note"])
        w.writeheader()
        w.writerows(sorted(merged.values(), key=lambda r: r["file"]))
    print(f"INDEX.csv: {len(merged)} clips")
    return 0


if __name__ == "__main__":
    sys.exit(main())
