"""
indicators.py - does a vehicle show a blinking indicator (turn signal or hazard lights)?

Two rules use it:
  signal_light    a turn needs a blinking indicator (reads the old edge samples, ledger.blink);
  illegal_parking a vehicle with a blinking indicator has not parked yet (reads the amber grids, ledger.blink_grid).

sample_indicators() runs once per frame and writes, for each vehicle it is asked about, ONE sample into two places however many rules
ask for it (a second call in the same frame adds nothing):
  ledger.blink       (t, left amber, right amber)    the share of amber at the left / right edge (signal_light)
  ledger.blink_grid  (t, grid)                       the share of amber in every cell of a GRID_COLS x GRID_ROWS grid laid over blink_ref

Why a grid and not two edges: a lamp is a few pixels. Averaged over a whole edge of the box it is lost in everything else that sits there
(tyres, bumper, a yellow body, the road), and a jittering box moves that "everything" in and out of the edge. In a grid the lamp is one or
two cells that go from dark to amber and back; the rest of the vehicle does not.
Why a FIXED part of the picture (blink_ref) and not the box of each picture: the detector's box of a parked vehicle shakes by several
pixels, and a lamp of 3 - 5 pixels would hop from cell to cell with it. The vehicle stands still, so its lamp stays on the same pixels of
the picture: the grid is cut from the same rectangle every time (a new one, with the grids cleared, when the vehicle really moves).

blink_report() reads a window of grids. A lamp is a cell (or a few cells together) that
  - swings between "not amber" and "amber" by a good part of its area,
  - switches on again and again at a steady rhythm (indicators: about 1 - 2 Hz), and is on for a middle share of the time,
  - while the rest of the box stays quiet (if most cells change, it is the light, a shadow or another vehicle passing, not a lamp).
Static amber (a yellow tricycle, orange paint, a sign) never switches. Something that passes in front switches once. Neither counts.
"""
from collections import namedtuple

import cv2
import numpy as np

from engine.slicer import NumpySlicer
from engine.traffic_light import amber_fraction
from engine.violations.base import VEHICLE_CLASSES

EDGE_SHARE = 0.3        # indicators sit at the left and right edge: read the outer 30% of the vehicle's box on each side

GRID_COLS, GRID_ROWS = 32, 24
REF_CENTRE = 0.25       # the fixed part is kept while the centre of the vehicle's box stays within this share of its size from the middle ...
REF_SIZE = (0.4, 2.5)   # ... and the box is not much smaller or larger than it (a detector box that wobbles in size is still the same vehicle)
REF_GROW = 0.08         # the fixed part is a little larger than the first box, for a box that was a bit small
GRID_SPEED = 62.5       # px/s: only a vehicle this slow is worth a grid (it is stopped or about to stop; see illegal_parking.SAMPLE_SPEED)
AMBER_HUE = (5, 32)     # OpenCV hue 0-180: orange to yellow. Wider and paler than the old reading: a lamp in full sun is washed out
AMBER_MIN_SAT = 70
AMBER_MIN_VAL = 140

MIN_SAMPLES = 8         # a window needs this many grids ...
MIN_SPAN_S = 1.3        # ... that cover at least this much time ...
MAX_STEP_S = 0.4        # ... and the usual time between two of them must be short enough to see a blink at all (1 - 2 Hz)
MIN_SWING = 0.18        # a cell changes by this share of its area between off and on (box jitter alone does not)
MIN_ON = 0.2            # and it is at least this amber when on
PERIOD_S = (0.3, 1.7)   # time between two switch-ons
MIN_RISES = 4           # it must switch on this many times in the window (3 periods) ...
PERIOD_CV = 0.3         # ... and the periods must be alike: spread (std / mean) at most this. A lamp is steady (0.1 at most with an uneven
                        # sample rate); flicker from noise or a shaking edge is not (0.5 and more), and many cells are tested
DUTY = (0.15, 0.85)     # share of the time the cell is on
GLOBAL_CELLS = 0.35     # more than this share of all cells swinging = light, shadow or a passing vehicle, not a lamp
NEIGHBOURS = 2          # cells this close (in cells) belong to one lamp
PHASE_S = 0.3           # and they switch on together within this time
STRONG_SWING = 0.5      # a lone cell this clear needs no neighbour

Blink = namedtuple("Blink", "left right")     # True for the side(s) where a lamp blinks; both = hazard lights


def amber_grid(crop: np.ndarray) -> np.ndarray:
    """The share of amber (a lit indicator) in each cell of a GRID_ROWS x GRID_COLS grid over a BGR crop, as 0 - 255."""
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    mask = ((h >= AMBER_HUE[0]) & (h <= AMBER_HUE[1]) & (s >= AMBER_MIN_SAT) & (v >= AMBER_MIN_VAL)).astype(np.float32)
    grid = cv2.resize(mask, (GRID_COLS, GRID_ROWS), interpolation=cv2.INTER_AREA)
    return (grid * 255.0 + 0.5).astype(np.uint8)


