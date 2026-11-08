"""
train.py — Train a HULI-KAMOTE specialist model using YOLOv8.

Usage:
    python scripts/train.py --model helmet_specialist
    python scripts/train.py --model plate_specialist --epochs 100 --imgsz 320
    python scripts/train.py --model cabin_specialist --batch 8
"""
import argparse
import yaml
from pathlib import Path
from ultralytics import YOLO

ROOT = Path(__file__).parent.parent
CONFIG_PATH = ROOT / "configs" / "training_config.yaml"


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def train(model_name: str, epochs: int | None, imgsz: int | None, batch: int | None,
          fraction: float = 1.0, name: str = "train"):
    cfg = load_config()
    model_cfg = cfg.get("models", {}).get(model_name, {})

    # Resolve params: CLI arg > per-model override > master default
    resolved_epochs = epochs or model_cfg.get("epochs", cfg["epochs"])
    resolved_imgsz  = imgsz  or model_cfg.get("imgsz",  cfg["imgsz"])
    resolved_batch  = batch  or cfg["batch"]

    data_yaml = ROOT / "datasets" / model_name / "data.yaml"
    if not data_yaml.exists():
        raise FileNotFoundError(f"data.yaml not found at {data_yaml}")

    print(f"\n{'='*60}")
    print(f"  Training: {model_name}")
    print(f"  Epochs:   {resolved_epochs}")
    print(f"  imgsz:    {resolved_imgsz}")
    print(f"  Batch:    {resolved_batch}")
    print(f"  Device:   {cfg['device']}")
    print(f"  Note:     {model_cfg.get('note', '')}")
    print(f"{'='*60}\n")

    # A relative "path:" in data.yaml is resolved by Ultralytics against ITS datasets folder
    # (not ours), so hand it a copy whose path is this dataset's absolute folder.
    data = yaml.safe_load(data_yaml.read_text(encoding="utf-8"))
    data["path"] = str(data_yaml.parent.resolve())
    resolved_yaml = ROOT / "runs" / model_name / "data_resolved.yaml"
    resolved_yaml.parent.mkdir(parents=True, exist_ok=True)
    resolved_yaml.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")

    model = YOLO(cfg["base_model"])
    model.train(
        data=str(resolved_yaml),
        epochs=resolved_epochs,
        imgsz=resolved_imgsz,
        batch=resolved_batch,
        device=cfg["device"],
        workers=cfg["workers"],
        patience=cfg["patience"],
        project=str(ROOT / "runs" / model_name),
        name=name,
        fraction=fraction,   # < 1.0 = quick check on part of the data
        exist_ok=False,
        # Augmentation overrides from config
        hsv_h=cfg["augment"]["hsv_h"],
        hsv_s=cfg["augment"]["hsv_s"],
        hsv_v=cfg["augment"]["hsv_v"],
        degrees=cfg["augment"]["degrees"],
        translate=cfg["augment"]["translate"],
        scale=cfg["augment"]["scale"],
        fliplr=cfg["augment"]["fliplr"],
        mosaic=cfg["augment"]["mosaic"],
    )
    print(f"\n✅ Training complete. Weights saved to: {model.trainer.save_dir}/weights/")
    print("→ Run export_onnx.py to convert and deploy to the backend.\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True,
                        choices=["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"],
                        help="Which specialist model to train")
    parser.add_argument("--epochs", type=int, default=None)
    parser.add_argument("--imgsz",  type=int, default=None)
    parser.add_argument("--batch",  type=int, default=None)
    parser.add_argument("--fraction", type=float, default=1.0, help="share of the training images to use (quick checks)")
    parser.add_argument("--name", default="train", help="run folder name under runs/<model>/")
    args = parser.parse_args()

    train(args.model, args.epochs, args.imgsz, args.batch, args.fraction, args.name)
