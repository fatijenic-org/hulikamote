"""
specialists.py - how the helmet / plate / cabin models are fed and how their answers are read.

The models were trained with Ultralytics: RGB images, letterboxed (aspect ratio kept, grey
padding) to the square size they were exported at, and duplicate boxes removed by NMS.
The app used to feed them BGR, stretched crops and no NMS; on held-out photos the plate was
found 7% of the time that way and 85% when fed like in training (measured with
`python training_lab/harvest.py probe-input`). This module is the one place that does it right.
"""
import cv2
import numpy as np

# Size the specialist models were exported at (read from the model when it says so)
INPUT_SIZE = 320
PAD_VALUE = 114          # Ultralytics' grey letterbox padding
NMS_IOU = 0.45

# Finding things (a plate only needs a box so it can be read) vs deciding a violation (needs a sure detection)
SEARCH_CONF = 0.1
CHECK_CONF = 0.4
# The helmet model is unsure on CCTV crops (it finds a rider box in about a third of looks): at 0.4 it caught 20% of the riders
# without a helmet on 24 HELMET Myanmar clips, at 0.25 it caught 28%, both with no false alarm. The ticket still needs the vote.
HELMET_CHECK_CONF = 0.25

# Helmet specialist class indices (must match datasets/helmet_specialist/data.yaml)
IDX_RIDER_WITH_HELMET = 0
IDX_RIDER_WITHOUT_HELMET = 1

# Plate specialist class index (must match datasets/plate_specialist/data.yaml)
IDX_LICENSE_PLATE = 0

# Cabin specialist class indices (must match datasets/cabin_specialist/data.yaml)
IDX_CLEAR_WINDOW = 0
IDX_TINTED_WINDOW = 1
IDX_SEATBELT = 2
IDX_DRIVER_PHONE = 3
IDX_SIDE_MIRROR = 4


def input_size(session) -> int:
    """The square input size of an ONNX session (falls back to INPUT_SIZE for dynamic / fake sessions)."""
    try:
        size = session.get_inputs()[0].shape[2]
        return int(size) if isinstance(size, int) and size > 0 else INPUT_SIZE
    except Exception:
        return INPUT_SIZE


def letterbox(crop: np.ndarray, size: int = INPUT_SIZE) -> tuple[np.ndarray, float, int, int]:
    """
    BGR crop -> (blob, scale, pad_x, pad_y). The blob is a (1, 3, size, size) float32 RGB tensor in [0, 1];
    scale / pad say how the crop sits inside it, so boxes can be mapped back.
    """
    h, w = crop.shape[:2]
    scale = min(size / w, size / h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    resized = cv2.resize(crop, (new_w, new_h), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((size, size, 3), PAD_VALUE, dtype=np.uint8)
    pad_x, pad_y = (size - new_w) // 2, (size - new_h) // 2
    canvas[pad_y:pad_y + new_h, pad_x:pad_x + new_w] = resized
    rgb = canvas[:, :, ::-1]                                   # OpenCV frames are BGR, the models want RGB
    blob = np.ascontiguousarray(rgb.astype(np.float32).transpose(2, 0, 1)[np.newaxis] / 255.0)
    return blob, scale, pad_x, pad_y


def nms(boxes_xyxy: np.ndarray, scores: np.ndarray, iou_threshold: float = NMS_IOU) -> list[int]:
    """Indices to keep: highest score first, dropping boxes that overlap a kept one by more than the threshold."""
    x1, y1, x2, y2 = boxes_xyxy[:, 0], boxes_xyxy[:, 1], boxes_xyxy[:, 2], boxes_xyxy[:, 3]
    areas = (x2 - x1) * (y2 - y1)
    order = scores.argsort()[::-1]
    keep: list[int] = []
    while order.size > 0:
        i = order[0]
        keep.append(int(i))
        rest = order[1:]
        inter = (np.maximum(0, np.minimum(x2[i], x2[rest]) - np.maximum(x1[i], x1[rest]))
                 * np.maximum(0, np.minimum(y2[i], y2[rest]) - np.maximum(y1[i], y1[rest])))
        iou = inter / (areas[i] + areas[rest] - inter + 1e-6)
        order = rest[iou <= iou_threshold]
    return keep


def detect(session, crop: np.ndarray, conf: float = SEARCH_CONF) -> list[dict]:
    """
    Run a specialist model on a BGR crop.
    Returns [{"class_id": int, "confidence": float, "box": [x, y, w, h]}] with the box in CROP pixels,
    best first, duplicates of the same class removed.
    """
    crop_h, crop_w = crop.shape[:2]
    if crop_h < 2 or crop_w < 2:
        return []
    size = input_size(session)
    blob, scale, pad_x, pad_y = letterbox(crop, size)
    output = session.run(None, {session.get_inputs()[0].name: blob})[0][0]
    preds = output.T if output.shape[0] < output.shape[1] else output      # -> (N, 4 + classes)
    if preds.shape[0] == 0:
        return []

    class_scores = preds[:, 4:]
    class_ids = class_scores.argmax(axis=1)
    confidences = class_scores[np.arange(len(class_ids)), class_ids]
    keep = confidences >= conf
    if not keep.any():
        return []
    cx, cy, bw, bh = (preds[keep, i] for i in range(4))
    class_ids, confidences = class_ids[keep], confidences[keep]

    # centre/size in the letterboxed input -> corners in crop pixels
    x1 = ((cx - bw / 2 - pad_x) / scale).clip(0, crop_w)
    y1 = ((cy - bh / 2 - pad_y) / scale).clip(0, crop_h)
    x2 = ((cx + bw / 2 - pad_x) / scale).clip(0, crop_w)
    y2 = ((cy + bh / 2 - pad_y) / scale).clip(0, crop_h)
    boxes = np.stack([x1, y1, x2, y2], axis=1)

    kept: list[int] = []
    for class_id in np.unique(class_ids):
        members = np.flatnonzero(class_ids == class_id)
        kept.extend(members[nms(boxes[members], confidences[members])])
    kept.sort(key=lambda i: -confidences[i])
    return [{
        "class_id": int(class_ids[i]),
        "confidence": float(confidences[i]),
        "box": [int(x1[i]), int(y1[i]), int(x2[i] - x1[i]), int(y2[i] - y1[i])],
    } for i in kept]
