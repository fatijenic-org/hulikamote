"""
Does ticket-photo data train a better car fingerprint than the stock ckpt.t7?  (reads the repo, writes nothing in it)

    python training_lab/experiments/reid/reid_cross_clip.py <output folder>      (about 20 minutes on a laptop GPU)

Data  : every ticketed car of the real analyses with >= 8 photos (tight car crops, RGB, 64x128 like the tracker feeds them).
        One analysis per clip, so the same physical car never appears twice (REID_CLIP_A / REID_CLIP_B pick them).
Test  : cars the model NEVER trained on. Each car's photos in time order: first half = queries, second half = gallery.
        "Find this car again among all the other cars": rank-1, mAP, AUC of same-car vs different-car similarity.
Models: stock ckpt.t7  vs  the same net fine-tuned on harvested cars (the repo's own recipe: classification over cars).
"""
import copy
import importlib.util
import json
import os
import random
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from scipy.stats import rankdata

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[3]
CLIP_A = os.environ.get("REID_CLIP_A", "1b4be534")     # the analysis ids (first 8 characters) to use, one per clip
CLIP_B = os.environ.get("REID_CLIP_B", "9db131ee")
sys.path.insert(0, str(REPO / "training_lab"))
from harvest_tool.config import Paths  # noqa: E402
from harvest_tool.sources import forensic_task_ids, tickets  # noqa: E402

