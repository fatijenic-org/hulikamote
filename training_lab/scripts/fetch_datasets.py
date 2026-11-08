"""
fetch_datasets.py — Download public datasets and merge them into our training sets.

Every source dataset uses its own class names. configs/datasets_manifest.yaml maps them
onto OUR classes (from datasets/<model>/data.yaml); classes that are not mapped are dropped.
Polygon labels are turned into boxes. A source's own train / valid / test split is kept
(valid -> val), so near-duplicate augmented copies never leak into the test set.

Sources (manifest `source:` field):
    roboflow (default)   needs your own free API key: roboflow.com -> Settings -> API Keys
    mendeley | zenodo | huggingface | openimages | url     no account or key (see data_tools/sources.py)
Without ROBOFLOW_API_KEY the Roboflow entries that are not downloaded yet are skipped, not fatal.

Usage:
    pip install roboflow                                   (only for Roboflow entries)
    set ROBOFLOW_API_KEY=<your key>            (PowerShell: $env:ROBOFLOW_API_KEY="<your key>")
                                               or skip it: from a terminal the script asks for the key (hidden, not saved)
    python scripts/fetch_datasets.py                       # every model in the manifest
    python scripts/fetch_datasets.py --model helmet_specialist
    python scripts/fetch_datasets.py --only edgevision_helmet --stage-only   # download one source, merge nothing
    python scripts/fetch_datasets.py --dry-run             # only show the class mapping
Then clean and describe the result:  python data.py curate   /   python data.py report

Downloads are cached in datasets/_downloads/<id>/ (delete a folder to re-download).
Merged files are named <id>__<original name>, so re-running overwrites instead of duplicating.
"""
import argparse
import os
import shutil
import sys
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:                      # data_tools lives next to scripts/
    sys.path.insert(0, str(ROOT))
