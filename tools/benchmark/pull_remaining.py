"""
pull_remaining.py - fetch the public video data that was held back for disk space, one batch at a time, and turn it into clips.

    python tools/benchmark/pull_remaining.py --dry-run          what is still missing, how big, how much room there is
    python tools/benchmark/pull_remaining.py                    everything, in this order: helmet, ridesafe, meteor
    python tools/benchmark/pull_remaining.py --only helmet      one source: helmet | ridesafe | meteor
    python tools/benchmark/pull_remaining.py --dest E:\\hk\\public_clips --stage D:\\staging

What a batch is: one downloaded file. It is downloaded (resumable, run the same command again after an interruption), unzipped, turned into
clips, and the raw download is moved to --dest right away, so the staging disk never holds more than one batch.
- helmet: the remaining clips of the parts already on disk, then parts 5 and 6; frames become 10 fps clips with no generated frames (make_ready_clips.py).
- ridesafe: every other RideSafe-400 zip; the dashcam mp4 files are unpacked into ready/ridesafe_400 and the zip is deleted once every
  file is checked (a zip that was already on disk is never deleted; --keep-zips keeps all).
- meteor: the five split chunks (93 GB) are downloaded straight to --dest, joined, unpacked into ready/meteor, then the chunks and the joined file are deleted.
Sources that need an account (Kaggle, Roboflow, forms) are listed at the end, never bypassed. Evaluation material only.

--dest defaults to benchmarks/public_clips (which may be a link to the external drive). Downloads go to --stage first (on the fast disk) when the
file is small enough and leaves --reserve-gb free; bigger files go straight to --dest. Run with the backend's python; nothing is installed.
"""
from __future__ import annotations

import argparse
import collections
import re
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

import fetch_public_clips as fpc          # sibling script: the manifest, the file listings and the resumable download
import make_ready_clips as mrc            # sibling script: HELMET frames to clips, RideSafe unpacking, INDEX.csv
import make_stitched_clips as msc         # sibling script: photos to a dissolving time-lapse clip
from ready_names import ready as R        # folder names under ready/: <origin>__<violations>

REPO = fpc.REPO
VIDEO = (".mp4", ".avi", ".mov", ".mkv", ".mpg", ".mpeg")
IMAGE = (".jpg", ".jpeg", ".png", ".bmp")
ALL_CLIPS = 10 ** 9
GENERIC = ["peshawar_roundabout_wrongturn", "motorcycle_violation_hetero", "keke_counting", "fluid_signalized_drone",
           "nancy_multiperspective", "avdl_latvia", "road_anomaly_cctv", "hanoi_motorbike_tracking",
           "road_lane_quality_dashcam", "australia_dashcam", "stock_traffic_footage"]


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def free(path: Path) -> int:
    return shutil.disk_usage(path).free


def gb(n: float) -> str:
    return f"{n / 1e9:,.1f} GB"


def done(path: Path, size: int | None) -> bool:
    return path.exists() and not Path(str(path) + ".part").exists() and (size is None or path.stat().st_size == size)


def source(data: dict, sid: str) -> dict:
    return next(s for s in data["sources"] if s["id"] == sid)


def get(a: argparse.Namespace, sid: str, f: dict) -> Path:
    """Make sure one file is in --dest/<id>/<name>. Small files are staged on the fast disk and moved over the moment they are complete."""
    final = a.dest / sid / f["name"]
    size = f["size"]
    if done(final, size):
        return final
    final.parent.mkdir(parents=True, exist_ok=True)
    if size and free(a.dest) < size * a.dest_factor.get(sid, 1.3):
        raise RuntimeError(f"not enough room on {a.dest.drive or a.dest} for {f['name']}: need about "
                           f"{gb(size * a.dest_factor.get(sid, 1.3))}, have {gb(free(a.dest))}")
    staged = a.stage / sid / f["name"]
    use_stage = bool(size) and a.cross_drive and size <= a.stage_max_gb * 1e9 and free(a.stage) - size >= a.reserve_gb * 1e9
    if use_stage or done(staged, size):
        staged.parent.mkdir(parents=True, exist_ok=True)
        if not done(staged, size):
            log(f"download {f['name']} ({gb(size or 0)}) -> staging")
            fpc.download_file(f["url"], staged, expected_size=size)
        log(f"move {f['name']} -> {a.dest / sid}")
        shutil.move(str(staged), str(final))
    else:
        log(f"download {f['name']} ({gb(size or 0)}) -> {final.parent}")
        fpc.download_file(f["url"], final, expected_size=size)
    return final


