"""
curate.py - Clean one YOLO dataset and put it in the single layout every trainer here expects.

    datasets/<model>/data.yaml            train: images/train   val: images/val   test: images/test
    datasets/<model>/images/<split>/*.jpg     datasets/<model>/labels/<split>/*.txt

What it checks, per picture:
    unreadable / truncated picture ........ quarantined         label missing, or no valid box left .. quarantined
    box outside the picture, too small,
    same-class duplicate, bad class id .... fixed in the label   picture too small (< 32 px) ........ quarantined
    public picture that is PNG / WEBP /
    rotated by EXIF / longer than 1280 px . re-saved as upright RGB JPEG (labels are normalised: unchanged)
    the same photo in two splits .......... the TRAIN copy is quarantined (val / test stay as they are)
    the same photo twice in one split ..... only exact duplicates with identical labels are dropped

Rules that keep your own work safe:
    * "Quarantined" means moved to datasets/_quarantine/<model>/<reason>/ - nothing is ever deleted.
    * Files named harvest__* (your reviewed CCTV pictures) are never moved, fixed or re-saved; problems are only reported.
    * Files without "<source>__" in the name (the original committed data) are never re-saved, only checked.
    * Dry-run by default: nothing changes until apply=True.
"""
from __future__ import annotations

import json
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

from .common import (DATASETS, SPLITS, Box, canonical_dirs, class_names, clean_boxes, dump_json, hamming,
                     inspect_image, load_yaml, pairs, quarantine, read_yolo, source_of, write_jpeg, write_yolo)

PROTECTED_PREFIX = "harvest__"
MIN_SIDE = 32
SPLIT_RANK = {"test": 0, "val": 1, "train": 2}        # lower = more precious: kept when the same photo is in two splits
NEAR_BITS = 16                                        # of 256 hash bits: the same photo, re-encoded / resized / slightly
BAND_BITS = 12                                        # rotated or brightened. Looked at by eye: unrelated pictures sit above 24


@dataclass
class Item:
    split: str
    img: Path
    lbl: Path
    source: str
    protected: bool
    legacy: bool                                      # no "<source>__" prefix: original committed data
    info: dict | None = None
    boxes: list[Box] = field(default_factory=list)
    fixed_labels: bool = False
    issues: list[str] = field(default_factory=list)
    action: str | None = None                         # None = keep, else a quarantine reason


# --------------------------------------------------------------------------- layout

def ensure_layout(model: str, apply: bool, log=print) -> list[str]:
    """Move an old-style split layout (train/images, valid/labels, ...) to images/<split> + labels/<split>."""
    base = DATASETS / model
    cfg = load_yaml(base / "data.yaml")
    moves: list[str] = []
    old_dirs: set[Path] = set()
    for split in SPLITS:
        rel = cfg.get(split)
        if rel is None and split != "train" and cfg.get("train"):
            rel = cfg["train"].replace("train", split)
        if not rel:
            continue
        img_src, lbl_src = base / rel, base / rel.replace("images", "labels")
        img_dst, lbl_dst = canonical_dirs(model, split)
        if img_src.resolve() == img_dst.resolve():
            continue
        for src, dst in ((img_src, img_dst), (lbl_src, lbl_dst)):
            if not src.exists():
                continue
            moves.append(f"{src.relative_to(base).as_posix()} -> {dst.relative_to(base).as_posix()}")
            if apply:
                dst.parent.mkdir(parents=True, exist_ok=True)
                if dst.exists():
                    if any(p.name != ".gitkeep" for p in dst.iterdir()):
                        raise RuntimeError(f"{dst} is not empty: cannot move {src} there")
                    for p in dst.iterdir():
                        p.unlink()
                    dst.rmdir()
                src.rename(dst)
                old_dirs.add(src.parent)
    if apply and moves:
        for d in old_dirs:                                    # train/, valid/, test/ left behind
            if d != base and d.exists() and not any(d.iterdir()):
                d.rmdir()
        text = (base / "data.yaml").read_text(encoding="utf-8")
        header = "".join(l + "\n" for l in text.splitlines() if l.startswith("#"))
        names = class_names(model)
        body = (f"path: datasets/{model}\ntrain: images/train\nval: images/val\ntest: images/test\n\n"
                f"nc: {len(names)}\nnames:\n" + "".join(f"  {i}: {n}\n" for i, n in enumerate(names)))
        (base / "data.yaml").write_text(header + body, encoding="utf-8")
        log(f"  layout: {len(moves)} folders moved to the standard layout")
    return moves


