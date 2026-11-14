"""
specialist_jobs.py - the three model "looks" the pipeline takes at a vehicle: helmet, plate, cabin.

A job decides WHICH vehicles it looks at, WHICH part of the picture it feeds its model, and returns
a Look (boxes in frame pixels). One look is shared by every violation judged from that model
(the cabin look serves seatbelt, phone and mirror), so each model runs once per vehicle per round.
What a look MEANS is decided by the violation modules (engine/violations/*.py: judge()).

The plate job also does plate identification (tight crops for OCR, plate position cache), which
runs for every vehicle whether or not "no_plate" is an active violation.
"""
import logging
from dataclasses import dataclass, field

import cv2

from engine import privacy, specialists
from engine.slicer import NumpySlicer
from engine.violations.base import VEHICLE_CLASSES
from engine.violations.no_seatbelt import NoSeatbelt
from engine.violations.geometry import rider_boxes

log = logging.getLogger(__name__)

# Max plate crops kept per car for Pass 2 voting. Each crop carries the time it was taken
# so forensics can link it to the nearest evidence frame.
MAX_PLATE_CROPS = 40


@dataclass
class Look:
    dets: list = field(default_factory=list)   # [{"class_id", "confidence", "box": [x, y, w, h] in FRAME pixels}]
    found: bool = False                        # plate job: a plate (or, in direct-OCR mode, a bumper to read) was found
    search_box: list | None = None             # plate job: the area that was searched, [x, y, w, h] in frame pixels
    crop: object = None                        # helmet / cabin jobs: the picture the model was given (raw frame pixels)
    origin: tuple = (0, 0)                     # where that crop's top-left corner sits in the frame


def _to_frame(dets: list, origin: tuple) -> list:
    """Specialist boxes are in crop pixels; move them onto the full frame."""
    return [{**d, "box": [origin[0] + d["box"][0], origin[1] + d["box"][1], d["box"][2], d["box"][3]]} for d in dets]


class HelmetJob:
    """Motorcycle + its riders -> rider with / without helmet."""
    name = "helmet"
    model = "helmet_specialist"

    def wanted(self, active, det) -> bool:
        return "no_helmet" in active and det.cls == "motorcycle"

    def look(self, pipe, frame, det, detections):
        session = pipe.registry.get_model(self.model)
        if session is None:
            return None
        # The motorcycle box often cuts off the riders' heads: look at the motorcycle together with
        # its riders (helmet training crops must be taken the same way).
        riders = rider_boxes(det.bbox, [d.bbox for d in detections if d.cls == "person"])
        boxes = [det.bbox] + riders
        x1, y1 = min(b[0] for b in boxes), min(b[1] for b in boxes)
        x2, y2 = max(b[0] + b[2] for b in boxes), max(b[1] + b[3] for b in boxes)
        crop = NumpySlicer.crop_box(frame, [x1, y1, x2 - x1, y2 - y1])
        if not crop.size:
            return None
        origin = (max(0, x1), max(0, y1))
        return Look(dets=_to_frame(specialists.detect(session, crop, specialists.HELMET_CHECK_CONF), origin), crop=crop, origin=origin)


class CabinJob:
    """Whole vehicle -> clear / tinted window, seatbelt, phone, side mirror."""
    name = "cabin"
    model = "cabin_specialist"
    violations = ("no_seatbelt", "distracted_driving", "missing_side_mirror")

    def wanted(self, active, det) -> bool:
        if det.cls not in VEHICLE_CLASSES:
            return False
        # no_seatbelt judges only cars and trucks: when it is the only cabin rule on, other vehicles are not looked at
        return any(v in active and (v != "no_seatbelt" or det.cls in NoSeatbelt.JUDGED_CLASSES) for v in self.violations)

    def look(self, pipe, frame, det, detections):
        session = pipe.registry.get_model(self.model)
        if session is None:
            return None
        crop = NumpySlicer.crop_box(frame, det.bbox)
        if not crop.size:
            return None
        origin = (max(0, int(det.bbox[0])), max(0, int(det.bbox[1])))
        return Look(dets=_to_frame(specialists.detect(session, crop, specialists.CHECK_CONF), origin), crop=crop, origin=origin)


