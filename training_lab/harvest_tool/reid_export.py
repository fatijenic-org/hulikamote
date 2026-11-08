"""
reid_export.py - Put the car folders in the shape the repo's own ReID trainer reads.

hulikamote_backend/engine/deep_sort/deep/train.py reads  <dir>/train/<car>/*.jpg  and  <dir>/val/<car>/*.jpg  (the SAME cars
in both, or its class numbers drift apart) and it crashes on a picture that is not already 64 wide x 128 tall: its random
crop has no resize step. datasets/reid is one folder per car under each analysis, with pictures of any size and no split.
So this writes a resized, split COPY into a folder of your choice. datasets/reid itself is never touched.

Pictures are stretched to 64x128 the way the tracker stretches a car before it asks the matcher for a fingerprint.
"""
import shutil
from pathlib import Path

import cv2

from .config import Paths

SIZE = (64, 128)                      # width, height
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp"}

HOW_TO = """HOW TO TRAIN THE CAR MATCHER ON THIS FOLDER

1. Copy train.py, model.py and original_model.py from hulikamote_backend/engine/deep_sort/deep/ into an empty scratch
   folder, so nothing is written under hulikamote_backend while the backend runs.
2. In that scratch folder:   python train.py --data-dir <this folder>
   It trains 40 epochs and writes checkpoint/original_e<epoch>acc<accuracy>.t7 (and train.jpg) next to itself.
3. To judge it, compare ID switches on the same clip before and after (benchmark), not the accuracy printed by train.py:
   that accuracy is "which of these cars is it", on photos of cars it already trained on.
4. To use it: keep a copy of hulikamote_backend/engine/deep_sort/deep/checkpoint/ckpt.t7, then put the new file there as
   ckpt.t7 (stop the backend first).
Starting from the old ckpt.t7 instead of from scratch: train.py --resume will fail because the old file has the wrong number
of cars in its last layer; load every weight except the layers named classifier.* .
"""


def _cars(paths: Paths, include_public: bool) -> list[tuple[str, Path]]:
    """(name, folder) of every car: one folder of its pictures."""
    found: list[tuple[str, Path]] = []
    roots = [paths.datasets / "reid" / "images"]
    if include_public:
        roots.append(paths.datasets / "reid_public" / "images")
    for root in roots:
        if not root.exists():
            continue
        for group in sorted(p for p in root.iterdir() if p.is_dir()):
            for car in sorted(p for p in group.iterdir() if p.is_dir()):
                name = car.name if root.parent.name == "reid" else f"{group.name}_{car.name}"
                found.append((name, car))
    return found


def reid_export(paths: Paths, out: Path, val_every: int = 5, min_photos: int = 4, include_public: bool = False) -> dict:
    out = Path(out).resolve()
    reid = (paths.datasets / "reid").resolve()
    if out == reid or reid in out.parents or out in reid.parents:
        raise ValueError("Choose a folder outside datasets/reid")
    if out.exists() and any(out.iterdir()):
        raise ValueError(f"{out} is not empty: choose a new folder")
    summary = {"cars": 0, "train": 0, "val": 0, "skipped_cars": 0, "unreadable": 0, "out": str(out)}
    for name, folder in _cars(paths, include_public):
        photos = sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXT)
        if len(photos) < max(min_photos, 2):
            summary["skipped_cars"] += 1
            continue
        # every val_every-th picture is for checking (at least one, so the car is in BOTH folders and the class numbers match)
        val_at = set(range(val_every - 1, len(photos), val_every)) or {len(photos) - 1}
        written = {"train": 0, "val": 0}
        for i, photo in enumerate(photos):
            image = cv2.imread(str(photo))
            if image is None:
                summary["unreadable"] += 1
                continue
            split = "val" if i in val_at else "train"
            dst = out / split / name
            dst.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(dst / f"{photo.stem}.jpg"), cv2.resize(image, SIZE), [cv2.IMWRITE_JPEG_QUALITY, 95])
            written[split] += 1
        if written["train"] and written["val"]:
            summary["cars"] += 1
            summary["train"] += written["train"]
            summary["val"] += written["val"]
        else:                                                   # a car in only one folder would shift the class numbers: drop it
            for split in ("train", "val"):
                shutil.rmtree(out / split / name, ignore_errors=True)
            summary["skipped_cars"] += 1
    if summary["cars"]:
        (out / "HOW_TO_TRAIN.txt").write_text(HOW_TO, encoding="utf-8")
    return summary
