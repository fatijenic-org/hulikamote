"""
road_flow.py - which way traffic goes on each part of the road: "incoming" (toward the camera) or "outgoing" (away from it).

The road finder (engine/road_lines.py) already follows the moving points of the footage: each one is a position and a unit direction.
It also knows the top view of the road: far at the top, near at the bottom, the road running straight up. In that view a point that moves
DOWN comes toward the camera and one that moves UP goes away. Counting both across the width of the road gives the carriageways: bands of
the road where the traffic goes one way. A one-way street is one band; a road with traffic both ways is split where the direction changes.

What it says, and what it does not:
  - A band is where the traffic WENT during the footage, so the direction is the observed one. It is a proposal for the operator to
    check (the dashboard shows it with an arrow and lets the operator flip it), never a verdict.
  - Only one direction seen on a road that has two (the other side was empty for those seconds) looks like a one-way street:
    the state says so ("one_way_in" / "one_way_out") so the dashboard can warn.
  - It needs the road direction as a vanishing point. A road that runs parallel to the picture has no toward / away, so no bands.
Pure numbers in, plain dict out: no model, no picture.
"""
from __future__ import annotations

import cv2
import numpy as np

MIN_POINTS = 120          # moving points that moved along the road: fewer and no direction is claimed
BINS = 48                 # slices across the road
SIDE = 0.5                # a slice belongs to one direction when that direction has clearly more traffic: (a - b) / (a + b)
MIN_SHARE = 0.06          # a band needs this share of all the points ...
MIN_BAND_POINTS = 25      # ... and at least this many ...
MIN_WIDTH = 0.04          # ... and this share of the top view's width
ALONG = 0.55              # a point counts only when it moves mostly along the road (cosine of its angle to the road axis)
STEP = 10.0               # video pixels a point's direction is followed, to see which way it goes in the top view
PAD = 0.04                # the road is a little wider than the traffic on it (share of the top view's width), as in road_lines._regions
GAP = 3                   # slices without a clear direction inside one direction still belong to it


def _project(matrix: np.ndarray, points: np.ndarray) -> np.ndarray:
    return cv2.perspectiveTransform(np.asarray(points, np.float64).reshape(-1, 1, 2), matrix).reshape(-1, 2)


def _video(matrix: np.ndarray, points, size: tuple[float, float]) -> list[list[float]]:
    vw, vh = size
    return [[round(float(min(max(x, 0.0), vw - 1.0)), 1), round(float(min(max(y, 0.0), vh - 1.0)), 1)] for x, y in _project(matrix, np.array(points))]


def _nothing(reason: str) -> dict:
    return {"state": "none", "bands": [], "points": 0, "reason": reason}


