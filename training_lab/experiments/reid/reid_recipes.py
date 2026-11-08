"""
Which way of fine-tuning the car matcher is best?  Leave-one-clip-out, at the 96x192 input the tracker now uses.

    python training_lab/experiments/reid/reid_recipes.py <output folder>      (about 30 minutes on a laptop GPU)

Data  : the ticketed cars of FIVE different real clips (A, B and three more; other analyses in the folder are repeats of these,
        checked by comparing fingerprints: repeats score 0.97+, different cars 0.9 or less) = 108 cars. Optionally the public
        SimVeRi cars (synthetic, pre-training only, never in a test).
Test  : for each clip, train on the OTHER four clips and find the cars of the held-out clip again (a different road, cars never
        seen): rank-1, mAP, AUC like reid_cross_clip.py. The mean over the five clips is the score.
Recipes: stock | CE (the old recipe) | CE + triplet | SimVeRi first, then CE | SimVeRi first, then CE + triplet | CE + stronger augmentation
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
import cv2  # noqa: E402
import numpy as np  # noqa: E402
import torch  # noqa: E402
import torch.nn.functional as F  # noqa: E402

import reid_cross_clip as rp  # noqa: E402

CLIPS = {"A": "1b4be534", "B": "9db131ee", "C": "ac483b8b", "D": "e10b2564", "E": "bd0d2944"}
SIMVERI = rp.REPO / "training_lab" / "datasets" / "reid_public" / "images" / "simveri"
BATCH_P, BATCH_K = 12, 4            # triplet batches: 12 cars x 4 photos


def pooled(net, x):
    """The 512-number body output (before the classifier layers)."""
    x = net.layer4(net.layer3(net.layer2(net.layer1(net.conv(x)))))
    return net.avgpool(x).view(x.size(0), -1)


def triplet(feat, y, margin=0.3):
    """Batch-hard triplet loss: for every photo the farthest photo of the same car must be closer than the nearest other car."""
    f = F.normalize(feat, dim=1)
    d = (2 - 2 * f @ f.T).clamp_min(1e-12).sqrt()
    same = y[:, None] == y[None, :]
    eye = torch.eye(len(y), dtype=torch.bool, device=y.device)
    pos = d.masked_fill(~same | eye, 0).max(1).values
    neg = d.masked_fill(same, 1e9).min(1).values
    return F.relu(pos - neg + margin).mean()


def augment(x, strong, rng):
    """x: normalised batch (B,3,H,W). Shift + flip per photo; strong adds brightness/contrast jitter and random erasing."""
    H, W = x.shape[2:]
    p = max(4, round(4 * H / 128))
    xp = F.pad(x, (p, p, p, p))
    out = []
    for i in range(len(x)):
        oy, ox = rng.randint(0, 2 * p), rng.randint(0, 2 * p)
        im = xp[i, :, oy:oy + H, ox:ox + W]
        if rng.random() < 0.5:
            im = im.flip(2)
        if strong:
            im = im * rng.uniform(0.75, 1.25) + rng.uniform(-0.3, 0.3)
            if rng.random() < 0.3:
                eh, ew = rng.randint(H // 8, H // 3), rng.randint(W // 8, W // 3)
                ey, ex = rng.randint(0, H - eh), rng.randint(0, W - ew)
                im = im.clone()
                im[:, ey:ey + eh, ex:ex + ew] = 0
        out.append(im)
    return torch.stack(out)


def fit(cars, init=None, epochs=10, lr_body=0.01, lr_head=0.1, tri=0.0, strong=False, seed=0, bs=48):
    """Fine-tune on cars (classification over the cars, optionally + triplet). init = body weights to start from (default: stock).
    Returns (reid net, body state dict)."""
    torch.manual_seed(seed); np.random.seed(seed); rng = random.Random(seed)
    X = np.concatenate([c["imgs"] for c in cars])
    y = np.concatenate([[k] * len(c["imgs"]) for k, c in enumerate(cars)])
    by_car = [np.where(y == k)[0] for k in range(len(cars))]
    net = rp.make_net(len(cars), "stock")
    if init is not None:
        net.load_state_dict(init, strict=False)
    head = [p for n, p in net.named_parameters() if n.startswith("classifier.")]
    body = [p for n, p in net.named_parameters() if not n.startswith("classifier.")]
    opt = torch.optim.SGD([{"params": body, "lr": lr_body}, {"params": head, "lr": lr_head}], momentum=0.9, weight_decay=5e-4)
    sched = torch.optim.lr_scheduler.MultiStepLR(opt, [int(epochs * 0.6), int(epochs * 0.85)], 0.1)
    yt = torch.from_numpy(y).to(rp.DEV)
    steps = max(1, len(X) // bs)
    for ep in range(epochs):
        net.train()
        order = np.random.permutation(len(X))
        for s in range(steps):
            if tri > 0:     # P cars x K photos, so every photo has same-car partners
                cs = rng.sample(range(len(cars)), min(BATCH_P, len(cars)))
                idx = np.concatenate([np.random.choice(by_car[k], BATCH_K, replace=len(by_car[k]) < BATCH_K) for k in cs])
            else:
                idx = order[s * bs:(s + 1) * bs]
            x = augment(rp.to_batch(X[idx]), strong, rng)
            feat = pooled(net, x)
            loss = F.cross_entropy(net.classifier(feat), yt[idx])
            if tri > 0:
                loss = loss + tri * triplet(feat, yt[idx])
            opt.zero_grad(); loss.backward(); opt.step()
        sched.step()
    state = {k: v.detach().clone() for k, v in net.state_dict().items() if not k.startswith("classifier.")}
    reid = rp.any_size(rp.Net(reid=True))
    reid.load_state_dict(state, strict=False)
    return reid.to(rp.DEV), state


def load_simveri(max_ids=None):
    cars = []
    for d in sorted(p for p in SIMVERI.iterdir() if p.is_dir())[:max_ids]:
        imgs = [rp.fit_to_net(cv2.cvtColor(cv2.imread(str(f)), cv2.COLOR_BGR2RGB)) for f in sorted(d.glob("*.jpg"))]
        if len(imgs) >= 2:
            cars.append({"id": f"simveri_{d.name}", "imgs": np.stack(imgs)})
    return cars


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    logf = open(out / "recipes.log", "w", encoding="utf-8")

    def log(s=""):
        print(s, flush=True)
        logf.write(s + "\n"); logf.flush()

    t0 = time.time()
    clips = {k: rp.load_cars(v, cap=12) for k, v in CLIPS.items()}
    log(f"device {rp.DEV}  input {rp.INPUT_W}x{rp.INPUT_H}  " + "  ".join(f"{k}:{len(v)} cars" for k, v in clips.items()) +
        f"  = {sum(len(v) for v in clips.values())} cars, {sum(len(c['imgs']) for v in clips.values() for c in v)} photos")
    stock = rp.stock_reid_net()

    sim = load_simveri()
    log(f"SimVeRi: {len(sim)} synthetic cars, {sum(len(c['imgs']) for c in sim)} photos ({time.time() - t0:.0f}s)")
    pre_ce, st_ce = fit(sim, epochs=6, seed=1)
    log(f"pre-trained on SimVeRi, CE only ({time.time() - t0:.0f}s)")
    pre_tri, st_tri = fit(sim, epochs=6, tri=1.0, seed=1)
    log(f"pre-trained on SimVeRi, CE + triplet ({time.time() - t0:.0f}s)")
    del pre_ce, pre_tri

    recipes = {
        "CE (old recipe)":        dict(),
        "CE + triplet":           dict(tri=1.0),
        "CE + strong aug":        dict(strong=True),
        "SimVeRi, then CE":       dict(init=st_ce),
        "SimVeRi, then CE+tri":   dict(init=st_tri, tri=1.0),
    }
    rows = {"stock": {}, **{r: {} for r in recipes}}
    for test_clip in clips:
        test = clips[test_clip]
        train_cars = [c for k, v in clips.items() if k != test_clip for c in v]
        rows["stock"][test_clip] = rp.evaluate(stock, test, n_query=6)
        line = f"test clip {test_clip} ({len(test)} cars, trained on {len(train_cars)}): stock {rows['stock'][test_clip]['rank1'] * 100:.1f}"
        for name, kw in recipes.items():
            net, _ = fit(train_cars, seed=7, **kw)
            rows[name][test_clip] = rp.evaluate(net, test, n_query=6)
            line += f" | {name} {rows[name][test_clip]['rank1'] * 100:.1f}"
            del net
        log(line + f"   ({time.time() - t0:.0f}s)")

    log("\nmean over the five held-out clips (each clip counts once)")
    for name, per in rows.items():
        log(f"{name:<24} " + "  ".join(f"{m} {np.mean([r[m] for r in per.values()]) * 100:5.1f}" for m in ("rank1", "mAP", "AUC")))
    (out / "recipes.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    log(f"\nseconds: {time.time() - t0:.0f}")
