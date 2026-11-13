"""
intersection_finder.py - find the junction box by itself, from how the traffic moves (no drawing).

A junction is where traffic goes two clearly different ways in the same place. On a straight road, even a two-way one, every vehicle
drives along ONE axis (one way or the other). Where roads cross, a second axis (at least 45 degrees away) shows up in the same cells, and
the vehicles that turn pass through both. So: from the learned flow (engine/flow_field.py: for every cell of the picture, how many vehicles
went which way) a cell is "junction" when it holds a lot of traffic on its main axis AND a real share on a crossing axis. The cells that
touch each other form the junction; the best group (most traffic) is wrapped in one four-or-more-corner shape.

What it needs: a fixed camera and traffic in more than one direction (a recorded clip is pre-scanned first, see flow_prescan.py; on a live
camera the box appears when enough cars have gone through). It does not read paint: crosswalks and stop lines do not enter into it, so a
junction nobody drove across stays unfound and the rule judges nothing there. An operator's drawn box or placed sign always wins.
"""
import math

import cv2
import numpy as np

CROSS_ANGLE = math.radians(45.0)    # a second axis must be at least this far from the main one
MIN_POOLED_VOTES = 12               # traffic in the 3 x 3 cells around a cell
MIN_TRACKS = 3                      # ... from at least this many different vehicles
MIN_OWN_VOTES = 4                   # the cell itself must have been driven through
MIN_AXIS_VOTES = 5                  # pooled votes on each of the two axes
CROSS_SHARE = 0.18                  # share of the pooled votes on the crossing axis
MIN_CELLS = 2                       # a junction is more than one cell
MIN_AREA = 0.01                     # ... and at least 1% of the picture
RECHECK_EVERY = 25                  # new votes between two searches


def junction_cells(flow) -> np.ndarray:
    """A boolean grid (cells_y, cells_x): True where traffic crosses (two axes, at least 45 degrees apart)."""
    rows, cols = flow.counts.shape[:2]
    out = np.zeros((rows, cols), dtype=bool)
    for r in range(rows):
        for c in range(cols):
            own = flow.counts[r, c]
            if own.sum() < MIN_OWN_VOTES:
                continue
            rs, cs = slice(max(0, r - 1), r + 2), slice(max(0, c - 1), c + 2)
            n = flow.counts[rs, cs].sum(axis=(0, 1))
            total = float(n.sum())
            if total < MIN_POOLED_VOTES:
                continue
            tracks = set()
            for rr in range(rs.start, rs.stop):
                for cc in range(cs.start, cs.stop):
                    tracks |= flow.tracks.get((rr, cc), set())
            if len(tracks) < MIN_TRACKS:
                continue
            s = flow.sums[rs, cs].sum(axis=(0, 1))                       # summed unit headings per bin (8, 2)
            axis = np.mod(np.arctan2(s[:, 1], s[:, 0]), math.pi)         # each bin's mean heading, folded: one way = the other way
            peak = int(n.argmax())
            gap = np.abs(axis - axis[peak])
            gap = np.minimum(gap, math.pi - gap)                         # 0 .. 90 degrees
            across = (n > 0) & (gap >= CROSS_ANGLE)
            cross = float(n[across].sum())
            main = total - cross
            own_cross = float(own[across].sum())
            if cross >= MIN_AXIS_VOTES and main >= MIN_AXIS_VOTES and cross / total >= CROSS_SHARE \
                    and own_cross >= 2 and float(own.sum()) - own_cross >= 2:
                out[r, c] = True
    return out


def find_junction(flow, frame_w: float, frame_h: float):
    """The junction as a polygon in frame pixels ([[x, y], ...]), or None while it is not clear. Cached between searches."""
    if flow is None or not getattr(flow, "samples", 0):
        return None
    key = (flow.samples // RECHECK_EVERY, round(frame_w), round(frame_h))
    cached = getattr(flow, "_junction_cache", None)
    if cached is not None and cached[0] == key:
        return cached[1]
    result = _search(flow, frame_w, frame_h)
    flow._junction_cache = (key, result)
    return result


def _search(flow, frame_w: float, frame_h: float):
    cells = junction_cells(flow)
    if not cells.any():
        return None
    count, labels = cv2.connectedComponents(cells.astype(np.uint8), connectivity=8)
    best, best_votes = None, 0.0
    for label in range(1, count):
        members = np.argwhere(labels == label)
        if len(members) < MIN_CELLS:
            continue
        votes = float(sum(flow.counts[r, c].sum() for r, c in members))
        if votes > best_votes:
            best, best_votes = members, votes
    if best is None:
        return None
    rows, cols = flow.counts.shape[:2]
    cw, ch = frame_w / cols, frame_h / rows
    corners = []
    for r, c in best:
        corners += [(c * cw, r * ch), ((c + 1) * cw, r * ch), ((c + 1) * cw, (r + 1) * ch), (c * cw, (r + 1) * ch)]
    hull = cv2.convexHull(np.array(corners, dtype=np.float32)).reshape(-1, 2)
    if cv2.contourArea(hull) < MIN_AREA * frame_w * frame_h:
        return None
    return [[int(round(x)), int(round(y))] for x, y in hull]
