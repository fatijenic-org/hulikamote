"""
plate_reread.py - read a ticket's plate again, and read a plate the reviewer drew by hand.

Pure logic: finding the plate in a picture, the OCR and the image files are passed in, so this runs (and is tested)
without models. routers/forensic.py wires the real ones.
"""
import copy

import numpy as np

from engine.ticket_merge import revote

UNREAD = ("unidentified", "no_plate_found", "", "OCR_NOT_INSTALLED")
CROP_MARGIN = 0.10            # a little room around the plate box, like the video pass
MIN_BOX_PIXELS = 8            # a drawn box smaller than this is a slip of the mouse


def reread(ticket: dict, files: list[str], *, find_plates, read_plate, load_image, save_image, plate_format: str) -> tuple[dict, dict]:
    """
    Look for the plate again in the clean vehicle picture of each chosen frame (`files`; empty = every frame).
    Returns (new ticket, summary); the input is not mutated.

    find_plates(image) -> [{"box": [x, y, w, h], "confidence": f}], best first
    read_plate(crop)   -> (raw, cleaned, raw_image, enhanced_image, confidence)
    load_image(name)   -> image or None;  save_image(image) -> file name

    Earlier re-reads of the same frame are replaced, so reading twice does not count a frame twice. A plate the
    reviewer typed stays; the new vote is returned as `suggested` instead.
    """
    out = copy.deepcopy(ticket)
    metas = [m for m in out.get("evidence_meta", []) if not files or m["file"] in files]
    if not metas:
        raise ValueError("There are no photos to read")

    summary = {"checked": len(metas), "no_picture": 0, "no_plate": 0, "found": 0}
    results = out.setdefault("crop_results", [])
    paths = out.setdefault("plate_crop_paths", [])

    for meta in metas:
        source = meta.get("clean") or meta.get("car_crop")
        image = load_image(source) if source else None
        if image is None:
            summary["no_picture"] += 1
            continue
        plates = find_plates(image)
        if not plates:
            summary["no_plate"] += 1
            continue
        x, y, w, h = plates[0]["box"]
        mx, my = int(w * CROP_MARGIN), int(h * CROP_MARGIN)
        crop = image[max(0, y - my): y + h + my, max(0, x - mx): x + w + mx]
        if crop.size == 0:
            summary["no_plate"] += 1
            continue

        stale = {c["image_raw"] for c in results if c.get("reread_of") == meta["file"]}
        results[:] = [c for c in results if c["image_raw"] not in stale]
        paths[:] = [p for p in paths if p not in stale]

        raw, cleaned, _, enhanced, confidence = read_plate(crop)
        crop_file, enhanced_file = save_image(crop), save_image(enhanced)
        results.append({"image_raw": crop_file, "image_sr": enhanced_file, "image_context": None, "t": meta.get("t"),
                        "raw": raw, "cleaned": cleaned, "confidence": confidence, "reread_of": meta["file"]})
        paths.append(crop_file)
        meta["crop"] = crop_file
        meta["plate"] = cleaned if cleaned not in UNREAD else None
        summary["found"] += 1

    vote = copy.deepcopy(out)
    revote(vote, plate_format)
    summary["suggested"] = vote.get("plate_text", "unidentified")
    if out.get("plate_manual"):
        summary["kept_manual"] = True                         # their typed plate stands; the vote is only a suggestion
    else:
        out = vote
        summary["kept_manual"] = False
    return out, summary


def crop_box(image: np.ndarray, box: list[float]) -> np.ndarray:
    """
    The part of `image` inside a box drawn by hand. `box` is [x0, y0, x1, y1] as fractions (0..1) of the picture,
    in any corner order. Raises ValueError when the box is too small or outside the picture.
    """
    if len(box) != 4 or any(not (-0.01 <= v <= 1.01) for v in box):
        raise ValueError("The box is outside the picture")
    height, width = image.shape[:2]
    x0, x1 = sorted(int(round(min(max(v, 0.0), 1.0) * width)) for v in (box[0], box[2]))
    y0, y1 = sorted(int(round(min(max(v, 0.0), 1.0) * height)) for v in (box[1], box[3]))
    if x1 - x0 < MIN_BOX_PIXELS or y1 - y0 < MIN_BOX_PIXELS:
        raise ValueError("Draw a bigger box around the plate")
    return image[y0:y1, x0:x1]
