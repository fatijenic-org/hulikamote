"""
export_ocr.py — Convert a fine-tuned OCR model to a deployable format and hot-swap it into the backend.

Usage:
    python training_lab/scripts/export_ocr.py --engine easyocr  --weights training_lab/runs/easyocr_finetune/best.pth
    python training_lab/scripts/export_ocr.py --engine paddleocr --weights training_lab/runs/paddleocr_finetune/output/best_accuracy
"""
import argparse
import shutil
import sys
from pathlib import Path

ROOT        = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT.parent / "hulikamote_backend"
MODELS_DIR  = BACKEND_DIR / "models"


def export_easyocr(weights_path: Path):
    if not weights_path.exists():
        print(f"[ERROR] Weights not found: {weights_path}")
        sys.exit(1)

    dest = MODELS_DIR / "easyocr_custom_rec.pth"
    shutil.copy2(weights_path, dest)
    print(f"✓ EasyOCR weights deployed → {dest}")
    print("  In the Forensic Analyzer, select 'EasyOCR (Standard)' — it will now use your fine-tuned model.")
    print("  Note: update `model_storage_directory` in _get_ocr_reader() to point to the models/ folder.")


def export_paddleocr(weights_path: Path):
    if not weights_path.exists():
        print(f"[ERROR] Weights path not found: {weights_path}")
        sys.exit(1)

    try:
        import subprocess
        # Step 1: Convert PaddlePaddle training model → inference model
        inference_dir = ROOT / "runs" / "paddleocr_finetune" / "inference"
        inference_dir.mkdir(parents=True, exist_ok=True)

        yaml_path = ROOT / "runs" / "paddleocr_finetune" / "rec_ph_plate.yml"
        cmd = [
            sys.executable, "-m", "paddleocr.tools.export_model",
            "-c", str(yaml_path),
            f"-o", f"Global.pretrained_model={weights_path}",
            f"Global.save_inference_dir={inference_dir}",
        ]
        subprocess.run(cmd, check=True)
        print(f"[PaddleOCR] Inference model saved → {inference_dir}")

        # Step 2: Copy to backend models dir
        dest = MODELS_DIR / "paddleocr_rec_inference"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(inference_dir, dest)
        print(f"✓ PaddleOCR inference model deployed → {dest}")
        print("  In the Forensic Analyzer, select 'PaddleOCR (Enterprise)' — it will now use your fine-tuned model.")

    except ImportError:
        print("[ERROR] PaddleOCR not installed. Run: pip install paddlepaddle paddleocr")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export and deploy a fine-tuned OCR model to the backend")
    parser.add_argument("--engine",  required=True, choices=["easyocr", "paddleocr"])
    parser.add_argument("--weights", required=True, help="Path to trained weights or model directory")
    args = parser.parse_args()

    weights = Path(args.weights).resolve()
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    if args.engine == "easyocr":
        export_easyocr(weights)
    else:
        export_paddleocr(weights)