spec = importlib.util.spec_from_file_location("reid_model", REPO / "hulikamote_backend/engine/deep_sort/deep/model.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
Net = mod.Net
CKPT = REPO / "hulikamote_backend/engine/deep_sort/deep/checkpoint/ckpt.t7"
DEV = "cuda" if torch.cuda.is_available() else "cpu"
paths = Paths()
MEAN = torch.tensor([0.485, 0.456, 0.406], device=DEV).view(1, 3, 1, 1)
STD = torch.tensor([0.229, 0.224, 0.225], device=DEV).view(1, 3, 1, 1)


INPUT_MODE = os.environ.get("REID_INPUT", "stretch")    # "stretch" = what the tracker does now; "pad" = keep the car's shape, gray bars
INPUT_W, INPUT_H = (int(v) for v in os.environ.get("REID_SIZE", "64x128").lower().split("x"))   # width x height fed to the network
ORIG_SIZES: list = []                                   # (height, width) of every photo as saved: does a bigger input have real detail?


def fit_to_net(im_rgb):
    """One RGB photo -> the INPUT_W x INPUT_H the network takes: stretched (as the tracker does now) or padded (shape kept)."""
    if INPUT_MODE != "pad":
        return cv2.resize(im_rgb, (INPUT_W, INPUT_H))
    h, w = im_rgb.shape[:2]
    scale = min(INPUT_W / w, INPUT_H / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    canvas = np.full((INPUT_H, INPUT_W, 3), 114, np.uint8)
    y, x = (INPUT_H - nh) // 2, (INPUT_W - nw) // 2
    canvas[y:y + nh, x:x + nw] = cv2.resize(im_rgb, (nw, nh))
    return canvas


def load_cars(prefix, min_photos=8, cap=24):
    task = next(t for t in forensic_task_ids(paths) if t.startswith(prefix))
    cars = []
    for tk in tickets(paths, task, max_frames=1, min_side=1):
        files, seen = [], set()
        for f in sorted(tk.crops, key=lambda f: (f.t is None, f.t or 0)):
            p = f.car_crop or f.image
            if p.name not in seen:
                seen.add(p.name)
                files.append(p)
        if len(files) < min_photos:
            continue
        if len(files) > cap:
            files = [files[i] for i in np.linspace(0, len(files) - 1, cap).round().astype(int)]
        imgs = []
        for p in files:
            im = cv2.imread(str(p))
            if im is not None:
                ORIG_SIZES.append(im.shape[:2])
                imgs.append(fit_to_net(cv2.cvtColor(im, cv2.COLOR_BGR2RGB)))
        if len(imgs) >= min_photos:
            cars.append({"id": f"{prefix}_{tk.uid}", "imgs": np.stack(imgs)})
    return cars


def to_batch(imgs_uint8):
    x = torch.from_numpy(imgs_uint8).to(DEV).permute(0, 3, 1, 2).float() / 255.0
    return (x - MEAN) / STD


@torch.no_grad()
def features(net, imgs_uint8, bs=None):
    bs = bs or max(16, 256 * (64 * 128) // (INPUT_W * INPUT_H))      # smaller batches for bigger pictures (laptop GPU memory)
    net.eval()
    out = []
    for i in range(0, len(imgs_uint8), bs):
        out.append(net(to_batch(imgs_uint8[i:i + bs])).cpu())
    return torch.cat(out).numpy()


def evaluate(net, cars, n_query=10):
    """Find the car again: queries from the first half of its photos, a gallery made of every car's second half."""
    qf, ql, gf, gl = [], [], [], []
    for k, c in enumerate(cars):
        f = features(net, c["imgs"])
        half = len(f) // 2
        first, second = f[:half], f[half:]
        pick = np.linspace(0, len(first) - 1, min(n_query, len(first))).round().astype(int)
        qf.append(first[pick]); ql += [k] * len(pick)
        gf.append(second); gl += [k] * len(second)
    Q, G = np.concatenate(qf), np.concatenate(gf)
    ql, gl = np.array(ql), np.array(gl)
    sims = Q @ G.T
    rank1 = float((gl[sims.argmax(1)] == ql).mean())
    aps = []
    for i in range(len(Q)):
        order = np.argsort(-sims[i])
        hit = (gl[order] == ql[i]).astype(float)
        if hit.sum() == 0:
            continue
        prec = np.cumsum(hit) / (np.arange(len(hit)) + 1)
        aps.append(float((prec * hit).sum() / hit.sum()))
    same = (gl[None, :] == ql[:, None])
    r = rankdata(sims.ravel())
    n_pos, n_neg = same.sum(), (~same).sum()
    auc = float((r[same.ravel()].sum() - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg))
    return {"rank1": rank1, "mAP": float(np.mean(aps)), "AUC": auc, "cars": len(cars), "queries": len(Q), "gallery": len(G)}


def any_size(net):
    """The stock pooling window is exactly the 64x128 feature map (8x4), i.e. a global average: the same maths for ANY input size."""
    if (INPUT_W, INPUT_H) != (64, 128):
        net.avgpool = torch.nn.AdaptiveAvgPool2d(1)
    return net


def make_net(k, init):
    net = any_size(Net(num_classes=k))
    if init == "stock":
        state = torch.load(CKPT, map_location="cpu", weights_only=False)["net_dict"]
        net.load_state_dict({n: v for n, v in state.items() if not n.startswith("classifier.")}, strict=False)
    return net.to(DEV)


def stock_reid_net():
    net = any_size(Net(reid=True))
    net.load_state_dict(torch.load(CKPT, map_location="cpu", weights_only=False)["net_dict"])
    return net.to(DEV)


def noisy_labels(cars, rng, share=0.3):
    """Pretend the tracker jumped: a share of the cars are filed as TWO cars (their photos cut at a random moment)."""
    out = []
    for c in cars:
        n = len(c["imgs"])
        if rng.random() < share and n >= 12:
            cut = rng.randint(int(n * 0.3), int(n * 0.7))
            out += [{"id": c["id"] + "_a", "imgs": c["imgs"][:cut]}, {"id": c["id"] + "_b", "imgs": c["imgs"][cut:]}]
        else:
            out.append(c)
    return out


def train(cars, epochs=10, seed=0, init="stock", bs=64, lr_backbone=0.01, lr_head=0.1, log=None):
    torch.manual_seed(seed); np.random.seed(seed); rng = random.Random(seed)
    X = np.concatenate([c["imgs"] for c in cars])
    y = np.concatenate([[k] * len(c["imgs"]) for k, c in enumerate(cars)])
    net = make_net(len(cars), init)
    head = [p for n, p in net.named_parameters() if n.startswith("classifier.")]
    body = [p for n, p in net.named_parameters() if not n.startswith("classifier.")]
    opt = torch.optim.SGD([{"params": body, "lr": lr_backbone if init == "stock" else lr_head}, {"params": head, "lr": lr_head}],
                          momentum=0.9, weight_decay=5e-4)
    sched = torch.optim.lr_scheduler.MultiStepLR(opt, [int(epochs * 0.6), int(epochs * 0.85)], 0.1)
    yt = torch.from_numpy(y).to(DEV)
    last = {}
    for ep in range(epochs):
        net.train()
        order = np.random.permutation(len(X))
        tot, correct, n = 0.0, 0, 0
        for i in range(0, len(order), bs):
            idx = order[i:i + bs]
            x = to_batch(X[idx])
            p = max(4, round(4 * INPUT_H / 128))                         # the repo's recipe: pad 4 (scaled with the size), random crop, random flip
            x = F.pad(x, (p, p, p, p))
            ox, oy = rng.randint(0, 2 * p), rng.randint(0, 2 * p)
            x = x[:, :, oy:oy + INPUT_H, ox:ox + INPUT_W]
            if rng.random() < 0.5:
                x = x.flip(3)
            out = net(x)
            loss = F.cross_entropy(out, yt[idx])
            opt.zero_grad(); loss.backward(); opt.step()
            tot += loss.item() * len(idx); n += len(idx); correct += (out.argmax(1) == yt[idx]).sum().item()
        sched.step()
        last = {"loss": tot / n, "acc": correct / n}
        if log and (ep == 0 or (ep + 1) % 5 == 0):
            log(f"      epoch {ep + 1:>2}: loss {last['loss']:.3f}  train accuracy {last['acc'] * 100:.1f}%")
    # keep the fingerprint part only
    reid = any_size(Net(reid=True))
    reid.load_state_dict({k: v for k, v in net.state_dict().items() if not k.startswith("classifier.")}, strict=False)
    return reid.to(DEV), last


def fmt(m):
    return f"rank-1 {m['rank1'] * 100:5.1f}%   mAP {m['mAP'] * 100:5.1f}%   AUC {m['AUC'] * 100:5.1f}%"


def mean_std(rows, key):
    v = [r[key] for r in rows]
    return f"{np.mean(v) * 100:5.1f}±{np.std(v) * 100:.1f}"


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    logf = open(out / "reid_proof.log", "w", encoding="utf-8")

    def log(s=""):
        print(s, flush=True)
        logf.write(s + "\n"); logf.flush()

    t0 = time.time()
    A = load_cars(CLIP_A)
    B = load_cars(CLIP_B)
    log(f"clip A: {len(A)} cars, {sum(len(c['imgs']) for c in A)} photos   clip B: {len(B)} cars, {sum(len(c['imgs']) for c in B)} photos   device {DEV}")
    stock = stock_reid_net()
    results = {}
    for name, train_set, test_set in (("train on clip B -> test on clip A (a different road)", B, A),
                                      ("train on clip A -> test on clip B (a different road)", A, B)):
        log(f"\n=== {name}   [{len(train_set)} training cars, {len(test_set)} unseen test cars]")
        base = evaluate(stock, test_set)
        log(f"  stock ckpt.t7 (what the app uses now)         {fmt(base)}")
        log(f"  (guessing would give rank-1 about {100 / len(test_set):.1f}%)")
        clean = []
        for s in (0, 1):
            net, last = train(train_set, seed=s, log=log if s == 0 else None)
            clean.append(evaluate(net, test_set))
            log(f"  fine-tuned on harvested cars, run {s + 1}          {fmt(clean[-1])}")
        net2, _ = train(noisy_labels(train_set, random.Random(100)), seed=0)
        noisy = evaluate(net2, test_set)
        log(f"  same, but 30% of the cars wrongly split in two {fmt(noisy)}")
        results[name] = {"stock": base, "clean": clean, "noisy": noisy}
        log(f"  seconds so far: {time.time() - t0:.0f}")
    log(f"\nseconds: {time.time() - t0:.0f}")
    (out / "reid_proof.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
