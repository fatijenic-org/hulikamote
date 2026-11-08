"""
Same cameras, NEW cars (the barangay case: you fine-tune on your own camera, then new cars drive by).
Both clips pooled, 70% of the cars train, 30% never seen are the test. Three random splits.
Two ways of fine-tuning: careful (backbone lr 0.01) and the repo train.py's own default (lr 0.1 everywhere).

    python training_lab/experiments/reid/reid_same_camera.py <output folder>     (about 25 minutes on a laptop GPU)
"""
import random
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reid_cross_clip as rp  # noqa: E402


def ms(rows, key):
    v = [r[key] * 100 for r in rows]
    return f"{np.mean(v):5.1f} ±{np.std(v):.1f}"


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    logf = open(out / "same_camera.log", "w", encoding="utf-8")

    def log(s=""):
        print(s, flush=True)
        logf.write(s + "\n")
        logf.flush()

    t0 = time.time()
    cars = rp.load_cars(rp.CLIP_A, cap=12) + rp.load_cars(rp.CLIP_B, cap=12)
    log(f"{len(cars)} cars, {sum(len(c['imgs']) for c in cars)} photos (12 per car at most), device {rp.DEV}")
    stock = rp.stock_reid_net()
    rows = {"stock": [], "careful": [], "script": []}
    for s in range(3):
        rng = random.Random(900 + s)
        idx = list(range(len(cars)))
        rng.shuffle(idx)
        cut = int(len(cars) * 0.7)
        tr, te = [cars[i] for i in idx[:cut]], [cars[i] for i in idx[cut:]]
        rows["stock"].append(rp.evaluate(stock, te, n_query=6))
        net, _ = rp.train(tr, epochs=10, seed=s, lr_backbone=0.01, lr_head=0.1)
        rows["careful"].append(rp.evaluate(net, te, n_query=6))
        net, _ = rp.train(tr, epochs=12, seed=s, lr_backbone=0.1, lr_head=0.1)
        rows["script"].append(rp.evaluate(net, te, n_query=6))
        log(f"split {s + 1}: {len(tr)} training cars, {len(te)} unseen test cars | rank-1  stock {rows['stock'][-1]['rank1'] * 100:.1f}  "
            f"careful {rows['careful'][-1]['rank1'] * 100:.1f}  script-default {rows['script'][-1]['rank1'] * 100:.1f}   ({time.time() - t0:.0f}s)")
    log("")
    for name, label in (("stock", "stock ckpt.t7 (the app now)"), ("careful", "fine-tuned, careful (lr 0.01)"), ("script", "fine-tuned, train.py defaults (lr 0.1)")):
        r = rows[name]
        log(f"{label:<38} rank-1 {ms(r, 'rank1')}%   mAP {ms(r, 'mAP')}%   AUC {ms(r, 'AUC')}%")
    log(f"\nseconds: {time.time() - t0:.0f}")