def finish_index(index: list[dict]) -> None:
    mrc.write_index(index)
    index.clear()


# ---- helmet -------------------------------------------------------------------------------------------------------------
def do_helmet(a: argparse.Namespace, data: dict, index: list[dict]) -> None:
    src = source(data, "helmet_myanmar")
    plan = fpc.plan(src, sample=False)
    files = plan["files"]
    for f in files:
        if re.search(r"(annotation\.zip|data_split\.csv|Readme\.txt)$", f["name"]):
            get(a, src["id"], f)
    images = sorted((f for f in files if re.search(r"image/part_\d+\.zip$", f["name"])), key=lambda f: f["name"])
    have = {Path(f["name"]).stem for f in images if done(a.dest / src["id"] / f["name"], f["size"])}
    if have:
        log(f"helmet: clips still missing from the parts already here: {sorted(have)}")
        mrc.do_helmet(ALL_CLIPS, a.workers, index, parts=have)
        finish_index(index)
    for f in images:
        part = Path(f["name"]).stem
        if part in have:
            continue
        get(a, src["id"], f)
        log(f"helmet: converting every clip of {part}")
        mrc.do_helmet(ALL_CLIPS, a.workers, index, parts={part})
        finish_index(index)
    fpc.write_notes(src, a.dest / src["id"], files, plan["license"])


# ---- ridesafe -----------------------------------------------------------------------------------------------------------
def unpacked(zp: Path, folder: Path) -> bool:
    """Every mp4 in the zip is in the folder with the right size."""
    with zipfile.ZipFile(zp) as z:
        return all((folder / Path(i.filename).name).exists() and (folder / Path(i.filename).name).stat().st_size == i.file_size
                   for i in z.infolist() if i.filename.endswith(".mp4"))


def do_ridesafe(a: argparse.Namespace, data: dict, index: list[dict]) -> None:
    src = source(data, "ridesafe_400")
    plan = fpc.plan(src, sample=False)
    out = a.dest / "ready" / R("ridesafe_400")
    for f in plan["files"]:
        was_there = done(a.dest / src["id"] / f["name"], f["size"])
        zp = get(a, src["id"], f)
        if re.search(r"_videos_part\d+\.zip$", f["name"]):
            log(f"ridesafe: unpacking {f['name']}")
            mrc.ridesafe_zip(zp, index)
            finish_index(index)
            if not was_there and not a.keep_zips:
                if unpacked(zp, out):
                    zp.unlink()
                    log(f"ridesafe: {f['name']} fully unpacked and checked, zip deleted")
                else:
                    log(f"ridesafe: {f['name']} NOT fully unpacked, zip kept")
        elif f["name"].endswith(".zip"):
            fpc.extract_zip(zp, zp.with_suffix(""))
    fpc.write_notes(src, a.dest / src["id"], plan["files"], plan["license"])


# ---- meteor -------------------------------------------------------------------------------------------------------------
def join_chunks(chunks: list[Path], joined: Path) -> None:
    total = sum(c.stat().st_size for c in chunks)
    if joined.exists() and joined.stat().st_size == total:
        return
    log(f"meteor: joining {len(chunks)} chunks ({gb(total)})")
    tmp = joined.with_suffix(".joining")
    with open(tmp, "wb") as out:
        for c in chunks:
            with open(c, "rb") as s:
                shutil.copyfileobj(s, out, 8 << 20)
    if tmp.stat().st_size != total:
        raise RuntimeError("joined file has the wrong size; chunks kept")
    tmp.replace(joined)


