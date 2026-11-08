"""
split_dataset.py — Split a folder of raw annotated images into train/val sets.

Expects raw data placed in:
    datasets/<model>/raw/images/  (all images)
    datasets/<model>/raw/labels/  (matching YOLO .txt files)

Outputs shuffled splits to:
    datasets/<model>/images/train/
    datasets/<model>/images/val/
    datasets/<model>/labels/train/
    datasets/<model>/labels/val/

Usage:
    python scripts/split_dataset.py --model helmet_specialist
    python scripts/split_dataset.py --model plate_specialist --ratio 0.85
"""
import argparse
import shutil
import random
from pathlib import Path

ROOT = Path(__file__).parent.parent
SUPPORTED_IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp"}


def split(model_name: str, ratio: float, seed: int):
    raw_images = ROOT / "datasets" / model_name / "raw" / "images"
    raw_labels = ROOT / "datasets" / model_name / "raw" / "labels"

    # Datasets that arrive already split (e.g. merged by fetch_datasets.py) have no raw/ images:
    # keep their split instead of failing.
    has_raw = raw_images.exists() and any(p.suffix.lower() in SUPPORTED_IMG_EXTS for p in raw_images.iterdir())
    train_dir = ROOT / "datasets" / model_name / "images" / "train"
    if not has_raw and train_dir.exists() and any(p.suffix.lower() in SUPPORTED_IMG_EXTS for p in train_dir.iterdir()):
        print(f"No raw images; datasets/{model_name} is already split into train/val. Skipping split.")
        return

    if not raw_images.exists():
        raise FileNotFoundError(
            f"Raw images not found at {raw_images}\n"
            f"Place annotated images in datasets/{model_name}/raw/images/"
        )

    images = sorted([p for p in raw_images.iterdir() if p.suffix.lower() in SUPPORTED_IMG_EXTS])
    if not images:
        raise ValueError(f"No images found in {raw_images}")

    random.seed(seed)
    random.shuffle(images)

    split_idx = int(len(images) * ratio)
    train_imgs = images[:split_idx]
    val_imgs   = images[split_idx:]

    print(f"\n{'='*60}")
    print(f"  Model:  {model_name}")
    print(f"  Total:  {len(images)} images")
    print(f"  Train:  {len(train_imgs)}")
    print(f"  Val:    {len(val_imgs)}")
    print(f"{'='*60}\n")

    for split_name, split_imgs in [("train", train_imgs), ("val", val_imgs)]:
        img_out = ROOT / "datasets" / model_name / "images" / split_name
        lbl_out = ROOT / "datasets" / model_name / "labels" / split_name
        img_out.mkdir(parents=True, exist_ok=True)
        lbl_out.mkdir(parents=True, exist_ok=True)

        for img_path in split_imgs:
            shutil.copy2(img_path, img_out / img_path.name)

            label_path = raw_labels / img_path.with_suffix(".txt").name
            if label_path.exists():
                shutil.copy2(label_path, lbl_out / label_path.name)
            else:
                print(f"  ⚠ WARNING: No label found for {img_path.name}")

    print(f"✅ Split complete → datasets/{model_name}/images/ and datasets/{model_name}/labels/\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True,
                        choices=["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"])
    parser.add_argument("--ratio", type=float, default=0.8,
                        help="Train/val split ratio (default: 0.8 = 80%% train)")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    split(args.model, args.ratio, args.seed)
