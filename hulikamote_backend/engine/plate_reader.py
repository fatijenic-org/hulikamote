"""
plate_reader.py - find the plate in the photos of a ticket and read it, with the real models.

This is what the plate worker process runs (engine/plate_worker.py); engine/plate_service.py sends the work to it. It imports no web
framework, no database and no live-pipeline code, so the worker starts fast and stays small.
"""
import os
import time
from pathlib import Path

import cv2

from engine import plate_ocr, plate_reread, plate_vote, specialists

BACKEND_DIR = Path(__file__).resolve().parent.parent
MODELS_DIR = BACKEND_DIR / "models"
EVIDENCE_DIR = BACKEND_DIR / "snapshots" / "evidence"      # same folder as engine/pipeline.py EVIDENCE_DIR

_plate_sessions: dict = {}


def save_image(image) -> str:
    """Save a JPEG in the evidence folder and return its file name. The name carries this process's id, so a picture the live backend
    saves in the same millisecond can never get the same name."""
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = int(time.time() * 1000)
    filename = f"{stamp}_{os.getpid()}.jpg"
    n = 1
    while (EVIDENCE_DIR / filename).exists():
        filename = f"{stamp}_{os.getpid()}_{n}.jpg"
        n += 1
    cv2.imwrite(str(EVIDENCE_DIR / filename), image, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return filename


def plate_finder(config: dict):
    """A function: vehicle picture -> plate boxes [{"box": [x, y, w, h], "confidence": f}], best first, with the
    plate model the analysis used (or, in direct-OCR mode, the bumper area to read)."""
    if config.get("plate_method") == "direct_ocr":
        def bumper(image):
            h, w = image.shape[:2]
            top = int(h * 0.6)
            return [{"box": [0, top, w, h - top], "confidence": 1.0}]
        return bumper

    import onnxruntime as ort

    name = Path(config.get("plate_model") or "plate_specialist.onnx").name
    path = MODELS_DIR / name
    if not path.exists():
        path = next(iter(MODELS_DIR.rglob(name)), MODELS_DIR / "plate_specialist.onnx")
    if path not in _plate_sessions:
        options = ort.SessionOptions()
        if plate_ocr._threads():
            options.intra_op_num_threads = plate_ocr._threads()
        options.inter_op_num_threads = 1
        _plate_sessions[path] = ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])
    session = _plate_sessions[path]

    def find(image):
        return [d for d in specialists.detect(session, image, specialists.SEARCH_CONF) if d["class_id"] == specialists.IDX_LICENSE_PLATE]
    return find


def reread_ticket(ticket: dict, frames: list[str], config: dict, plate_format: str, written: list | None = None):
    """Runs plate_reread.reread with the real plate model, OCR and image files (slow). Every crop is read as seen and enhanced.
    `written` (optional) collects the names of the files made, for a clean-up. Returns (new ticket, summary)."""
    ocr_engine = config.get("ocr_engine", "easyocr")
    enhancement = config.get("enhancement", "lanczos")

    def read_both(crop):
        got = plate_ocr.extract_plate_reads(crop, plate_format, ocr_engine, enhancement)
        top = plate_vote.best_read(got["reads"], plate_format)
        return top["raw"], top["cleaned"], got["raw_crop"], got["enhanced_crop"], top["confidence"], got["reads"]

    def save(image):
        name = save_image(image)
        if written is not None:
            written.append(name)
        return name

    return plate_reread.reread(
        ticket, frames,
        find_plates=plate_finder(config),
        read_plate=read_both,
        load_image=lambda name: cv2.imread(str(EVIDENCE_DIR / Path(name).name)),
        save_image=save,
        plate_format=plate_format,
    )
