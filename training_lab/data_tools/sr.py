"""
sr.py - Sharp plate crops for the image enhancer (Real-ESRGAN): datasets/sr_plates/clean/<split>/*.jpg

The enhancer learns to rebuild a clear plate from a blurry one, so it needs CLEAR plates to learn from. Crops are cut
from the plate detector's labelled pictures and kept only when they are big enough, plate-shaped, sharp and not a
repeat. A crop inherits the split of its picture, so enhancer scores are never measured on a plate seen in training.
The trainer (scripts/train_realesrgan.py) makes the blurry versions itself.
"""
from __future__ import annotations

import json
import shutil
from collections import Counter
from datetime import date
from pathlib import Path

import numpy as np

from .common import DATASETS, SPLITS, canonical_dirs, hamming, pairs, read_yolo

OUT = DATASETS / "sr_plates" / "clean"
MARGIN = 0.04            # extra border around the plate box (share of the box size)
ASPECT = (1.6, 6.5)      # plate width / height


def sharpness(gray: np.ndarray, width: int = 128) -> float:
    """Variance of the Laplacian after scaling to a fixed width, so big and small crops are judged alike."""
    import cv2
    h = max(8, round(gray.shape[0] * width / gray.shape[1]))
    return float(cv2.Laplacian(cv2.resize(gray, (width, h), interpolation=cv2.INTER_AREA), cv2.CV_64F).var())


def gray_hash(gray: np.ndarray, size: int = 16) -> int:
    import cv2
    g = cv2.resize(gray, (size + 1, size), interpolation=cv2.INTER_AREA)
    bits = (g[:, :-1] > g[:, 1:]).flatten()
    return int("".join("1" if b else "0" for b in bits), 2)


def build(model: str = "plate_specialist", per_split: dict[str, int] | None = None, min_w: int = 128, min_h: int = 32,
          min_sharp: float = 40.0, log=print) -> dict:
    import cv2
    caps = {"train": 6000, "val": 500, "test": 500, **(per_split or {})}
    shutil.rmtree(OUT, ignore_errors=True)                  # always rebuilt from scratch: no crops of removed pictures left over
    stats: Counter = Counter()
    kept_meta: dict[str, list] = {s: [] for s in SPLITS}
    for split in SPLITS:
        img_dir, lbl_dir = canonical_dirs(model, split)
        candidates = []
        for img_path, lbl_path in pairs(img_dir, lbl_dir):
            boxes = read_yolo(lbl_path)
            if not boxes:
                continue
            img = cv2.imread(str(img_path))
            if img is None:
                stats["unreadable"] += 1
                continue
            H, W = img.shape[:2]
            for k, (_, cx, cy, bw, bh) in enumerate(boxes):
                x1, x2 = int((cx - bw / 2 - bw * MARGIN) * W), int((cx + bw / 2 + bw * MARGIN) * W)
                y1, y2 = int((cy - bh / 2 - bh * MARGIN) * H), int((cy + bh / 2 + bh * MARGIN) * H)
                x1, y1, x2, y2 = max(0, x1), max(0, y1), min(W, x2), min(H, y2)
                w, h = x2 - x1, y2 - y1
                stats["plates_seen"] += 1
                if w < min_w or h < min_h:
                    stats["too_small"] += 1
                    continue
                if not (ASPECT[0] <= w / h <= ASPECT[1]):
                    stats["not_plate_shaped"] += 1
                    continue
                crop = img[y1:y2, x1:x2]
                gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                s = sharpness(gray)
                if s < min_sharp:
                    stats["blurry"] += 1
                    continue
                candidates.append((s, f"{img_path.stem}_{k}", crop, gray_hash(gray)))
        candidates.sort(key=lambda c: -c[0])                  # sharpest first, then cap
        seen_hashes: list[int] = []
        out_dir = OUT / split
        out_dir.mkdir(parents=True, exist_ok=True)
        for s, name, crop, hsh in candidates:
            if len(kept_meta[split]) >= caps[split]:
                break
            if any(hamming(hsh, o) <= 8 for o in seen_hashes):
                stats["repeat"] += 1
                continue
            seen_hashes.append(hsh)
            cv2.imwrite(str(out_dir / f"{name}.jpg"), crop, [cv2.IMWRITE_JPEG_QUALITY, 95])
            kept_meta[split].append({"name": name, "sharpness": round(s, 1), "size": [crop.shape[1], crop.shape[0]]})
        log(f"  {split}: {len(kept_meta[split]):,} sharp plate crops (of {len(candidates):,} that passed the size / shape gates)")
    report = {"built": date.today().isoformat(), "from": model, "gates": {"min_w": min_w, "min_h": min_h, "min_sharpness": min_sharp,
              "aspect": ASPECT}, "counts": {s: len(v) for s, v in kept_meta.items()}, "rejected": dict(stats)}
    (DATASETS / "sr_plates").mkdir(parents=True, exist_ok=True)
    (DATASETS / "sr_plates" / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report
