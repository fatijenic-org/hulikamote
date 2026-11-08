"""
accept.py - Add the pictures a human finished ("ready") to a model's training dataset.

Safety rules:
  - refused while that model is training (YOLO reads its dataset every epoch);
  - all pictures of one car (one group) go to the same side of the train/val split, so the
    validation score is never inflated by near-identical frames seen in training;
  - the test split is never touched, so old and new models stay comparable;
  - files are named harvest__<id>.* (ignored by git; fetch_datasets.py leaves them alone).
"""
import hashlib
import shutil
from collections import Counter

import yaml

from .config import MODELS, Paths
from .store import Store, yolo_text


VAL_SHARE = 0.15


class TrainingBusy(RuntimeError):
    """The model is being trained right now; its dataset must not change underneath it."""


def training_models() -> set[str]:
    """Models being trained right now, by whoever started them (one scan of the process list)."""
    import psutil
    busy = set()
    for proc in psutil.process_iter(["cmdline"]):
        try:
            cmd = " ".join(proc.info["cmdline"] or [])
        except Exception:
            continue
        if "train.py" not in cmd and "resume=True" not in cmd:
            continue
        for model in MODELS:
            if (("train.py" in cmd and f"--model {model}" in cmd) or ("resume=True" in cmd and model in cmd)):
                busy.add(model)
    return busy


def is_training(model: str) -> bool:
    return model in training_models()


def split_dirs(paths: Paths, model: str, split: str):
    """(images dir, labels dir) of a split, following the dataset's own data.yaml layout."""
    cfg = yaml.safe_load((paths.datasets / model / "data.yaml").read_text(encoding="utf-8"))
    images = cfg.get(split) or cfg["train"].replace("train", split)
    base = paths.datasets / model
    return base / images, base / images.replace("images", "labels")


def pick_split(group_id: str, hint: str | None, val_share: float = VAL_SHARE) -> str:
    if hint in ("train", "val"):
        return hint
    bucket = int(hashlib.sha1(group_id.encode("utf-8")).hexdigest(), 16) % 1000 / 1000
    return "val" if bucket < val_share else "train"


def accept(paths: Paths, store: Store, model: str, dry_run: bool = False) -> dict:
    if model not in MODELS:
        raise ValueError(f"Unknown model '{model}'")
    ready = store.ready(model)
    result = {"model": model, "ready": len(ready), "added": 0, "train": 0, "val": 0,
              "empty_labels": 0, "per_class": {}}
    if not ready:
        return result
    if is_training(model):
        raise TrainingBusy(f"{MODELS[model]['title']} is training right now. Pause or wait for it to finish, "
                           "then add the pictures (they stay safe in the inbox).")
    per_class: Counter = Counter()
    for item in ready:
        split = pick_split(item.group_id, item.split_hint)
        if dry_run:
            result[split] += 1
            continue
        img_dir, lbl_dir = split_dirs(paths, model, split)
        img_dir.mkdir(parents=True, exist_ok=True)
        lbl_dir.mkdir(parents=True, exist_ok=True)
        name = f"harvest__{item.id}"
        shutil.copy2(store.image_path(model, item.id), img_dir / f"{name}.jpg")
        (lbl_dir / f"{name}.txt").write_text(yolo_text(item.boxes), encoding="utf-8")
        store.mark_accepted(item.id, f"{name}.jpg")
        result[split] += 1
        result["added"] += 1
        result["empty_labels"] += 0 if item.boxes else 1
        for b in item.boxes:
            per_class[int(b[0])] += 1
    result["per_class"] = dict(per_class)
    return result
