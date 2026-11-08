"""
ReID training data from operator review decisions (merge / split / "different car").

Layout (training_lab/datasets/reid/):
    images/<task>/<identity>/<crop>.jpg   vehicle crops, one folder per physical car
    decisions.jsonl                       one JSON line per operator decision

Same identity folder = same car; different folders = different cars.
Best-effort only: a failure here must never block the review action.
"""
import json
import logging
import shutil
import time
from pathlib import Path

log = logging.getLogger("root.reid_dataset")

REID_DIR = Path(__file__).resolve().parent.parent.parent / "training_lab" / "datasets" / "reid"


def _crop_file(meta: dict, evidence_dir: Path) -> Path | None:
    """Clean vehicle crop for an evidence frame; older reports fall back to cropping the evidence photo."""
    if meta.get("car_crop") and (evidence_dir / meta["car_crop"]).exists():
        return evidence_dir / meta["car_crop"]
    bbox, src = meta.get("bbox"), evidence_dir / meta.get("file", "")
    if not bbox or not src.exists():
        return None
    try:
        import cv2
        img = cv2.imread(str(src))
        x, y, w, h = (int(v) for v in bbox)
        crop = img[max(0, y):max(0, y) + h, max(0, x):max(0, x) + w]
        if crop.size == 0:
            return None
        out = REID_DIR / "_tmp" / f"{src.stem}_crop.jpg"
        out.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(out), crop)
        return out
    except Exception:
        return None


def record(kind: str, task_id: str, groups: dict[str, list[dict]], evidence_dir: Path) -> int:
    """Save the crops of each group under its identity folder and log the decision.
    `groups` maps an identity label to the evidence_meta entries of that car.
    Returns the number of crops saved."""
    try:
        saved: dict[str, list[str]] = {}
        for label, metas in groups.items():
            folder = REID_DIR / "images" / task_id / label
            for m in metas:
                src = _crop_file(m, evidence_dir)
                if src is None:
                    continue
                folder.mkdir(parents=True, exist_ok=True)
                dest = folder / src.name
                if not dest.exists():
                    shutil.copy2(src, dest)
                saved.setdefault(label, []).append(f"images/{task_id}/{label}/{src.name}")
        if not saved:
            return 0
        REID_DIR.mkdir(parents=True, exist_ok=True)
        with open(REID_DIR / "decisions.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps({"ts": time.time(), "kind": kind, "task_id": task_id, "identities": saved}) + "\n")
        return sum(len(v) for v in saved.values())
    except Exception as e:  # never break the review action
        log.warning(f"[ReID dataset] could not record {kind}: {e}")
        return 0
