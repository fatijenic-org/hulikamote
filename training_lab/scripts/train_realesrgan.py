"""
train_realesrgan.py — Train a custom License Plate Super-Resolution GAN (Option B).

Uses your existing plate_specialist dataset (3,000 UK/EU plate images) to train
a lightweight RRDB-based GAN specifically optimized for license plate text recovery.

Architecture: BasicSR ESRGAN (RRDB backbone, 6 blocks, x4 scale)
              Lightweight variant — fits in RTX 3050 6GB VRAM.

Steps performed:
  1. Build HR/LR image pairs from your existing plate_specialist dataset
  2. Write a BasicSR YAML config pointing to those pairs
  3. Launch BasicSR training (ESRGAN pipeline)
  4. Export best checkpoint to ONNX as realesrgan.onnx
  5. Deploy to hulikamote_backend/models/realesrgan.onnx

Usage:
    python training_lab/scripts/train_realesrgan.py [--epochs 100]
    (Recommended: 200 epochs minimum for visible GAN improvement)
"""

import argparse
import subprocess
import sys
import os
import shutil
import random
import cv2
import numpy as np
from pathlib import Path

ROOT          = Path(__file__).resolve().parent.parent
DATASET_DIR   = ROOT / "datasets" / "plate_specialist"
SR_DIR        = ROOT / "datasets" / "sr_plates"
BACKEND_DIR   = ROOT.parent / "hulikamote_backend"
MODELS_DIR    = BACKEND_DIR / "models"
RUNS_DIR      = ROOT / "runs" / "realesrgan"
CONFIG_PATH   = ROOT / "configs" / "realesrgan_train.yml"
ONNX_OUT      = MODELS_DIR / "realesrgan.onnx"

SCALE         = 4
TILE_SIZE     = 128    # HR tile size. LR = 128/4 = 32px
NUM_BLOCKS    = 6      # Lightweight RRDB depth for RTX 3050


def install_deps():
    print("[Setup] Installing BasicSR...")
    subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "basicsr", "requests"], check=True)


