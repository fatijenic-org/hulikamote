"""
download_model.py
-----------------
Downloads the official pre-trained YOLOv8n ONNX model directly from
Ultralytics GitHub releases — no PyTorch loading needed at all.

Run: venv/Scripts/python.exe scripts/download_model.py
"""
import urllib.request
from pathlib import Path

MODELS_DIR = Path(__file__).parent.parent / "models"
MODELS_DIR.mkdir(exist_ok=True)

ONNX_URL = (
    "https://github.com/ultralytics/assets/releases/download/v8.4.0/yolov8n.onnx"
)
DEST = MODELS_DIR / "yolov8n.onnx"


def _progress(block_num, block_size, total_size):
    downloaded = block_num * block_size
    pct = min(downloaded / total_size * 100, 100) if total_size > 0 else 0
    print(f"\r  {pct:.1f}%  ({downloaded // 1024} KB)", end="", flush=True)


if DEST.exists():
    print(f"Model already exists at {DEST} ({DEST.stat().st_size // 1024} KB)")
else:
    print(f"Downloading YOLOv8n ONNX from GitHub releases...")
    urllib.request.urlretrieve(ONNX_URL, DEST, reporthook=_progress)
    print(f"\nSaved to: {DEST} ({DEST.stat().st_size // 1024} KB)")

print("Done. Backend is ready to run ONNX inference.")
