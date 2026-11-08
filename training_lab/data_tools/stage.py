"""
stage.py - Turn whatever a source publishes into the same staging folder the Roboflow downloads use:

    _downloads/<id>/{train,valid,test}/{images,labels}/   +  data.yaml (names)  +  SOURCE.json (where it came from)

scripts/fetch_datasets.py then maps the source's class names onto ours and merges it into datasets/<model>/.
"""
from __future__ import annotations

import json
import re
import shutil
from collections import Counter
from pathlib import Path

from .common import (DOWNLOADS, IMAGE_EXT, ROBOFLOW_SPLIT, SPLIT_ALIASES, Box, group_key, read_yolo, split_for,
                     write_yolo, xywh_to_yolo)


class Stage:
    """Writer for one staging folder."""

    def __init__(self, source_id: str, names: list[str], root: Path | None = None):
        self.root = root or DOWNLOADS / source_id
        self.names = list(names)
        self.counts: Counter = Counter()
        for split in ROBOFLOW_SPLIT.values():
            (self.root / split / "images").mkdir(parents=True, exist_ok=True)
            (self.root / split / "labels").mkdir(parents=True, exist_ok=True)

    def add(self, image: Path, boxes: list[Box], split: str, name: str | None = None, move: bool = False) -> Path:
        """Put one picture + its labels into a split ('train' | 'val' | 'test')."""
        sub = ROBOFLOW_SPLIT[split]
        name = name or image.name
        dst = self.root / sub / "images" / name
        if move:
            shutil.move(str(image), str(dst))
        else:
            shutil.copy2(image, dst)
        write_yolo(self.root / sub / "labels" / (Path(name).stem + ".txt"), boxes)
        self.counts[split] += 1
        self.counts["boxes"] += len(boxes)
        return dst

    def finish(self, meta: dict) -> Path:
        """Write data.yaml + SOURCE.json. A staging folder without data.yaml counts as 'not downloaded yet'."""
        import yaml
        on_disk = {split: sum(1 for p in (self.root / sub / "images").iterdir() if p.suffix.lower() in IMAGE_EXT)
                   for split, sub in ROBOFLOW_SPLIT.items()}                      # a resumed run added only part of them
        (self.root / "SOURCE.json").write_text(
            json.dumps({**meta, "staged": {**on_disk, "boxes_added_this_run": self.counts["boxes"]}}, indent=2, ensure_ascii=False),
            encoding="utf-8")
        (self.root / "data.yaml").write_text(
            yaml.safe_dump({"train": "train/images", "val": "valid/images", "test": "test/images",
                            "nc": len(self.names), "names": self.names}, sort_keys=False), encoding="utf-8")
        return self.root


def find_images(root: Path, only_dirs: list[str] | None = None):
    """Pictures under root; with `only_dirs` (paths relative to root) just those folders."""
    bases = [root / d for d in only_dirs] if only_dirs else [root]
    for base in bases:
        for p in sorted(base.rglob("*")):
            if p.suffix.lower() in IMAGE_EXT and p.is_file():
                yield p


def read_labels(path: Path, fmt: str = "yolo") -> list[Box]:
    """
    Label file -> boxes. fmt 'yolo': `class cx cy w h` (polygons allowed).
    fmt 'tf_corners': `ymin, xmin, ymax, xmax` as fractions, comma separated, no class (class 0), one or more
    boxes of four numbers (the Turkish plate set uses this; found by drawing the box on the picture).
    """
    if fmt == "yolo":
        return read_yolo(path)
    if fmt != "tf_corners":
        raise ValueError(f"unknown label format '{fmt}'")
    try:
        nums = [float(v) for v in re.split(r"[,\s]+", Path(path).read_text(encoding="utf-8").strip()) if v]
    except (OSError, ValueError):
        return []
    boxes = []
    for i in range(0, len(nums) - 3, 4):
        ymin, xmin, ymax, xmax = nums[i:i + 4]
        if xmax > xmin and ymax > ymin:
            boxes.append((0, (xmin + xmax) / 2, (ymin + ymax) / 2, xmax - xmin, ymax - ymin))
    return boxes


def infer_split(path: Path, root: Path) -> str | None:
    """'train' / 'val' / 'test' from the folders in a path, else None."""
    for part in path.relative_to(root).parts[:-1]:
        s = SPLIT_ALIASES.get(part.lower())
        if s:
            return s
    return None


def import_yolo_tree(root: Path, stage: Stage, src_names: list[str] | None = None, ratios=(0.8, 0.1, 0.1),
                     label_roots: list[Path] | None = None, move: bool = True, image_dirs: list[str] | None = None,
                     label_format: str = "yolo") -> Counter:
    """
    Import any folder that holds pictures with YOLO .txt labels, however it is laid out:
    labels next to the picture, in a parallel images/ -> labels/ folder, or in a separate folder
    (matched by file name). Pictures with no label file are skipped. When the folders say nothing
    about train/val/test the split is chosen per photo group by hash (80/10/10).
    `src_names` only checks class ids; the real names are the stage's.
    """
    seen = Counter()
    search = [root] + (label_roots or [])
    by_stem: dict[str, list[Path]] = {}
    for base in search:
        for t in base.rglob("*.txt"):
            if t.name.lower() in ("classes.txt", "readme.txt", "license.txt") or t.stem.lower().startswith("readme"):
                continue
            by_stem.setdefault(t.stem, []).append(t)
    for img in find_images(root, image_dirs):
        lbl = img.with_suffix(".txt")
        if not lbl.exists():
            parts = list(img.parts)
            swapped = None
            for i in range(len(parts) - 2, -1, -1):              # .../images/... -> .../labels/...
                if parts[i].lower() == "images":
                    parts[i] = "labels"
                    swapped = Path(*parts).with_suffix(".txt")
                    break
            if swapped is not None and swapped.exists():
                lbl = swapped
            elif len(by_stem.get(img.stem, [])) == 1:             # a separate label folder, matched by file name
                lbl = by_stem[img.stem][0]
            else:
                seen["no_label"] += 1
                continue
        boxes = read_labels(lbl, label_format)
        split = infer_split(img, root) or split_for(group_key(img.name), ratios)
        stage.add(img, boxes, split, move=move)
        seen[split] += 1
    return seen


def import_coco(json_path: Path, images_dir: Path, stage: Stage, split: str, move: bool = True) -> Counter:
    """COCO json (Roboflow export style) -> staging. Category order in `stage.names` must match the json's."""
    data = json.loads(Path(json_path).read_text(encoding="utf-8"))
    cats = sorted(data["categories"], key=lambda c: c["id"])
    cat_index = {c["id"]: stage.names.index(c["name"]) for c in cats if c["name"] in stage.names}
    anns: dict[int, list] = {}
    for a in data.get("annotations", []):
        anns.setdefault(a["image_id"], []).append(a)
    seen = Counter()
    for im in data["images"]:
        path = images_dir / im["file_name"]
        if not path.exists():
            seen["missing"] += 1
            continue
        w, h = im["width"], im["height"]
        boxes = []
        for a in anns.get(im["id"], []):
            if a["category_id"] not in cat_index:
                continue
            x, y, bw, bh = a["bbox"]
            boxes.append((cat_index[a["category_id"]], *xywh_to_yolo(x, y, bw, bh, w, h)))
        stage.add(path, boxes, split, move=move)
        seen[split] += 1
    return seen
