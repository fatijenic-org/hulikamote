"""
model_compare.py - what does each vehicle model actually see on a kept clip? Counts per class plus side-by-side pictures.

Replays frames of a clip that an analysis KEPT ("Keep the uploaded video") through the app's real detector, once per model.
Read-only: it writes only pictures into a temp folder and does not touch the running backend or the active model.

    cd hulikamote_backend
    venv\\Scripts\\python.exe ..\\tools\\model_compare.py <first 8 characters of the analysis id> [frames] [model.onnx ...]

With no model names it compares the LIVE vehicle model (models/active_model.txt) with every model in "Vehicle Detectors".
Use it to answer "does this model find the motorcycles on MY footage?" before pressing "Use this" in the Models hub, and after
retraining. The pictures show every box with its class and confidence (green = motorcycle, red = person).
"""
import sys
import tempfile
from collections import Counter
from pathlib import Path

import torch  # noqa: F401  (must be imported before onnxruntime on Windows, or torch's cuDNN fails to load)
import cv2
import numpy as np

BACKEND = Path(__file__).resolve().parents[1] / "hulikamote_backend"
sys.path.insert(0, str(BACKEND))
import yolo_inference as yi  # noqa: E402

COLOURS = {"person": (0, 0, 255), "motorcycle": (0, 220, 0), "tricycle": (255, 0, 255)}
SHOWN = ("car", "person", "motorcycle", "tricycle", "bus", "truck")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    task = sys.argv[1]
    n_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    names = sys.argv[3:] or [yi.MODEL_PATH.name] + sorted(p.name for p in (BACKEND / "models" / "Vehicle Detectors").glob("*.onnx")
                                                         if p.name != yi.MODEL_PATH.name)
    forensic = BACKEND / "snapshots" / "evidence" / "forensic"
    folder = next((p for p in forensic.iterdir() if p.name.startswith(task)), None)
    video = folder / "input_video.mp4" if folder else None
    if video is None or not video.exists():
        raise SystemExit(f"No kept video for analysis '{task}' (the wizard switch 'Keep the uploaded video' must have been on).")

    cap = cv2.VideoCapture(str(video))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frames = []
    for index in np.linspace(total * 0.05, total * 0.95, n_frames).astype(int):
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(index))
        ok, frame = cap.read()
        if ok:
            frames.append(frame)
    cap.release()

    out_dir = Path(tempfile.gettempdir()) / "hulikamote_model_compare" / folder.name[:8]
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"clip {folder.name[:8]}  {frames[0].shape[1]}x{frames[0].shape[0]}  {len(frames)} frames   (live model: {yi.MODEL_PATH.name})")
    print(f"{'model':42s}" + "".join(f"{c:>12s}" for c in SHOWN))
    panels = {k: [] for k in range(len(frames))}
    for name in names:
        yi.MODEL_PATH = next((BACKEND / "models").rglob(name))
        yi.VIOLATION_CLASS_NAMES = yi._load_classes_for_model(name)
        engine = yi.YoloInference(tracker_type="bytetrack")
        counts = Counter()
        for k, frame in enumerate(frames):
            dets = engine.infer(frame)
            counts.update(d.cls for d in dets)
            img, (h, w) = frame.copy(), frame.shape[:2]
            thick = max(2, w // 600)
            for d in dets:
                x, y, bw, bh = d.bbox
                colour = COLOURS.get(d.cls, (255, 160, 0))
                cv2.rectangle(img, (x, y), (x + bw, y + bh), colour, thick)
                cv2.putText(img, f"{d.cls} {d.confidence:.2f}", (x, max(20, y - 6)), cv2.FONT_HERSHEY_SIMPLEX, max(0.7, w / 1800), colour, thick)
            cv2.putText(img, name, (20, 60), cv2.FONT_HERSHEY_SIMPLEX, max(1.2, w / 1200), (255, 255, 255), thick + 2)
            panels[k].append(cv2.resize(img, (800, int(800 * h / w))))
        print(f"{name:42s}" + "".join(f"{counts[c]:12d}" for c in SHOWN))
    for k, row in panels.items():
        cv2.imwrite(str(out_dir / f"frame_{k:02d}.jpg"), np.hstack(row), [cv2.IMWRITE_JPEG_QUALITY, 82])
    print(f"pictures (one per frame, one panel per model): {out_dir}")


if __name__ == "__main__":
    main()
