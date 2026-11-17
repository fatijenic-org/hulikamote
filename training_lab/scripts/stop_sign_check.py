"""
stop_sign_check.py - does the stop sign reader (hulikamote_backend/engine/sign_reader.py) find a stop sign?

Two checks, nothing is written:
  1. Painted signs: the project's own stop sign picture (engine/overlay_objects.py) is painted on frames of a road
     video at several places and sizes; the reader must find it, and must find nothing on the same frames without it.
     This is a SYNTHETIC check (a drawn sign), good for "does the link work", not proof on real signs.
  2. Real pictures: every .jpg / .png in --photos <folder> (put held-out photos of real stop signs there, and a few
     road photos without one in --clean <folder>).

    python training_lab/scripts/stop_sign_check.py
    python training_lab/scripts/stop_sign_check.py --photos C:/stop_signs --clean C:/no_signs
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "hulikamote_backend"))

import torch  # noqa: E402,F401  (before onnxruntime on Windows)
import cv2  # noqa: E402

from engine import overlay_objects, sign_reader  # noqa: E402

SIZES = (0.6, 0.9, 1.2, 1.8, 2.5)                     # overlay scale: about 20 px to 90 px wide on a 1080p frame
PLACES = ((0.2, 0.45), (0.5, 0.5), (0.8, 0.45), (0.85, 0.7))


def frames_of(video: Path, count: int = 6):
    cap = cv2.VideoCapture(str(video))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    for i in range(count):
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(total * (i + 0.5) / count))
        ok, frame = cap.read()
        if ok:
            yield frame
    cap.release()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", default=str(REPO / "hulikamote_backend" / "test_video.mp4"))
    ap.add_argument("--photos", help="folder of held-out photos that each show a real stop sign")
    ap.add_argument("--clean", help="folder of road photos with no stop sign")
    args = ap.parse_args()
    if not sign_reader.available():
        raise SystemExit("No stock COCO detector found in hulikamote_backend/models (yolo11_primary.onnx / yolov8n.onnx).")

    frames = list(frames_of(Path(args.video)))
    false_alarms = sum(bool(sign_reader.find_stop_signs(f)) for f in frames)
    print(f"painted check on {len(frames)} frames of {Path(args.video).name}; frames with a false stop sign before painting: {false_alarms}")
    for size in SIZES:
        found = tried = 0
        widths = []
        for frame in frames:
            h, w = frame.shape[:2]
            for fx, fy in PLACES:
                painted = frame.copy()
                overlay_objects.draw_object(painted, (fx * w, fy * h), "stop_sign", {"scale": size}, True)
                changed = cv2.absdiff(painted, frame).max(axis=2) > 12
                if changed.any():
                    widths.append(int(changed.any(axis=0).sum()))
                tried += 1
                found += bool(sign_reader.find_stop_signs(painted))
        width = sorted(widths)[len(widths) // 2] if widths else 0
        print(f"  sign scale {size} (object about {width} px wide): found {found} of {tried}")

    for label, folder, want in (("real stop signs", args.photos, True), ("no stop sign", args.clean, False)):
        if not folder:
            continue
        files = [p for p in Path(folder).iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")]
        hits = sum(bool(sign_reader.find_stop_signs(cv2.imread(str(p)))) for p in files)
        print(f"{label}: sign found in {hits} of {len(files)} photos ({'recall' if want else 'false alarms'})")


if __name__ == "__main__":
    main()
