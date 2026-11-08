"""
find_road_lines.py - find the painted stop line, crosswalk and lane lines of a fixed-camera video, with no AI model.

    cd hulikamote_backend
    venv\\Scripts\\python.exe ..\\tools\\find_road_lines.py <video> [--out <folder>]

Needs a fixed camera (small hand-held shake is fine) and some traffic passing: the road direction is read from the movement of the
vehicles. Writes four files into the folder (default: road_lines_out next to where you run it):
    <video name>_lines.png        the empty road with everything it found drawn on it (look at this one first)
    <video name>_topdown.png      the same road seen from above, with the paint it picked out (green box = crosswalk, red = stop line)
    <video name>_background.png   the empty road alone (the traffic taken out)
    <video name>_lines.json       the same result as numbers, plus zone suggestions in the wizard's shape

Read-only for the project: it touches nothing else and does not need the backend to be running.
"""
import argparse
import json
import sys
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hulikamote_backend"))
from engine.road_lines import analyse_video, draw, zone_hints  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("--seconds", type=float, default=None, help="how much of the video to look at (default: as much as the time budget allows)")
    ap.add_argument("--out", default="road_lines_out")
    args = ap.parse_args()

    result, background = analyse_video(args.video, args.seconds, keep_top=True)
    topdown = result.pop("topdown", None)
    result["zone_hints"] = zone_hints(result)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    name = Path(args.video).stem
    cv2.imwrite(str(out / f"{name}_background.png"), background)
    cv2.imwrite(str(out / f"{name}_lines.png"), draw(background, result))
    if topdown is not None:
        cv2.imwrite(str(out / f"{name}_topdown.png"), topdown)
    (out / f"{name}_lines.json").write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"Looked at {result['seconds_used']} s of {args.video}")
    if not result["ok"]:
        print(f"  Could not read the road: {result['reason']}")
        return 1
    solid = [ln for ln in result["lane_lines"] if ln["style"] == "solid"]
    print(f"  crosswalks found:   {len(result['crosswalks'])}")
    print(f"  stop lines found:   {len(result['stop_lines'])}")
    print(f"  lane lines found:   {len(result['lane_lines'])} ({len(solid)} solid, {len(result['lane_lines']) - len(solid)} dashed)")
    print(f"Open {out / (name + '_lines.png')} and check the drawn lines against the real paint.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
