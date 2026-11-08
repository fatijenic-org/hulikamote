"""
Does adding a colour fingerprint to the stock matcher find cars again more often?  (no training, nothing deployed)

    REID_SIZE=96x192 python training_lab/experiments/reid/reid_colour.py <output folder>

fingerprint = [ sqrt(w) * CNN fingerprint , sqrt(1 - w) * colour fingerprint ], both unit length, so the cosine similarity
DeepSORT computes on it is exactly  w * cos(CNN) + (1 - w) * cos(colour).  w = 1 is the stock matcher.
Colour fingerprint: hue x saturation histogram of the middle of the picture (borders hold road), in 3 horizontal bands,
square-rooted (Hellinger) and unit length; optionally with the mean colour of all photos subtracted ("centred").
Test: every clip alone (same road, other cars: how DeepSORT meets them), the same query/gallery rule as reid_cross_clip.py.
"""
import json
import os
import sys
import time
from pathlib import Path

os.environ.setdefault("REID_SIZE", "96x192")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import cv2  # noqa: E402
import numpy as np  # noqa: E402

import reid_cross_clip as rp  # noqa: E402
import reid_recipes as rr  # noqa: E402

WEIGHTS = (1.0, 0.9, 0.8, 0.7, 0.6, 0.5)
BANDS = 3


def colour(img_rgb):
    """img_rgb uint8 (H, W, 3) -> hue x saturation histogram per band, unit length (before centring)."""
    h, w = img_rgb.shape[:2]
    mid = img_rgb[int(h * 0.1):int(h * 0.9), int(w * 0.15):int(w * 0.85)]
    hsv = cv2.cvtColor(mid, cv2.COLOR_RGB2HSV)
    parts = []
    for b in range(BANDS):
        band = hsv[b * len(hsv) // BANDS:(b + 1) * len(hsv) // BANDS]
        hist = cv2.calcHist([band], [0, 1], None, [12, 6], [0, 180, 0, 256]).ravel()
        parts.append(np.sqrt(hist / max(hist.sum(), 1)))
    return np.concatenate(parts)


def unit(a):
    return a / np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-9)


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    logf = open(out / f"colour_{rp.INPUT_W}x{rp.INPUT_H}.log", "w", encoding="utf-8")

    def log(s=""):
        print(s, flush=True)
        logf.write(s + "\n"); logf.flush()

    clips = {k: rp.load_cars(v, cap=12) for k, v in rr.CLIPS.items()}
    stock = rp.stock_reid_net()
    plain = rp.features
    allc = np.stack([colour(im) for v in clips.values() for c in v for im in c["imgs"]])
    mean_col = allc.mean(0)
    log(f"input {rp.INPUT_W}x{rp.INPUT_H}, {len(allc)} photos, colour vector {allc.shape[1]} numbers")

    def make_features(w, centred):
        def features(net, imgs, bs=None):
            cnn = plain(net, imgs, bs)
            if w >= 1.0:
                return cnn
            col = np.stack([colour(im) for im in imgs])
            col = unit(col - mean_col) if centred else unit(col)
            return np.concatenate([np.sqrt(w) * cnn, np.sqrt(1 - w) * col], axis=1)
        return features

    results = {}
    for centred in (False, True):
        for w in WEIGHTS:
            if w >= 1.0 and centred:
                continue
            rp.features = make_features(w, centred)
            per = [rp.evaluate(stock, clips[k], n_query=6) for k in clips]
            rp.features = plain
            name = "stock (w=1)" if w >= 1.0 else f"w={w} {'centred' if centred else 'raw'}"
            results[name] = per
            log(f"{name:<18} " + "  ".join(f"{m} {np.mean([r[m] for r in per]) * 100:5.1f}" for m in ("rank1", "mAP", "AUC")) +
                "   rank-1 per clip: " + " ".join(f"{r['rank1'] * 100:.0f}" for r in per))
    (out / f"colour_{rp.INPUT_W}x{rp.INPUT_H}.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
