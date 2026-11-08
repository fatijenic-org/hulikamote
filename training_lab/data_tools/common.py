"""
common.py - Small shared helpers for the dataset tools: paths, label files, box maths, splits, JPEG writing.

Everything here is plain functions on plain data so it can be unit tested without any dataset on disk.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

LAB = Path(__file__).resolve().parent.parent          # training_lab/
DATASETS = LAB / "datasets"
DOWNLOADS = DATASETS / "_downloads"                   # raw cache, one folder per source id (git-ignored)
QUARANTINE = DATASETS / "_quarantine"                 # files taken out by the curator (reversible, git-ignored)

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SPLITS = ("train", "val", "test")                     # our names; Roboflow calls "val" -> "valid"
ROBOFLOW_SPLIT = {"train": "train", "val": "valid", "test": "test"}
SPLIT_ALIASES = {"train": "train", "training": "train", "val": "val", "valid": "val", "validation": "val",
                 "dev": "val", "test": "test", "testing": "test"}

Box = tuple[int, float, float, float, float]          # class id, cx, cy, w, h (all normalised 0..1)


# --------------------------------------------------------------------------- names and splits

def group_key(name: str) -> str:
    """Photo id of a file name: no extension and no Roboflow '.rf.<hash>' suffix (augmented copies share it)."""
    return Path(name).stem.split(".rf.")[0]


def source_of(name: str) -> str:
    """'<source id>__<photo>' -> source id. Files without '__' are legacy / hand-made ('legacy')."""
    return name.split("__", 1)[0] if "__" in name else "legacy"


def split_for(group: str, ratios: tuple[float, float, float] = (0.8, 0.1, 0.1), salt: str = "huli-kamote-v1") -> str:
    """Deterministic train/val/test choice for a photo group: the same photo always lands on the same side."""
    u = int(hashlib.sha1(f"{salt}:{group}".encode("utf-8")).hexdigest()[:8], 16) / 0xFFFFFFFF
    if u < ratios[0]:
        return "train"
    return "val" if u < ratios[0] + ratios[1] else "test"


def sha256_file(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while block := f.read(chunk):
            h.update(block)
    return h.hexdigest()


# --------------------------------------------------------------------------- label files and boxes

def read_yolo(path: Path) -> list[Box]:
    """Parse a YOLO label file. Polygons (segmentation) become their bounding box. Bad lines are skipped."""
    out: list[Box] = []
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return out
    for raw in text.splitlines():
        parts = raw.split()
        if len(parts) < 5:
            continue
        try:
            cls = int(float(parts[0]))
            vals = [float(v) for v in parts[1:]]
        except ValueError:
            continue
        if len(vals) == 4:
            cx, cy, w, h = vals
        elif len(vals) >= 6 and len(vals) % 2 == 0:
            cx, cy, w, h = polygon_to_box(vals)
        else:
            continue
        out.append((cls, cx, cy, w, h))
    return out


def write_yolo(path: Path, boxes: list[Box]) -> None:
    Path(path).write_text("\n".join(f"{c} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in boxes),
                          encoding="utf-8")


def polygon_to_box(values: list[float]) -> tuple[float, float, float, float]:
    """x1 y1 x2 y2 ... (normalised) -> (cx, cy, w, h)."""
    xs, ys = values[0::2], values[1::2]
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    return ((x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1)


def xyxy_to_yolo(x1: float, y1: float, x2: float, y2: float, img_w: float, img_h: float) -> tuple[float, float, float, float]:
    """Pixel corners -> normalised (cx, cy, w, h)."""
    return (((x1 + x2) / 2) / img_w, ((y1 + y2) / 2) / img_h, (x2 - x1) / img_w, (y2 - y1) / img_h)


def xywh_to_yolo(x: float, y: float, w: float, h: float, img_w: float, img_h: float) -> tuple[float, float, float, float]:
    """COCO pixel box (x, y, w, h) -> normalised (cx, cy, w, h)."""
    return ((x + w / 2) / img_w, (y + h / 2) / img_h, w / img_w, h / img_h)


def iou(a: Box, b: Box) -> float:
    ax1, ay1, ax2, ay2 = a[1] - a[3] / 2, a[2] - a[4] / 2, a[1] + a[3] / 2, a[2] + a[4] / 2
    bx1, by1, bx2, by2 = b[1] - b[3] / 2, b[2] - b[4] / 2, b[1] + b[3] / 2, b[2] + b[4] / 2
    iw, ih = min(ax2, bx2) - max(ax1, bx1), min(ay2, by2) - max(ay1, by1)
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    return inter / (a[3] * a[4] + b[3] * b[4] - inter)


def clean_boxes(boxes: list[Box], img_w: int, img_h: int, nc: int, min_px: float = 3.0,
                dup_iou: float = 0.95) -> tuple[list[Box], dict[str, int]]:
    """
    Make a box list safe for training: clip to the picture, drop unknown classes, boxes thinner than
    `min_px` pixels, and same-class near-identical duplicates. Returns (clean boxes, what was dropped).
    """
    dropped = {"bad_class": 0, "tiny": 0, "duplicate": 0, "clipped": 0}
    kept: list[Box] = []
    for cls, cx, cy, w, h in boxes:
        if not (0 <= cls < nc) or any(v != v for v in (cx, cy, w, h)) or w <= 0 or h <= 0:   # v != v: NaN
            dropped["bad_class"] += 1
            continue
        x1, y1, x2, y2 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
        c1 = (max(0.0, x1), max(0.0, y1), min(1.0, x2), min(1.0, y2))
        if any(abs(a - b) > 1e-4 for a, b in zip(c1, (x1, y1, x2, y2))):     # rounding noise is not "outside the picture"
            dropped["clipped"] += 1
        x1, y1, x2, y2 = c1
        w, h = x2 - x1, y2 - y1
        if w * img_w < min_px or h * img_h < min_px:
            dropped["tiny"] += 1
            continue
        box = (cls, (x1 + x2) / 2, (y1 + y2) / 2, w, h)
        if any(k[0] == cls and iou(k, box) >= dup_iou for k in kept):
            dropped["duplicate"] += 1
            continue
        kept.append(box)
    return kept, dropped


def crop_windows(boxes: list[Box], anchor: int, wanted: dict[int, int], img_w: int, img_h: int,
                 margin: float = 0.1, min_px: int = 32, keep_frac: float = 0.6):
    """
    Cut a window around every `anchor` box (a vehicle / rider: the picture the pipeline hands a specialist model)
    and express the boxes of the `wanted` classes that sit inside it in the window's own coordinates.
      boxes   [(source class, cx, cy, w, h)] normalised;      wanted  {source class: our class}
    Returns [((x1, y1, x2, y2) in pixels, [Box in OUR classes, normalised to the window])].
    A window thinner than `min_px` or without a wanted box is left out; a box that the window edge cuts
    (less than `keep_frac` of it inside) is dropped, not trained as a half object.
    """
    out = []
    for cls, cx, cy, w, h in boxes:
        if cls != anchor:
            continue
        bw, bh = w * img_w, h * img_h
        x1 = max(0, round((cx - w / 2) * img_w - margin * bw))
        y1 = max(0, round((cy - h / 2) * img_h - margin * bh))
        x2 = min(img_w, round((cx + w / 2) * img_w + margin * bw))
        y2 = min(img_h, round((cy + h / 2) * img_h + margin * bh))
        if x2 - x1 < min_px or y2 - y1 < min_px:
            continue
        ww, wh = x2 - x1, y2 - y1
        inside: list[Box] = []
        for c, bx, by, bw2, bh2 in boxes:
            if c not in wanted:
                continue
            ax1, ay1 = (bx - bw2 / 2) * img_w, (by - bh2 / 2) * img_h
            ax2, ay2 = (bx + bw2 / 2) * img_w, (by + bh2 / 2) * img_h
            ix1, iy1, ix2, iy2 = max(ax1, x1), max(ay1, y1), min(ax2, x2), min(ay2, y2)
            if ix2 <= ix1 or iy2 <= iy1 or (ix2 - ix1) * (iy2 - iy1) < keep_frac * (ax2 - ax1) * (ay2 - ay1):
                continue
            inside.append((wanted[c], ((ix1 + ix2) / 2 - x1) / ww, ((iy1 + iy2) / 2 - y1) / wh,
                           (ix2 - ix1) / ww, (iy2 - iy1) / wh))
        if inside:
            out.append(((x1, y1, x2, y2), inside))
    return out


# --------------------------------------------------------------------------- images

def write_jpeg(src: Path, dst: Path, max_side: int = 1280, quality: int = 92) -> tuple[int, int]:
    """
    Re-save any picture as an upright RGB JPEG whose longest side is at most `max_side` (labels are normalised,
    so resizing never changes them). Grayscale and palette pictures become 3-channel RGB.
    """
    from PIL import Image, ImageOps
    with Image.open(src) as im:
        im.load()
        im = ImageOps.exif_transpose(im)
        if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
            bg = Image.new("RGB", im.size, (255, 255, 255))
            bg.paste(im.convert("RGBA"), mask=im.convert("RGBA").split()[-1])
            im = bg
        else:
            im = im.convert("RGB")
        w, h = im.size
        if max(w, h) > max_side:
            s = max_side / max(w, h)
            im = im.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_suffix(".tmp.jpg")
        im.save(tmp, "JPEG", quality=quality, optimize=True)
    tmp.replace(dst)
    return im.size


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


def inspect_image(path: Path, size: int = 16) -> dict | None:
    """
    One decode that answers everything the curator asks: is the file a readable picture, its true size
    (after EXIF rotation), whether it needs re-saving, and its 256-bit difference hash. None = unreadable.
    JPEGs are decoded at reduced size (fast); a truncated file still fails.
    """
    from PIL import Image
    try:
        with Image.open(path) as im:
            fmt, mode = im.format, im.mode
            w, h = im.size
            orient = im.getexif().get(274, 1) if hasattr(im, "getexif") else 1
            if fmt == "JPEG":
                im.draft("L", (size * 16, size * 16))
            im.load()
            if orient in (5, 6, 7, 8):
                w, h = h, w
            g = im.convert("L").resize((size + 1, size), Image.BILINEAR)
            px = list(g.tobytes())
    except Exception:
        return None
    bits = 0
    for row in range(size):
        for col in range(size):
            bits = (bits << 1) | (px[row * (size + 1) + col] > px[row * (size + 1) + col + 1])
    return {"w": w, "h": h, "format": fmt, "mode": mode, "rotated": orient not in (0, 1), "dhash": bits}


# --------------------------------------------------------------------------- dataset layout

def load_yaml(path: Path) -> dict:
    import yaml
    return yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}


def class_names(model: str) -> list[str]:
    """Class names of datasets/<model>/data.yaml in id order."""
    names = load_yaml(DATASETS / model / "data.yaml")["names"]
    if isinstance(names, dict):
        return [str(names[k]) for k in sorted(names)]
    return [str(n) for n in names]


def canonical_dirs(model: str, split: str) -> tuple[Path, Path]:
    """Our one layout: datasets/<model>/images/<split> and datasets/<model>/labels/<split>."""
    base = DATASETS / model
    return base / "images" / split, base / "labels" / split


def pairs(img_dir: Path, lbl_dir: Path):
    """Yield (image path, label path) for every picture in a folder (label path may not exist)."""
    if not img_dir.exists():
        return
    for p in sorted(img_dir.iterdir()):
        if p.suffix.lower() in IMAGE_EXT:
            yield p, lbl_dir / (p.stem + ".txt")


def quarantine(path: Path, model: str, reason: str) -> Path:
    """Move a file out of the dataset (never delete): datasets/_quarantine/<model>/<reason>/<name>."""
    dst_dir = QUARANTINE / model / reason
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / path.name
    n = 1
    while dst.exists():
        dst = dst_dir / f"{path.stem}.{n}{path.suffix}"
        n += 1
    shutil.move(str(path), str(dst))
    return dst


def dump_json(path: Path, data) -> None:
    Path(path).write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