def read_flow(result: dict, motion) -> dict:
    """{"state": "two_way" | "one_way_in" | "one_way_out" | "none", "bands": [...], "points": n, "reason": str | None}.
    A band: {"flow": "in" | "out", "polygon": four corners, "arrow": two points (the way the traffic goes), "points": n, "share": 0..1},
    in the video's pixels, left to right. `motion` = (moving points, their unit directions, width of the picture they are in), the
    finder's own `kept["motion"]`."""
    direction = result.get("road_direction") or {}
    if motion is None or not result.get("rectifier"):
        return _nothing("The road direction was not found, so the direction of the traffic is not read.")
    if direction.get("kind") != "vanishing point":
        return _nothing("The road runs across the picture, so toward and away from the camera cannot be told.")
    points, directions, grey_w = motion
    vw, vh = result["video_size"]
    tw, th = result["rectifier"]["top_size"]
    to_video = np.array(result["rectifier"]["top_to_video"], np.float64)
    try:
        to_top = np.linalg.inv(to_video)
    except np.linalg.LinAlgError:
        return _nothing("The top view of the road could not be used.")
    if len(points) < MIN_POINTS or not grey_w:
        return _nothing("Too little traffic was seen to read its direction.")

    start = np.asarray(points, np.float64) * (vw / float(grey_w))
    a = _project(to_top, start)
    move = _project(to_top, start + np.asarray(directions, np.float64) * STEP) - a
    length = np.hypot(move[:, 0], move[:, 1])
    with np.errstate(invalid="ignore"):
        keep = (np.isfinite(a).all(axis=1) & np.isfinite(move).all(axis=1) & (length > 1e-6) & (a[:, 0] >= 0) & (a[:, 0] < tw)
                & (a[:, 1] >= 0) & (a[:, 1] < th) & (np.abs(move[:, 1]) >= ALONG * length))
    n = int(keep.sum())
    if n < MIN_POINTS:
        return {**_nothing("Too little traffic moved along the road to read its direction."), "points": n}
    u, toward = a[keep, 0], move[keep, 1] > 0                   # down in the top view = coming toward the camera

    valid = cv2.warpPerspective(np.full((int(vh), int(vw)), 255, np.uint8), to_top, (int(tw), int(th)), flags=cv2.INTER_NEAREST)
    rows, cols = np.where(valid.any(axis=1))[0], np.where(valid.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return {**_nothing("The top view of the road is empty."), "points": n}
    v0, v1 = float(rows.min()), float(rows.max())
    pad = PAD * tw
    low, high = np.percentile(u, [3, 97])
    lo, hi = max(float(cols.min()), float(low) - pad), min(float(cols.max()), float(high) + pad)
    if hi - lo < MIN_WIDTH * tw:
        return {**_nothing("The traffic used too narrow a strip to split it into directions."), "points": n}

    edges = np.linspace(lo, hi, BINS + 1)
    inc = np.histogram(u[toward], bins=edges)[0].astype(float)
    out = np.histogram(u[~toward], bins=edges)[0].astype(float)
    kernel = np.array([1.0, 2.0, 1.0]) / 4.0
    inc_s, out_s = np.convolve(inc, kernel, mode="same"), np.convolve(out, kernel, mode="same")
    total = inc_s + out_s
    sure = total >= max(3.0, 0.004 * n)
    balance = np.where(total > 0, (inc_s - out_s) / np.maximum(total, 1e-9), 0.0)
    label = np.where(sure & (balance >= SIDE), 1, np.where(sure & (balance <= -SIDE), -1, 0))

    runs: list[list[int]] = []                                   # [direction, first slice, last slice]
    for i, lab in enumerate(label):
        if lab == 0:
            continue
        if runs and runs[-1][0] == lab and i - runs[-1][2] <= GAP:
            runs[-1][2] = i
        else:
            runs.append([int(lab), i, i])
    big = []
    for lab, first, last in runs:                                # small patches are noise, not a carriageway
        count = float(inc[first:last + 1].sum() + out[first:last + 1].sum())
        width = edges[last + 1] - edges[first]
        if count >= max(MIN_BAND_POINTS, MIN_SHARE * n) and width >= MIN_WIDTH * tw:
            big.append([lab, first, last])
    merged: list[list[int]] = []
    for run in big:
        if merged and merged[-1][0] == run[0]:                   # a small opposite patch between two like runs was dropped
            merged[-1][2] = run[2]
        else:
            merged.append(run)
    if not merged:
        return {**_nothing("The traffic does not keep to one direction anywhere clearly enough."), "points": n}

    bands = []
    for k, (lab, first, last) in enumerate(merged):
        u0 = lo if k == 0 else (edges[merged[k - 1][2] + 1] + edges[first]) / 2.0     # neighbours meet halfway between their traffic
        u1 = hi if k == len(merged) - 1 else (edges[last + 1] + edges[merged[k + 1][1]]) / 2.0
        centre = (u0 + u1) / 2.0
        far, near = v0 + 0.30 * (v1 - v0), v0 + 0.78 * (v1 - v0)
        way = [[centre, far], [centre, near]] if lab > 0 else [[centre, near], [centre, far]]
        count = float(inc[first:last + 1].sum() + out[first:last + 1].sum())
        bands.append({"flow": "in" if lab > 0 else "out",
                      "polygon": _video(to_video, [[u0, v0], [u1, v0], [u1, v1], [u0, v1]], (vw, vh)),
                      "arrow": _video(to_video, way, (vw, vh)), "points": int(count), "share": round(count / n, 2)})
    flows = {b["flow"] for b in bands}
    state = "two_way" if len(flows) == 2 else ("one_way_in" if "in" in flows else "one_way_out")
    return {"state": state, "bands": bands, "points": n, "reason": None}


def add_flow(result: dict, motion) -> None:
    """Put the traffic direction of each part of the road into the finder's result as result["flow"]. Never raises: the direction is a
    bonus, and the crosswalks and lines must not be lost over it."""
    try:
        result["flow"] = read_flow(result, motion)
    except Exception as exc:                                     # noqa: BLE001
        result["flow"] = _nothing("The direction of the traffic could not be read.")
        result["flow_error"] = str(exc)
