"""
detect.py - Suggest boxes on a picture with one of our ONNX models (CPU only).

Used to pre-draw boxes so a human only has to confirm or fix them. It runs on the CPU on
purpose: the GPU belongs to the training. Input is prepared the way ultralytics trained the
models (aspect-preserving letterbox, RGB, 0-1); `rgb=False, letterbox=False` reproduces how
the live app currently feeds images (BGR, stretched) so the two can be compared.

Pure numpy + onnxruntime + cv2: importing this never loads torch.
"""
import ast
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np


@dataclass
class Det:
    cls: int
    conf: float
    x1: float   # pixels of the ORIGINAL image
    y1: float
    x2: float
    y2: float

    def yolo(self, width: int, height: int) -> list:
        """[cls, cx, cy, w, h] normalised to the original image."""
        return [self.cls, (self.x1 + self.x2) / 2 / width, (self.y1 + self.y2) / 2 / height,
                (self.x2 - self.x1) / width, (self.y2 - self.y1) / height]


def _iou(a: np.ndarray, rest: np.ndarray) -> np.ndarray:
    xx1 = np.maximum(a[0], rest[:, 0])
    yy1 = np.maximum(a[1], rest[:, 1])
    xx2 = np.minimum(a[2], rest[:, 2])
    yy2 = np.minimum(a[3], rest[:, 3])
    inter = np.maximum(0, xx2 - xx1) * np.maximum(0, yy2 - yy1)
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_r = (rest[:, 2] - rest[:, 0]) * (rest[:, 3] - rest[:, 1])
    return inter / (area_a + area_r - inter + 1e-9)


def nms(boxes: np.ndarray, scores: np.ndarray, iou: float) -> list[int]:
    """Plain greedy non-maximum suppression; returns kept indices, best first."""
    order = scores.argsort()[::-1]
    keep = []
    while order.size:
        i = order[0]
        keep.append(int(i))
        if order.size == 1:
            break
        rest = order[1:]
        order = rest[_iou(boxes[i], boxes[rest]) <= iou]
    return keep


def parse_names(raw: str | None) -> dict[int, str]:
    """ultralytics stores class names in the ONNX metadata as "{0: 'person', 1: 'bicycle', ...}"."""
    if not raw:
        return {}
    try:
        parsed = ast.literal_eval(raw)
        return {int(k): str(v) for k, v in parsed.items()}
    except Exception:
        return {}


class Detector:
    def __init__(self, session, size: int, names: dict[int, str] | None = None):
        self.session = session
        self.size = size
        self.names = names or {}
        self.input_name = session.get_inputs()[0].name

    @classmethod
    def load(cls, onnx_path: Path, threads: int = 2) -> "Detector":
        import onnxruntime as ort
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = 1
        session = ort.InferenceSession(str(onnx_path), opts, providers=["CPUExecutionProvider"])
        shape = session.get_inputs()[0].shape
        size = int(shape[2]) if isinstance(shape[2], int) else 640
        meta = session.get_modelmeta().custom_metadata_map or {}
        return cls(session, size, parse_names(meta.get("names")))

    # ── pre / post processing ──
    def prepare(self, bgr: np.ndarray, rgb: bool = True, letterbox: bool = True):
        """-> (blob, scale_x, scale_y, pad_x, pad_y)."""
        h, w = bgr.shape[:2]
        s = self.size
        if letterbox:
            r = min(s / w, s / h)
            nw, nh = max(1, round(w * r)), max(1, round(h * r))
            resized = cv2.resize(bgr, (nw, nh), interpolation=cv2.INTER_LINEAR)
            canvas = np.full((s, s, 3), 114, dtype=np.uint8)
            left, top = (s - nw) // 2, (s - nh) // 2
            canvas[top:top + nh, left:left + nw] = resized
            sx = sy = r
            pad_x, pad_y = left, top
        else:
            canvas = cv2.resize(bgr, (s, s), interpolation=cv2.INTER_LINEAR)
            sx, sy, pad_x, pad_y = s / w, s / h, 0, 0
        if rgb:
            canvas = canvas[:, :, ::-1]
        blob = np.ascontiguousarray(canvas.astype(np.float32).transpose(2, 0, 1)[None] / 255.0)
        return blob, sx, sy, pad_x, pad_y

    def detect(self, bgr: np.ndarray, conf: float = 0.25, iou: float = 0.5,
               rgb: bool = True, letterbox: bool = True) -> list[Det]:
        h, w = bgr.shape[:2]
        blob, sx, sy, pad_x, pad_y = self.prepare(bgr, rgb=rgb, letterbox=letterbox)
        out = np.asarray(self.session.run(None, {self.input_name: blob})[0])[0]
        if out.ndim != 2 or out.size == 0:
            return []

        if out.shape[1] == 6 and out.shape[0] != 6:
            # end-to-end export (NMS inside the model): [x1, y1, x2, y2, conf, cls] in input pixels
            keep = out[:, 4] >= conf
            rows = out[keep]
            xyxy, scores, classes = rows[:, :4], rows[:, 4], rows[:, 5].astype(int)
        else:
            preds = out.T if out.shape[0] < out.shape[1] else out        # -> (N, 4 + nc)
            scores_all = preds[:, 4:]
            classes = scores_all.argmax(axis=1)
            scores = scores_all[np.arange(len(classes)), classes]
            keep = scores >= conf
            if not keep.any():
                return []
            cx, cy, bw, bh = (preds[keep, i] for i in range(4))
            xyxy = np.stack([cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2], axis=1)
            scores, classes = scores[keep], classes[keep]
            kept: list[int] = []
            for c in np.unique(classes):                                   # NMS per class
                idx = np.flatnonzero(classes == c)
                kept += [int(idx[i]) for i in nms(xyxy[idx], scores[idx], iou)]
            xyxy, scores, classes = xyxy[kept], scores[kept], classes[kept]

        # back to ORIGINAL image pixels
        xyxy = xyxy.astype(np.float64)
        xyxy[:, [0, 2]] = ((xyxy[:, [0, 2]] - pad_x) / sx).clip(0, w)
        xyxy[:, [1, 3]] = ((xyxy[:, [1, 3]] - pad_y) / sy).clip(0, h)
        dets = [Det(int(c), float(s_), *map(float, b)) for b, s_, c in zip(xyxy, scores, classes)
                if b[2] - b[0] > 1 and b[3] - b[1] > 1]
        return sorted(dets, key=lambda d: -d.conf)
