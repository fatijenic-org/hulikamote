"""
reid_suggest_class.py - Guess the class (car, motorcycle, tricycle, bus, truck) of every vehicle folder in datasets/reid.

    python training_lab/scripts/reid_suggest_class.py --out classes.json

For each vehicle (images/<analysis>/<vehicle>/ and temporary/<analysis>/<vehicle>/) up to --photos photos, evenly spread, go through
the 6-class vehicle model (the newest training_lab/runs/primary_anchor/*/weights/best.pt, or --weights). In each photo the class with the
largest confidence x area wins; the vehicle gets the class most of its photos agree on, but only when at least 2 photos voted and 3 of 4
of them agree (a split vote is left to you). Photos where nothing is found cast no vote.
It only suggests "car" and "motorcycle": on the real photos it was right for those, but it mixed up trucks, tricycles and buses (many
tricycles came out as "truck"), so those are left for you to set. 
It only READS the photos and writes the JSON file. Used by Datasets > Car matcher (ReID) > Suggest classes: a hint, never a decision
(a class you set, or the ticket's class, always wins).
"""
import argparse
import json
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent            # training_lab/
VEHICLES = ("car", "motorcycle", "tricycle", "bus", "truck")
RELIABLE = ("car", "motorcycle")      # checked by eye on the real photos: right for these; trucks, tricycles and buses were mixed up
MIN_VOTERS, MIN_AGREE = 2, 0.75        # a suggestion needs at least 2 photos with a vehicle in them and 3 of 4 of those to agree
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def spread(items: list, n: int) -> list:
    if len(items) <= n:
        return list(items)
    return [items[round(i * (len(items) - 1) / (n - 1))] for i in range(n)] if n > 1 else [items[0]]


def photo_class(boxes: list[tuple[str, float, float]]) -> str | None:
    """boxes: (class name, confidence, area share of the photo) -> the vehicle class with the largest confidence x area, or None."""
    score: dict[str, float] = defaultdict(float)
    for name, conf, area in boxes:
        if name in VEHICLES:
            score[name] += conf * max(area, 1e-6)
    return max(score, key=score.get) if score else None


def vote(per_photo: list[str | None]) -> tuple[str, int, int] | None:
    """The class most photos agree on -> (class, photos that agree, photos that voted). Ties go to the first class that reached the top."""
    votes = [c for c in per_photo if c]
    if not votes:
        return None
    counts = Counter(votes)
    top = max(counts.values())
    winner = next(c for c in votes if counts[c] == top)
    return winner, top, len(votes)


def confident(winner: tuple[str, int, int] | None) -> bool:
    """Only suggest a car or a motorcycle that most photos agree on: a guess from one photo, a split vote, or a class the model
    mixes up (truck / tricycle / bus) is left for you."""
    return (winner is not None and winner[0] in RELIABLE and winner[2] >= MIN_VOTERS
            and winner[1] / winner[2] >= MIN_AGREE)


def newest_weights() -> Path:
    runs = sorted((ROOT / "runs" / "primary_anchor").glob("*/weights/best.pt"), key=lambda p: p.stat().st_mtime)
    if not runs:
        raise FileNotFoundError("no vehicle model found: train primary_anchor first, or pass --weights")
    return runs[-1]


def vehicle_folders(data_dir: Path) -> list[tuple[str, Path]]:
    out = []
    for base in (data_dir / "images", data_dir / "temporary"):
        if not base.is_dir():
            continue
        for a in sorted(p for p in base.iterdir() if p.is_dir()):
            for c in sorted(p for p in a.iterdir() if p.is_dir()):
                key = f"{a.name}/{c.name}"
                if base.name == "temporary" and (data_dir / "images" / a.name / c.name).is_dir():
                    continue
                out.append((key, c))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="the JSON file to write")
    ap.add_argument("--data-dir", default=str(ROOT / "datasets" / "reid"))
    ap.add_argument("--weights", help="a vehicle model (default: the newest primary_anchor run)")
    ap.add_argument("--photos", type=int, default=4, help="photos looked at per vehicle")
    ap.add_argument("--cpu", action="store_true", help="do not use the GPU")
    args = ap.parse_args(argv)
    from ultralytics import YOLO
    weights = Path(args.weights) if args.weights else newest_weights()
    model = YOLO(str(weights))
    folders = vehicle_folders(Path(args.data_dir))
    result: dict[str, dict] = {}
    for key, folder in folders:
        files = sorted(f for f in folder.iterdir() if f.suffix.lower() in IMAGE_EXT)
        per_photo = []
        for f in spread(files, args.photos):
            r = model.predict(str(f), imgsz=640, conf=0.15, verbose=False, device="cpu" if args.cpu else None)[0]
            h, w = r.orig_shape
            boxes = [(model.names[int(c)], float(p), float((x2 - x1) * (y2 - y1)) / (w * h))
                     for (x1, y1, x2, y2), c, p in zip(r.boxes.xyxy.tolist(), r.boxes.cls.tolist(), r.boxes.conf.tolist())]
            per_photo.append(photo_class(boxes))
        winner = vote(per_photo)
        if confident(winner):
            result[key] = {"class": winner[0], "agree": winner[1], "of": winner[2]}
    Path(args.out).write_text(json.dumps({"ts": time.time(), "weights": weights.parent.parent.name, "vehicles": len(folders),
                                          "classes": result}), encoding="utf-8")
    print(f"[Suggest] {len(result)} of {len(folders)} vehicles got a class ({weights.parent.parent.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
