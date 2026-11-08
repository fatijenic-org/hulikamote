"""
train_ocr.py — Fine-tune EasyOCR or PaddleOCR on the Pop Quiz plate dataset.

Usage:
    python training_lab/scripts/train_ocr.py --engine easyocr
    python training_lab/scripts/train_ocr.py --engine paddleocr
    python training_lab/scripts/train_ocr.py --engine easyocr --epochs 50 --batch 16
"""
import argparse
import os
import sys
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATASET_IMAGES = ROOT / "datasets" / "plate_ocr" / "images" / "train"
DATASET_LABELS = ROOT / "datasets" / "plate_ocr" / "labels" / "train"
RUNS_DIR = ROOT / "runs"

# ── Helpers ────────────────────────────────────────────────────────────────────

def load_pairs() -> list[tuple[Path, str]]:
    """Load (image_path, label_text) pairs from the Pop Quiz dataset."""
    pairs = []
    for label_file in DATASET_LABELS.glob("*.txt"):
        img_file = DATASET_IMAGES / (label_file.stem + ".jpg")
        if not img_file.exists():
            continue
        raw = label_file.read_text(encoding="utf-8").strip()
        # Format: "0 PLATE_TEXT"  — strip the class ID prefix
        text = raw.split(" ", 1)[-1].strip() if raw else ""
        pairs.append((img_file, text))
    return pairs


def validate_dataset():
    pairs = load_pairs()
    if len(pairs) == 0:
        print("[ERROR] No data found.")
        print(f"  Images dir : {DATASET_IMAGES}")
        print(f"  Labels dir : {DATASET_LABELS}")
        print("  Run the dashboard and use the Inbox to accumulate corrections first.")
        sys.exit(1)

    positives = [(p, t) for p, t in pairs if t.strip()]
    negatives = [(p, t) for p, t in pairs if not t.strip()]
    print(f"[Dataset] {len(pairs)} total  |  {len(positives)} labelled  |  {len(negatives)} false-positive/background")
    return pairs, positives, negatives


# ── EasyOCR fine-tune ──────────────────────────────────────────────────────────

def train_easyocr(pairs: list, epochs: int, batch: int):
    """
    Fine-tune EasyOCR's recognition model using the CRAFT+CRNN pipeline.
    EasyOCR supports custom training via the `trainer` module.
    """
    try:
        import easyocr
        from easyocr.trainer.train import train as easyocr_train
    except ImportError:
        print("[ERROR] EasyOCR not installed. Run: pip install easyocr")
        sys.exit(1)

    run_dir = RUNS_DIR / "easyocr_finetune"
    run_dir.mkdir(parents=True, exist_ok=True)

    # Build gt_label.txt in EasyOCR trainer format: "path/to/img.jpg\tTEXT"
    gt_path = run_dir / "gt_label.txt"
    with open(gt_path, "w", encoding="utf-8") as f:
        for img_path, text in pairs:
            if text:  # EasyOCR recognition only trains on labelled images
                f.write(f"{img_path.resolve()}\t{text}\n")

    print(f"[EasyOCR] Ground truth written → {gt_path}  ({len(pairs)} entries)")
    print(f"[EasyOCR] Starting fine-tune | epochs={epochs} batch={batch}")

    # EasyOCR trainer config
    config = {
        "experiment_name": "plate_specialist_ocr",
        "train_data": str(gt_path),
        "valid_data": str(gt_path),  # re-use for now; swap when val split is ready
        "character": "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "batch_size": batch,
        "num_epoch": epochs,
        "lr": 1e-4,
        "saved_model": "",  # start from scratch; set path for resume
        "FT": False,
        "Transformation": "TPS",
        "FeatureExtraction": "ResNet",
        "SequenceModeling": "BiLSTM",
        "Prediction": "CTC",
        "num_fiducial": 20,
        "input_channel": 1,
        "output_channel": 512,
        "hidden_size": 256,
        "workers": 0,
        "valInterval": 5,
        "save_interval": 10,
        "experiment_dir": str(run_dir),
        "manualSeed": 1111,
        "imgH": 32,
        "imgW": 100,
        "PAD": False,
        "data_filtering_off": True,
    }

    config_path = run_dir / "config.json"
    config_path.write_text(json.dumps(config, indent=2))
    print(f"[EasyOCR] Config saved → {config_path}")

    try:
        easyocr_train(config)
        print(f"\n✓ EasyOCR fine-tune complete. Weights in: {run_dir}")
        print("  Next: copy the best `.pth` file into your EasyOCR model directory")
        print("  and point your config to it using `model_storage_directory`.")
    except Exception as e:
        print(f"[EasyOCR] Training error: {e}")
        print("  Tip: EasyOCR trainer requires: pip install easyocr[trainer]")
        sys.exit(1)


# ── PaddleOCR fine-tune ────────────────────────────────────────────────────────

