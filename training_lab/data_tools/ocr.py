"""
ocr.py - Plate reader (OCR) data: cut plate crops that come with their text and add them to datasets/plate_ocr.

Layout (the same one Pop Quiz corrections already use, plus val / test folders):
    datasets/plate_ocr/images/<split>/<source id>__<TEXT>_<n>.jpg
    datasets/plate_ocr/labels/<split>/<source id>__<TEXT>_<n>.txt        ->  "0 TEXT"
Text is upper-case letters and digits only (spaces, dashes and dots removed), like the Pop Quiz labels.
"""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from .common import DATASETS, IMAGE_EXT, ROBOFLOW_SPLIT, read_yolo

MARGIN = 0.06           # extra border around the plate box, as a share of its size


def normalise_text(raw: str) -> str:
    """'01 DVZ 18' -> '01DVZ18'. Empty when nothing usable is left."""
    return re.sub(r"[^A-Z0-9]", "", raw.upper())


def merge_filename_text(src: dict, folder: Path) -> Counter:
    """
    Staging folder whose YOLO boxes mark one plate per picture and whose FILE NAME is the plate text
    (manifest: `text_from: filename`) -> cropped plates + text labels in datasets/plate_ocr.
    """
    from PIL import Image, ImageOps
    counts: Counter = Counter()
    root = DATASETS / "plate_ocr"
    for split, sub in ROBOFLOW_SPLIT.items():
        img_dir, lbl_dir = folder / sub / "images", folder / sub / "labels"
        if not img_dir.exists():
            continue
        out_img, out_lbl = root / "images" / split, root / "labels" / split
        out_img.mkdir(parents=True, exist_ok=True)
        out_lbl.mkdir(parents=True, exist_ok=True)
        for n, img in enumerate(sorted(p for p in img_dir.iterdir() if p.suffix.lower() in IMAGE_EXT)):
            text = normalise_text(img.stem)
            boxes = read_yolo(lbl_dir / (img.stem + ".txt"))
            if len(text) < 4 or len(boxes) != 1:
                counts["skipped"] += 1
                continue
            _, cx, cy, w, h = boxes[0]
            with Image.open(img) as im:
                im = ImageOps.exif_transpose(im).convert("RGB")
                W, H = im.size
                x1, x2 = (cx - w / 2 - w * MARGIN) * W, (cx + w / 2 + w * MARGIN) * W
                y1, y2 = (cy - h / 2 - h * MARGIN) * H, (cy + h / 2 + h * MARGIN) * H
                crop = im.crop((max(0, round(x1)), max(0, round(y1)), min(W, round(x2)), min(H, round(y2))))
            if crop.width < 24 or crop.height < 8:
                counts["skipped"] += 1
                continue
            name = f"{src['id']}__{text}_{n}"
            crop.save(out_img / f"{name}.jpg", "JPEG", quality=95)
            (out_lbl / f"{name}.txt").write_text(f"0 {text}", encoding="utf-8")
            counts[split] += 1
    return counts
