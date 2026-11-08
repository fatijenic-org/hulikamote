"""
probe.py - How much does the way the model is fed cost? (measure, do not guess)

Compares ways of preparing a vehicle picture for the plate model:
    A  how the app does it today: BGR colours, stretched to a square, only the bottom 40% of the vehicle
    B  same, but RGB (the colour order the model was trained on)
    C  RGB + letterbox (keep the picture's proportions) on the bottom 40%
    D  RGB + letterbox on the WHOLE vehicle
    E  the app's way (BGR + stretch) on the whole vehicle
on (1) held-out labelled plate photos cut into vehicle pictures, and (2) your real "no plate" tickets.
CPU only, read-only. Re-run it after changing how the app feeds images to see the effect.
"""
import sqlite3

import cv2
import numpy as np

from .accept import split_dirs
from .config import Paths, active_onnx, active_vehicle_onnx
from .cut_plates import cut_one, read_plate_boxes, vehicle_classes
from .detect import Detector

MODES = {
    "A  app today (BGR, stretched, bottom 40%)": ("bottom40", False, False),
    "B  RGB fixed (RGB, stretched, bottom 40%)": ("bottom40", True, False),
    "C  RGB + letterbox, bottom 40%": ("bottom40", True, True),
    "D  RGB + letterbox, whole vehicle": ("full", True, True),
    "E  app's way on the whole vehicle": ("full", False, False),
}


def _iou(a, b) -> float:
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter + 1e-9)


def _top1(plate: Detector, img, region: str, rgb: bool, letterbox: bool, conf: float):
    y0 = int(0.6 * img.shape[0]) if region == "bottom40" else 0
    dets = plate.detect(img[y0:], conf=conf, rgb=rgb, letterbox=letterbox)
    if not dets:
        return None
    d = dets[0]
    return (d.x1, d.y1 + y0, d.x2, d.y2 + y0, d.conf)


def run(paths: Paths | None = None, photos: int = 160, log=print) -> dict:
    paths = paths or Paths()
    plate_onnx, vehicle_onnx = active_onnx(paths, "plate_specialist"), active_vehicle_onnx(paths)
    if plate_onnx is None or vehicle_onnx is None:
        raise FileNotFoundError("Need a deployed plate model and a vehicle detector in hulikamote_backend/models/")
    plate, vehicles = Detector.load(plate_onnx), Detector.load(vehicle_onnx)
    vclasses = vehicle_classes(vehicles)
    log(f"Plate model: {plate_onnx.name} | vehicle detector: {vehicle_onnx.name}")

    # (1) held-out labelled photos -> vehicle pictures with a known plate
    img_dir, lbl_dir = split_dirs(paths, "plate_specialist", "val")          # whatever layout data.yaml says
    files = [p for p in sorted(img_dir.iterdir()) if p.suffix.lower() in (".jpg", ".jpeg", ".png")]
    files = files[:: max(1, len(files) // photos)]
    hits, n, in_bottom = {m: 0 for m in MODES}, 0, 0
    for p in files:
        plates = read_plate_boxes(lbl_dir / (p.stem + ".txt"))
        img = cv2.imread(str(p))
        if img is None or not plates:
            continue
        found = [d for d in vehicles.detect(img, conf=0.35) if d.cls in vclasses]
        for crop, labels in cut_one(img, plates, found, margin=0.08, min_side=80):
            H, W = crop.shape[:2]
            gts = [((cx - w / 2) * W, (cy - h / 2) * H, (cx + w / 2) * W, (cy + h / 2) * H) for _, cx, cy, w, h in labels]
            n += 1
            in_bottom += any(((g[1] + g[3]) / 2) >= 0.6 * H for g in gts)
            for name, (region, rgb, lb) in MODES.items():
                t = _top1(plate, crop, region, rgb, lb, conf=0.1)
                hits[name] += bool(t and any(_iou(t[:4], g) >= 0.5 for g in gts))
    log(f"\n(1) Held-out labelled photos: {n} vehicle pictures with a known plate")
    log(f"    plate sits in the bottom 40% of the vehicle: {in_bottom}/{n} = {100 * in_bottom / max(n, 1):.0f}%")
    for name in MODES:
        log(f"    {name:44} found right: {hits[name]:3d}/{n} = {100 * hits[name] / max(n, 1):3.0f}%")

    # (2) real "no plate" tickets: how many have a plate the model finds when fed properly?
    result = {"photos_with_plate": n, "in_bottom_40": in_bottom, "found": hits, "tickets": 0, "ticket_found": {}}
    db = paths.inbox / "harvest.db"
    if db.exists():
        con = sqlite3.connect(db)
        rows = con.execute("SELECT id FROM items WHERE model='plate_specialist' AND violation='no_plate'").fetchall()
        con.close()
        tf = {m: 0 for m in MODES}
        for (item_id,) in rows:
            img = cv2.imread(str(paths.inbox / "plate_specialist" / "images" / f"{item_id}.jpg"))
            if img is None:
                continue
            for name, (region, rgb, lb) in MODES.items():
                tf[name] += _top1(plate, img, region, rgb, lb, conf=0.25) is not None
        result.update(tickets=len(rows), ticket_found=tf)
        log(f"\n(2) Your real 'no plate' tickets: {len(rows)} pictures (model confidence 0.25 or more)")
        log("    These were flagged because the app found no plate; any 'found' below is a likely FALSE ticket.")
        for name in MODES:
            log(f"    {name:44} plate found in {tf[name]:3d}/{len(rows)} = {100 * tf[name] / max(len(rows), 1):3.0f}%")
    return result