def unpack_meteor(joined: Path, out: Path, index: list[dict]) -> int:
    with open(joined, "rb") as f:
        head = f.read(4)
        f.seek(257)
        tar_magic = f.read(5)
    out.mkdir(parents=True, exist_ok=True)
    names: list[str] = []
    if head[:2] == b"PK":
        with zipfile.ZipFile(joined) as z:
            for i in z.infolist():
                if i.filename.lower().endswith(VIDEO):
                    target = out / Path(i.filename)
                    if not (target.exists() and target.stat().st_size == i.file_size):
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with z.open(i) as s, open(target, "wb") as d:
                            shutil.copyfileobj(s, d, 8 << 20)
                    names.append(str(Path(i.filename)))
    elif head[:2] == b"\x1f\x8b" or tar_magic == b"ustar":
        with tarfile.open(joined, "r:*") as t:
            for m in t:
                if m.isfile() and m.name.lower().endswith(VIDEO):
                    target = out / Path(m.name)
                    if not (target.exists() and target.stat().st_size == m.size):
                        t.extract(m, out, filter="data")
                    names.append(str(Path(m.name)))
    else:
        raise RuntimeError(f"METEOR archive type not recognised (starts with {head!r}); {joined} kept for a manual look")
    for n in sorted(names):
        index.append({"source": "meteor", "file": f"meteor/{Path(n).as_posix()}", "seconds": "", "fps": "",
                      "violations": "swerving, red_light, counterflow", "truth": "none yet: write it in benchmarks/registry.yaml",
                      "note": "dashcam (moving camera): zone rules will not work"})
    return len(names)


def do_meteor(a: argparse.Namespace, data: dict, index: list[dict]) -> None:
    src = source(data, "meteor")
    plan = fpc.plan(src, sample=False)
    chunks_f = sorted((f for f in plan["files"] if Path(f["name"]).name.startswith("chunk_")), key=lambda f: f["name"])
    joined = a.dest / src["id"] / "_joined.archive"
    out = a.dest / "ready" / "meteor"
    if not (out / ".complete").exists():                       # marker: an interrupted unpack must not count as finished
        total = sum(f["size"] or 0 for f in chunks_f)
        if free(a.dest) < total * 2.2 and not joined.exists():
            raise RuntimeError(f"METEOR needs about {gb(total * 2.2)} free on the destination (chunks plus the joined file); have {gb(free(a.dest))}")
        for f in plan["files"]:
            if not Path(f["name"]).name.startswith("chunk_") or not joined.exists():
                get(a, src["id"], f)
        chunk_paths = [a.dest / src["id"] / f["name"] for f in chunks_f]
        if all(p.exists() for p in chunk_paths):
            join_chunks(chunk_paths, joined)
            for p in chunk_paths:
                p.unlink()
        log("meteor: unpacking the videos")
        n = unpack_meteor(joined, out, index)
        log(f"meteor: {n} videos unpacked")
        (out / ".complete").write_text(f"{n} videos")
        joined.unlink()
        finish_index(index)
    fpc.write_notes(src, a.dest / src["id"], plan["files"], plan["license"])


# ---- every other source: unpack, stitch photos, copy or re-encode videos -----------------------------------------------------
def natural(p: Path) -> list:
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", p.name)]


def slug(rel: Path) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "-", "__".join(rel.with_suffix("").parts)).strip("-")[:90]


def fit(w: int, h: int) -> tuple[int, int]:
    """Output size: the picture scaled into 1280x720 (never more than 2x up), both sides even."""
    s = min(1280 / w, 720 / h, 2.0)
    return max(2, round(w * s / 2) * 2), max(2, round(h * s / 2) * 2)