def build_image_pairs(max_images: int = 2000):
    """
    Crop plate regions from existing labeled images to build HR/LR pairs.
    Falls back to using the full images if crops are too small.
    """
    print("[Data] Building HR/LR pairs from plate_specialist dataset...")

    hr_dir = SR_DIR / "hr"
    lr_dir = SR_DIR / "lr"
    hr_dir.mkdir(parents=True, exist_ok=True)
    lr_dir.mkdir(parents=True, exist_ok=True)

    images_dir  = DATASET_DIR / "images" / "train"       # the standard layout (data.yaml: images/train)
    labels_dir  = DATASET_DIR / "labels" / "train"
    img_files   = list(images_dir.glob("*.jpg")) + list(images_dir.glob("*.png"))
    random.shuffle(img_files)
    img_files   = img_files[:max_images]

    count = 0
    for img_path in img_files:
        img = cv2.imread(str(img_path))
        if img is None:
            continue
        H, W = img.shape[:2]

        label_path = labels_dir / (img_path.stem + ".txt")
        crops = []

        if label_path.exists():
            for line in label_path.read_text().splitlines():
                parts = line.strip().split()
                if len(parts) < 5:
                    continue
                _, cx, cy, bw, bh = map(float, parts[:5])
                x1 = int((cx - bw / 2) * W)
                y1 = int((cy - bh / 2) * H)
                x2 = int((cx + bw / 2) * W)
                y2 = int((cy + bh / 2) * H)
                x1, y1 = max(0, x1), max(0, y1)
                x2, y2 = min(W, x2), min(H, y2)
                if (x2 - x1) >= TILE_SIZE and (y2 - y1) >= TILE_SIZE // 2:
                    crops.append(img[y1:y2, x1:x2])

        if not crops:
            # Use full image resized to tile
            crops = [cv2.resize(img, (TILE_SIZE * 2, TILE_SIZE))]

        for crop in crops:
            # HR: resize to TILE_SIZE width preserving AR
            aspect = crop.shape[0] / crop.shape[1]
            hr_w = TILE_SIZE
            hr_h = max(32, int(TILE_SIZE * aspect))
            # Round to multiples of SCALE
            hr_h = (hr_h // SCALE) * SCALE
            hr_w = (hr_w // SCALE) * SCALE
            if hr_h < SCALE or hr_w < SCALE:
                continue

            hr = cv2.resize(crop, (hr_w, hr_h), interpolation=cv2.INTER_LANCZOS4)
            lr = cv2.resize(hr, (hr_w // SCALE, hr_h // SCALE), interpolation=cv2.INTER_CUBIC)

            name = f"plate_{count:05d}.png"
            cv2.imwrite(str(hr_dir / name), hr)
            cv2.imwrite(str(lr_dir / name), lr)
            count += 1

    print(f"[Data] Built {count} HR/LR pairs → {SR_DIR}")
    return count


def write_basicsr_config(epochs: int):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    cfg = f"""
# BasicSR ESRGAN config for License Plate SR (huli-kamote)
name: realesrgan
model_type: ESRGANModel
scale: {SCALE}
num_gpu: 1
manual_seed: 42

datasets:
  train:
    name: PlateHR
    type: PairedImageDataset
    dataroot_gt: {hr_dir := SR_DIR / "hr"}
    dataroot_lq: {lr_dir := SR_DIR / "lr"}
    io_backend:
      type: disk
    gt_size: {TILE_SIZE}
    use_hflip: true
    use_rot: true
    num_worker_per_gpu: 2
    batch_size_per_gpu: 8

network_g:
  type: RRDBNet
  num_in_ch: 3
  num_out_ch: 3
  num_feat: 32
  num_block: {NUM_BLOCKS}
  num_grow_ch: 16
  scale: {SCALE}

network_d:
  type: VGGStyleDiscriminator
  num_in_ch: 3
  num_feat: 32

path:
  pretrain_network_g: ~
  strict_load_g: true
  resume_state: ~
  models: {RUNS_DIR / "models"}
  training_states: {RUNS_DIR / "states"}

train:
  optim_g:
    type: Adam
    lr: !!float 1e-4
    weight_decay: 0
    betas: [0.9, 0.99]
  optim_d:
    type: Adam
    lr: !!float 1e-4
    weight_decay: 0
    betas: [0.9, 0.99]
  scheduler:
    type: MultiStepLR
    milestones: [{epochs // 2}, {int(epochs * 0.75)}]
    gamma: 0.5
  total_iter: {epochs * 100}
  warmup_iter: -1
  pixel_opt:
    type: L1Loss
    loss_weight: !!float 1e-2
    reduction: mean
  perceptual_opt:
    type: PerceptualLoss
    layer_weights:
      'conv5_4': 1
    vgg_type: vgg19
    use_input_norm: true
    perceptual_weight: 1.0
    style_weight: 0
    norm_img: false
    criterion: l1
  gan_opt:
    type: GANLoss
    gan_type: vanilla
    real_label_val: 1.0
    fake_label_val: 0.0
    loss_weight: !!float 5e-3
  net_d_iters: 1
  net_d_init_iters: 0

val:
  val_freq: !!float 1e3
  save_img: false
  metrics:
    psnr:
      type: calculate_psnr
      crop_border: {SCALE}
      test_y_channel: false

logger:
  print_freq: 100
  save_checkpoint_freq: !!float 5e3
  use_tb_logger: false
"""
    CONFIG_PATH.write_text(cfg)
    print(f"[Config] Written to {CONFIG_PATH}")


def export_to_onnx():
    import torch
    from basicsr.archs.rrdbnet_arch import RRDBNet

    checkpoints = list((RUNS_DIR / "models").glob("net_g_*.pth"))
    if not checkpoints:
        raise FileNotFoundError("No checkpoints found. Did training complete?")
    latest = max(checkpoints, key=lambda p: int(p.stem.split("_")[-1]))
    print(f"[Export] Loading checkpoint: {latest}")

    model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=32, num_block=NUM_BLOCKS, num_grow_ch=16, scale=SCALE)
    state = torch.load(str(latest), map_location="cpu")
    model.load_state_dict(state.get("params_ema", state.get("params", state)), strict=True)
    model.eval()

    dummy = torch.randn(1, 3, 80, 320)
    torch.onnx.export(
        model, dummy, str(ONNX_OUT),
        opset_version=11,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {2: "height", 3: "width"}, "output": {2: "height", 3: "width"}}
    )
    print(f"\n✅ Custom realesrgan exported → {ONNX_OUT}")
    print("   Restart FastAPI to activate.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=200)
    parser.add_argument("--export-only", action="store_true", help="Skip training, only export latest checkpoint")
    args = parser.parse_args()

    install_deps()

    if not args.export_only:
        count = build_image_pairs()
        if count < 50:
            print("[ERROR] Not enough plate images found. Check plate_specialist dataset.")
            sys.exit(1)
        write_basicsr_config(args.epochs)

        print(f"\n[Train] Starting ESRGAN training ({args.epochs} epochs)...")
        subprocess.run(
            [sys.executable, "-m", "basicsr.train", "-opt", str(CONFIG_PATH)],
            cwd=str(ROOT),
            check=True
        )

    print("\n[Export] Converting best checkpoint to ONNX...")
    export_to_onnx()


if __name__ == "__main__":
    main()
