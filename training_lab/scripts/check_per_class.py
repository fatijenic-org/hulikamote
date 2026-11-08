"""
check_per_class.py - Score one finished detector run per type (car, tricycle, helmet ...) on its test photos.

    python scripts/check_per_class.py --model primary_anchor --run train-3

The Training Studio's numbers are one score for all types together; a detector can be good at buses and poor at people and still
show a fine overall score. This runs the run's best weights over the dataset's test split (the validation split when there is no
test split) and saves runs/<model>/<run>/per_class.json, which the Models page shows. Reads the run, writes only that file.
"""
import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # training_lab/


def check(model_key: str, run: str) -> dict:
    from ultralytics import YOLO

    run_dir = ROOT / "runs" / model_key / run
    weights = run_dir / "weights" / "best.pt"
    data = ROOT / "runs" / model_key / "data_resolved.yaml"
    if not weights.exists():
        raise FileNotFoundError(f"No weights at {weights}")
    if not data.exists():
        raise FileNotFoundError(f"No dataset file at {data} (it is written when the model is trained)")
    split = "test" if "\ntest:" in "\n" + data.read_text(encoding="utf-8") else "val"
    model = YOLO(str(weights))
    # workers=0: Windows would start worker processes that re-import this file
    r = model.val(data=str(data), split=split, imgsz=640, batch=16, plots=False, workers=0, verbose=False,
                  project=str(ROOT / "runs" / "_checks"), name=f"{model_key}_{run}", exist_ok=True)
    classes = [{"name": model.names[int(ci)], "score": round(float(r.box.ap50[k]), 3),
                "boxes": int(r.nt_per_class[ci])} for k, ci in enumerate(r.box.ap_class_index)]
    classes.sort(key=lambda c: c["score"], reverse=True)
    out = {"split": split, "map50": round(float(r.box.map50), 3), "classes": classes}
    tmp = run_dir / "per_class.json.tmp"
    tmp.write_text(json.dumps(out, indent=1), encoding="utf-8")
    os.replace(tmp, run_dir / "per_class.json")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="e.g. primary_anchor, plate_specialist, helmet_specialist, cabin_specialist")
    ap.add_argument("--run", required=True, help="run folder, e.g. train-3")
    args = ap.parse_args(argv)
    out = check(args.model, args.run)
    print(f"[Per type] {args.model}/{args.run} on the {out['split']} photos: overall {out['map50']:.3f}")
    for c in out["classes"]:
        print(f"  {c['name']:<14} {c['score']:.3f}  ({c['boxes']} boxes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