def _same_spot(ref, box) -> bool:
    """True when `box` is the vehicle that stands in the fixed part `ref`: its centre has not left the middle of it and its size is alike."""
    if ref[2] <= 0 or ref[3] <= 0 or box[2] <= 0 or box[3] <= 0:
        return False
    if abs((box[0] + box[2] / 2) - (ref[0] + ref[2] / 2)) > REF_CENTRE * ref[2]:
        return False
    if abs((box[1] + box[3] / 2) - (ref[1] + ref[3] / 2)) > REF_CENTRE * ref[3]:
        return False
    return REF_SIZE[0] <= (box[2] * box[3]) / (ref[2] * ref[3]) <= REF_SIZE[1]


def sample_indicators(pipe, frame, detections, wanted=None) -> None:
    """Record the amber of each vehicle's box (edges) and of the fixed part of the picture it stands on (grid).
    wanted: optional test on the ledger; a vehicle it rejects is not sampled (saves time for rules that only need parked vehicles)."""
    for det in detections:
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        if ledger is None or det.cls not in VEHICLE_CLASSES or not ledger.path:
            continue
        t = ledger.path[-1][0]
        if ledger.blink and ledger.blink[-1][0] == t:       # another rule already read this vehicle in this frame
            continue
        if wanted is not None and not wanted(ledger):
            continue
        crop = NumpySlicer.crop_box(frame, det.bbox)
        if crop.size == 0:
            continue
        edge = max(1, int(crop.shape[1] * EDGE_SHARE))
        ledger.blink.append((t, amber_fraction(crop[:, :edge]), amber_fraction(crop[:, -edge:])))
        if ledger.get_speed() >= GRID_SPEED:                 # moving: no grid (signal_light reads the edges above)
            ledger.blink_ref = None
            continue
        box = [float(v) for v in det.bbox]
        if ledger.blink_ref is None or not _same_spot(ledger.blink_ref, box):       # first look, or the vehicle moved: start again
            ledger.blink_ref = [int(round(v)) for v in (box[0] - REF_GROW * box[2], box[1] - REF_GROW * box[3], box[2] * (1 + 2 * REF_GROW), box[3] * (1 + 2 * REF_GROW))]
            ledger.blink_grid.clear()
        fixed = NumpySlicer.crop_box(frame, ledger.blink_ref)
        if fixed.shape[0] >= 8 and fixed.shape[1] >= 8:
            ledger.blink_grid.append((t, amber_grid(fixed)))


def blink_report(ledger, t: float, lookback_s: float) -> Blink | None:
    """Where a lamp blinks on this vehicle in the last lookback_s seconds, or None when none does (or when the samples are too few or
    too far apart to tell)."""
    recent = [(ts, g) for ts, g in ledger.blink_grid if ts >= t - lookback_s]
    if len(recent) < MIN_SAMPLES:
        return None
    times = np.array([ts for ts, _g in recent], dtype=np.float64)
    if times[-1] - times[0] < MIN_SPAN_S or float(np.median(np.diff(times))) > MAX_STEP_S:
        return None
    cells = np.stack([g for _ts, g in recent]).astype(np.float32) / 255.0          # (n, rows, cols)
    # A lamp may sit across the edge of several cells: add up each 2 x 2 block (in cell areas, at most 1) so it counts whole wherever it falls.
    cells = np.minimum(1.0, cells[:, :-1, :-1] + cells[:, 1:, :-1] + cells[:, :-1, 1:] + cells[:, 1:, 1:])

    low, high = np.percentile(cells, 10, axis=0), np.percentile(cells, 90, axis=0)
    swing = high - low
    candidate = (swing >= MIN_SWING) & (high >= MIN_ON)
    if not candidate.any() or candidate.mean() > GLOBAL_CELLS:
        return None

    # every cell: on / off with a margin (a value between the two keeps the state it had)
    upper, lower, middle = low + 0.65 * swing, low + 0.35 * swing, low + 0.5 * swing
    state = cells[0] > middle
    on = np.zeros(cells.shape, dtype=bool)
    for k in range(len(cells)):
        state = np.where(cells[k] >= upper, True, np.where(cells[k] <= lower, False, state))
        on[k] = state
    rises = on[1:] & ~on[:-1]

    lamps = []                               # (row, col, last switch-on, swing) of the cells that blink in a steady rhythm
    for r, c in np.argwhere(candidate):
        stamps = times[1:][rises[:, r, c]]
        if len(stamps) < MIN_RISES:
            continue
        gaps = np.diff(stamps)
        if not (PERIOD_S[0] <= float(np.median(gaps)) <= PERIOD_S[1]):
            continue
        if float(gaps.std()) > PERIOD_CV * float(gaps.mean()):
            continue
        if not (DUTY[0] <= float(on[:, r, c].mean()) <= DUTY[1]):
            continue
        lamps.append((int(r), int(c), float(stamps[-1]), float(swing[r, c])))

    seen = [
        a for a in lamps
        if a[3] >= STRONG_SWING or any(
            b is not a and max(abs(a[0] - b[0]), abs(a[1] - b[1])) <= NEIGHBOURS and abs(a[2] - b[2]) <= PHASE_S for b in lamps
        )
    ]
    if not seen:
        return None
    middle_col = cells.shape[2] / 2
    return Blink(left=any(a[1] < middle_col for a in seen), right=any(a[1] >= middle_col for a in seen))


def is_signalling(ledger, t: float, lookback_s: float) -> bool:
    """True when a lamp of the vehicle blinked during the last lookback_s seconds."""
    return blink_report(ledger, t, lookback_s) is not None
