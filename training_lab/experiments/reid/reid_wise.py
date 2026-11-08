"""
Can the car matcher get better on the cameras it was trained on WITHOUT getting worse on roads it never saw?

    python training_lab/experiments/reid/reid_wise.py <output folder>      (about 15 minutes on a laptop GPU)

reid_recipes.py showed: fine-tuning on other clips gives no gain on a new clip. Two cheap ideas to keep the stock matcher's
general skill while adding the new skill:
  blend    average the stock weights and the fine-tuned weights:  w = (1 - a) * stock + a * tuned   (a = 0.25 / 0.5 / 0.75)
  flip     the fingerprint of a photo = the mean of its fingerprint and its mirror image's (no training at all)
Two tests, both with cars the model never trained on:
  new clip   leave-one-clip-out over the 5 clips (a different road)
  same cams  70 % of all 108 cars train, 30 % test, 3 random splits (a camera it has seen, new cars drive by)
"""
import json
import os
import random
import sys
import time
from pathlib import Path

os.environ.setdefault("REID_SIZE", "96x192")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import numpy as np  # noqa: E402
import torch  # noqa: E402

import reid_cross_clip as rp  # noqa: E402
import reid_recipes as rr  # noqa: E402

ALPHAS = (0.25, 0.5, 0.75)


def blend(stock_sd, tuned_sd, a):
    out = {}
    for k, v in tuned_sd.items():
        if k.startswith("classifier."):
            out[k] = v
        elif v.dtype.is_floating_point:
            out[k] = (1 - a) * stock_sd[k].to(v.device) + a * v
        else:
            out[k] = v
    return out


def reid_net_from(sd):
    net = rp.any_size(rp.Net(reid=True))
    net.load_state_dict(sd, strict=False)
    return net.to(rp.DEV)


_plain_features = rp.features


def _flip_features(net, imgs_uint8, bs=None):
    f = _plain_features(net, imgs_uint8, bs) + _plain_features(net, imgs_uint8[:, :, ::-1].copy(), bs)
    return f / np.linalg.norm(f, axis=1, keepdims=True)


def evaluate(net, cars, flip=False):
    rp.features = _flip_features if flip else _plain_features
    try:
        return rp.evaluate(net, cars, n_query=6)
    finally:
        rp.features = _plain_features


def variants(stock, stock_sd, tuned):
    """name -> (net, flip)"""
    tuned_sd = {k: v.detach().clone() for k, v in tuned.state_dict().items()}
    v = {"stock": (stock, False), "stock+flip": (stock, True), "tuned": (tuned, False)}
    for a in ALPHAS:
        v[f"blend {a}"] = (reid_net_from(blend(stock_sd, tuned_sd, a)), False)
    v["blend 0.5+flip"] = (v["blend 0.5"][0], True)
    return v


def show(log, title, rows):
    log(f"\n{title}")
    for name, per in rows.items():
        log(f"{name:<16} " + "  ".join(f"{m} {np.mean([r[m] for r in per]) * 100:5.1f}" for m in ("rank1", "mAP", "AUC")) +
            "   rank-1 per test: " + " ".join(f"{r['rank1'] * 100:.0f}" for r in per))


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    logf = open(out / "wise.log", "w", encoding="utf-8")

    def log(s=""):
        print(s, flush=True)
        logf.write(s + "\n"); logf.flush()

    t0 = time.time()
    clips = {k: rp.load_cars(v, cap=12) for k, v in rr.CLIPS.items()}
    log(f"input {rp.INPUT_W}x{rp.INPUT_H}, " + ", ".join(f"{k}:{len(v)}" for k, v in clips.items()) + " cars")
    stock = rp.stock_reid_net()
    stock_sd = {k: v.detach().clone() for k, v in stock.state_dict().items()}

    loco = {}
    for test_clip, test in clips.items():
        tuned, _ = rr.fit([c for k, v in clips.items() if k != test_clip for c in v], tri=1.0, seed=7)
        for name, (net, flip) in variants(stock, stock_sd, tuned).items():
            loco.setdefault(name, []).append(evaluate(net, test, flip))
        log(f"new clip {test_clip} done ({time.time() - t0:.0f}s): " +
            "  ".join(f"{n} {r[-1]['rank1'] * 100:.0f}" for n, r in loco.items()))
        del tuned
    show(log, "A. NEW CLIP (leave-one-clip-out, mean of 5)", loco)

    allcars = [c for v in clips.values() for c in v]
    same = {}
    for s in range(3):
        rng = random.Random(900 + s)
        idx = list(range(len(allcars)))
        rng.shuffle(idx)
        cut = int(len(allcars) * 0.7)
        tr, te = [allcars[i] for i in idx[:cut]], [allcars[i] for i in idx[cut:]]
        tuned, _ = rr.fit(tr, tri=1.0, seed=s)
        for name, (net, flip) in variants(stock, stock_sd, tuned).items():
            same.setdefault(name, []).append(evaluate(net, te, flip))
        log(f"same cams split {s + 1} done ({time.time() - t0:.0f}s)")
        del tuned
    show(log, "B. SAME CAMERAS, NEW CARS (3 random splits, 75 train / 33 test cars)", same)
    (out / "wise.json").write_text(json.dumps({"new_clip": loco, "same_cameras": same}, indent=1), encoding="utf-8")
    log(f"\nseconds: {time.time() - t0:.0f}")