MANIFEST = ROOT / "configs" / "datasets_manifest.yaml"
DATASETS = ROOT / "datasets"
DOWNLOADS = DATASETS / "_downloads"
SPLITS = {"train": "train", "valid": "val", "test": "test"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def target_classes(model: str) -> dict[str, int]:
    """Our class name -> id, from datasets/<model>/data.yaml."""
    cfg = yaml.safe_load((DATASETS / model / "data.yaml").read_text(encoding="utf-8"))
    names = cfg["names"]
    items = names.items() if isinstance(names, dict) else enumerate(names)
    return {str(name): int(i) for i, name in items}


DOWNLOAD_TRIES = 3


def _api_key() -> str | None:
    """ROBOFLOW_API_KEY, or (run from a terminal) ask once: hidden, kept only in this process, never saved."""
    key = os.environ.get("ROBOFLOW_API_KEY")
    if not key and sys.stdin.isatty():
        import getpass
        key = getpass.getpass("Roboflow API key (hidden, not saved): ").strip()
        if key:
            os.environ["ROBOFLOW_API_KEY"] = key
    return key or None


def download(src: dict) -> Path | None:
    """
    Staging folder of one source in YOLO format (cached). Roboflow entries come with their own split folders;
    every other host is converted to the same folders by data_tools.sources. Returns None when a Roboflow entry
    cannot be fetched because no key is set (the caller reports it and carries on).
    """
    out = DOWNLOADS / src.get("stage_as", src["id"])       # stage_as: share one download between two manifest entries
    if (out / "data.yaml").exists():
        return out
    if src.get("source", "roboflow") != "roboflow":
        from data_tools import sources
        return sources.fetch(src)
    key = _api_key()
    if not key:
        return None
    try:
        from roboflow import Roboflow
    except ImportError:
        raise SystemExit("Run: pip install roboflow")
    project = Roboflow(api_key=key).workspace(src["workspace"]).project(src["project"])
    version = src["version"]
    if str(version) == "latest":
        version = max(int(v.version) for v in project.versions())
    for attempt in range(1, DOWNLOAD_TRIES + 1):
        try:
            project.version(int(version)).download("yolov8", location=str(out), overwrite=True)
            return out
        except Exception as e:                                     # a cut-off download leaves a broken zip behind
            print(f"  ! download attempt {attempt}/{DOWNLOAD_TRIES} failed: {e}")
            shutil.rmtree(out, ignore_errors=True)                 # staging folder only (no data.yaml yet)
            if attempt == DOWNLOAD_TRIES:
                raise


def source_classes(folder: Path) -> list[str]:
    names = yaml.safe_load((folder / "data.yaml").read_text(encoding="utf-8"))["names"]
    return [names[k] for k in sorted(names)] if isinstance(names, dict) else list(names)


def build_map(src: dict, src_names: list[str], ours: dict[str, int]) -> dict[int, int]:
    """Source class id -> our class id, using the manifest's (case-insensitive) name mapping."""
    wanted = {str(k).strip().lower(): v for k, v in (src.get("classes") or {}).items()}
    mapping = {}
    for i, name in enumerate(src_names):
        target = wanted.get(str(name).strip().lower())
        if target is None:
            continue
        if target not in ours:
            raise SystemExit(f"[{src['id']}] maps to unknown class '{target}'. Ours: {list(ours)}")
        mapping[i] = ours[target]
    missing = set(wanted) - {str(n).strip().lower() for n in src_names}
    if missing:
        print(f"  ! [{src['id']}] manifest names not in the dataset: {sorted(missing)} (dataset has {src_names})")
    return mapping


def to_box(values: list[float]) -> tuple[float, float, float, float]:
    """YOLO box (cx, cy, w, h) from a box or a polygon (x1 y1 x2 y2 ...), all normalised."""
    if len(values) == 4:
        return tuple(values)
    xs, ys = values[0::2], values[1::2]
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    return ((x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1)


def read_source_boxes(lbl: Path) -> list[tuple[int, float, float, float, float]]:
    """Every box of a source label file (polygons -> boxes), with the SOURCE's class ids."""
    rows = []
    if lbl.exists():
        for raw in lbl.read_text().splitlines():
            parts = raw.split()
            if len(parts) >= 5:
                cx, cy, w, h = to_box([float(v) for v in parts[1:]])
                if w > 0 and h > 0:
                    rows.append((int(parts[0]), cx, cy, w, h))
    return rows


def merge_crops(src: dict, img: Path, lbl: Path, mapping: dict[int, int], crop_id: int,
                out_img: Path, out_lbl: Path, counts: Counter, our_split: str) -> None:
    """`crop_to:` sources: save one picture per anchor box (a motorcycle, a rider) with the wanted boxes inside it."""
    from PIL import Image, ImageOps
    from data_tools.common import crop_windows
    with Image.open(img) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        for k, (win, boxes) in enumerate(crop_windows(read_source_boxes(lbl), crop_id, mapping, *im.size,
                                                      margin=float(src.get("crop_margin", 0.1)))):
            name = f"{src['id']}__{img.stem}__c{k}.jpg"
            im.crop(win).save(out_img / name, "JPEG", quality=95)
            (out_lbl / (Path(name).stem + ".txt")).write_text(
                "\n".join(f"{c} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in boxes))
            for c, *_ in boxes:
                counts[(our_split, c)] += 1
            counts[(our_split, "images")] += 1


def merge(src: dict, folder: Path, mapping: dict[int, int], model: str, keep_empty: bool,
          crop_id: int | None = None) -> Counter:
    counts = Counter()
    for rf_split, our_split in SPLITS.items():
        our_split = src.get("force_split") or our_split   # e.g. a dataset shipped entirely as "test"
        img_dir = folder / rf_split / "images"
        if not img_dir.exists():
            continue
        out_img, out_lbl = split_dirs(model, our_split)
        out_img.mkdir(parents=True, exist_ok=True)
        out_lbl.mkdir(parents=True, exist_ok=True)
        for img in img_dir.iterdir():
            if img.suffix.lower() not in IMAGE_EXT:
                continue
            lbl = folder / rf_split / "labels" / (img.stem + ".txt")
            if crop_id is not None:
                merge_crops(src, img, lbl, mapping, crop_id, out_img, out_lbl, counts, our_split)
                continue
            lines = []
            if lbl.exists():
                for raw in lbl.read_text().splitlines():
                    parts = raw.split()
                    if len(parts) < 5 or int(parts[0]) not in mapping:
                        continue
                    cx, cy, w, h = to_box([float(v) for v in parts[1:]])
                    if w > 0 and h > 0:
                        cls = mapping[int(parts[0])]
                        lines.append(f"{cls} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}")
                        counts[(our_split, cls)] += 1
            if not lines and not keep_empty:
                continue
            name = f"{src['id']}__{img.name}"
            shutil.copy2(img, out_img / name)
            (out_lbl / (Path(name).stem + ".txt")).write_text("\n".join(lines))
            counts[(our_split, "images")] += 1
    return counts


def split_dirs(model: str, split: str) -> tuple[Path, Path]:
    """(images dir, labels dir) for a split, following the target's own data.yaml layout
    (images/train + labels/train, or train/images + train/labels)."""
    cfg = yaml.safe_load((DATASETS / model / "data.yaml").read_text(encoding="utf-8"))
    images = cfg.get(split) or cfg["train"].replace("train", split)
    return DATASETS / model / images, DATASETS / model / images.replace("images", "labels")


def remove_leaks(model: str) -> int:
    """
    Some public datasets put the same photo in train AND val/test (checked: cabin + vehicle
    sets, pixel-identical). That inflates test scores, so any merged val/test image whose
    source photo is also in train is moved into train. Returns how many were moved.
    """
    def source(name: str) -> str:   # "<id>__<photo>_jpg.rf.<hash>.jpg" -> "<photo>_jpg"
        return name.split("__", 1)[-1].split(".rf.")[0]

    train_img, train_lbl = split_dirs(model, "train")
    if not train_img.exists():
        return 0
    in_train = {source(f.name) for f in train_img.iterdir() if "__" in f.name}
    moved = 0
    for split in ("val", "test"):
        img_dir, lbl_dir = split_dirs(model, split)
        if not img_dir.exists():
            continue
        for img in list(img_dir.iterdir()):
            if "__" in img.name and source(img.name) in in_train:
                img.replace(train_img / img.name)
                lbl = lbl_dir / (img.stem + ".txt")
                if lbl.exists():
                    lbl.replace(train_lbl / lbl.name)
                moved += 1
    return moved


def ensure_test_split(model: str) -> None:
    """Point data.yaml at the test split too (used by validate.py / benchmarks)."""
    path = DATASETS / model / "data.yaml"
    text = path.read_text(encoding="utf-8")
    test_images, _ = split_dirs(model, "test")
    if test_images.exists() and "test" not in yaml.safe_load(text):
        rel = test_images.relative_to(DATASETS / model).as_posix()
        path.write_text(text.rstrip() + f"\ntest: {rel}\n", encoding="utf-8")


OCR_MODELS = {"plate_ocr"}      # text-labelled plate crops, not boxes: merged by data_tools.ocr


def describe(src: dict) -> str:
    kind = src.get("source", "roboflow")
    where = {"roboflow": lambda s: f"{s.get('workspace')}/{s.get('project')} v{s.get('version')}",
             "mendeley": lambda s: f"mendeley {s.get('dataset')}", "zenodo": lambda s: f"zenodo {s.get('record')}",
             "huggingface": lambda s: f"huggingface {s.get('repo')}", "openimages": lambda s: "Open Images V7",
             "url": lambda s: s.get("url", "")}.get(kind, lambda s: kind)
    return f"{src['id']}: {where(src)}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", help="only this model (e.g. helmet_specialist)")
    ap.add_argument("--only", help="only this source id (e.g. edgevision_helmet)")
    ap.add_argument("--stage-only", action="store_true", help="download / convert to the staging folder, merge nothing")
    ap.add_argument("--dry-run", action="store_true", help="download + show the class mapping, write nothing")
    args = ap.parse_args()

    manifest = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    skipped, failed = [], []
    for model, sources in manifest.items():
        if model.startswith("_"):                                  # `_manual:` etc. = notes for humans
            continue
        if args.model and model != args.model:
            continue
        if args.only and not any(s["id"] == args.only for s in sources or []):
            continue
        if model == "reid_public":                                 # identity folders, not boxes
            from data_tools import reid
            for src in sources or []:
                if args.only and src["id"] != args.only:
                    continue
                print(f"\n=== {model}\n- {src['id']}: zenodo {src.get('record')} ({src.get('file')})")
                if args.dry_run:
                    continue
                try:
                    reid.fetch(src)
                except Exception as e:
                    print(f"  ! failed: {e}")
                    failed.append(src["id"])
            continue
        ocr = model in OCR_MODELS
        ours = {} if ocr else target_classes(model)
        id_to_name = {v: k for k, v in ours.items()}
        print(f"\n=== {model}  (our classes: {list(ours) or 'plate text'})")
        total = Counter()
        for src in sources or []:
            if args.only and src["id"] != args.only:
                continue
            print(f"- {describe(src)}")
            try:
                folder = download(src)
            except Exception as e:                                 # one broken source must not stop the others
                print(f"  ! failed: {e}")
                failed.append(src["id"])
                continue
            if folder is None:
                print("  - skipped: Roboflow entry and no ROBOFLOW_API_KEY set (already-downloaded ones are used)")
                skipped.append(src["id"])
                continue
            if args.stage_only:
                continue
            if src.get("merge") is False:                          # downloaded and documented, kept out of the training set
                print(f"    not merged (merge: false) - {src.get('notes', 'see the manifest')}")
                continue
            if ocr:
                from data_tools import ocr as ocr_tools
                if not args.dry_run:
                    got = ocr_tools.merge_filename_text(src, folder)
                    print(f"    plate crops with text: {dict(got)}")
                continue
            names = source_classes(folder)
            if src.get("source") == "openimages":                  # staged under OUR class names already
                src = {**src, "classes": {n: n for n in src["classes"].values()}}
            mapping = build_map(src, names, ours)
            for s, t in mapping.items():
                print(f"    {names[s]!r:30} -> {id_to_name[t]}")
            crop_id = None
            if src.get("crop_to"):                                 # train on the crop the pipeline will hand the model
                lowered = [str(n).strip().lower() for n in names]
                if str(src["crop_to"]).strip().lower() not in lowered:
                    raise SystemExit(f"[{src['id']}] crop_to '{src['crop_to']}' is not a class of the dataset: {names}")
                crop_id = lowered.index(str(src["crop_to"]).strip().lower())
                print(f"    pictures are cut around every {src['crop_to']!r} box (margin {src.get('crop_margin', 0.1)})")
            if not args.dry_run:
                total += merge(src, folder, mapping, model, bool(src.get("keep_empty", False)), crop_id)
        if not args.dry_run and not args.stage_only and not ocr:
            ensure_test_split(model)
            moved = remove_leaks(model)
            if moved:
                print(f"  moved {moved} val/test images into train (same photo was also in train)")
            for split in ("train", "val", "test"):
                per_class = {id_to_name[c]: n for (s, c), n in sorted(total.items(), key=str)
                             if s == split and c != "images"}
                print(f"  {split:5}: {total[(split, 'images')]} images  {per_class}")
    if skipped:
        print(f"\nSkipped (need ROBOFLOW_API_KEY): {', '.join(skipped)}")
    if failed:
        print(f"\nFAILED: {', '.join(failed)}  (see the messages above; re-run with --only <id>)")


if __name__ == "__main__":
    main()