class PlateJob:
    """
    Whole vehicle -> licence plate. The plate is searched in the WHOLE vehicle (not just a bumper
    strip): the model was trained on whole-vehicle crops, and diagonal CCTV views put only about half
    the plates in the lower 40% of the box. In "direct_ocr" mode there is no detector, so the bumper
    strip (lower 40%) is handed to the OCR.
    """
    name = "plate"
    model = "plate_specialist"

    def wanted(self, active, det) -> bool:
        return det.cls in VEHICLE_CLASSES      # plates are read for every ticket, not only no_plate ones

    def look(self, pipe, frame, det, detections):
        direct = getattr(pipe.registry, "plate_method", "smart") == "direct_ocr"
        session = None
        if not direct:
            session = pipe.registry.get_model(self.model)
            if session is None:
                return None

        vx, vy, vw, vh = (int(v) for v in det.bbox)
        fh, fw = frame.shape[:2]
        top = vy + int(vh * 0.60) if direct else vy          # direct OCR reads the bumper strip only
        if vw < 20 or (vy + vh - top) < 10:                  # too small to read
            return None
        px1, py1 = max(0, vx), max(0, top)
        px2, py2 = min(fw, vx + vw), min(fh, vy + vh)
        if py2 <= py1 or px2 <= px1:
            return None

        area = frame[py1:py2, px1:px2].copy()
        area_h, area_w = area.shape[:2]
        search_box = [px1, py1, area_w, area_h]
        ledger = pipe.ledger_manager.ledgers.get(det.track_id) if det.track_id != -1 else None
        stamp = ledger.history[-1][0] if ledger is not None and ledger.history else None

        plate_box, best_conf = search_box, 0.0
        if direct:
            found = True          # no detector: just scan the bumper with OCR
            if ledger is not None and len(ledger.plate_crops) < MAX_PLATE_CROPS:
                ledger.plate_crops.append((area, area, stamp))
        else:
            plates = [d for d in specialists.detect(session, area, specialists.SEARCH_CONF)
                      if d["class_id"] == specialists.IDX_LICENSE_PLATE]
            found = bool(plates)
            if found:
                best = plates[0]                     # detect() returns best first
                best_conf = best["confidence"]
                lx, ly, lw, lh = best["box"]
                plate_box = [px1 + lx, py1 + ly, lw, lh]
                # tight crop (10% margin) for the OCR, plus the whole vehicle with the plate boxed green
                pad_x, pad_y = int(lw * 0.1), int(lh * 0.1)
                tight = frame[max(0, py1 + ly - pad_y):min(fh, py1 + ly + lh + pad_y),
                              max(0, px1 + lx - pad_x):min(fw, px1 + lx + lw + pad_x)].copy()
                context = frame[max(0, vy):max(0, vy) + vh, max(0, vx):max(0, vx) + vw].copy()
                plate_in_context = (plate_box[0] - max(0, vx), plate_box[1] - max(0, vy), lw, lh)
                if getattr(pipe, "blur_privacy", True):
                    privacy.anonymize_crop(context, (max(0, vx), max(0, vy)), detections, keep=plate_in_context)
                cv2.rectangle(context, (plate_in_context[0], plate_in_context[1]),
                              (plate_in_context[0] + lw, plate_in_context[1] + lh), (0, 255, 0), 2)
                if ledger is not None and len(ledger.plate_crops) < MAX_PLATE_CROPS:
                    ledger.plate_crops.append((tight, context, stamp))

        if found and ledger is not None:             # cache position and text for the frames in between
            ledger.plate_text = "unidentified"
            ledger.plate_bbox = plate_box
        log.debug("[Plate] Track %s: %s", det.track_id,
                  f"plate found ({best_conf:.0%})" if found else "no plate detected")
        return Look(found=found, search_box=search_box)


JOBS = (HelmetJob(), PlateJob(), CabinJob())
