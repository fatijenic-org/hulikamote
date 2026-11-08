"""
flow_field.py - learn which way traffic normally goes, so counterflow needs no drawn zone or arrow.

Idea (a heuristic, like every rule here): split the picture into a grid. Every moving, tracked vehicle
"votes" for the direction it is heading in the cell it is in. After enough traffic each cell has a
dominant direction; a vehicle that keeps heading AGAINST the dominant direction of the cell it is in
is going the wrong way. Drawn zones (ROI mode) stay available and take priority; this is the
no-ROI alternative, and compare_with_zones() scores the learned flow against a hand-drawn arrow.

Why it is built this way
  - Directions are counted in 8 bins of 45 deg, in a grid of normalised cells (16 x 9), so it works at any resolution.
  - A vehicle adds at most 3 votes per cell, so one slow or parked-then-moving car cannot outvote real traffic.
  - A cell is only judged when it has enough votes from enough different vehicles (a 3 x 3 block of cells
    is pooled, so thin lanes still learn) and one direction owns 70% of them. A two-way cell (no clear
    majority) is never judged: nothing can say which side is legal.
  - Vehicles already flagged wrong-way do not teach the field.
  - Needs a FIXED camera (pan / zoom changes where cells are) and some traffic; a clip where the first cars
    are the wrong-way ones learns the wrong flow. Recorded clips can be pre-scanned first (flow_prescan).
"""
import math

import numpy as np

from engine.violations.geometry import dot, heading, is_driving

BINS = 8                      # 45 deg each
CELLS_X, CELLS_Y = 16, 9
VOTES_PER_TRACK_AND_CELL = 3
MIN_VOTES = 15                # pooled over the 3 x 3 block of cells around the vehicle
MIN_TRACKS = 3
MIN_OWN_VOTES = 2             # the cell itself must have been driven through (no judging of grass next to the road)
DOMINANT_SHARE = 0.70         # share of the votes (peak bin +-1) that must agree before a cell is judged
AGAINST_COS = math.cos(math.radians(135.0))   # heading further than 135 deg from the flow = against it
_FORGET_AFTER = 200_000       # bookkeeping entries; cleared when exceeded (only loosens the per-track vote cap)


def _bin_of(ux: float, uy: float) -> int:
    return int(((math.atan2(uy, ux) + math.pi) / (2 * math.pi)) * BINS) % BINS


def draw_test_banner(frame: np.ndarray, text: str = "TEST: FLOW REVERSED") -> np.ndarray:
    """A small amber label in the top-left corner, so a photo or video made with the reversed-flow test can never be
    mistaken for a real finding."""
    import cv2
    h = frame.shape[0]
    scale, thick = max(0.6, h / 1200), max(1, h // 540)
    (tw, th), base = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)
    pad = int(10 * scale)
    cv2.rectangle(frame, (pad, pad), (pad + tw + 2 * pad, pad + th + base + 2 * pad), (0, 140, 255), -1)
    cv2.putText(frame, text, (2 * pad, 2 * pad + th), cv2.FONT_HERSHEY_SIMPLEX, scale, (20, 20, 20), thick, cv2.LINE_AA)
    return frame