def is_sequence(files: list[Path]) -> bool:
    """Real consecutive frames (numbered one after another and nearly identical) or separate photos of one place."""
    nums = [int(m.group(1)) for f in files if (m := re.search(r"(\d+)$", f.stem))]
    if len(nums) < len(files) * 0.9:
        return False
    steps = [b - a for a, b in zip(nums, nums[1:])]
    if sum(1 for d in steps if 0 < d <= 2) < len(steps) * 0.8:
        return False
    diffs = []
    for i in range(0, len(files) - 1, max(1, len(files) // 20)):
        try:
            g = [np.asarray(Image.open(files[j]).convert("L").resize((64, 64)), dtype=np.int16) for j in (i, i + 1)]
            diffs.append(float(np.abs(g[0] - g[1]).mean()))
        except Exception:
            pass
    return bool(diffs) and float(np.median(diffs)) < 25.0


def label_text(img: Path) -> str:
    """What the dataset says is in a picture, from a YOLO .txt or a Pascal VOC .xml next to it (class numbers are kept as numbers)."""
    parts = list(img.parts)
    cands = [img.with_suffix(".txt"), img.with_suffix(".xml")]
    if "images" in parts:
        k = len(parts) - 1 - parts[::-1].index("images")
        cands += [Path(*parts[:k], "labels", img.stem + ".txt"), Path(*parts[:k], "Annotations", img.stem + ".xml")]
    for c in cands:
        if c.exists():
            try:
                text = c.read_text(errors="replace")
            except OSError:
                continue
            names = re.findall(r"<name>(.*?)</name>", text) if c.suffix == ".xml" else \
                [f"class {t.split()[0]}" for t in text.splitlines() if t.split() and t.split()[0].isdigit()]
            n = collections.Counter(names)
            return ", ".join(f"{k} x{v}" for k, v in sorted(n.items())) or "no labels"
    return ""


def sequence_clip(files: list[Path], dest: Path, size: tuple[int, int]) -> None:
    w, h = size
    proc = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-framerate", "10",
                             "-i", "-", "-c:v", "libx264", "-crf", "22",
                             "-pix_fmt", "yuv420p", "-threads", "2", str(dest)], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for f in files:
            proc.stdin.write(ImageOps.pad(Image.open(f).convert("RGB"), size, Image.BICUBIC).tobytes())
    except BrokenPipeError:
        pass
    else:
        proc.stdin.close()
    err = proc.stderr.read().decode(errors="replace")
    if proc.wait():
        raise RuntimeError(err[:300])


def extract(arc: Path, into: Path) -> None:
    into.mkdir(parents=True, exist_ok=True)
    if arc.suffix.lower() == ".zip":
        fpc.extract_zip(arc, into)
        return
    exe = shutil.which("bsdtar") or r"C:\Windows\System32\tar.exe"          # Windows' own tar reads .rar and .7z; GNU tar (Git Bash) does not
    r = subprocess.run([exe, "-xf", str(arc), "-C", str(into)], capture_output=True)
    if r.returncode:
        raise RuntimeError(f"cannot unpack {arc.name}: {r.stderr.decode(errors='replace')[:300]}")


def work_dir(a: argparse.Namespace, sid: str, arc: Path) -> Path:
    """Unpack on the fast disk when it fits and leaves the reserve, else on the destination."""
    need = arc.stat().st_size * 1.2
    base = a.stage if a.cross_drive and free(a.stage) - need >= a.reserve_gb * 1e9 else a.dest / "_x"
    return base / sid / arc.stem


def convert_tree(a: argparse.Namespace, sid: str, root: Path, index: list[dict]) -> None:
    src = source(fpc.load(), sid)
    folder = a.dest / "ready" / R(sid)
    folder.mkdir(parents=True, exist_ok=True)
    violations = ", ".join(src["violations"])
    plans: list[tuple] = []
    for p in sorted(root.rglob("*"), key=natural):
        if p.is_file() and p.suffix.lower() in VIDEO:
            plans.append(("video", slug(p.relative_to(root)), p))
    groups: dict[Path, list[Path]] = collections.defaultdict(list)
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in IMAGE:
            groups[p.parent].append(p)
    for d, files in sorted(groups.items()):
        files.sort(key=natural)
        if len(files) < 6:
            continue
        seq = is_sequence(files)
        for k, i in enumerate(range(0, len(files), 150 if seq else 200), 1):
            part = files[i:i + (150 if seq else 200)]
            if len(part) >= 6:
                plans.append(("sequence" if seq else "stills", f"{slug(d.relative_to(root)) or 'frames'}-{k:02d}", part))
    if len(plans) > a.max_clips:                                             # spread the cap evenly over everything found
        step = len(plans) / a.max_clips
        plans = [plans[int(i * step)] for i in range(a.max_clips)]

    def one(plan: tuple) -> dict:
        kind, name, data = plan
        dest = folder / f"{name}.mp4"
        truth = folder / f"{name}_truth.txt"
        if kind == "video":
            if not dest.exists():
                if data.suffix.lower() == ".mp4":
                    shutil.copy2(data, dest)
                else:
                    mrc.ffmpeg(["-i", str(data), "-an", "-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p", str(dest)])
            truth.write_text(f"{src['title']}\nOriginal video; no per-clip truth file. Labels, where the dataset has them, are in the raw download.\n", encoding="utf-8")
            return {"source": sid, "file": f"{R(sid)}/{dest.name}", "seconds": "", "fps": "", "violations": violations,
                    "truth": f"{R(sid)}/{truth.name}", "note": f"original video ({src['camera'][:80]})"}
        w, h = Image.open(data[0]).size
        size = fit(w, h)
        if kind == "sequence":
            lines = [f"{i / 10:6.1f}s  {f.name}  {label_text(f)}".rstrip() for i, f in enumerate(data)]
            if not dest.exists():
                sequence_clip(data, dest, size)
            secs, note = len(data) / 10, "consecutive frames at an assumed 10 fps, no frames generated"
        else:
            lines = [f"{msc.stamp(i * msc.STILL)}  {f.name}  {label_text(f)}".rstrip() for i, f in enumerate(data)]
            if not dest.exists():
                msc.timelapse([(f.read_bytes(), "") for f in data], dest, size)
            secs, note = len(data) * msc.STILL, "separate photos in file order, each held 1 s and dissolved into the next: spot checks, no tracking across photos"
        truth.write_text(f"{src['title']}. {note}.\ntime  photo  labels in the dataset\n" + "\n".join(lines) + "\n", encoding="utf-8")
        return {"source": sid, "file": f"{R(sid)}/{dest.name}", "seconds": round(secs), "fps": 30, "violations": violations,
                "truth": f"{R(sid)}/{truth.name}", "note": note}

    log(f"{sid}: {len(plans)} clips to make from {root.name}")
    with ThreadPoolExecutor(a.workers) as ex:
        for row in ex.map(one, plans):
            index.append(row)


def do_generic(a: argparse.Namespace, data: dict, index: list[dict], sid: str) -> None:
    src = source(data, sid)
    plan = fpc.plan(src, sample=False)
    seen = collections.Counter(f["name"] for f in plan["files"])
    count: collections.Counter = collections.Counter()
    for f in plan["files"]:                                                 # figshare can list several files under one name
        if seen[f["name"]] > 1:
            count[f["name"]] += 1
            p = Path(f["name"])
            f["name"] = str(p.with_name(f"{p.stem}_{count[f['name']]}{p.suffix}"))
    for f in plan["files"]:
        arc = get(a, sid, f)
        if arc.suffix.lower() in (".zip", ".rar", ".7z"):
            work = work_dir(a, sid, arc)
            if not (work / ".unpacked").exists():
                log(f"{sid}: unpacking {arc.name} -> {work}")
                shutil.rmtree(work, ignore_errors=True)
                extract(arc, work)
                (work / ".unpacked").write_text("ok")
            convert_tree(a, sid, work, index)
            finish_index(index)
            shutil.rmtree(work, ignore_errors=True)
            log(f"{sid}: {arc.name} done, unpacked files deleted")
    loose = a.dest / sid                                                    # videos that were downloaded as they are (Hugging Face repos)
    if any(p.suffix.lower() in VIDEO for p in loose.rglob("*") if "_x" not in p.parts):
        convert_tree(a, sid, loose, index)
        finish_index(index)
    fpc.write_notes(src, a.dest / sid, plan["files"], plan["license"])


# ---- command line -------------------------------------------------------------------------------------------------------
STEPS = {"helmet": ("helmet_myanmar", do_helmet), "ridesafe": ("ridesafe_400", do_ridesafe), "meteor": ("meteor", do_meteor)}
for _sid in GENERIC:
    STEPS[_sid] = (_sid, lambda a, d, i, _s=_sid: do_generic(a, d, i, _s))
ORDER = ["helmet", "ridesafe", *GENERIC, "meteor"]                            # the 93 GB METEOR download goes last


def dry_run(a: argparse.Namespace, data: dict, only: list[str]) -> None:
    print(f"destination {a.dest}  free {gb(free(a.dest))}\nstaging     {a.stage}  free {gb(free(a.stage))}  (used for files up to {a.stage_max_gb:g} GB)")
    total = 0
    for key in only:
        sid = STEPS[key][0]
        try:
            files = fpc.plan(source(data, sid), sample=False)["files"]
        except Exception as e:
            print(f"- {sid}: could not be looked up ({e})")
            continue
        todo = [f for f in files if not done(a.dest / sid / f["name"], f["size"])]
        size = sum(f["size"] or 0 for f in todo)
        total += size
        print(f"- {sid}: {len(todo)} of {len(files)} files still to fetch, {gb(size)}")
        for f in todo:
            print(f"    {f['name']}  {gb(f['size'] or 0)}")
    print(f"\nTo download: {gb(total)}. Clips of the helmet parts already here are converted without downloading.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="+", choices=[*STEPS, "new"], default=ORDER, help="a step, a source id, or new = every source added on 2026-11-03")
    ap.add_argument("--dest", type=Path, default=REPO / "benchmarks" / "public_clips")
    ap.add_argument("--stage", type=Path, default=REPO / "benchmarks" / "_staging")
    ap.add_argument("--reserve-gb", type=float, default=5.0, help="never let the staging disk drop below this much free space")
    ap.add_argument("--stage-max-gb", type=float, default=6.0, help="files bigger than this go straight to --dest")
    ap.add_argument("--workers", type=int, default=3, help="parallel ffmpeg jobs")
    ap.add_argument("--max-clips", type=int, default=60, help="most clips made from one downloaded archive (spread evenly over what it holds)")
    ap.add_argument("--keep-zips", action="store_true", help="keep RideSafe video zips after unpacking")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    a.only = [k for x in a.only for k in (GENERIC if x == "new" else [x])]
    a.dest, a.stage = a.dest.resolve(), a.stage.resolve()
    if "hulikamote_backend" in a.dest.parts or "hulikamote_backend" in a.stage.parts:
        raise SystemExit("Refusing to write inside hulikamote_backend/ (a write there restarts the running backend).")
    if not a.dest.exists():
        raise SystemExit(f"{a.dest} does not exist: is the external drive connected?")
    a.stage.mkdir(parents=True, exist_ok=True)
    a.cross_drive = a.dest.drive.lower() != a.stage.drive.lower()
    a.dest_factor = {"meteor": 2.2}
    mrc.SRC, mrc.OUT = a.dest, a.dest / "ready"          # raw files and clips both live on the destination
    data = fpc.load()
    if a.dry_run:
        dry_run(a, data, a.only)
        return 0
    failed, index = [], []
    for key in a.only:
        sid, step = STEPS[key]
        log(f"==== {sid}")
        try:
            step(a, data, index)
        except Exception as e:                                     # one source failing must not stop the others
            log(f"FAILED {sid}: {e}\n    run the same command again to resume")
            failed.append(sid)
            index.clear()
    if not (a.stage.exists() and any(a.stage.rglob("*"))):
        shutil.rmtree(a.stage, ignore_errors=True)
    log("by hand (needs an account or a form, never bypassed): " +
        ", ".join(s["id"] for s in data["sources"] if s["host"] in ("manual", "kaggle", "roboflow")))
    log(f"finished; free on destination {gb(free(a.dest))}" + (f"; NOT finished: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
