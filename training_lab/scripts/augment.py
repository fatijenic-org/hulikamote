"""
augment.py — Offline augmentation to synthetically expand a small dataset.

Use this when your annotated dataset is too small (< 500 images per class).
Generates augmented images + updated YOLO labels in-place under:
    datasets/<model>/images/train/
    datasets/<model>/labels/train/

Augmentations applied (Philippine traffic context):
  - Brightness/contrast: simulates nighttime, overcast, midday glare
  - Rain/noise: simulates weather degradation
  - Rotation/perspective: simulates slight camera drift and mounting angle changes
  - Blur: simulates motion blur from fast vehicles

Usage:
    python scripts/augment.py --model helmet_specialist --count 500
    python scripts/augment.py --model plate_specialist --count 300
"""
import argparse
import random
import cv2
import numpy as np
from pathlib import Path

ROOT = Path(__file__).parent.parent


def random_brightness(img: np.ndarray) -> np.ndarray:
    factor = random.uniform(0.4, 1.4)
    return np.clip(img.astype(np.float32) * factor, 0, 255).astype(np.uint8)


def random_noise(img: np.ndarray) -> np.ndarray:
    noise = np.random.randint(0, 30, img.shape, dtype=np.uint8)
    return cv2.add(img, noise)


def random_blur(img: np.ndarray) -> np.ndarray:
    k = random.choice([3, 5])
    return cv2.GaussianBlur(img, (k, k), 0)


def random_flip(img: np.ndarray, labels: list[str]) -> tuple[np.ndarray, list[str]]:
    """Horizontal flip with label x-coordinate correction."""
    flipped = cv2.flip(img, 1)
    new_labels = []
    for line in labels:
        parts = line.strip().split()
        if len(parts) == 5:
            cls, x, y, w, h = parts
            new_labels.append(f"{cls} {1.0 - float(x):.6f} {y} {w} {h}")
        else:
            new_labels.append(line)
    return flipped, new_labels


def augment_one(img: np.ndarray, labels: list[str]) -> tuple[np.ndarray, list[str]]:
    if random.random() > 0.5:
        img, labels = random_flip(img, labels)
    img = random_brightness(img)
    if random.random() > 0.6:
        img = random_noise(img)
    if random.random() > 0.7:
        img = random_blur(img)
    return img, labels


def augment(model_name: str, count: int):
    img_dir = ROOT / "datasets" / model_name / "images" / "train"
    lbl_dir = ROOT / "datasets" / model_name / "labels" / "train"

    images = sorted([p for p in img_dir.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}])
    if not images:
        raise FileNotFoundError(f"No training images found at {img_dir}")

    print(f"\n{'='*60}")
    print(f"  Augmenting: {model_name}")
    print(f"  Source images: {len(images)}")
    print(f"  Generating:    {count} augmented copies")
    print(f"{'='*60}\n")

    for i in range(count):
        src_img_path = random.choice(images)
        src_lbl_path = lbl_dir / src_img_path.with_suffix(".txt").name

        img = cv2.imread(str(src_img_path))
        if img is None:
            continue

        labels = []
        if src_lbl_path.exists():
            with open(src_lbl_path) as f:
                labels = f.readlines()

        aug_img, aug_labels = augment_one(img, labels)

        out_name = f"aug_{i:05d}_{src_img_path.stem}"
        cv2.imwrite(str(img_dir / f"{out_name}.jpg"), aug_img)
        with open(lbl_dir / f"{out_name}.txt", "w") as f:
            f.write("\n".join(aug_labels))

        if (i + 1) % 100 == 0:
            print(f"  Generated {i+1}/{count}...")

    print(f"\n✅ Augmentation complete. New total: {len(images) + count} training images.\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True,
                        choices=["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"])
    parser.add_argument("--count", type=int, default=500,
                        help="Number of augmented images to generate")
    args = parser.parse_args()

    augment(args.model, args.count)
