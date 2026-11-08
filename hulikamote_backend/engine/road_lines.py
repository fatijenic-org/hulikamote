"""
road_lines.py - find the painted stop line, crosswalk and lane lines of a fixed camera with classic image processing (no trained model).

The steps follow published traffic-camera work:
  1. One pass over the video (ffmpeg): a few dozen colour frames for the empty road, every frame at low resolution for motion.
  2. Small camera sway is removed (phase correlation); the empty road is the per-pixel median of the aligned frames, so moving
     vehicles vanish.
  3. Moving points are tracked (KLT). For vehicles every tracked point is a short line in the picture and all of them pass through one
     point, the vanishing point of the road direction. It is found by voting (RANSAC): Dubska, Herout, Sochor, Juranek, "Fully Automatic
     Roadside Camera Calibration for Traffic Surveillance" (IEEE T-ITS 2014) and "Automatic Camera Calibration for Traffic
     Understanding" (BMVC 2014).
  4. With that point the road is re-drawn as seen from above (inverse perspective mapping, camera assumed level): lane lines become
     parallel verticals and the stripes of a crosswalk become equal, evenly spaced vertical bars. A top view makes marking detection
     much simpler and keeps paint width constant (Gavrilovic et al., ISPRS 2010; Se 2000; lane-detection IPM + line-segment work).
  5. Paint is what is bright and thin in that view, kept only where traffic moved (a road region from motion, as in the activity-map
     lane papers). Crosswalks are rows of evenly spaced bars, stop lines are long thin horizontal lines, lane lines are long thin
     vertical lines; solid or dashed is told by the gaps along the line.
  6. Everything is mapped back to the video's own pixels.

Limits: needs a fixed camera and some traffic (a vehicle or two passing is not enough), faded paint, rain, glare and night footage
lower the result, the road is assumed flat, and a camera that rolls sideways is not handled. The answer is a proposal for the operator
to check, never a verdict.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
from pathlib import Path

import cv2
import numpy as np

WORK_W = 1280                    # width of the colour frames the empty road is built from
FLOW_W = 480                     # width of the grey frames used for alignment and motion
SAMPLE_FPS = 8                   # frames per second looked at (one eighth of a second between motion samples)
DECODE_BUDGET = 9e9              # source pixels the decoder may chew through (about 36 s of 4K at 30 fps)
TOP_W, TOP_H = 1200, 1200        # size of the top view
FAR_FRAC = 0.18                  # how far toward the horizon the top view reaches (share of the way from the bottom row)
PAINT_THRESHOLD = 13.0           # grey levels a thin bright thing must stand out from its surroundings to count as paint
MIN_SAMPLES = 150                # fewer moving points than this and the road direction is not trusted


def _no_window() -> int:
    return subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0


def _even(x: float) -> int:
    return max(int(round(x / 2.0)) * 2, 2)


# ───────────────────────────── reading the video ─────────────────────────────

def _probe(path: str | Path) -> tuple[int, int, float, float]:
    exe = shutil.which("ffprobe")
    if not exe:
        raise ValueError("ffmpeg is needed to read the video but was not found")
    out = subprocess.run([exe, "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height,r_frame_rate,duration:format=duration", "-of", "json", str(path)],
                         capture_output=True, text=True, creationflags=_no_window())
    try:
        info = json.loads(out.stdout)
        stream = info["streams"][0]
        width, height = int(stream["width"]), int(stream["height"])
    except (ValueError, KeyError, IndexError):
        raise ValueError("cannot read that video")
    num, _, den = str(stream.get("r_frame_rate", "30/1")).partition("/")
    try:
        fps = float(num) / float(den or 1)
    except (ValueError, ZeroDivisionError):
        fps = 30.0
    if not (0.0 < fps <= 240.0):
        fps = 30.0
    seconds = 0.0
    for value in (stream.get("duration"), info.get("format", {}).get("duration")):
        try:
            seconds = float(value)
            break
        except (TypeError, ValueError):
            continue
    return width, height, fps, seconds


def _read_video(path: str | Path, max_seconds: float | None, bg_count: int = 30) -> dict:
    """Colour frames spread over the clip and every sampled frame as a small grey picture."""
    width, height, fps, seconds = _probe(path)
    if max_seconds is None:
        max_seconds = max(8.0, min(90.0, DECODE_BUDGET / (width * height * fps)))
    used = min(seconds, max_seconds) if seconds > 0 else max_seconds
    cw, ch = WORK_W, _even(height * WORK_W / width)
    gw, gh = FLOW_W, _even(height * FLOW_W / width)
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise ValueError("ffmpeg is needed to read the video but was not found")
    cmd = [ffmpeg, "-v", "error", "-nostdin", "-t", f"{used:.2f}", "-i", str(path), "-an", "-sn",
           "-vf", f"fps={SAMPLE_FPS},scale={cw}:{ch}", "-f", "rawvideo", "-pix_fmt", "bgr24", "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=_no_window())
    size = cw * ch * 3
    keep_every = max(int(used * SAMPLE_FPS) // bg_count, 1)
    colours, colour_at, greys = [], [], []
    try:
        while True:
            buf = proc.stdout.read(size)
            if len(buf) < size:
                break
            frame = np.frombuffer(buf, np.uint8).reshape(ch, cw, 3)
            if len(greys) % keep_every == 0 and len(colours) < bg_count:
                colours.append(frame.copy())
                colour_at.append(len(greys))
            greys.append(cv2.cvtColor(cv2.resize(frame, (gw, gh), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY))
    finally:
        proc.stdout.close()
        proc.wait()
    if len(greys) < 16:
        raise ValueError("the video is too short or could not be read (need at least 2 seconds)")
    return {"video": (width, height), "fps": fps, "seconds": len(greys) / SAMPLE_FPS, "colours": colours, "colour_at": colour_at,
            "greys": greys, "colour_size": (cw, ch), "grey_size": (gw, gh)}


# ───────────────────────────── alignment and motion ─────────────────────────────

def _translate(img: np.ndarray, dx: float, dy: float) -> np.ndarray:
    h, w = img.shape[:2]
    return cv2.warpAffine(img, np.float32([[1, 0, -dx], [0, 1, -dy]]), (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)


def _stabilise(greys: list[np.ndarray]) -> tuple[list[np.ndarray], float, float]:
    """A matrix per frame that undoes camera shake (hand-held footage): features are matched to a middle frame and the matches most
    of the picture agrees on are kept (RANSAC), so moving vehicles do not pull the result. Returns (matrices, how far the picture
    corners move in a typical bad moment (90th percentile, grey-picture pixels), share of frames that could not be matched)."""
    h, w = greys[0].shape
    orb = cv2.ORB_create(1500, fastThreshold=8)
    ref = greys[len(greys) // 2]
    ref_keys, ref_desc = orb.detectAndCompute(ref, None)
    matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
    corners = np.float32([[0, 0], [w, 0], [w, h], [0, h]]).reshape(-1, 1, 2)
    mats, moves, failed = [], [], 0
    for g in greys:
        mat = np.eye(3)
        found = False
        if ref_desc is not None:
            keys, desc = orb.detectAndCompute(g, None)
            if desc is not None and len(keys) >= 30:
                matches = sorted(matcher.match(desc, ref_desc), key=lambda m: m.distance)[:400]
                if len(matches) >= 30:
                    src = np.float32([keys[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
                    dst = np.float32([ref_keys[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
                    cand, inliers = cv2.findHomography(src, dst, cv2.RANSAC, 2.5)
                    if cand is not None and int(inliers.sum()) >= 25:
                        shift = cv2.perspectiveTransform(corners, cand).reshape(-1, 2) - corners.reshape(-1, 2)
                        if np.hypot(shift[:, 0], shift[:, 1]).max() < 0.4 * w:        # a believable correction
                            mat, found = cand, True
        failed += 0 if found else 1
        mats.append(mat)
        moved = cv2.perspectiveTransform(corners, mat).reshape(-1, 2) - corners.reshape(-1, 2)
        moves.append(float(np.hypot(moved[:, 0], moved[:, 1]).mean()))
    return mats, float(np.percentile(moves, 90)), failed / len(greys)


def _motion(greys: list[np.ndarray], mats: list[np.ndarray]) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Moving points as lines (position, unit direction), where things moved (a 0/255 road region) and the empty road as a grey picture,
    all in grey-picture pixels."""
    h, w = greys[0].shape
    aligned = [cv2.warpPerspective(g, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE) for g, m in zip(greys, mats)]
    background = np.median(np.stack(aligned[:: max(len(aligned) // 60, 1)]), axis=0).astype(np.uint8)
    level = float(np.median(background))
    aligned = [cv2.convertScaleAbs(a, alpha=min(max(level / max(float(np.median(a)), 1.0), 0.7), 1.4)) for a in aligned]   # auto-exposure drift
    seen = np.zeros((h, w), np.uint16)
    points, directions = [], []
    k3, k7 = np.ones((3, 3), np.uint8), np.ones((7, 7), np.uint8)
    min_blob = 0.0012 * w * h                                          # a vehicle, not a leaf or a pedestrian's shadow
    for i in range(len(aligned) - 1):
        a, b = aligned[i], aligned[i + 1]
        moving = (cv2.absdiff(a, background) > 25).astype(np.uint8)
        moving = cv2.morphologyEx(moving, cv2.MORPH_OPEN, k3)
        count, labels, stats, _c = cv2.connectedComponentsWithStats(moving, connectivity=8)
        big = np.isin(labels, [j for j in range(1, count) if stats[j, cv2.CC_STAT_AREA] >= min_blob])
        seen += big.astype(np.uint16)
        if i % 2:
            continue
        p0 = cv2.goodFeaturesToTrack(a, 250, 0.01, 5, mask=cv2.dilate(moving, k7))
        if p0 is None or len(p0) < 5:
            continue
        p1, status, _err = cv2.calcOpticalFlowPyrLK(a, b, p0, None, winSize=(15, 15), maxLevel=2)
        ok = status[:, 0] == 1
        d = (p1 - p0)[ok][:, 0, :]
        p = p0[ok][:, 0, :]
        m = np.hypot(d[:, 0], d[:, 1])
        keep = (m >= 1.2) & (m <= 60.0)
        points.append(p[keep])
        directions.append(d[keep] / m[keep, None])
    road = (seen >= 2).astype(np.uint8) * 255
    road = cv2.dilate(road, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(w * 0.03) | 1,) * 2))
    road = cv2.morphologyEx(road, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(w * 0.08) | 1,) * 2))
    P = np.vstack(points).astype(np.float32) if points else np.zeros((0, 2), np.float32)
    D = np.vstack(directions).astype(np.float32) if directions else np.zeros((0, 2), np.float32)
    return P, D, road, background


