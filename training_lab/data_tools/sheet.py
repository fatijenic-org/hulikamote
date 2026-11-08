"""
sheet.py - Contact sheets: a grid of random pictures of one source with their boxes drawn and named.
Look at one before trusting a source: wrong class names, shifted boxes or rotated pictures are obvious in seconds.
"""
from __future__ import annotations

import random
from pathlib import Path

from .common import DATASETS, DOWNLOADS, IMAGE_EXT, read_yolo, source_of

COLORS = [(230, 25, 75), (60, 180, 75), (255, 225, 25), (0, 130, 200), (245, 130, 48), (145, 30, 180), (70, 240, 240), (240, 50, 230)]


def collect_staged(source_id: str) -> tuple[list[tuple[Path, Path]], list[str]]:
    """(picture, label) pairs and class names of a downloaded source (before it is merged)."""
    import yaml
    root = DOWNLOADS / source_id
    names = yaml.safe_load((root / "data.yaml").read_text(encoding="utf-8"))["names"]
    names = [names[k] for k in sorted(names)] if isinstance(names, dict) else list(names)
    pairs = []
    for sub in ("train", "valid", "test"):
        d = root / sub / "images"
        if d.exists():
            pairs += [(p, root / sub / "labels" / (p.stem + ".txt")) for p in d.iterdir() if p.suffix.lower() in IMAGE_EXT]
    return pairs, names


def collect_merged(model: str, source_id: str | None, split: str | None) -> tuple[list[tuple[Path, Path]], list[str]]:
    from .common import class_names
    pairs = []
    for sp in ([split] if split else ["train", "val", "test"]):
        d = DATASETS / model / "images" / sp
        if d.exists():
            for p in d.iterdir():
                if p.suffix.lower() in IMAGE_EXT and (source_id is None or source_of(p.name) == source_id):
                    pairs.append((p, DATASETS / model / "labels" / sp / (p.stem + ".txt")))
    return pairs, class_names(model)


def make_sheet(pairs: list[tuple[Path, Path]], names: list[str], out: Path, cols: int = 4, rows: int = 3,
               thumb: int = 360, seed: int = 0) -> Path:
    from PIL import Image, ImageDraw, ImageOps
    random.Random(seed).shuffle(pairs)
    picks = pairs[: cols * rows]
    sheet = Image.new("RGB", (cols * thumb, rows * thumb), (24, 24, 24))
    for k, (img_path, lbl_path) in enumerate(picks):
        try:
            with Image.open(img_path) as im:
                im = ImageOps.exif_transpose(im).convert("RGB")
        except Exception:
            continue
        W, H = im.size
        draw = ImageDraw.Draw(im)
        line = max(2, round(max(W, H) / 250))
        for cls, cx, cy, w, h in read_yolo(lbl_path):
            x1, y1, x2, y2 = (cx - w / 2) * W, (cy - h / 2) * H, (cx + w / 2) * W, (cy + h / 2) * H
            color = COLORS[cls % len(COLORS)]
            draw.rectangle([x1, y1, x2, y2], outline=color, width=line)
            label = names[cls] if 0 <= cls < len(names) else str(cls)
            tw = draw.textlength(label)
            draw.rectangle([x1, max(0, y1 - 14), x1 + tw + 6, max(14, y1)], fill=color)
            draw.text((x1 + 3, max(0, y1 - 13)), label, fill=(0, 0, 0))
        im.thumbnail((thumb - 4, thumb - 4))
        sheet.paste(im, ((k % cols) * thumb + 2, (k // cols) * thumb + 2))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out
