"""
class_flip_report.py - does a tracked vehicle keep its class, or does it flip (motorcycle <-> person, car <-> truck)?

Replays a clip that an analysis KEPT ("Keep the uploaded video") through the app's real detector + tracker and counts, per
track, how often the class changes. Read-only: it writes nothing into the project and does not touch the running backend.

    cd hulikamote_backend
    venv\\Scripts\\python.exe ..\\tools\\class_flip_report.py <first 8 characters of the analysis id> [frames] [deepsort|bytetrack]

Read the result:
    "tracks that are BOTH motorcycle and person"   must be 0 (a rider box must never take over a bike's track)
    "class changes inside tracks"                    fewer is better; what is left is mostly car <-> truck on vans / pickups
    "bike anchors where another class won"           how many motorcycle boxes the 'top class' step threw away (should be ~0)
"""
import sys
from collections import Counter, defaultdict
from pathlib import Path

import torch  # noqa: F401  (must be imported before onnxruntime on Windows, or torch's cuDNN fails to load)
import cv2
import numpy as np

BACKEND = Path(__file__).resolve().parents[1] / "hulikamote_backend"
sys.path.insert(0, str(BACKEND))
import yolo_inference as yi  # noqa: E402

STRIDE = 3                      # the pipeline looks at every 3rd frame of 30 fps video


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    task = sys.argv[1]
    n_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 250
    tracker = sys.argv[3] if len(sys.argv) > 3 else "deepsort"

    forensic = BACKEND / "snapshots" / "evidence" / "forensic"
    folder = next((p for p in forensic.iterdir() if p.name.startswith(task)), None)
    video = folder / "input_video.mp4" if folder else None
    if video is None or not video.exists():
        raise SystemExit(f"No kept video for analysis '{task}' (the wizard switch 'Keep the uploaded video' must have been on).")

    yolo = yi.get_inference(force_reload=True, tracker_type=tracker)
    moto, person = yolo._classes.index("motorcycle"), yolo._classes.index("person")
    cap = cv2.VideoCapture(str(video))
    print(f"clip {folder.name[:8]}  {int(cap.get(3))}x{int(cap.get(4))}  tracker {tracker}  frames looked at {n_frames}")

    tracks = defaultdict(list)                  # track id -> classes in time order
    bike_anchors = bike_lost = 0
    index = taken = 0
    while taken < n_frames:
        ok, frame = cap.read()
        if not ok:
            break
        if index % STRIDE == 0:
            blob, *_ = yolo.preprocess(frame)   # the raw scores, to see what the 'top class' step discards
            out = yolo._session.run(None, {yolo._input_name: blob})[0][0]
            scores = (out.T if out.shape[0] < out.shape[1] else out)[:, 4:]
            bike = scores[:, moto] >= yi.CLASS_CONFIDENCE.get("motorcycle", yi.CONFIDENCE_THRESHOLD)
            bike_anchors += int(bike.sum())
            bike_lost += int((bike & (scores.argmax(axis=1) != moto) & (scores.argmax(axis=1) != person)).sum())
            for d in yolo.infer(frame):
                if d.track_id != -1:
                    tracks[d.track_id].append(d.cls)
            taken += 1
        index += 1
    cap.release()

    changes = sum(1 for seq in tracks.values() for a, b in zip(seq, seq[1:]) if a != b)
    mixed = [t for t, seq in tracks.items() if {"motorcycle", "person"} <= set(seq)]
    print(f"\ntracks: {len(tracks)}")
    print(f"tracks that are BOTH motorcycle and person: {len(mixed)}   <- must be 0")
    print(f"class changes inside tracks: {changes}")
    print(f"bike anchors where another class won (not person): {bike_lost} of {bike_anchors}")
    worst = sorted(((sum(a != b for a, b in zip(s, s[1:])), t, Counter(s).most_common()) for t, s in tracks.items()), reverse=True)[:5]
    print("tracks that change class most (changes, id, classes):")
    for row in worst:
        if row[0]:
            print("  ", row)


if __name__ == "__main__":
    main()