# --------------------------------------------------------------------------- scan and check

def scan(model: str) -> list[Item]:
    items = []
    for split in SPLITS:
        img_dir, lbl_dir = canonical_dirs(model, split)
        for img, lbl in pairs(img_dir, lbl_dir):
            name = img.name
            items.append(Item(split, img, lbl, source_of(name), name.startswith(PROTECTED_PREFIX),
                              "__" not in name))
    return items


def check(item: Item, nc: int, max_side: int) -> None:
    """Fill in item.info / boxes / issues. Pure reading: changes nothing on disk."""
    item.info = inspect_image(item.img)
    if item.info is None:
        item.issues.append("corrupt_image")
        return
    if min(item.info["w"], item.info["h"]) < MIN_SIDE:
        item.issues.append("tiny_image")
    if not item.lbl.exists():
        item.issues.append("no_label")
        return
    raw = read_yolo(item.lbl)
    item.boxes, dropped = clean_boxes(raw, item.info["w"], item.info["h"], nc)
    if len(item.boxes) != len(raw) or dropped["clipped"]:
        item.fixed_labels = True
        item.issues.append("fixed_boxes")
    if not item.boxes:
        item.issues.append("no_boxes")
    needs = (item.info["format"] != "JPEG" or item.info["rotated"] or item.info["mode"] != "RGB"
             or max(item.info["w"], item.info["h"]) > max_side)
    if needs and not item.legacy and not item.protected:
        item.issues.append("resave")


