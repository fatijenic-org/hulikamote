"""
cut_plates.py - Make "one vehicle, plate somewhere on it" training pictures from the plate photos
you already have.

Why: the plate model learned from whole street photos, but the app hands it ONE vehicle cut
out of the frame, from any camera angle. This script finds the vehicles in each plate photo,
cuts each one out (with a small margin) and moves the existing plate box into the cut-out's
coordinates. Labels come from the original human-made boxes, never from a model, so the
results go straight to "ready" (you can still sample them in the check page).

Safety: reads datasets/plate_specialist (never writes there); the new pictures go to the inbox
and join the dataset through accept(). Crops of a TRAIN photo stay in train, crops of a VAL
photo stay in val, and TEST photos are never used, so the test set stays pristine.
"""
import cv2

from .accept import split_dirs
from .config import Paths, active_vehicle_onnx
from .detect import Detector
from .store import Item, Store, make_id, yolo_text

MODEL = "plate_specialist"
VEHICLE_NAMES = {"car", "motorcycle", "bus", "truck", "tricycle", "van", "jeepney"}
COCO_VEHICLES = {2, 3, 5, 7}         # car, motorcycle, bus, truck
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp"}


def vehicle_classes(detector: Detector) -> set[int]:
    if detector.names:
        return {i for i, n in detector.names.items() if n.lower() in VEHICLE_NAMES}
    return set(COCO_VEHICLES)


def read_plate_boxes(label_path) -> list[tuple[float, float, float, float]]:
    """Plate boxes (cx, cy, w, h normalised) from a YOLO label file (boxes or polygons)."""
    boxes = []
    if not label_path.exists():
        return boxes
    for line in label_path.read_text().splitlines():
        p = line.split()
        if len(p) < 5:
            continue
        v = [float(x) for x in p[1:]]
        if len(v) == 4:
            boxes.append((v[0], v[1], v[2], v[3]))
        else:
            xs, ys = v[0::2], v[1::2]
            boxes.append(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, max(xs) - min(xs), max(ys) - min(ys)))
    return boxes


def cut_one(image, plate_boxes, vehicles, margin: float = 0.08, min_side: int = 80):
    """-> [(crop, [[0, cx, cy, w, h]])] one per vehicle that holds at least one labelled plate."""
    H, W = image.shape[:2]
    out = []
    for v in vehicles:
        bw, bh = v.x2 - v.x1, v.y2 - v.y1
        x1, y1 = max(0, int(v.x1 - margin * bw)), max(0, int(v.y1 - margin * bh))
        x2, y2 = min(W, int(v.x2 + margin * bw)), min(H, int(v.y2 + margin * bh))
        if min(x2 - x1, y2 - y1) < min_side:
            continue
        labels = []
        for cx, cy, w, h in plate_boxes:
            pcx, pcy = cx * W, cy * H
            if not (x1 <= pcx <= x2 and y1 <= pcy <= y2):
                continue                                     # this plate belongs to another vehicle
            px1, py1 = max(x1, pcx - w * W / 2), max(y1, pcy - h * H / 2)
            px2, py2 = min(x2, pcx + w * W / 2), min(y2, pcy + h * H / 2)
            if px2 - px1 < 2 or py2 - py1 < 2:
                continue
            full = max(1e-9, (w * W) * (h * H))
            if (px2 - px1) * (py2 - py1) / full < 0.6:
                continue                       # mostly cut off by the crop edge: do not teach a fragment as a plate
            cw, ch = x2 - x1, y2 - y1
            labels.append([0, ((px1 + px2) / 2 - x1) / cw, ((py1 + py2) / 2 - y1) / ch,
                           (px2 - px1) / cw, (py2 - py1) / ch])
        if labels:
            out.append((image[y1:y2, x1:x2], labels))
    return out


def cut_plates(paths: Paths | None = None, store: Store | None = None, detector: Detector | None = None,
               limit: int | None = None, log=print) -> dict:
    paths, store = paths or Paths(), store
    store = store or Store(paths)
    if detector is None:
        onnx = active_vehicle_onnx(paths)
        if onnx is None:
            raise FileNotFoundError("No vehicle detector found in hulikamote_backend/models/")
        detector = Detector.load(onnx)
    classes = vehicle_classes(detector)
    result = {"photos": 0, "crops": 0, "no_vehicle": 0, "already_cut": 0}
    for split, hint in (("train", "train"), ("val", "val")):       # the test split is never used
        img_dir, lbl_dir = split_dirs(paths, MODEL, split)
        if not img_dir.exists():
            continue
        for photo in sorted(img_dir.iterdir()):
            if photo.suffix.lower() not in IMAGE_EXT or photo.name.startswith("harvest__"):
                continue
            if limit is not None and result["photos"] >= limit:
                return result
            plates = read_plate_boxes(lbl_dir / (photo.stem + ".txt"))
            if not plates:
                continue
            result["photos"] += 1
            if store.has_group(MODEL, f"photo:{photo.stem}"):
                result["already_cut"] += 1
                continue
            image = cv2.imread(str(photo))
            if image is None:
                continue
            vehicles = [d for d in detector.detect(image, conf=0.35) if d.cls in classes]
            crops = cut_one(image, plates, vehicles)
            if not crops:
                result["no_vehicle"] += 1
                store.add(Item(id=make_id("cut", hint, photo.stem, "none"), model=MODEL, state="skipped",
                               source="plate_photo_cut", reason="no vehicle found", group_id=f"photo:{photo.stem}",
                               split_hint=hint, created=0))
                continue
            for n, (crop, labels) in enumerate(crops):
                item_id = make_id("cut", hint, photo.stem, str(n))
                dst = store.image_path(MODEL, item_id)
                dst.parent.mkdir(parents=True, exist_ok=True)
                cv2.imwrite(str(dst), crop, [cv2.IMWRITE_JPEG_QUALITY, 92])
                store.add(Item(id=item_id, model=MODEL, state="ready", source="plate_photo_cut",
                               reason=f"Cut from {photo.name}", boxes=labels, suggested=False,
                               group_id=f"photo:{photo.stem}", split_hint=hint,
                               width=crop.shape[1], height=crop.shape[0], priority=6))
                lp = store.label_path(MODEL, item_id)
                lp.parent.mkdir(parents=True, exist_ok=True)
                lp.write_text(yolo_text(labels), encoding="utf-8")
                result["crops"] += 1
    return result
