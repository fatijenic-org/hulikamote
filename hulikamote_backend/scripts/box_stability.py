"""
box_stability.py - how steady are the boxes of a saved live run, and what would the box stabilizer (engine/box_stabilizer.py) change?

Reads the index.jsonl of a saved run (the boxes and track numbers of every picture) - no video and no model is needed - and prints:
  - blinks:  a vehicle's box is missing for 1..30 pictures and then comes back under the same number (what the eye sees as blinking)
  - broken:  a new number starts close to where another number just ended (the same vehicle under two numbers)
  - jumps:   the same number moves more than 1.5 box sizes between two pictures
and, for several hold times, the same run through the stabilizer: how many blink pictures got a ghost (good), how many ghost pictures were
wasted (the vehicle did not come back within the hold), and what is left blinking.

    venv\\Scripts\\python.exe scripts\\box_stability.py "A:\\huli-kamote\\videos\\live_run_20261121_065801" [more run folders]
"""
import json
import statistics
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from engine.box_stabilizer import BoxStabilizer  # noqa: E402
from engine.violations.base import VEHICLE_CLASSES  # noqa: E402

MAX_BLINK = 30
HOLDS = (0.3, 0.6, 1.0, 1.5)


def load(folder: Path):
    """[(t, [(track_id, [x, y, w, h], class)])] of a saved run."""
    frames = []
    with open(folder / "index.jsonl", "rb") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            dets = []
            for d in row.get("detections") or []:
                tid = d.get("track_id", -1)
                box = d.get("bbox")
                if tid is None or tid == -1 or not box or len(box) != 4:
                    continue
                cls = d.get("class") or "car"
                dets.append((int(tid), [float(v) for v in box], cls if cls in VEHICLE_CLASSES else "car", bool(d.get("is_violator"))))
            frames.append((float(row.get("t") or 0.0), dets))
    return frames


def fps_of(frames) -> float:
    gaps = sorted(b[0] - a[0] for a, b in zip(frames, frames[1:]) if b[0] > a[0])
    return 1.0 / gaps[len(gaps) // 2] if gaps else 25.0


def appearances(frames):
    seen: dict = {}
    for i, (_t, dets) in enumerate(frames):
        for tid, box, _cls, _v in dets:
            seen.setdefault(tid, []).append((i, box))
    return seen


def baseline(frames):
    seen = appearances(frames)
    blink_events = blink_frames = jumps = 0
    ends, starts = {}, {}
    for tid, rows in seen.items():
        starts[tid], ends[tid] = rows[0], rows[-1]
        for (i, a), (j, b) in zip(rows, rows[1:]):
            gap = j - i - 1
            if 1 <= gap <= MAX_BLINK:
                blink_events += 1
                blink_frames += gap
            if gap == 0:
                size = max(a[2], a[3], 1.0)
                if ((a[0] + a[2] / 2 - b[0] - b[2] / 2) ** 2 + (a[1] + a[3] / 2 - b[1] - b[3] / 2) ** 2) ** 0.5 > 1.5 * size:
                    jumps += 1
    broken = 0
    for tid, (i0, b0) in starts.items():
        for other, (i1, b1) in ends.items():
            if other == tid or not (0 < i0 - i1 <= 30):
                continue
            size = max(b1[2], b1[3], 1.0)
            if ((b0[0] + b0[2] / 2 - b1[0] - b1[2] / 2) ** 2 + (b0[1] + b0[3] / 2 - b1[1] - b1[3] / 2) ** 2) ** 0.5 < size:
                broken += 1
                break
    vehicle_frames = sum(len(r) for r in seen.values())
    return {"tracks": len(seen), "vehicle_frames": vehicle_frames, "blink_events": blink_events, "blink_frames": blink_frames,
            "broken": broken, "jumps": jumps}


def _iou(a, b) -> float:
    iw = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    ih = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def simulate(frames, hold_s: float, fps: float, size=(1280, 720)):
    """A ghost picture is GOOD when the vehicle is seen again within the hold, under its own number or under another one that covers the
    ghost's place (the box would have blinked otherwise); else it is WASTED (the vehicle had really gone: a ghost for nothing)."""
    stab = BoxStabilizer(hold_s=hold_s, fps=fps)
    ghosts = []                          # (picture, track id, box)
    for i, (_t, dets) in enumerate(frames):
        items = [SimpleNamespace(track_id=tid, bbox=box, cls=cls, confidence=0.8, is_violator=viol, violation_type="")
                 for tid, box, cls, viol in dets]
        for g in stab.step(items, i, size):
            ghosts.append((i, g.track_id, [float(v) for v in g.bbox]))
    hold = stab.hold_frames
    good = wasted = 0
    for i, tid, box in ghosts:
        found = False
        for j in range(i + 1, min(len(frames), i + hold + 2)):
            for other, b, _c, _v in frames[j][1]:
                if other == tid or _iou(box, b) >= 0.25:
                    found = True
                    break
            if found:
                break
        good += found
        wasted += not found
    return {"hold_s": hold_s, "hold_frames": hold, "ghost_frames": good + wasted, "good": good, "wasted": wasted, "stats": stab.stats}


def report(folder: Path) -> None:
    frames = load(folder)
    if not frames:
        print(f"{folder.name}: no pictures")
        return
    fps = fps_of(frames)
    base = baseline(frames)
    print(f"\n== {folder.name}: {len(frames)} pictures, about {fps:.0f} per second, {base['tracks']} tracks, {base['vehicle_frames']} vehicle-boxes")
    pct = 100.0 * base["blink_frames"] / max(1, base["vehicle_frames"])
    print(f"   blinks: {base['blink_events']} events, {base['blink_frames']} missing pictures ({pct:.1f}% of all boxes)")
    print(f"   broken numbers (same place, new number within 1 s): {base['broken']}    jumps (> 1.5 box sizes in one picture): {base['jumps']}")
    size = (1280, 720)
    try:
        first = json.loads(open(folder / "index.jsonl", "rb").readline())
        size = (int(first.get("w") or 1280), int(first.get("h") or 720))
    except (OSError, ValueError):
        pass
    for hold in HOLDS:
        r = simulate(frames, hold, fps, size)
        left = max(0, base["blink_frames"] - r["good"])
        waste = 100.0 * r["wasted"] / max(1, r["ghost_frames"])
        print(f"   hold {hold:.1f}s ({r['hold_frames']} pictures): ghost pictures {r['ghost_frames']}  good {r['good']}  wasted {r['wasted']} ({waste:.0f}%)"
              f"  -> still blinking about {left} pictures")


if __name__ == "__main__":
    folders = [Path(a) for a in sys.argv[1:]]
    if not folders:
        print(__doc__)
        sys.exit(1)
    for f in folders:
        report(f)
