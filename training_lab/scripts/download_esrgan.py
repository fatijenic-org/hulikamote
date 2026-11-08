"""
download_esrgan.py — Download & ONNX-convert Real-ESRGAN x4 for plate upscaling.

This is Option A (Fast). Run this while training Option B (custom realesrgan).

Steps performed:
  1. Download RealESRGAN_x4plus.pth from official xinntao releases
  2. Clone Real-ESRGAN repo (temp, for model architecture class)
  3. Export to ONNX with fixed 320x80 plate input shape
  4. Deploy to hulikamote_backend/models/realesrgan.onnx

Usage:
    python training_lab/scripts/download_esrgan.py
"""

import subprocess
import sys
import os
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent / "hulikamote_backend"
MODELS_DIR = BACKEND_DIR / "models"
SCRIPT_DIR = Path(__file__).resolve().parent
TEMP_DIR = SCRIPT_DIR / "_esrgan_temp"

PTH_URL = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
PTH_PATH = TEMP_DIR / "RealESRGAN_x4plus.pth"
REPO_URL = "https://github.com/xinntao/Real-ESRGAN.git"
ONNX_OUT = MODELS_DIR / "realesrgan.onnx"

def run(cmd, cwd=None):
    print(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.stdout: print(result.stdout)
    if result.stderr: print(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result


def main():
    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    
    # 1. Install deps
    print("\n[1/4] Installing dependencies...")
    run([sys.executable, "-m", "pip", "install", "--quiet", "basicsr", "facexlib", "gfpgan", "realesrgan", "requests"])

    # 2. Download .pth weights
    print(f"\n[2/4] Downloading RealESRGAN_x4plus.pth...")
    import requests
    r = requests.get(PTH_URL, stream=True)
    r.raise_for_status()
    with open(PTH_PATH, "wb") as f:
        for chunk in r.iter_content(chunk_size=8192):
            f.write(chunk)
    print(f"    Saved to {PTH_PATH}")

    # 3. Export to ONNX
    print("\n[3/4] Exporting to ONNX (plate shape 3x80x320)...")
    export_script = TEMP_DIR / "export.py"
    export_script.write_text(f"""
import torch
import sys
from pathlib import Path

# Use RRDBNet from realesrgan package
from basicsr.archs.rrdbnet_arch import RRDBNet

model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=4)
state = torch.load(r"{PTH_PATH}", map_location="cpu")
key = "params_ema" if "params_ema" in state else "params" if "params" in state else None
model.load_state_dict(state[key] if key else state)
model.eval()

dummy = torch.randn(1, 3, 80, 320)   # typical plate crop (h=80, w=320)
out_path = r"{ONNX_OUT}"

torch.onnx.export(
    model, dummy, out_path,
    opset_version=11,
    input_names=["input"],
    output_names=["output"],
    dynamic_axes={{"input": {{2: "height", 3: "width"}}, "output": {{2: "height", 3: "width"}}}}
)
print(f"ONNX exported to {{out_path}}")
""")
    run([sys.executable, str(export_script)])

    # 4. Verify
    import onnxruntime as ort
    sess = ort.InferenceSession(str(ONNX_OUT))
    print(f"\n[4/4] Verification OK. Input: {sess.get_inputs()[0].shape}")
    print(f"\n✅ realesrgan.onnx deployed to {ONNX_OUT}")
    print("    Restart your FastAPI server to activate GAN enhancement.")


if __name__ == "__main__":
    main()