# ───────────────────────────── road direction ─────────────────────────────

def _straight_edges(grey: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Long straight edges of the empty road (curbs, building lines, markings) as (midpoint, unit direction, weight). Along a street they
    all point at the same vanishing point as the traffic does, and near the camera they are far better spread than distant vehicles."""
    h, w = grey.shape
    found = cv2.createLineSegmentDetector(cv2.LSD_REFINE_STD).detect(grey)[0]
    if found is None:
        return np.zeros((0, 2), np.float32), np.zeros((0, 2), np.float32), np.zeros(0, np.float32)
    seg = found[:, 0, :].astype(np.float32)
    d = seg[:, 2:4] - seg[:, 0:2]
    length = np.hypot(d[:, 0], d[:, 1])
    unit = d / np.maximum(length, 1e-6)[:, None]
    from_horizontal = np.degrees(np.arctan2(np.abs(unit[:, 1]), np.abs(unit[:, 0])))
    keep = (length >= 0.06 * w) & (from_horizontal < 70.0)             # not the verticals of poles and building corners
    mid = (seg[:, 0:2] + seg[:, 2:4]) / 2.0
    return mid[keep], unit[keep], np.clip(length[keep] / (0.06 * w), 1.0, 6.0)


def _vote_vanishing_point(P: np.ndarray, D: np.ndarray, weight: np.ndarray, pool: np.ndarray, min_dist: float, rng: np.random.Generator,
                          iters: int = 2000) -> tuple[np.ndarray | None, float]:
    """Best point by weighted votes; candidate points come from pairs of lines drawn out of `pool` (indexes)."""
    i, j = rng.choice(pool, iters), rng.choice(pool, iters)
    di, dj = D[i], D[j]
    cross = di[:, 0] * dj[:, 1] - di[:, 1] * dj[:, 0]
    ok = np.abs(cross) > math.sin(math.radians(5))
    i, j, di, dj, cross = i[ok], j[ok], di[ok], dj[ok], cross[ok]
    if not len(i):
        return None, 0
    dp = P[j] - P[i]
    t = (dp[:, 0] * dj[:, 1] - dp[:, 1] * dj[:, 0]) / cross
    cand = P[i] + t[:, None] * di
    tol = math.sin(math.radians(2.0))
    best_count, best = 0.0, None
    for s in range(0, len(cand), 150):
        c = cand[s:s + 150]
        v = c[:, None, :] - P[None, :, :]
        dist = np.hypot(v[..., 0], v[..., 1]) + 1e-9
        sin = np.abs(v[..., 0] * D[None, :, 1] - v[..., 1] * D[None, :, 0]) / dist
        count = ((sin < tol) & (dist > min_dist)).astype(np.float32) @ weight
        k = int(count.argmax())
        if count[k] > best_count:
            best_count, best = float(count[k]), c[k]
    return best, best_count


def _refine_vanishing_point(vp: np.ndarray, P: np.ndarray, D: np.ndarray, weight: np.ndarray, min_dist: float) -> np.ndarray:
    for _ in range(3):
        v = vp[None, :] - P
        dist = np.hypot(v[:, 0], v[:, 1]) + 1e-9
        inl = (np.abs(v[:, 0] * D[:, 1] - v[:, 1] * D[:, 0]) / dist < math.sin(math.radians(2.5))) & (dist > min_dist)
        if inl.sum() < 20:
            break
        nrm = np.stack([-D[inl, 1], D[inl, 0]], 1).astype(np.float64)
        wgt = weight[inl].astype(np.float64)[:, None]
        a = (nrm * wgt).T @ nrm
        b = (nrm * wgt * (nrm * P[inl]).sum(1, keepdims=True)).sum(0)
        try:
            vp = np.linalg.solve(a, b)
        except np.linalg.LinAlgError:
            break
    return vp


def _road_direction(P: np.ndarray, D: np.ndarray, size: tuple[int, int], edges: tuple[np.ndarray, np.ndarray, np.ndarray] | None = None) -> dict | None:
    """The vanishing point of the road direction ("finite"), or only its direction when the lines are nearly parallel.
    Votes come from the moving points (weight 1 each) and from the long straight edges of the empty road (weight 1 to 6 each, times 8)."""
    n = len(P)
    if n < MIN_SAMPLES:
        return None
    rng = np.random.default_rng(7)
    sub = rng.choice(n, min(n, 6000), replace=False)
    min_dist = 0.04 * size[0]
    Pm, Dm = P[sub], D[sub]
    if edges is not None and len(edges[0]) >= 8:
        Pe, De, We = edges
        Pv, Dv = np.vstack([Pm, Pe]), np.vstack([Dm, De])
        weight = np.concatenate([np.ones(len(Pm), np.float32), 8.0 * We])
        pool_all = np.arange(len(Pv))
        pool_edges = np.arange(len(Pm), len(Pv))
    else:
        Pv, Dv, weight = Pm, Dm, np.ones(len(Pm), np.float32)
        pool_all = pool_edges = np.arange(len(Pm))
    vp_a, votes_a = _vote_vanishing_point(Pv, Dv, weight, pool_all, min_dist, rng, 1500)
    vp_b, votes_b = _vote_vanishing_point(Pv, Dv, weight, pool_edges, min_dist, rng, 700)
    vp = vp_a if votes_a >= votes_b else vp_b
    finite_count = 0
    if vp is not None:
        vp = _refine_vanishing_point(vp.astype(np.float64), Pv, Dv, weight, min_dist)
        v = vp[None, :] - P                                           # support counted on the moving points only
        dist = np.hypot(v[:, 0], v[:, 1]) + 1e-9
        finite_count = int(((np.abs(v[:, 0] * D[:, 1] - v[:, 1] * D[:, 0]) / dist < math.sin(math.radians(2.5))) & (dist > min_dist)).sum())
    angles = np.degrees(np.arctan2(D[:, 1], D[:, 0])) % 180.0
    hist = np.bincount((angles // 3).astype(int) % 60, minlength=60)
    centre = (int(hist.argmax()) * 3 + 1.5)
    gap = np.minimum(np.abs(angles - centre), 180.0 - np.abs(angles - centre))
    near = gap < 2.5                                                  # the same tolerance the vanishing point is held to
    theta = float(np.degrees(np.arctan2(D[near, 1].sum(), D[near, 0].sum())) % 180.0) if near.any() else centre
    parallel_count = int(near.sum())
    # by chance any point is "voted for" by about 2% of random directions, so a real road direction needs clearly more than that
    if vp is not None and finite_count >= max(100, 0.06 * n) and finite_count >= 0.95 * parallel_count:     # a far point also explains parallel lines
        return {"kind": "finite", "vp": vp, "angle": None, "inliers": finite_count, "lines": n}
    if parallel_count >= max(120, 0.20 * n):
        return {"kind": "parallel", "vp": None, "angle": theta, "inliers": parallel_count, "lines": n}
    return {"kind": None, "inliers": max(finite_count, parallel_count), "lines": n}


# ───────────────────────────── the top view ─────────────────────────────

def _top_homography(info: dict, size: tuple[int, int]) -> np.ndarray:
    """3x3 matrix from the colour-frame picture to the top view (far at the top, near at the bottom, road direction vertical)."""
    w, h = size
    if info["kind"] == "finite":
        vx, vy = float(info["vp"][0]), float(info["vp"][1])
        yb = h - 1.0
        if vy < yb - 0.12 * h:                                       # a sensible horizon: well above the bottom row
            f = float(w)                                             # focal length guess: one picture width
            y_far = max(vy + FAR_FRAC * (yb - vy), 0.08 * h)
            xmin, xmax = (0 - vx) / (yb - vy), (w - vx) / (yb - vy)
            znear, zfar = f / (yb - vy), f / (y_far - vy)
            a, b = TOP_W / (xmax - xmin), TOP_H / (zfar - znear)
            return np.array([[a, -a * xmin, -a * vx + a * xmin * vy],
                             [0, b * zfar, -b * zfar * vy - b * f],
                             [0, 1, -vy]], np.float64)
        theta = math.degrees(math.atan2(yb - vy, w / 2.0 - vx)) % 180.0     # an unreliable horizon: use the direction only
    else:
        theta = float(info["angle"])
    phi = math.radians(90.0 - theta)                                  # rotate so that the road direction becomes vertical
    rot = np.array([[math.cos(phi), -math.sin(phi)], [math.sin(phi), math.cos(phi)]])
    corners = (np.array([[0, 0], [w, 0], [w, h], [0, h]], float) - [w / 2.0, h / 2.0]) @ rot.T
    lo, hi = corners.min(0), corners.max(0)
    scale = min(TOP_W / (hi[0] - lo[0]), TOP_H / (hi[1] - lo[1]))
    m = np.eye(3)
    m[:2, :2] = rot * scale
    m[:2, 2] = -(np.array([w / 2.0, h / 2.0]) @ rot.T + lo) * scale + [(TOP_W - (hi[0] - lo[0]) * scale) / 2.0, (TOP_H - (hi[1] - lo[1]) * scale) / 2.0]
    return m


def _warp(img: np.ndarray, homography: np.ndarray, interp: int = cv2.INTER_LINEAR) -> np.ndarray:
    return cv2.warpPerspective(img, homography, (TOP_W, TOP_H), flags=interp)


# ───────────────────────────── finding the marks in the top view ─────────────────────────────

def _runs(flags: np.ndarray) -> list[tuple[int, int]]:
    out, start = [], None
    for i, v in enumerate(flags):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, len(flags) - 1))
    return out


def _paint(top: np.ndarray, road: np.ndarray, valid: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """(white paint, yellow paint, loose white, warm-coloured pixels, contrast) in the top view: the three masks are 0/255, thin and bright,
    kept only where traffic moved. The loose mask also holds faint paint and is only used to extend a crosswalk that is already certain."""
    hsv = cv2.cvtColor(top, cv2.COLOR_BGR2HSV)
    grey = cv2.GaussianBlur(cv2.cvtColor(top, cv2.COLOR_BGR2GRAY).astype(np.float32), (0, 0), 1.2)
    k = int(TOP_W * 0.075) | 1
    tophat = cv2.morphologyEx(grey, cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    inside = (cv2.erode(valid, np.ones((9, 9), np.uint8)) > 0) & (road > 0)
    local = cv2.GaussianBlur(grey, (0, 0), TOP_W * 0.08)              # how bright the surroundings are (shade needs less contrast)
    weak = (tophat > np.maximum(PAINT_THRESHOLD - 3.0, 0.07 * local)) & inside
    strong = (tophat > np.maximum(PAINT_THRESHOLD + 5.0, 0.12 * local)) & inside
    count, labels = cv2.connectedComponents(weak.astype(np.uint8), connectivity=8)
    paint = np.isin(labels, np.unique(labels[strong])) & weak & (labels > 0)   # a faint region only counts if part of it clearly stands out
    white = paint & (hsv[..., 1] < 80)
    yellow = paint & (hsv[..., 0] >= 12) & (hsv[..., 0] <= 38) & (hsv[..., 1] >= 70) & (hsv[..., 2] >= 80)
    loose = (tophat > np.maximum(PAINT_THRESHOLD - 5.0, 0.045 * local)) & inside & (hsv[..., 1] < 90)
    o = np.ones((3, 3), np.uint8)
    return (cv2.morphologyEx(white.astype(np.uint8) * 255, cv2.MORPH_OPEN, o),
            cv2.morphologyEx(yellow.astype(np.uint8) * 255, cv2.MORPH_OPEN, o),
            cv2.morphologyEx(loose.astype(np.uint8) * 255, cv2.MORPH_OPEN, o),
            ((((hsv[..., 0] <= 25) | (hsv[..., 0] >= 165)) & (hsv[..., 1] >= 55)).astype(np.float32)), tophat)


def _crosswalks(white: np.ndarray, road: np.ndarray, loose: np.ndarray, warm: np.ndarray) -> list[dict]:
    """Rows of evenly spaced vertical bars in the top view."""
    h, w = white.shape
    win = int(h * 0.10)
    step = max(win // 4, 1)
    hits = []
    for v in range(0, h - win, step):
        cov = (white[v:v + win] > 0).mean(0).astype(np.float32)
        cov = cv2.blur(cov.reshape(1, -1), (7, 1))[0]
        bars = [(a, b) for a, b in _runs(cov >= 0.5) if 0.006 * w <= (b - a + 1) <= 0.13 * w]
        best: list[tuple[int, int]] = []
        for s in range(len(bars)):
            chain = [bars[s]]
            for k in range(s + 1, len(bars)):
                gap = bars[k][0] - chain[-1][1] - 1
                widths = [b - a + 1 for a, b in chain + [bars[k]]]
                gaps = [chain[i + 1][0] - chain[i][1] - 1 for i in range(len(chain) - 1)] + [gap]
                if max(widths) / min(widths) > 3.2 or max(gaps) / max(min(gaps), 1) > 5.0 or gap > 5 * max(widths):
                    break
                chain.append(bars[k])
            if len(chain) > len(best):
                best = chain
        if len(best) < 4:
            continue
        bar_cov = float(np.mean([cov[a:b + 1].mean() for a, b in best]))
        gap_cov = float(np.mean([cov[best[i][1] + 1:best[i + 1][0]].mean() for i in range(len(best) - 1) if best[i + 1][0] > best[i][1] + 1] or [0.0]))
        starts = np.array([a for a, _b in best], float)
        spacing = np.diff(starts)
        if bar_cov >= 0.62 and gap_cov <= 0.25 and spacing.std() / spacing.mean() <= 0.4:
            hits.append({"v": v, "chain": best, "stripes": len(best), "bar_cov": bar_cov})
    groups, cur = [], []
    for hit in hits:                                                  # windows that overlap vertically belong to one crosswalk
        if cur and hit["v"] - cur[-1]["v"] > win:
            groups.append(cur)
            cur = []
        cur.append(hit)
    if cur:
        groups.append(cur)
    out = []
    for g in groups:
        best = max(g, key=lambda d: (d["stripes"], d["bar_cov"]))
        cols = np.zeros(w, bool)
        for a, b in best["chain"]:
            cols[a:b + 1] = True
        v0, v1 = g[0]["v"], g[-1]["v"] + win
        rowcov = np.convolve((white[:, cols] > 0).mean(1), np.ones(9) / 9, "same")
        rows = np.flatnonzero(rowcov[v0:v1] >= 0.45)
        if len(rows) < 8:
            continue
        top, bottom = v0 + int(rows[0]), v0 + int(rows[-1])
        chain = list(best["chain"])
        period = float(np.median(np.diff([a for a, _b in chain])))
        width = float(np.median([b - a + 1 for a, b in chain]))
        loose_cov = (loose[top:bottom + 1] > 0).mean(0)
        for step in (1, -1):                                          # faint stripes of the same crosswalk, one period further out
            pos = chain[-1][0] if step > 0 else chain[0][0]
            misses = 0
            while misses < 2:                                         # one missing stripe is forgiven, two end the row
                pos += step * period
                a, b = int(round(pos)), int(round(pos + width - 1))
                if a < 0 or b >= w:
                    break
                if loose_cov[a:b + 1].mean() >= 0.45:
                    chain = chain + [(a, b)] if step > 0 else [(a, b)] + chain
                    misses = 0
                else:
                    misses += 1
        u0, u1 = chain[0][0], chain[-1][1]
        if (road[top:bottom + 1, u0:u1 + 1] > 0).mean() < 0.5:        # a crosswalk is on the road, not on the pavement
            continue
        if warm[top:bottom + 1, u0:u1 + 1].mean() > 0.35:             # grey road and white paint; pavement tiles and brick are reddish
            continue
        if len(chain) < 5 and (u1 - u0) < 0.25 * w:                   # four stripes on a short strip are more likely tiles or railings
            continue
        out.append({"u0": u0, "u1": u1, "v0": top, "v1": bottom, "stripes": len(chain), "score": round(best["bar_cov"], 2)})
    return out


def _stop_lines(white: np.ndarray, road: np.ndarray, contrast: np.ndarray, crosswalks: list[dict]) -> list[dict]:
    """Long, thin, solid horizontal lines in the top view."""
    h, w = white.shape
    opened = cv2.morphologyEx(white, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (int(w * 0.14), 1)))
    opened = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (1, 5)))
    near = cv2.dilate(white, np.ones((5, 5), np.uint8))
    n, labels, stats, _c = cv2.connectedComponentsWithStats(opened, connectivity=8)
    out = []
    for i in range(1, n):
        x, y, bw, bh = (int(s) for s in stats[i, :4])
        if bw < w * 0.25 or bh < h * 0.012 or bh > h * 0.06:           # long, and as thick as paint (a crack is a hair)
            continue
        ys, xs = np.nonzero(labels[y:y + bh, x:x + bw] == i)
        if len(xs) < 30:
            continue
        vx, vy, x0, y0 = cv2.fitLine(np.stack([xs + x, ys + y], 1).astype(np.float32), cv2.DIST_L2, 0, 0.01, 0.01).ravel()
        tilt = abs(math.degrees(math.atan2(vy, vx)))
        if min(tilt, 180.0 - tilt) > 8.0 or abs(vx) < 1e-6:
            continue
        ya, yb = float(y0 + (x - x0) * vy / vx), float(y0 + (x + bw - x0) * vy / vx)
        xs_line = np.linspace(x, x + bw, bw).round().astype(int).clip(0, w - 1)
        ys_line = np.linspace(ya, yb, bw).round().astype(int).clip(0, h - 1)
        if (near[ys_line, xs_line] > 0).mean() < 0.9 or (road[ys_line, xs_line] > 0).mean() < 0.7:     # solid and on the road
            continue
        above, below = (ys_line - int(0.04 * h)).clip(0, h - 1), (ys_line + int(0.04 * h)).clip(0, h - 1)
        if ((road[above, xs_line] > 0) & (road[below, xs_line] > 0)).mean() < 0.75 or contrast[ys_line, xs_line].mean() < 22.0:
            continue                                                  # road on both sides of it, and clearly brighter than the road
        mid = (ya + yb) / 2.0
        if any(c["u0"] - 0.03 * w <= x + bw / 2 <= c["u1"] + 0.03 * w and c["v0"] - 0.02 * h <= mid <= c["v1"] + 0.02 * h for c in crosswalks):
            continue                                                  # the bars of a crosswalk, not a line
        out.append({"u0": float(x), "v0": ya, "u1": float(x + bw), "v1": yb, "length": bw})
    return sorted(out, key=lambda ln: -ln["length"])[:3]


def _lane_lines(white: np.ndarray, yellow: np.ndarray, road: np.ndarray) -> list[dict]:
    """Long, thin, vertical lines in the top view, told solid or dashed by the gaps along them."""
    h, w = white.shape
    both = cv2.bitwise_or(white, yellow)
    near = cv2.dilate(both, np.ones((5, 5), np.uint8))
    opened = cv2.morphologyEx(both, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (1, int(h * 0.03))))
    n, labels, stats, _c = cv2.connectedComponentsWithStats(opened, connectivity=8)
    pieces = []
    for i in range(1, n):
        x, y, bw, bh = (int(s) for s in stats[i, :4])
        if bh < h * 0.04 or bw > w * 0.05:                               # a dash of a dashed line is short; the line as a whole is checked below
            continue
        ys, xs = np.nonzero(labels[y:y + bh, x:x + bw] == i)
        if len(xs) < 30 or len(xs) / max(bh, 1) < 4.0:                 # as thick as paint, not a hairline
            continue
        vx, vy, x0, y0 = cv2.fitLine(np.stack([xs + x, ys + y], 1).astype(np.float32), cv2.DIST_L2, 0, 0.01, 0.01).ravel()
        if abs(vy) < 1e-6 or math.degrees(math.atan2(abs(vx), abs(vy))) > 6.0:      # lines along the road are exactly vertical here; poles lean
            continue
        pieces.append((float(x0 + (y - y0) * vx / vy), float(y), float(x0 + (y + bh - y0) * vx / vy), float(y + bh)))
    pieces.sort(key=lambda p: p[0])
    columns: list[list[tuple]] = []
    for p in pieces:                                                  # dashes of one line share a column
        for col in columns:
            if abs(np.mean([q[0] for q in col]) - p[0]) < w * 0.012:
                col.append(p)
                break
        else:
            columns.append([p])
    out = []
    for col in columns:
        ya, yb = min(p[1] for p in col), max(p[3] for p in col)
        if yb - ya < h * 0.18:
            continue
        xa = float(np.mean([p[0] + (ya - p[1]) * (p[2] - p[0]) / (p[3] - p[1] + 1e-9) for p in col]))
        xb = float(np.mean([p[0] + (yb - p[1]) * (p[2] - p[0]) / (p[3] - p[1] + 1e-9) for p in col]))
        count = max(int(yb - ya), 2)
        xs = np.linspace(xa, xb, count).round().astype(int).clip(0, w - 1)
        ys = np.linspace(ya, yb, count).round().astype(int).clip(0, h - 1)
        hit = near[ys, xs] > 0
        coverage = float(hit.mean())
        stretches = int(np.count_nonzero(hit[1:] & ~hit[:-1])) + int(hit[0])
        style = "solid" if coverage >= 0.85 else ("dashed" if coverage >= 0.25 and stretches >= 3 else None)
        if style is None or (road[ys, xs] > 0).mean() < 0.6:           # and on the road
            continue
        side = int(0.04 * w)
        if ((road[ys, (xs - side).clip(0, w - 1)] > 0) & (road[ys, (xs + side).clip(0, w - 1)] > 0)).mean() < 0.75:
            continue                                                  # a lane or centre line has road on both sides, a curb or wall base does not
        yellow_share = float((yellow[ys, xs] > 0).sum() / max(int(hit.sum()), 1))
        out.append({"u0": xa, "v0": ya, "u1": xb, "v1": yb, "style": style, "colour": "yellow" if yellow_share >= 0.5 else "white",
                    "coverage": round(coverage, 2)})
    return out


# ───────────────────────────── the whole thing ─────────────────────────────

def _to_video(matrix: np.ndarray, points: list[list[float]]) -> list[list[float]]:
    out = cv2.perspectiveTransform(np.float32(points).reshape(-1, 1, 2), matrix.astype(np.float64)).reshape(-1, 2)
    return [[round(float(x), 1), round(float(y), 1)] for x, y in out]


def analyse_video(video_path: str | Path, max_seconds: float | None = None, keep_top: bool = False) -> tuple[dict, np.ndarray]:
    """(what was found, in the video's own pixels; the empty road at WORK_W wide).
    result["ok"] is False, with result["reason"] in plain words, when the road could not be read. With keep_top the top view with
    everything drawn on it is added as result["topdown"] (a picture, not JSON)."""
    return analyse_clip(_read_video(video_path, max_seconds), keep_top)


def analyse_clip(clip: dict, keep_top: bool = False) -> tuple[dict, np.ndarray]:
    """analyse_video on frames that were already read (_read_video)."""
    vw, vh = clip["video"]
    gw, gh = clip["grey_size"]
    cw, ch = clip["colour_size"]
    result: dict = {"ok": False, "reason": None, "video_size": [vw, vh], "seconds_used": round(clip["seconds"], 1),
                    "frames_used": len(clip["greys"]), "stop_lines": [], "lane_lines": [], "crosswalks": [], "road_direction": None}
    mats, sway, failed = _stabilise(clip["greys"])
    result["camera_shake_px"] = round(sway * vw / gw, 1)
    sx, sy = cw / gw, ch / gh
    scale = np.diag([sx, sy, 1.0])
    aligned = [cv2.warpPerspective(f, scale @ mats[i] @ np.linalg.inv(scale), (cw, ch), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
               for f, i in zip(clip["colours"], clip["colour_at"])]
    background = np.median(np.stack(aligned), axis=0).astype(np.uint8)
    if sway > 0.10 * gw or failed > 0.35:
        result["reason"] = "The camera moves too much (panning or heavy shake). This needs a fixed camera."
        return result, background
    points, directions, road_small, grey_background = _motion(clip["greys"], mats)
    info = _road_direction(points, directions, (gw, gh), _straight_edges(grey_background))
    if info is None or info["kind"] is None:
        seen = "" if info is None else f" ({info['lines']} moving points seen, only {info['inliers']} agree on one direction)"
        result["reason"] = ("Not enough traffic movement to find the road direction" + seen +
                            ". Try a clip with more vehicles passing, or draw it by hand.")
        return result, background
    if info["kind"] == "finite":
        vp_work = np.array([info["vp"][0] * sx, info["vp"][1] * sy])
        result["road_direction"] = {"kind": "vanishing point", "point": [round(vp_work[0] * vw / cw, 1), round(vp_work[1] * vh / ch, 1)],
                                    "inliers": info["inliers"], "moving_points": info["lines"]}
        info = {**info, "vp": vp_work}
    else:
        result["road_direction"] = {"kind": "parallel", "angle": round(info["angle"], 1), "inliers": info["inliers"], "moving_points": info["lines"]}
    homography = _top_homography(info, (cw, ch))
    top = _warp(background, homography)
    valid = _warp(np.full((ch, cw), 255, np.uint8), homography, cv2.INTER_NEAREST)
    road = _warp(cv2.resize(road_small, (cw, ch), interpolation=cv2.INTER_NEAREST), homography, cv2.INTER_NEAREST)
    road = cv2.dilate(road, np.ones((int(TOP_W * 0.03) | 1,) * 2, np.uint8))
    white, yellow, loose, warm, contrast = _paint(top, road, valid)
    to_video = np.diag([vw / cw, vh / ch, 1.0]) @ np.linalg.inv(homography)
    result["rectifier"] = {"top_to_video": to_video.tolist(), "top_size": [TOP_W, TOP_H]}
    on_road = max(int(((road > 0) & (valid > 0)).sum()), 1)
    density = float(((white > 0) | (yellow > 0)).sum()) / on_road
    result["paint_share"] = round(density, 3)
    if density > 0.50:                                                # "paint" everywhere means the road could not be read, not that it is all paint
        result["reason"] = "The paint could not be told apart from the road surface (too much of the road looks like paint). Draw it by hand."
        if keep_top:
            result["topdown"] = draw_topdown(top, white, yellow, [], [], [])
        return result, background
    crosswalks = _crosswalks(white, road, loose, warm)
    trust_lines = bool(crosswalks) or density <= 0.25               # lines are only believed where the paint picture is clean or a crosswalk proves paint is there
    stops = _stop_lines(white, road, contrast, crosswalks) if trust_lines else []
    lanes = _lane_lines(white, yellow, road) if trust_lines else []

    def line(item: dict, **extra) -> dict:
        p0, p1 = _to_video(to_video, [[item["u0"], item["v0"]], [item["u1"], item["v1"]]])
        return {"p0": p0, "p1": p1, "top": {k: round(float(item[k]), 1) for k in ("u0", "v0", "u1", "v1")}, **extra}
    result["stop_lines"] = [line(s, length=round(s["length"], 1)) for s in stops]
    result["lane_lines"] = [line(ln, style=ln["style"], colour=ln["colour"], coverage=ln["coverage"]) for ln in lanes]
    result["crosswalks"] = [{"polygon": _to_video(to_video, [[c["u0"], c["v0"]], [c["u1"], c["v0"]], [c["u1"], c["v1"]], [c["u0"], c["v1"]]]),
                             "stripes": c["stripes"], "score": c["score"],
                             "top": {k: float(c[k]) for k in ("u0", "u1", "v0", "v1")}} for c in crosswalks]
    result["ok"] = True
    if keep_top:
        result["topdown"] = draw_topdown(top, white, yellow, crosswalks, stops, lanes)
    return result, background


def _quad(top: dict, pad_u: float, pad_v: float) -> list[list[float]]:
    u0, u1, v0, v1 = top["u0"] - pad_u, top["u1"] + pad_u, top["v0"] - pad_v, top["v1"] + pad_v
    return [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]


def zone_hints(result: dict, band: float = 0.10) -> list[dict]:
    """Zone suggestions in the wizard's shape ({"violation", "polygon", "ui_vector"}), in the video's pixels. They are drawn in the top
    view (rectangles there) and mapped back, so they follow the road's perspective. `band` is how far a line's road section reaches
    on each side, as a share of the top view's width."""
    if not result.get("ok"):
        return []
    to_video = np.array(result["rectifier"]["top_to_video"], np.float64)
    tw, th = result["rectifier"]["top_size"]
    vw, vh = result["video_size"]

    def clipped(points: list[list[float]]) -> list[list[float]]:
        return [[round(min(max(x, 0.0), vw - 1.0), 1), round(min(max(y, 0.0), vh - 1.0), 1)] for x, y in _to_video(to_video, points)]
    hints = []
    for ln in result["lane_lines"]:
        if ln["style"] != "solid":
            continue
        t = ln["top"]
        mid = (t["u0"] + t["u1"]) / 2.0
        quad = _quad({"u0": mid, "u1": mid, "v0": min(t["v0"], t["v1"]), "v1": max(t["v0"], t["v1"])}, band * tw, 0.02 * th)
        hints.append({"violation": "crossing_solid_line", "polygon": clipped(quad), "ui_vector": [ln["p0"], ln["p1"]]})
    for ln in result["stop_lines"]:
        t = ln["top"]
        mid = (t["v0"] + t["v1"]) / 2.0
        quad = _quad({"u0": min(t["u0"], t["u1"]), "u1": max(t["u0"], t["u1"]), "v0": mid, "v1": mid}, 0.03 * tw, 0.15 * th)
        hints.append({"violation": "red_light", "polygon": clipped(quad), "ui_vector": [ln["p0"], ln["p1"]]})
    for c in result["crosswalks"]:
        hints.append({"violation": "pedestrian_lane", "polygon": clipped(_quad(c["top"], 0.02 * tw, 0.02 * th))})
    return hints


def reference_zones(result: dict, ref: tuple[int, int] = (1920, 1080)) -> dict[str, list[dict]]:
    """The zone suggestions as the Forensic wizard stores its own zones: {violation: [zone, ...]}, points in the wizard's
    1920x1080 reference space (the video's pixels scaled to it). A zone has a "polygon"; the line rules also have the
    line's two points as "ui_vector" and its direction as "vector"."""
    vw, vh = result["video_size"]
    sx, sy = ref[0] / vw, ref[1] / vh

    def pts(points):
        return [[round(x * sx, 1), round(y * sy, 1)] for x, y in points]
    out: dict[str, list[dict]] = {}
    for hint in zone_hints(result):
        zone = {"polygon": pts(hint["polygon"])}
        if hint.get("ui_vector"):
            line = pts(hint["ui_vector"])
            zone["ui_vector"] = line
            zone["vector"] = {"x_dir": line[1][0] - line[0][0], "y_dir": line[1][1] - line[0][1]}
        out.setdefault(hint["violation"], []).append(zone)
    return out


# ───────────────────────────── pictures ─────────────────────────────

def draw_topdown(top: np.ndarray, white: np.ndarray, yellow: np.ndarray, crosswalks: list[dict], stops: list[dict], lanes: list[dict]) -> np.ndarray:
    out = top.copy()
    out[white > 0] = (out[white > 0] * 0.45 + np.array([255, 255, 0]) * 0.55).astype(np.uint8)
    out[yellow > 0] = (out[yellow > 0] * 0.45 + np.array([0, 140, 255]) * 0.55).astype(np.uint8)
    for c in crosswalks:
        cv2.rectangle(out, (int(c["u0"]), int(c["v0"])), (int(c["u1"]), int(c["v1"])), (0, 255, 0), 3)
    for s in stops:
        cv2.line(out, (int(s["u0"]), int(s["v0"])), (int(s["u1"]), int(s["v1"])), (0, 0, 255), 5)
    for ln in lanes:
        colour = (0, 215, 255) if ln["colour"] == "yellow" else (255, 140, 0)
        cv2.line(out, (int(ln["u0"]), int(ln["v0"])), (int(ln["u1"]), int(ln["v1"])), colour, 4 if ln["style"] == "solid" else 2)
    return out


def draw(background: np.ndarray, result: dict) -> np.ndarray:
    """The empty road with everything found drawn on it (and a legend). `background` may be any size."""
    out = background.copy()
    k = out.shape[1] / float(result["video_size"][0])
    thick = max(2, out.shape[1] // 400)

    def p(pt):
        return int(round(pt[0] * k)), int(round(pt[1] * k))
    for c in result["crosswalks"]:
        cv2.polylines(out, [np.array([p(q) for q in c["polygon"]])], True, (0, 220, 0), thick, cv2.LINE_AA)
    for ln in result["lane_lines"]:
        colour = (0, 215, 255) if ln["colour"] == "yellow" else (255, 200, 0)
        cv2.line(out, p(ln["p0"]), p(ln["p1"]), colour, thick if ln["style"] == "solid" else max(1, thick // 2), cv2.LINE_AA)
    for ln in result["stop_lines"]:
        cv2.line(out, p(ln["p0"]), p(ln["p1"]), (0, 0, 255), thick + 2, cv2.LINE_AA)
    vp = (result.get("road_direction") or {}).get("point")
    if vp:
        x, y = p(vp)
        if -2000 < x < 4000 and -2000 < y < 4000:
            cv2.circle(out, (x, y), thick * 3, (255, 0, 255), -1)
    legend = [("stop line", (0, 0, 255)), ("crosswalk", (0, 220, 0)), ("yellow lane line", (0, 215, 255)), ("white lane line", (255, 200, 0))]
    size = max(0.5, out.shape[1] / 1800)
    for i, (text, colour) in enumerate(legend):
        y = int(30 * size) + i * int(34 * size)
        cv2.rectangle(out, (10, y - int(18 * size)), (10 + int(26 * size), y), colour, -1)
        cv2.putText(out, text, (int(46 * size), y - 2), cv2.FONT_HERSHEY_SIMPLEX, size, (255, 255, 255), max(1, thick - 1), cv2.LINE_AA)
    return out
