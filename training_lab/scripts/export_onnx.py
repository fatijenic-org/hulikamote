"""
export_onnx.py — Convert a trained best.pt to best.onnx and deploy to the backend.

Usage:
    python scripts/export_onnx.py --model helmet_specialist
    python scripts/export_onnx.py --model plate_specialist --run train2

The script:
  1. Finds the best.pt from the latest training run.
  2. Exports it to ONNX format.
  3. Copies the .onnx file to hulikamote_backend/models/<model_name>.onnx
"""
import argparse
import shutil
from pathlib import Path
from ultralytics import YOLO

ROOT         = Path(__file__).parent.parent
REPO_ROOT    = ROOT.parent
BACKEND_MODELS = REPO_ROOT / "hulikamote_backend" / "models"

# Output filename mapping
MODEL_OUTPUT_NAMES = {
    "primary_anchor":    "yolov8n.onnx",
    "helmet_specialist": "helmet_specialist.onnx",
    "plate_specialist":  "plate_specialist.onnx",
    "cabin_specialist":  "cabin_specialist.onnx",
}


def latest_run(model_name: str) -> str:
    """Newest run folder that has weights (training makes train, train2, train3 ...)."""
    runs = [p.parent.parent for p in (ROOT / "runs" / model_name).glob("*/weights/best.pt")]
    if not runs:
        raise FileNotFoundError(f"No trained run with weights/best.pt under runs/{model_name}/")
    return max(runs, key=lambda p: (p / "weights" / "best.pt").stat().st_mtime).name


def export(model_name: str, run: str | None, deploy: bool = True):
    run = run or latest_run(model_name)
    weights_dir = ROOT / "runs" / model_name / run / "weights"
    best_pt = weights_dir / "best.pt"

    if not best_pt.exists():
        raise FileNotFoundError(
            f"best.pt not found at {best_pt}\n"
            f"Make sure training has completed for '{model_name}' with run '{run}'."
        )

    print(f"\n{'='*60}")
    print(f"  Exporting: {model_name}")
    print(f"  Source:    {best_pt}")
    print(f"{'='*60}\n")

    # Ensure PyTorch 2.6+ allows loading Ultralytics model checkpoints
    import torch
    orig_load = torch.load
    torch.load = lambda *a, **kw: orig_load(*a, **{**kw, 'weights_only': False})

    imgsz = 640 if model_name == "primary_anchor" else 320
    model = YOLO(str(best_pt))
    model.export(format="onnx", imgsz=imgsz, dynamic=False, simplify=True)

    exported_onnx = weights_dir / "best.onnx"
    if not exported_onnx.exists():
        raise RuntimeError("ONNX export failed — best.onnx not found after export.")
    if not deploy:
        print(f"\n✅ Exported (not deployed): {exported_onnx}\n")
        return

    # Deploy to backend with unique name
    from datetime import datetime
    import json
    
    date_str = datetime.now().strftime("%Y%m%d")
    unique_name = f"{model_name}_{run}_{date_str}.onnx"
    
    # Figure out category folder
    category_map = {
        "primary_anchor": "Vehicle Detectors",
        "helmet_specialist": "Helmet Detectors",
        "plate_specialist": "Plate Models",
        "cabin_specialist": "Cabin Models",
    }
    
    sub_dir = category_map.get(model_name, "Other Models")
    target_dir = BACKEND_MODELS / sub_dir
    target_dir.mkdir(parents=True, exist_ok=True)
    
    dest = target_dir / unique_name
    shutil.copy2(exported_onnx, dest)

    # Update manifest
    manifest_path = BACKEND_MODELS / "model_manifest.json"
    manifest = {}
    if manifest_path.exists():
        with open(manifest_path, "r") as f:
            manifest = json.load(f)
            
    if "active_models" not in manifest:
        manifest["active_models"] = {}
        
    manifest["active_models"][model_name] = f"{sub_dir}/{unique_name}"
    
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=4)

    print(f"\n✅ Exported and deployed:")
    print(f"   {exported_onnx}")
    print(f"→  {dest}")
    print(f"→  Updated model_manifest.json to point to {unique_name}\n")
    
    print("To publish this release to GitHub, run:")
    print(f"  set GITHUB_TOKEN=your_pat_here")
    print(f"  python scripts/publish_release.py --file \"{dest}\" --tag \"{model_name}_{run}\"")
    print("\nRestart the FastAPI backend to load the new active model.\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True,
                        choices=list(MODEL_OUTPUT_NAMES.keys()),
                        help="Which specialist model to export")
    parser.add_argument("--run", default=None,
                        help="Training run subfolder name (default: the newest run with weights)")
    parser.add_argument("--no-deploy", action="store_true", help="only convert to ONNX, do not deploy to the backend")
    args = parser.parse_args()

    export(args.model, args.run, deploy=not args.no_deploy)
