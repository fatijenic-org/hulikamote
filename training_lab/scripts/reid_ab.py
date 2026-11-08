"""
reid_ab.py - Count suspected ID jumps with the old and the new car matcher on the SAME clip.

    python training_lab/scripts/reid_ab.py --task <analysis id, or its first 8 characters> --new <path to the new ckpt.t7>
    python training_lab/scripts/reid_ab.py --video some_clip.mp4 --old a.t7 --new b.t7

The vehicle finder runs ONCE on the clip (its boxes are cached next to the results). DeepSORT then runs twice on those very
same boxes with the app's own settings (engine/tracker.py), once per car matcher, so the only difference between the two runs
is the matcher. The analysis must have kept its video ("Keep the uploaded video" in the wizard), or give --video.

There is no ground truth here, so the numbers are SUSPECTED errors, counted the same way for both matchers:
    jump   a track starts soon after, and close to where, another one ended, and the two look alike (colour layout):
           probably ONE car that got a new number
    merge  one track whose look changes abruptly between samples: probably TWO cars that share one number
Fewer is better. Check the worst ones by eye (Harvest > Same car?) before believing a small difference.

Reads the repo, writes only to training_lab/runs/reid_ab/. Not for running while a training uses the GPU.
"""
import argparse
import json
import math
import statistics
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent                  # training_lab/
REPO = ROOT.parent
BACKEND = REPO / "hulikamote_backend"
CKPT_DIR = BACKEND / "engine" / "deep_sort" / "deep" / "checkpoint"
sys.path.insert(0, str(ROOT))

from harvest_tool.pairs import how_alike, look  # noqa: E402  (a model-free colour look: it cannot favour either matcher)

# What the app runs (engine/tracker.py DeepSortStrategy, "LOCKED BY USER"): copied here, never changed here.
APP_TRACKER = dict(max_dist=0.4, min_confidence=0.1, nms_max_overlap=0.5, max_iou_distance=0.7, max_age=90, n_init=3, nn_budget=100)
DETECT_CONF, DETECT_IOU = 0.45, 0.45                           # engine/yolo_inference.py CONFIDENCE_THRESHOLD / IOU

SHORT_SECONDS = 1.0            # a track shorter than this is a fragment
JUMP_GAP_SECONDS = 1.5         # a new track this soon after another ended may be the same car
GATE_BOX_FACTOR, GATE_MIN_PX = 1.2, 40.0       # as engine/track_stitcher.py: how far a car may have moved
AREA_RATIO = (0.4, 2.5)
JUMP_LOOK = 0.6                # colour likeness needed to suspect a jump
MERGE_LOOK = 0.35              # colour likeness below this between two samples of ONE track suspects a merge
SAMPLE_SECONDS = 0.4


# ── finding things ──

def find_video(task: str) -> Path:
    from harvest_tool.config import Paths
    from harvest_tool.sources import forensic_task_ids
    paths = Paths()
    hits = [t for t in forensic_task_ids(paths) if t.startswith(task)] or [
        d.name for d in paths.forensic.iterdir() if d.is_dir() and d.name.startswith(task)]
    if not hits:
        raise SystemExit(f"No analysis starts with '{task}'.")
    video = paths.forensic / hits[0] / "input_video.mp4"
    if not video.exists():
        raise SystemExit(f"Analysis {hits[0][:8]} did not keep its video. Turn on \"Keep the uploaded video\" in the wizard, "
                         "or pass --video.")
    return video


def default_old() -> Path:
    original = CKPT_DIR / "ckpt_original.t7"                  # made by the Studio the first time it deploys a new matcher
    return original if original.exists() else CKPT_DIR / "ckpt.t7"


# ── 1. the boxes, once ──

def detect_clip(video: Path, seconds: float, cache: Path) -> dict:
    """Vehicle boxes of every frame of the first `seconds` of the clip: {"fps", "size", "frames": [[x1,y1,x2,y2,conf], ...]}."""
    cap = cv2.VideoCapture(str(video))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    size = [int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))]
    frames_wanted = min(total, int(seconds * fps)) if seconds > 0 else total
    key = {"video": video.name, "bytes": video.stat().st_size, "mtime": int(video.stat().st_mtime), "frames": frames_wanted}
    if cache.exists():
        try:
            cached = json.loads(cache.read_text())
            if cached.get("key") == key:
                cap.release()
                return cached
        except ValueError:
            pass
    from harvest_tool.config import active_vehicle_onnx, Paths
    from harvest_tool.cut_plates import vehicle_classes
    from harvest_tool.detect import Detector
    onnx = active_vehicle_onnx(Paths())
    if onnx is None:
        raise SystemExit("No vehicle detector found in hulikamote_backend/models/.")
    detector = Detector.load(onnx, threads=4)
    kinds = vehicle_classes(detector)
    frames = []
    for i in range(frames_wanted):
        ok, bgr = cap.read()
        if not ok:
            break
        dets = [d for d in detector.detect(bgr, conf=DETECT_CONF, iou=DETECT_IOU) if d.cls in kinds]
        frames.append([[round(d.x1, 1), round(d.y1, 1), round(d.x2, 1), round(d.y2, 1), round(d.conf, 3)] for d in dets])
        if (i + 1) % 100 == 0:
            print(f"  detecting vehicles: frame {i + 1}/{frames_wanted}", flush=True)
    cap.release()
    result = {"key": key, "fps": fps, "size": size, "frames": frames}
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(result))
    return result


