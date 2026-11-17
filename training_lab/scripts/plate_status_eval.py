"""
plate_status_eval.py - numbers behind "no plate" versus "plate not read" (engine/violations/no_plate.py).

It feeds the deployed plate model the HELD-OUT pictures of the plate dataset (the test split, never trained on),
the same way the app feeds it (engine.specialists.detect), and reports how confident the model is:
  - on pictures that HAVE a plate (a label file with a box): how often one look is "sure" (>= 0.5), weak (0.1 - 0.5)
    or blind (< 0.1), and how often a vehicle would be called "plate seen" after N looks,
  - on pictures with NO plate (an empty label file), if the split has any: how often the model fires anyway.
Use the table to set PLATE_SURE_CONF and PLATE_SEEN_SUM in no_plate.py.

    python training_lab/scripts/plate_status_eval.py                    (about 2 minutes; writes nothing)
    python training_lab/scripts/plate_status_eval.py --split val --limit 300
"""
import argparse
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "hulikamote_backend"))

import torch  # noqa: E402,F401  (must be imported before onnxruntime on Windows)
import cv2  # noqa: E402
import numpy as np  # noqa: E402

from engine import specialists  # noqa: E402
from engine.violations.no_plate import PLATE_SEEN_SUM, PLATE_SURE_CONF  # noqa: E402
from inference.providers import make_session  # noqa: E402

DATASET = REPO / "training_lab" / "datasets" / "plate_specialist"
MODELS = REPO / "hulikamote_backend" / "models" / "Plate Models"


def best_conf(session, image) -> float:
    plates = [d for d in specialists.detect(session, image, specialists.SEARCH_CONF)
              if d["class_id"] == specialists.IDX_LICENSE_PLATE]
    return float(plates[0]["confidence"]) if plates else 0.0


def seen_after(confs: list, looks: int, rng: random.Random, trials: int = 2000) -> float:
    """Share of vehicles called "plate seen" when `looks` looks are drawn at random from these confidences."""
    hit = 0
    for _ in range(trials):
        sample = [c for c in (rng.choice(confs) for _ in range(looks)) if c > 0]
        hit += bool(sample) and (max(sample) >= PLATE_SURE_CONF or sum(sample) >= PLATE_SEEN_SUM)
    return hit / trials


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="test")
    ap.add_argument("--limit", type=int, default=0, help="at most this many pictures (0 = all)")
    ap.add_argument("--model", default="", help="plate model file name (default: the newest in models/Plate Models)")
    args = ap.parse_args()

    model = MODELS / args.model if args.model else max(MODELS.glob("*.onnx"), key=lambda p: p.stat().st_mtime)
    session = make_session(str(model))
    images = sorted((DATASET / "images" / args.split).glob("*.*"))
    if args.limit:
        random.Random(0).shuffle(images)
        images = images[:args.limit]
    with_plate, without = [], []
    for img in images:
        label = DATASET / "labels" / args.split / (img.stem + ".txt")
        picture = cv2.imread(str(img))
        if picture is None:
            continue
        has_plate = label.exists() and label.read_text(encoding="utf-8").strip() != ""
        (with_plate if has_plate else without).append(best_conf(session, picture))

    print(f"model {model.name}, split {args.split}: {len(with_plate)} pictures with a plate, {len(without)} without")
    if with_plate:
        c = np.array(with_plate)
        print(f"WITH a plate   sure (>= {PLATE_SURE_CONF}): {np.mean(c >= PLATE_SURE_CONF):.1%}   "
              f"weak (0.1 - {PLATE_SURE_CONF}): {np.mean((c > 0) & (c < PLATE_SURE_CONF)):.1%}   blind (no box): {np.mean(c == 0):.1%}")
        rng = random.Random(0)
        for looks in (1, 3, 6):
            print(f"   after {looks} looks: called 'plate seen' {seen_after(with_plate, looks, rng):.1%}, "
                  f"all {looks} looks blind (would be 'no plate' at 6) {np.mean(c == 0) ** looks:.1%}")
    if without:
        c = np.array(without)
        print(f"WITHOUT a plate   model fires anyway: {np.mean(c > 0):.1%}   fires 'sure': {np.mean(c >= PLATE_SURE_CONF):.1%}")
    else:
        print("WITHOUT a plate   this split has no picture with an empty label: the false-fire rate cannot be measured here.\n"
              "                  Label some plateless vehicles in the harvest tool (N = nothing here) and run again.")


if __name__ == "__main__":
    main()