def train_paddleocr(pairs: list, epochs: int, batch: int):
    """
    Fine-tune PaddleOCR's recognition model (SVTR_LCNet) on the Pop Quiz dataset.
    """
    try:
        import paddle
        from paddleocr import paddleocr as _paddle_check
    except ImportError:
        print("[ERROR] PaddleOCR not installed.")
        print("  Install: pip install paddlepaddle paddleocr")
        sys.exit(1)

    run_dir = RUNS_DIR / "paddleocr_finetune"
    img_dir = run_dir / "images"
    img_dir.mkdir(parents=True, exist_ok=True)

    # Copy images into run dir and write label list
    label_lines = []
    for img_path, text in pairs:
        if not text:
            continue  # skip background-only images for recognition training
        dest = img_dir / img_path.name
        shutil.copy2(img_path, dest)
        # PaddleOCR rec label format: "relative/path.jpg\tTEXT"
        label_lines.append(f"images/{img_path.name}\t{text}")

    label_file = run_dir / "rec_gt_train.txt"
    label_file.write_text("\n".join(label_lines), encoding="utf-8")
    print(f"[PaddleOCR] Label file written → {label_file}  ({len(label_lines)} entries)")

    # Write the YAML config that PaddleOCR's training pipeline reads
    char_set = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    char_dict_path = run_dir / "ph_plate_chars.txt"
    char_dict_path.write_text("\n".join(list(char_set)), encoding="utf-8")

    yaml_content = f"""
Global:
  use_gpu: true
  epoch_num: {epochs}
  log_smooth_window: 20
  print_batch_step: 10
  save_model_dir: {run_dir / "output"}
  save_epoch_step: 3
  eval_batch_step: [0, 2000]
  cal_metric_during_train: true
  pretrained_model:         # leave blank to train from scratch; set path to resume
  checkpoints:
  character_dict_path: {char_dict_path}
  max_text_length: 10
  infer_mode: false
  use_space_char: false

Optimizer:
  name: Adam
  beta1: 0.9
  beta2: 0.999
  lr:
    name: Cosine
    learning_rate: 0.001
    warmup_epoch: 5

Architecture:
  model_type: rec
  algorithm: SVTR_LCNet
  Transform:
  Backbone:
    name: MobileNetV1Enhance
    scale: 0.5
    last_conv_stride: [1, 2]
    last_pool_type: avg
  Head:
    name: MultiHead
    head_list:
      - CTCHead:
          Neck:
            name: svtr
            dims: 64
            depth: 2
            hidden_dims: 120
            use_guide: True
          Head:
            fc_decay: 0.00001
      - SARHead:
          enc_dim: 512
          max_text_length: 10

Loss:
  name: MultiLoss
  loss_config_list:
    - CTCLoss:
    - SARLoss:

PostProcess:
  name: CTCLabelDecode

Metric:
  name: RecMetric
  main_indicator: acc
  ignore_space: true

Train:
  dataset:
    name: SimpleDataSet
    data_dir: {run_dir}
    label_file_list: [{label_file}]
    transforms:
      - DecodeImage:
          img_mode: BGR
          channel_first: False
      - RecAug:
      - CTCLabelEncode:
      - RecResizeImg:
          image_shape: [3, 32, 320]
      - KeepKeys:
          keep_keys: [image, label, length]
  loader:
    shuffle: true
    batch_size_per_card: {batch}
    drop_last: true
    num_workers: 0

Eval:
  dataset:
    name: SimpleDataSet
    data_dir: {run_dir}
    label_file_list: [{label_file}]
    transforms:
      - DecodeImage:
          img_mode: BGR
          channel_first: False
      - CTCLabelEncode:
      - RecResizeImg:
          image_shape: [3, 32, 320]
      - KeepKeys:
          keep_keys: [image, label, length]
  loader:
    shuffle: false
    drop_last: false
    batch_size_per_card: {batch}
    num_workers: 0
"""
    yaml_path = run_dir / "rec_ph_plate.yml"
    yaml_path.write_text(yaml_content.strip(), encoding="utf-8")
    print(f"[PaddleOCR] YAML config written → {yaml_path}")

    print(f"[PaddleOCR] Starting fine-tune | epochs={epochs} batch={batch}")
    print("[PaddleOCR] Launching PaddleOCR training subprocess...")

    import subprocess
    cmd = [
        sys.executable, "-m", "paddle.distributed.launch",
        "--gpus", "0",
        "-m", "paddleocr.tools.train",
        "-c", str(yaml_path),
    ]
    # Fallback to single-GPU if distributed not available
    try:
        result = subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        print("[PaddleOCR] Distributed launch failed. Retrying in single-GPU mode...")
        cmd_single = [sys.executable, "-m", "paddleocr.tools.train", "-c", str(yaml_path)]
        subprocess.run(cmd_single, check=True)

    print(f"\n✓ PaddleOCR fine-tune complete.")
    print(f"  Best model saved to: {run_dir / 'output'}")
    print("  Next: run export_ocr.py to convert to inference model and deploy.")


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fine-tune OCR on Pop Quiz plate dataset")
    parser.add_argument("--engine", required=True, choices=["easyocr", "paddleocr"], help="OCR engine to train")
    parser.add_argument("--epochs", type=int, default=30, help="Number of training epochs (default: 30)")
    parser.add_argument("--batch",  type=int, default=8,  help="Batch size (default: 8)")
    args = parser.parse_args()

    print(f"\n{'='*60}")
    print(f"  HULI-KAMOTE  OCR Fine-Tuner")
    print(f"  Engine : {args.engine}")
    print(f"  Epochs : {args.epochs}")
    print(f"  Batch  : {args.batch}")
    print(f"{'='*60}\n")

    pairs, positives, negatives = validate_dataset()

    if args.engine == "easyocr":
        train_easyocr(positives, args.epochs, args.batch)
    else:
        train_paddleocr(positives, args.epochs, args.batch)