# ── 2. the tracker, once per matcher, on the same boxes ──

def app_tracker(ckpt: Path, size: tuple | None = None):
    """DeepSORT with the app's own settings and the given car matcher (read-only import of the backend's code).
    size = (width, height) the car crops are stretched to; None = whatever the app uses now."""
    import torch
    sys.path.insert(0, str(BACKEND))
    from engine.deep_sort.deep_sort import DeepSort
    tracker = DeepSort(model_path=str(ckpt), use_cuda=torch.cuda.is_available(), **APP_TRACKER)
    if size:
        tracker.extractor.size = size
    return tracker


def parse_size(text: str | None) -> tuple | None:
    return tuple(int(v) for v in text.lower().split("x")) if text else None


def track_video(video: Path, clip: dict, make_tracker, sample_every: int) -> dict:
    """Replays the clip frame by frame. -> {track id: {"frames": [...], "boxes": [[x1,y1,x2,y2], ...], "first", "last", "samples"}}
    where first / last / samples are model-free colour looks of the car at those moments."""
    tracker = make_tracker()
    cap = cv2.VideoCapture(str(video))
    tracks: dict = {}
    for i, dets in enumerate(clip["frames"]):
        ok, bgr = cap.read()
        if not ok:
            break
        if not dets:                       # as the app: with nothing detected the tracker is not asked at all
            continue
        boxes = np.array([[(d[0] + d[2]) / 2, (d[1] + d[3]) / 2, d[2] - d[0], d[3] - d[1]] for d in dets], dtype=float)
        conf = np.array([d[4] for d in dets], dtype=float)
        outputs, _ = tracker.update(boxes, conf, cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        for x1, y1, x2, y2, tid in (outputs if len(outputs) else []):
            x1, y1, x2, y2, tid = int(x1), int(y1), int(x2), int(y2), int(tid)
            if x2 - x1 < 8 or y2 - y1 < 8:
                continue
            t = tracks.setdefault(tid, {"frames": [], "boxes": [], "first": None, "last": None, "samples": []})
            desc = look(bgr[y1:y2, x1:x2])
            if t["first"] is None:
                t["first"] = desc
            t["last"] = desc
            if not t["frames"] or i - t.get("_sampled", -10**9) >= sample_every:
                t["samples"].append(desc)
                t["_sampled"] = i
            t["frames"].append(i)
            t["boxes"].append([x1, y1, x2, y2])
    cap.release()
    return tracks


# ── 3. count the suspected errors (pure: no video, no model) ──

def _centre(b):
    return (b[0] + b[2]) / 2, (b[1] + b[3]) / 2


def _side(b):
    return max(b[2] - b[0], b[3] - b[1])


def _area(b):
    return max(1.0, (b[2] - b[0]) * (b[3] - b[1]))


def summarise(tracks: dict, fps: float) -> dict:
    """tracks as made by track_video. Same thresholds whatever matcher made the tracks."""
    lengths = [len(t["frames"]) / fps for t in tracks.values()]
    short = sum(1 for n in lengths if n < SHORT_SECONDS)

    # jump: B starts soon after A ended, near where A ended, similar size, and looks like A -> one car, two numbers
    ended = {i: (t["frames"][-1], t["boxes"][-1], t["last"]) for i, t in tracks.items()}
    started = {i: (t["frames"][0], t["boxes"][0], t["first"]) for i, t in tracks.items()}
    candidates = []
    for a, (fa, ba, da) in ended.items():
        for b, (fb, bb, db) in started.items():
            gap = (fb - fa) / fps
            if a == b or gap < 0 or gap > JUMP_GAP_SECONDS:
                continue
            (xa, ya), (xb, yb) = _centre(ba), _centre(bb)
            if math.hypot(xb - xa, yb - ya) > GATE_BOX_FACTOR * max(_side(ba), _side(bb)) + GATE_MIN_PX:
                continue
            if not AREA_RATIO[0] <= _area(bb) / _area(ba) <= AREA_RATIO[1]:
                continue
            like = how_alike(da, db)
            if like >= JUMP_LOOK:
                candidates.append((like, a, b))
    jumps, used_a, used_b = [], set(), set()
    for like, a, b in sorted(candidates, reverse=True):            # one old track, one new track, best look first
        if a not in used_a and b not in used_b:
            used_a.add(a)
            used_b.add(b)
            jumps.append({"ended": a, "started": b, "look": round(like, 3)})

    # merge: the look of ONE track changes abruptly between two samples -> two cars, one number
    merges = []
    for i, t in tracks.items():
        s = t["samples"]
        worst = min((how_alike(s[k], s[k + 1]) for k in range(len(s) - 1)), default=1.0)
        if len(s) >= 3 and worst < MERGE_LOOK:
            merges.append({"track": i, "look": round(worst, 3)})

    return {
        "tracks": len(tracks),
        "short_tracks": short,
        "median_track_seconds": round(statistics.median(lengths), 2) if lengths else 0.0,
        "suspected_jumps": len(jumps),
        "suspected_merges": len(merges),
        "suspected_errors": len(jumps) + len(merges),
        "jumps": jumps,
        "merges": merges,
    }


# ── the command ──

def table(old: dict, new: dict) -> str:
    rows = [("tracks", "tracks"), ("tracks shorter than 1 s", "short_tracks"), ("median track length (s)", "median_track_seconds"),
            ("suspected jumps (one car, new number)", "suspected_jumps"), ("suspected merges (two cars, one number)", "suspected_merges"),
            ("suspected errors in all", "suspected_errors")]
    lines = [f"{'':<42}{'old':>8}{'new':>8}"]
    for label, key in rows:
        lines.append(f"{label:<42}{old[key]:>8}{new[key]:>8}")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", help="the analysis (id or its first 8 characters); it must have kept its video")
    ap.add_argument("--video", help="a clip instead of an analysis")
    ap.add_argument("--old", help="the car matcher to compare against (default: the original ckpt.t7)")
    ap.add_argument("--new", required=True, help="the new car matcher (a ckpt.t7 file)")
    ap.add_argument("--seconds", type=float, default=20.0, help="how much of the clip to replay (0 = all)")
    ap.add_argument("--old-size", help="WxH the old matcher is fed, e.g. 64x128 (default: the app's current size)")
    ap.add_argument("--new-size", help="WxH the new matcher is fed, e.g. 96x192 (default: the app's current size)")
    args = ap.parse_args(argv)
    if not (args.task or args.video):
        ap.error("give --task or --video")
    video = Path(args.video) if args.video else find_video(args.task)
    old, new = Path(args.old) if args.old else default_old(), Path(args.new)
    for f in (video, old, new):
        if not f.exists():
            raise SystemExit(f"Not found: {f}")
    out = ROOT / "runs" / "reid_ab" / (args.task[:8] if args.task else video.stem)
    print(f"clip {video.name}, old {old.name}, new {new.name}", flush=True)
    t0 = time.time()
    clip = detect_clip(video, args.seconds, out / "detections.json")
    fps = clip["fps"]
    every = max(1, int(SAMPLE_SECONDS * fps))
    print(f"{len(clip['frames'])} frames, {sum(len(f) for f in clip['frames'])} vehicle boxes ({time.time() - t0:.0f}s)", flush=True)
    results = {}
    for name, ckpt, size in (("old", old, parse_size(args.old_size)), ("new", new, parse_size(args.new_size))):
        t1 = time.time()
        results[name] = summarise(track_video(video, clip, lambda c=ckpt, s=size: app_tracker(c, s), every), fps)
        print(f"{name}: {results[name]['tracks']} tracks ({time.time() - t1:.0f}s)", flush=True)
    print()
    print(table(results["old"], results["new"]))
    better = results["old"]["suspected_errors"] - results["new"]["suspected_errors"]
    print("\n" + (f"The new matcher has {better} fewer suspected errors." if better > 0 else
                  f"The new matcher has {-better} MORE suspected errors." if better < 0 else "No difference in suspected errors."))
    print("These are suspects, not proof: look at them in Harvest > Same car? before believing a small difference.")
    out.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    (out / f"ab_{stamp}.json").write_text(json.dumps({"video": str(video), "old": str(old), "new": str(new), "seconds": args.seconds,
                                                      "results": results}, indent=1))
    print(f"saved {out / f'ab_{stamp}.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