def find_duplicates(items: list[Item]) -> Counter:
    """
    Mark train copies of photos that are also in val / test (and exact repeats inside a split).
    Returns how many val / test pictures had a twin in train: those scores were measured on seen pictures.
    """
    live = [i for i in items if i.action is None and i.info]
    buckets: dict[tuple[int, int], list[int]] = defaultdict(list)
    for idx, it in enumerate(live):                       # 22 bands of 12 bits: hashes <= 21 bits apart share a band
        for band in range(0, 256, BAND_BITS):
            buckets[(band, (it.info["dhash"] >> band) & ((1 << BAND_BITS) - 1))].append(idx)
    parent = list(range(len(live)))

    def root(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    seen_pairs = set()
    for members in buckets.values():
        if len(members) < 2 or len(members) > 400:        # a huge bucket = flat/black pictures, not photos
            continue
        for a in range(len(members)):
            for b in range(a + 1, len(members)):
                i, j = members[a], members[b]
                if (i, j) in seen_pairs:
                    continue
                seen_pairs.add((i, j))
                x, y = live[i], live[j]
                d = hamming(x.info["dhash"], y.info["dhash"])
                if x.split != y.split and d <= NEAR_BITS:
                    parent[root(i)] = root(j)
                elif x.split == y.split and d == 0 and (x.info["w"], x.info["h"]) == (y.info["w"], y.info["h"]) \
                        and sorted(x.boxes) == sorted(y.boxes):
                    parent[root(i)] = root(j)
    clusters: dict[int, list[Item]] = defaultdict(list)
    for idx, it in enumerate(live):
        clusters[root(idx)].append(it)
    contaminated: Counter = Counter()
    for group in clusters.values():
        if len(group) < 2:
            continue
        if any(it.split == "train" for it in group):
            for it in group:
                if it.split != "train":
                    contaminated[it.split] += 1
        # keep the copy in the most precious split; inside it keep the one with most boxes / pixels
        group.sort(key=lambda it: (SPLIT_RANK[it.split], -len(it.boxes), -(it.info["w"] * it.info["h"]), it.img.name))
        keeper = group[0]
        for it in group[1:]:
            if it.protected:
                it.issues.append("duplicate_of_protected" if keeper.protected else "duplicate_kept_protected")
                continue
            it.action = "leak" if it.split != keeper.split else "duplicate"
    return contaminated


# --------------------------------------------------------------------------- the whole pass

def curate_model(model: str, apply: bool = False, max_side: int = 1280, workers: int = 8, log=print) -> dict:
    t0 = time.time()
    moves = ensure_layout(model, apply, log)
    names = class_names(model)
    nc = len(names)
    items = scan(model) if (apply or not moves) else []
    log(f"{model}: {len(items):,} pictures to check ({'apply' if apply else 'dry-run'})")
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for n, _ in enumerate(pool.map(lambda it: check(it, nc, max_side), items), 1):
            if n % 4000 == 0:
                log(f"    checked {n:,} / {len(items):,}")

    for it in items:                                      # problems that remove a picture
        for reason in ("corrupt_image", "tiny_image", "no_label", "no_boxes"):
            if reason in it.issues and not it.protected:
                it.action = it.action or reason
    contaminated = find_duplicates(items)

    dropped = Counter()
    resaved = fixed = 0
    for it in items:
        if it.action:
            dropped[it.action] += 1
            if apply:
                lbl = it.lbl if it.lbl.exists() else None
                quarantine(it.img, model, it.action)
                if lbl:
                    quarantine(lbl, model, it.action)
            continue
        if it.fixed_labels and not it.protected:
            fixed += 1
            if apply:
                write_yolo(it.lbl, it.boxes)
        if "resave" in it.issues:
            resaved += 1
            scale = min(1.0, max_side / max(it.info["w"], it.info["h"]))
            it.info["w"], it.info["h"] = round(it.info["w"] * scale), round(it.info["h"] * scale)   # size AFTER the re-save
            if apply:
                dst = it.img.with_suffix(".jpg")
                write_jpeg(it.img, dst, max_side)
                if dst != it.img:
                    it.img.unlink()
                    it.img = dst

    kept = [it for it in items if it.action is None]
    per_split = {s: sum(1 for it in kept if it.split == s) for s in SPLITS}
    per_class = {s: Counter() for s in SPLITS}
    per_source: dict[str, Counter] = defaultdict(Counter)
    sizes = []
    for it in kept:
        for c, *_ in it.boxes:
            per_class[it.split][names[c]] += 1
        per_source[it.source][it.split] += 1
        if it.info:
            sizes.append(max(it.info["w"], it.info["h"]))
    for it in items:
        if it.action:
            per_source[it.source]["dropped"] += 1
    sizes.sort()
    box_areas = sorted(b[3] * b[4] for it in kept for b in it.boxes)
    report = {
        "model": model, "applied": apply, "seconds": round(time.time() - t0, 1),
        "classes": names, "layout_moves": moves,
        "checked": len(items), "kept": len(kept), "dropped": dict(dropped),
        "fixed_labels": fixed, "resaved_pictures": resaved,
        "issues_kept": dict(Counter(i for it in kept for i in it.issues if i not in ("resave", "fixed_boxes"))),
        "images_per_split": per_split,
        "eval_pictures_with_train_twin": dict(contaminated),
        "boxes_per_class": {s: dict(per_class[s]) for s in SPLITS},
        "per_source": {k: dict(v) for k, v in sorted(per_source.items())},
        "long_side_px": {"min": sizes[0] if sizes else 0, "median": sizes[len(sizes) // 2] if sizes else 0,
                         "max": sizes[-1] if sizes else 0},
        "box_area_share": {"p10": round(box_areas[len(box_areas) // 10], 5) if box_areas else 0,
                           "median": round(box_areas[len(box_areas) // 2], 5) if box_areas else 0,
                           "p90": round(box_areas[(9 * len(box_areas)) // 10], 5) if box_areas else 0},
        "empty_pictures_kept": sum(1 for it in kept if not it.boxes),
    }
    if apply:
        rp = DATASETS / model / "report.json"
        try:
            prev = json.loads(rp.read_text(encoding="utf-8")) if rp.exists() else {}
        except ValueError:
            prev = {}
        first = prev.get("eval_twins_before_first_cleaning") or (dict(contaminated) if contaminated else None)
        if first:                                           # later passes find nothing: keep what the FIRST pass found
            report["eval_twins_before_first_cleaning"] = first
        dump_json(rp, report)
    log(f"  kept {len(kept):,}, quarantined {sum(dropped.values()):,} {dict(dropped)}, labels fixed {fixed}, re-saved {resaved} "
        f"({report['seconds']}s)")
    return report
