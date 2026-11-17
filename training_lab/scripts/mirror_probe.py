"""
mirror_probe.py - can a model learn the motorcycle side mirror from the data we have? (feasibility test, T4)

The only mirror data is the source mc_helmet_overload inside datasets/cabin_specialist: small motorcycle crops of ONE
street camera, all in the train split (no val, no test), so the cabin model's mirror class was never scored.
This script builds a separate one-class dataset from those crops, split by TIME (blocks of 100 video frames go
whole to train, val or test: neighbouring frames look the same, a random split would leak), and writes test lists
by crop height so the smallest crop size that works can be read from the results. Nothing in datasets/ is changed.

    python training_lab/scripts/mirror_probe.py            # builds training_lab/runs/mirror_probe/dataset, prints the commands
Then run the printed `yolo` commands (train about 30-60 min on the laptop GPU, each val under a minute).
"""
import re
import shutil
from collections import Counter
from pathlib import Path

import cv2

LAB = Path(__file__).resolve().parents[1]
SOURCE = LAB / "datasets" / "cabin_specialist"
OUT = LAB / "runs" / "mirror_probe" / "dataset"
PREFIX = "mc_helmet_overload__"
MIRROR_ID = 4                       # side_mirror in cabin_specialist/data.yaml
BLOCK = 100                         # video frames per block
PATTERN = ["train", "train", "train", "val", "test"]       # of every 5 blocks in time order (the source has only 15 blocks)
BINS = ((0, 70), (70, 100), (100, 140), (140, 10000))      # crop height in pixels

_NAME = re.compile(r"__(?P<video>.+?)-(?P<frame>\d+)_jpg\.rf\.")


def main():
    images = sorted(p for p in (SOURCE / "images" / "train").iterdir() if p.name.startswith(PREFIX))
    blocks = sorted({(m["video"], int(m["frame"]) // BLOCK) for m in map(_NAME.search, (p.name for p in images)) if m})
    split_of = {block: PATTERN[i % len(PATTERN)] for i, block in enumerate(blocks)}
    if OUT.exists():                # a rebuild starts clean (an older split must not stay mixed in)
        shutil.rmtree(OUT)
    for split in ("train", "val", "test"):
        (OUT / "images" / split).mkdir(parents=True, exist_ok=True)
        (OUT / "labels" / split).mkdir(parents=True, exist_ok=True)

    pictures, boxes = Counter(), Counter()
    by_bin: dict = {b: [] for b in BINS}
    for img in images:
        m = _NAME.search(img.name)
        if not m:
            continue
        split = split_of[(m["video"], int(m["frame"]) // BLOCK)]
        label = SOURCE / "labels" / "train" / (img.stem + ".txt")
        rows = [r.split() for r in label.read_text(encoding="utf-8").splitlines()] if label.exists() else []
        mirrors = ["0 " + " ".join(r[1:5]) for r in rows if r and int(r[0]) == MIRROR_ID]
        dest = OUT / "images" / split / img.name
        if not dest.exists():
            shutil.copy2(img, dest)
        (OUT / "labels" / split / (img.stem + ".txt")).write_text("\n".join(mirrors), encoding="utf-8")
        pictures[split] += 1
        boxes[split] += len(mirrors)
        if split == "test":
            picture = cv2.imread(str(img))
            if picture is not None:
                height = picture.shape[0]
                next(v for (lo, hi), v in by_bin.items() if lo <= height < hi).append(dest)

    def yaml_for(name: str, test: str) -> Path:
        path = OUT / f"{name}.yaml"
        path.write_text(f"path: {OUT.as_posix()}\ntrain: images/train\nval: images/val\ntest: {test}\nnc: 1\nnames:\n  0: side_mirror\n",
                        encoding="utf-8")
        return path

    data = yaml_for("data", "images/test")
    print(f"{len(blocks)} time blocks of {BLOCK} frames; pictures {dict(pictures)}; mirror boxes {dict(boxes)}")
    yolo = "hulikamote_backend/venv/Scripts/yolo.exe"
    run = "training_lab/runs/mirror_probe"
    print("\n1. Train (from the repo root; the backend may stay off):")
    print(f"   {yolo} detect train data={data.as_posix()} model=yolov8n.pt imgsz=320 epochs=60 batch=32 project={run} name=train")
    print("2. Score on the held-out test blocks (precision and recall are in the 'all' row):")
    print(f"   {yolo} detect val data={data.as_posix()} model={run}/train/weights/best.pt split=test imgsz=320")
    print("3. The same by crop height (the smallest height whose recall is still acceptable is the answer):")
    for (lo, hi), files in by_bin.items():
        if not files:
            continue
        listing = OUT / f"test_h{lo}.txt"
        listing.write_text("\n".join(f.as_posix() for f in files), encoding="utf-8")
        binned = yaml_for(f"data_h{lo}", listing.name)
        print(f"   height {lo}-{hi} px, {len(files)} pictures:  {yolo} detect val data={binned.as_posix()} "
              f"model={run}/train/weights/best.pt split=test imgsz=320")


if __name__ == "__main__":
    main()
