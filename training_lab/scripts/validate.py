"""
validate.py — Run mAP validation on a trained model against the val set.

Usage:
    python scripts/validate.py --model helmet_specialist
    python scripts/validate.py --model plate_specialist --run train2

Prints mAP@0.5, mAP@0.5:0.95, precision, recall per class.
Compared against the target benchmarks from the README:
  - helmet_specialist:  mAP@0.5 >= 0.85
  - plate_specialist:   mAP@0.5 >= 0.90
  - cabin_specialist:   mAP@0.5 >= 0.80
"""
import argparse
import yaml
from pathlib import Path
from ultralytics import YOLO

ROOT = Path(__file__).parent.parent

TARGET_MAP = {
    "primary_anchor":    0.80,
    "helmet_specialist": 0.85,
    "plate_specialist":  0.90,
    "cabin_specialist":  0.80,
}


def validate(model_name: str, run: str):
    weights_dir = ROOT / "runs" / model_name / run / "weights"
    best_pt = weights_dir / "best.pt"

    if not best_pt.exists():
        raise FileNotFoundError(f"best.pt not found at {best_pt}")

    data_yaml = ROOT / "datasets" / model_name / "data.yaml"

    with open(data_yaml) as f:
        cfg = yaml.safe_load(f)

    print(f"\n{'='*60}")
    print(f"  Validating: {model_name}")
    print(f"  Weights:    {best_pt}")
    print(f"  Classes:    {cfg['names']}")
    print(f"{'='*60}\n")

    model = YOLO(str(best_pt))
    metrics = model.val(data=str(data_yaml))

    map50 = metrics.box.map50
    target = TARGET_MAP.get(model_name, 0.80)

    print(f"\n{'='*60}")
    print(f"  mAP@0.5:       {map50:.4f}")
    print(f"  mAP@0.5:0.95:  {metrics.box.map:.4f}")
    print(f"  Target mAP@0.5: {target}")

    if map50 >= target:
        print(f"  ✅ PASS — Ready for ONNX export and deployment.")
    else:
        print(f"  ❌ FAIL — mAP below target. Collect more data or train longer.")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True,
                        choices=list(TARGET_MAP.keys()))
    parser.add_argument("--run", default="train")
    args = parser.parse_args()

    validate(args.model, args.run)