class FlowField:
    def __init__(self, cells_x: int = CELLS_X, cells_y: int = CELLS_Y):
        self.cells_x, self.cells_y = cells_x, cells_y
        self.counts = np.zeros((cells_y, cells_x, BINS), dtype=np.float32)
        self.sums = np.zeros((cells_y, cells_x, BINS, 2), dtype=np.float32)    # sum of unit headings per bin
        self.tracks: dict[tuple, set] = {}                                      # cell -> distinct vehicle ids (capped)
        self._votes: dict[tuple, int] = {}                                      # (vehicle, cell) -> votes cast
        self.samples = 0
        self._cache: tuple | None = None                                        # (key, cells) for learned_cells

    # ── learning ─────────────────────────────────────────────────────────────
    def cell_at(self, x: float, y: float, frame_w: float, frame_h: float) -> tuple[int, int]:
        cx = min(self.cells_x - 1, max(0, int(x / max(frame_w, 1) * self.cells_x)))
        cy = min(self.cells_y - 1, max(0, int(y / max(frame_h, 1) * self.cells_y)))
        return cy, cx

    def observe(self, track_id: int, x: float, y: float, head: tuple, frame_w: float, frame_h: float) -> None:
        """One vote: vehicle `track_id`, standing at (x, y), heading along unit vector `head`."""
        cell = self.cell_at(x, y, frame_w, frame_h)
        key = (track_id, cell)
        if self._votes.get(key, 0) >= VOTES_PER_TRACK_AND_CELL:
            return
        if len(self._votes) > _FORGET_AFTER:
            self._votes.clear()
        self._votes[key] = self._votes.get(key, 0) + 1
        b = _bin_of(*head)
        self.counts[cell][b] += 1
        self.sums[cell][b] += head
        seen = self.tracks.setdefault(cell, set())
        if len(seen) < 50:
            seen.add(track_id)
        self.samples += 1

    def observe_frame(self, mgr, detections: list, frame_w: float, frame_h: float) -> None:
        """Vote for every tracked, moving vehicle on screen (people are not traffic; flagged wrong-way cars do not teach)."""
        for det in detections:
            ledger = mgr.ledgers.get(getattr(det, "track_id", -1))
            if ledger is None or not ledger.path or "person" in (ledger.vclass, ledger.latest_class):
                continue
            if "counterflow" in ledger.violations:
                continue
            head = heading(ledger)                  # None while barely moving
            if head is not None and is_driving(ledger):     # a creeping or drifting car must not teach a direction
                self.observe(ledger.track_id, ledger.path[-1][1], ledger.path[-1][2], head, frame_w, frame_h)

    # ── asking ───────────────────────────────────────────────────────────────
    def _pool(self, x: float, y: float, frame_w: float, frame_h: float):
        """(votes per bin, summed headings per bin, distinct vehicles) pooled over the 3 x 3 cells around (x, y),
        or None when the cell itself was barely driven through or there is too little traffic."""
        r, c = self.cell_at(x, y, frame_w, frame_h)
        if self.counts[r, c].sum() < MIN_OWN_VOTES:
            return None
        rs, cs = slice(max(0, r - 1), r + 2), slice(max(0, c - 1), c + 2)
        counts = self.counts[rs, cs].sum(axis=(0, 1))
        tracks = set()
        for rr in range(rs.start, rs.stop):
            for cc in range(cs.start, cs.stop):
                tracks |= self.tracks.get((rr, cc), set())
        if float(counts.sum()) < MIN_VOTES or len(tracks) < MIN_TRACKS:
            return None
        return counts, self.sums[rs, cs].sum(axis=(0, 1)), len(tracks)

    def dominant(self, x: float, y: float, frame_w: float, frame_h: float):
        """{'direction': (ux, uy), 'share': 0-1, 'votes': n, 'tracks': n} for the cells around (x, y), or None if not learned."""
        pooled = self._pool(x, y, frame_w, frame_h)
        if pooled is None:
            return None
        counts, sums, n_tracks = pooled
        total = float(counts.sum())
        peak = int(counts.argmax())
        near = [(peak + k) % BINS for k in (-1, 0, 1)]
        agreeing = float(counts[near].sum())
        vx, vy = sums[near].sum(axis=0)
        norm = math.hypot(vx, vy)
        if norm == 0:
            return None
        return {"direction": (float(vx / norm), float(vy / norm)), "share": agreeing / total,
                "votes": int(total), "tracks": n_tracks}

    def road_axis(self, x: float, y: float, frame_w: float, frame_h: float):
        """Unit vector ALONG the road at (x, y), whichever way: the axis that most of the traffic uses, in either
        direction (a two-way road still has one). None where traffic is not learned or goes every which way."""
        pooled = self._pool(x, y, frame_w, frame_h)
        if pooled is None:
            return None
        counts, sums, _n = pooled
        peak = int(counts.argmax())
        near = [(peak + k) % BINS for k in (-1, 0, 1)]
        opposite = [(peak + BINS // 2 + k) % BINS for k in (-1, 0, 1)]
        if float(counts[near].sum() + counts[opposite].sum()) / float(counts.sum()) < DOMINANT_SHARE:
            return None
        vx, vy = sums[near].sum(axis=0)
        norm = math.hypot(vx, vy)
        return (float(vx / norm), float(vy / norm)) if norm else None

    def verdict(self, x: float, y: float, frame_w: float, frame_h: float, head: tuple) -> str:
        """'with' | 'against' | 'unknown' (cell not learned yet, or two-way / no clear majority)."""
        d = self.dominant(x, y, frame_w, frame_h)
        if d is None or d["share"] < DOMINANT_SHARE:
            return "unknown"
        return "against" if dot(head, d["direction"]) <= AGAINST_COS else "with"

    # ── explaining ───────────────────────────────────────────────────────────
    def learned_cells(self, frame_w: float, frame_h: float) -> list[dict]:
        """Every cell that is judged: centre (px), direction, share. For drawing, saving and scoring."""
        key = (self.samples // 25, round(frame_w), round(frame_h))      # recomputed every 25 new votes
        if self._cache is not None and self._cache[0] == key:
            return self._cache[1]
        out = []
        for r in range(self.cells_y):
            for c in range(self.cells_x):
                x, y = (c + 0.5) * frame_w / self.cells_x, (r + 0.5) * frame_h / self.cells_y
                d = self.dominant(x, y, frame_w, frame_h)
                if d is not None and d["share"] >= DOMINANT_SHARE:
                    out.append({"x": x, "y": y, "direction": d["direction"], "share": d["share"], "votes": d["votes"]})
        self._cache = (key, out)
        return out

    def draw(self, frame: np.ndarray, invert: bool = False) -> np.ndarray:
        """What the system believes the legal flow is: one soft arrow per 2 x 2 block of judged cells (a calm teal,
        smooth edges, see-through), not one per cell. `invert` draws the opposite way in amber: the flow the
        counterflow test treats as legal (see Counterflow, "invert_flow")."""
        import cv2
        h, w = frame.shape[:2]
        cell_w, cell_h = w / self.cells_x, h / self.cells_y
        blocks: dict[tuple, list] = {}
        for cell in self.learned_cells(w, h):
            key = (int(cell["x"] // (2 * cell_w)), int(cell["y"] // (2 * cell_h)))
            blocks.setdefault(key, []).append(cell)
        if not blocks:
            return frame
        length = 0.6 * min(cell_w, cell_h)
        thick = max(2, h // 360)
        shadow, ink = (30, 30, 30), ((0, 140, 255) if invert else (170, 190, 0))      # BGR: amber for the test, teal otherwise
        layer = frame.copy()
        for cells in blocks.values():
            weight = sum(c["votes"] for c in cells)
            vx = sum(c["direction"][0] * c["votes"] for c in cells) / weight
            vy = sum(c["direction"][1] * c["votes"] for c in cells) / weight
            norm = math.hypot(vx, vy)
            if norm < 0.5:                      # the cells of this block disagree: no honest single arrow
                continue
            ux, uy = (vx / norm, vy / norm) if not invert else (-vx / norm, -vy / norm)
            x = sum(c["x"] * c["votes"] for c in cells) / weight
            y = sum(c["y"] * c["votes"] for c in cells) / weight
            a = (int(x - ux * length), int(y - uy * length))
            b = (int(x + ux * length), int(y + uy * length))
            cv2.arrowedLine(layer, a, b, shadow, thick + 2, cv2.LINE_AA, tipLength=0.35)
            cv2.arrowedLine(layer, a, b, ink, thick, cv2.LINE_AA, tipLength=0.35)
        cv2.addWeighted(layer, 0.75, frame, 0.25, 0, dst=frame)
        return frame

    def summary(self, frame_w: float, frame_h: float) -> dict:
        cells = self.learned_cells(frame_w, frame_h)
        return {"votes": self.samples, "judged_cells": len(cells), "cells": self.cells_x * self.cells_y}

    def compare_with_zones(self, zones: list[dict], frame_w: float, frame_h: float) -> dict:
        """Score the learned flow against hand-drawn counterflow zones ({'polygon', 'vector'}): the share of judged
        cells inside the zones whose learned direction is within 45 deg of the drawn arrow."""
        from engine.violations.geometry import point_in_polygon, unit
        agree = total = 0
        for cell in self.learned_cells(frame_w, frame_h):
            for zone in zones:
                if point_in_polygon(cell["x"], cell["y"], zone["polygon"]):
                    total += 1
                    arrow = unit(*zone["vector"])
                    agree += dot(cell["direction"], arrow) >= math.cos(math.radians(45.0))
                    break
        return {"cells_compared": total, "agree": agree, "agreement": (agree / total) if total else None}

    # ── saving ───────────────────────────────────────────────────────────────
    def to_dict(self) -> dict:
        return {"cells_x": self.cells_x, "cells_y": self.cells_y, "samples": self.samples,
                "counts": self.counts.tolist(), "sums": self.sums.tolist(),
                "tracks": [[list(cell), len(ids)] for cell, ids in self.tracks.items()]}

    @classmethod
    def from_dict(cls, data: dict) -> "FlowField":
        field = cls(data["cells_x"], data["cells_y"])
        field.counts = np.array(data["counts"], dtype=np.float32)
        field.sums = np.array(data["sums"], dtype=np.float32)
        field.samples = int(data.get("samples", 0))
        for (r, c), n in data.get("tracks", []):       # only the number of distinct vehicles is kept
            field.tracks[(r, c)] = set(range(-1, -n - 1, -1))
        return field
