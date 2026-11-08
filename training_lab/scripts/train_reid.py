"""
train_reid.py - Fine-tune the DeepSORT vehicle ReID ("fingerprint") model.

Data (made by the Forensic Analyzer review actions and the Harvest tab):
    datasets/reid/images/<task>/<identity>/*.jpg    one folder per physical car (photos in time order by file name)

The current model is the starting point. Only the body is changed: the deployed file keeps the original classifier layer so
DeepSORT loads it with no code change.

How it decides (an honest check): a quarter of the CARS are never trained on. Both the old and the new model are asked "find this
car again among the other cars": the earlier photos of each held-out car are the questions, its later photos are among the
answers. The new model is deployed ONLY if it finds the right car clearly more often (MIN_GAIN) on those unseen cars, and there
are enough cars to tell (MIN_TO_VERIFY), and it does not order the other cars worse (mAP). When it passes, the model is trained once more on ALL the cars for the same number of
epochs, and that is the file that is deployed. (Earlier versions judged on held-out photos of the cars they trained on, which a
model that only memorised them passes too.)

Usage:
    python scripts/train_reid.py --epochs 12            # check on unseen cars, write runs/reid/train_<time>/ckpt.t7
    python scripts/train_reid.py --epochs 12 --deploy   # ... and replace the live model if it passed
"""
import argparse
import csv
import importlib.util
import json
import random
import shutil
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from PIL import Image
from torch.utils.data import DataLoader, Dataset
import torchvision.transforms as T

ROOT = Path(__file__).resolve().parent.parent          # training_lab/
BACKEND = ROOT.parent / "hulikamote_backend"
CKPT_DIR = BACKEND / "engine" / "deep_sort" / "deep" / "checkpoint"
DEPLOYED = CKPT_DIR / "ckpt.t7"
ORIGINAL_BACKUP = CKPT_DIR / "ckpt_original.t7"

MIN_IDENTITIES = 5          # hard minimum to train at all
MIN_TO_VERIFY = 8           # fewer cars cannot be tested on cars it never saw: such a model is never deployed
RECOMMENDED_IDENTITIES = 30
HOLDOUT_SHARE = 0.25        # of the cars, never trained on in the check
MIN_GAIN = 0.02             # the new model must find the right car at least 2 points more often on those cars
MAX_PHOTOS = 40             # per car: a car seen for 50 frames must not drown one seen for 8
SIZE = (192, 96)            # (h, w) - same as the DeepSORT extractor (engine/deep_sort/deep/feature_extractor.py)
LR_BODY, LR_HEAD = 1e-4, 1e-3
# Two cars filed by DIFFERENT analyses whose average fingerprints are this alike AND whose closest two photos are this alike are one
# car filed twice (training_lab/experiments/reid: 94 % of re-filed cars caught, ~1 in 1,400 pairs of cars from other clips also meets
# it, and those are mostly the same parked vehicle seen in both clips).
REPEAT_MEAN, REPEAT_PHOTO = 0.95, 0.98
# Inside ONE analysis, two cars this alike (a little looser on the photos) are probably one car the tracker gave two numbers; a folder
# with at least MIXED_SHARE of its photos below MIXED_FAR (cosine to its own average) is probably two cars under one number.
SUSPECT_MEAN, SUSPECT_PHOTO = 0.95, 0.97
MIXED_FAR, MIXED_SHARE, MIXED_MIN_PHOTOS = 0.80, 0.25, 6


def load_net_class():
    """Import deep_sort's Net straight from its file (avoids importing the whole backend)."""
    path = BACKEND / "engine" / "deep_sort" / "deep" / "model.py"
    spec = importlib.util.spec_from_file_location("reid_model", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Net


def collect_identities(data_dir: Path) -> dict[str, list[Path]]:
    """identity key -> photos in time order. Only identities with at least 2 photos can teach anything."""
    ids = {}
    root = data_dir / "images"
    if not root.exists():
        return ids
    for task in sorted(p for p in root.iterdir() if p.is_dir()):
        for ident in sorted(p for p in task.iterdir() if p.is_dir()):
            files = sorted([f for f in ident.iterdir() if f.suffix.lower() in (".jpg", ".jpeg", ".png")])
            if len(files) >= 2:
                ids[f"{task.name}/{ident.name}"] = files
    return ids


def spread(files: list, n: int) -> list:
    """At most n of them, evenly spaced, in the same order."""
    if len(files) <= n:
        return list(files)
    return [files[i] for i in np.linspace(0, len(files) - 1, n).round().astype(int)]


def split_cars(keys: list[str], seed: int = 0, share: float = HOLDOUT_SHARE) -> tuple[list[str], list[str]]:
    """(cars to train on, cars to test on): whole cars, so the test is on cars the model never saw."""
    order = sorted(keys)
    random.Random(seed).shuffle(order)
    n_test = min(max(2, round(len(order) * share)), len(order) - 3)
    return order[n_test:], order[:n_test]


def training_items(ids: dict, keys: list[str]) -> list[tuple[Path, int]]:
    return [(f, label) for label, key in enumerate(keys) for f in spread(ids[key], MAX_PHOTOS)]


def probe_items(ids: dict, keys: list[str], per_car: int = 8, cap: int = 24):
    """(gallery, queries): a car's earlier photos are the questions, its later photos are among the answers."""
    gallery, queries = [], []
    for label, key in enumerate(keys):
        files = spread(ids[key], cap)
        half = max(1, len(files) // 2)
        first, second = files[:half], files[half:] or files[-1:]
        queries += [(f, label) for f in spread(first, per_car)]
        gallery += [(f, label) for f in second]
    return gallery, queries


def decide(before: float | None, after: float | None, cars: int, before_map: float | None = None,
           after_map: float | None = None) -> tuple[bool, str]:
    """May the new model replace the live one? -> (yes / no, the reason in plain words).
    It must find the right car clearly more often AND must not order the other answers worse (mAP), so one lucky guess on a
    handful of cars cannot get it through."""
    if cars < MIN_TO_VERIFY or before is None or after is None:
        return False, (f"Only {cars} cars: too few to test on cars it never saw (needs {MIN_TO_VERIFY}). "
                       "Not deployed, so an unchecked model never replaces yours.")
    if after < before + MIN_GAIN:
        return False, "Not clearly better on cars it never saw (needs +%d points)." % round(MIN_GAIN * 100)
    if before_map is not None and after_map is not None and after_map < before_map:
        return False, "It finds the right car a bit more often but orders the other cars worse: not clearly better."
    return True, "Better on cars it never saw."


class CarPhotos(Dataset):
    def __init__(self, items, transform):
        self.items, self.transform = items, transform

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        path, label = self.items[i]
        return self.transform(Image.open(path).convert("RGB")), label


NORM = T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
TRAIN_TF = T.Compose([
    T.Resize(SIZE), T.RandomHorizontalFlip(), T.ColorJitter(0.3, 0.3, 0.3),
    T.ToTensor(), NORM, T.RandomErasing(p=0.3),
])
EVAL_TF = T.Compose([T.Resize(SIZE), T.ToTensor(), NORM])


@torch.no_grad()
def embed(net, items, device):
    """L2-normalised fingerprints (reid mode) for a list of (path, label)."""
    net.eval()
    net.reid = True
    feats, labels = [], []
    for x, y in DataLoader(CarPhotos(items, EVAL_TF), batch_size=64):
        feats.append(net(x.to(device)).cpu())
        labels.append(y)
    net.reid = False
    return torch.cat(feats), torch.cat(labels)


def scores(net, gallery, queries, device) -> dict:
    """rank-1 (the closest answer is the same car) and mAP (how well ALL the answers are ordered): the second is steadier."""
    if not gallery or not queries:
        return {"rank1": 0.0, "map": 0.0}
    gf, gl = embed(net, gallery, device)
    qf, ql = embed(net, queries, device)
    sims = qf @ gf.T
    rank1 = float((gl[sims.argmax(dim=1)] == ql).float().mean())
    aps = []
    for i in range(len(qf)):
        hit = (gl[sims[i].argsort(descending=True)] == ql[i]).float()
        if hit.sum() > 0:
            aps.append(float(((hit.cumsum(0) / torch.arange(1, len(hit) + 1)) * hit).sum() / hit.sum()))
    return {"rank1": rank1, "map": float(np.mean(aps)) if aps else 0.0}


def top1(net, gallery, queries, device) -> float:
    """How often the closest gallery photo (cosine) is the same car as the query photo."""
    return scores(net, gallery, queries, device)["rank1"]


def fingerprints(ids: dict, net, device) -> dict:
    """car key -> the fingerprints (one row per photo, up to 12 spread over the car) of that car."""
    return {k: embed(net, [(p, 0) for p in spread(ids[k], 12)], device)[0] for k in sorted(ids)}


def alike(fa, fb) -> tuple[float, float]:
    """(how alike the two cars' AVERAGE fingerprints are, how alike their two closest photos are): both are cosines."""
    mean_a, mean_b = fa.mean(0), fb.mean(0)
    return float(mean_a @ mean_b / (mean_a.norm() * mean_b.norm())), float((fa @ fb.T).max())


def find_repeats(ids: dict, feats: dict) -> tuple[dict, list[tuple[str, str]]]:
    keys = sorted(ids)
    parent = {k: k for k in keys}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if a.split("/")[0] == b.split("/")[0]:
                continue
            mean_cos, best = alike(feats[a], feats[b])
            if mean_cos > REPEAT_MEAN and best > REPEAT_PHOTO:
                parent[find(a)] = find(b)
    groups: dict[str, list[str]] = {}
    for k in keys:
        groups.setdefault(find(k), []).append(k)
    kept, dropped = set(), []
    for members in groups.values():
        best = max(members, key=lambda k: (len(ids[k]), k))
        kept.add(best)
        dropped += [(m, best) for m in members if m != best]
    return {k: v for k, v in ids.items() if k in kept}, dropped


def drop_repeats(ids: dict, net, device) -> tuple[dict, list[tuple[str, str]]]:
    """Analyses of the same clip each file the same cars again. Left in, one car is several "cars" with different labels, and the
    check on unseen cars would meet a copy of the very car it trained on.
    -> (the cars with every repeat but one removed, [(dropped, kept)]). The one with most photos is kept.
    Cars of the SAME analysis are never merged: a person already decided about those (Same / Different)."""
    return find_repeats(ids, fingerprints(ids, net, device))


def scan_data(ids: dict, net, device) -> dict:
    """What a person should look at before training (the Datasets > Car matcher manager shows this):
    repeats (the same car filed by several analyses: the trainer uses it once), jumps (two cars of ONE analysis that look like one car:
    the tracker probably gave it a new number) and mixed folders (photos that do not look like the rest: probably two cars under one number)."""
    feats = fingerprints(ids, net, device)
    keys = sorted(ids)
    kept, dropped = find_repeats(ids, feats)
    used = sorted(kept)                                  # a repeat is not trained on, so only the cars that ARE need cleaning
    jumps = []
    for i, a in enumerate(used):
        for b in used[i + 1:]:
            if a.split("/")[0] != b.split("/")[0]:
                continue
            mean_cos, best = alike(feats[a], feats[b])
            if mean_cos > SUSPECT_MEAN and best > SUSPECT_PHOTO:
                jumps.append({"a": a, "b": b, "alike": round(mean_cos, 3)})
    mixed = []
    for k in used:
        f = feats[k]
        if len(f) < MIXED_MIN_PHOTOS:
            continue
        mean = f.mean(0)
        share = float(((f @ (mean / mean.norm())) < MIXED_FAR).float().mean())
        if share >= MIXED_SHARE:
            mixed.append({"car": k, "share": round(share, 2)})
    return {"ts": time.time(), "cars": len(ids), "photos": sum(len(v) for v in ids.values()),
            "used": len(kept), "photos_used": sum(len(v) for v in kept.values()),
            "repeats": [{"dropped": d, "kept": k} for d, k in dropped],
            "jumps": sorted(jumps, key=lambda j: -j["alike"]), "mixed": sorted(mixed, key=lambda m: -m["share"])}


def make_net(Net, original: dict, n_classes: int, device):
    """The current model's body with a fresh last layer for OUR cars."""
    net = Net(num_classes=n_classes, reid=False)
    net.load_state_dict({k: v for k, v in original.items() if not k.startswith("classifier.4")}, strict=False)
    return net.to(device)


def fit(Net, original, items, n_classes, epochs, batch, device, seed=0, after_epoch=None, tag=""):
    """Fine-tune on (path, label) items. after_epoch(net) -> a number shown next to each epoch (the check on unseen cars)."""
    torch.manual_seed(seed)
    net = make_net(Net, original, n_classes, device)
    head = list(net.classifier[4].parameters())
    head_ids = {id(p) for p in head}
    rest = [p for p in net.parameters() if id(p) not in head_ids]
    opt = torch.optim.Adam([{"params": rest, "lr": LR_BODY}, {"params": head, "lr": LR_HEAD}])
    loss_fn = nn.CrossEntropyLoss(label_smoothing=0.1)
    loader = DataLoader(CarPhotos(items, TRAIN_TF), batch_size=batch, shuffle=True, drop_last=len(items) > batch)
    rows = []
    for epoch in range(1, epochs + 1):
        net.train()
        total, correct, loss_sum = 0, 0, 0.0
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            if x.size(0) < 2:      # BatchNorm needs more than one sample
                continue
            opt.zero_grad()
            out = net(x)
            loss = loss_fn(out, y)
            loss.backward()
            opt.step()
            loss_sum += loss.item() * x.size(0)
            correct += (out.argmax(1) == y).sum().item()
            total += x.size(0)
        val = after_epoch(net) if after_epoch else None
        rows.append({"epoch": epoch, "loss": round(loss_sum / max(total, 1), 4), "train_acc": round(correct / max(total, 1), 4),
                     "val_top1": None if val is None else round(val, 4)})
        shown = "" if val is None else f" unseen_cars={val:.3f}"
        print(f"Epoch {epoch}/{epochs}{tag} loss={rows[-1]['loss']} train_acc={rows[-1]['train_acc']}{shown}", flush=True)
    return net, rows


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--data-dir", default=str(ROOT / "datasets" / "reid"))
    ap.add_argument("--out-dir", default=str(ROOT / "runs" / "reid" / f"train_{int(time.time())}"))
    ap.add_argument("--deploy", action="store_true", help="Replace the live model if the check on unseen cars passes")
    ap.add_argument("--ckpt", default=str(DEPLOYED), help="the model to start from and to beat (default: the live one)")
    ap.add_argument("--deploy-dir", default=str(CKPT_DIR), help=argparse.SUPPRESS)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--cpu", action="store_true", help="do not use the GPU")
    ap.add_argument("--scan", metavar="FILE", help="do not train: write what to look at in the data (repeats, jumps, mixed folders) as JSON")
    args = ap.parse_args(argv)

    data_dir, out_dir, stock_path = Path(args.data_dir), Path(args.out_dir), Path(args.ckpt)
    ids = collect_identities(data_dir)
    if args.scan:
        device = "cpu" if args.cpu or not torch.cuda.is_available() else "cuda"
        original = torch.load(stock_path, map_location="cpu", weights_only=False)["net_dict"]
        report = scan_data(ids, make_net(load_net_class(), original, 2, device), device) if ids else             {"ts": time.time(), "cars": 0, "photos": 0, "used": 0, "photos_used": 0, "repeats": [], "jumps": [], "mixed": []}
        Path(args.scan).write_text(json.dumps(report), encoding="utf-8")
        print(f"[Scan] {report['cars']} cars, {report['used']} different, {len(report['repeats'])} repeats, "
              f"{len(report['jumps'])} possible jumps, {len(report['mixed'])} mixed folders")
        return 0
    n_photos = sum(len(v) for v in ids.values())
    print(f"[Data] {len(ids)} cars with 2+ photos, {n_photos} photos total ({data_dir})")
    if len(ids) < MIN_IDENTITIES:
        print(f"[ERROR] Need at least {MIN_IDENTITIES} cars with 2+ photos each; found {len(ids)}. "
              f"Keep reviewing tickets (merge / separate) and answering Same car? in the Harvest tab to collect more.")
        sys.exit(1)
    device = "cpu" if args.cpu or not torch.cuda.is_available() else "cuda"
    Net = load_net_class()
    original = torch.load(stock_path, map_location="cpu", weights_only=False)["net_dict"]
    ids, repeats = drop_repeats(ids, make_net(Net, original, 2, device), device)
    n_photos = sum(len(v) for v in ids.values())
    if repeats:
        print(f"[Data] {len(repeats)} of those are the same car filed again by another analysis of the same clip: used once -> "
              f"{len(ids)} different cars, {n_photos} photos")
    if len(ids) < MIN_IDENTITIES:
        print(f"[ERROR] Need at least {MIN_IDENTITIES} different cars with 2+ photos each; found {len(ids)}. "
              f"Keep reviewing tickets (merge / separate) and answering Same car? in the Harvest tab to collect more.")
        sys.exit(1)
    if len(ids) < RECOMMENDED_IDENTITIES:
        print(f"[WARN] Only {len(ids)} cars; {RECOMMENDED_IDENTITIES}+ is recommended. Results may be weak.")
    keys = list(ids)

    before = after = before_map = after_map = None
    held_out = 0
    rows: list = []
    if len(keys) >= MIN_TO_VERIFY:
        train_keys, test_keys = split_cars(keys, args.seed)
        held_out = len(test_keys)
        gallery, queries = probe_items(ids, test_keys)
        print(f"[Check] {len(train_keys)} cars to train on, {held_out} cars it will never see to test on")
        base = scores(make_net(Net, original, len(train_keys), device), gallery, queries, device)
        before, before_map = base["rank1"], base["map"]
        print(f"[Baseline] the current model finds the right car {before * 100:.1f}% of the time on those unseen cars")
        check_net, rows = fit(Net, original, training_items(ids, train_keys), len(train_keys), args.epochs, args.batch, device,
                              args.seed, after_epoch=lambda n: top1(n, gallery, queries, device), tag=" (check)")
        final = scores(check_net, gallery, queries, device)   # the LAST epoch: no picking the best one on the test cars
        after, after_map = final["rank1"], final["map"]
        del check_net
    else:
        print(f"[WARN] {len(keys)} cars are too few to test on cars it never saw (needs {MIN_TO_VERIFY}): "
              "the model will be trained but not deployed.")

    print(f"[Final] training on all {len(keys)} cars for {args.epochs} epochs")
    final_net, final_rows = fit(Net, original, training_items(ids, keys), len(keys), args.epochs, args.batch, device, args.seed,
                                tag=" (final)")
    out_dir.mkdir(parents=True, exist_ok=True)
    # Deployable weights: fine-tuned body + the ORIGINAL classifier layers (DeepSORT expects that shape).
    state = {k: v.detach().cpu().clone() for k, v in final_net.state_dict().items()}
    deploy_sd = {k: v for k, v in state.items() if not k.startswith("classifier.")}
    deploy_sd.update({k: v for k, v in original.items() if k.startswith("classifier.")})
    new_ckpt = out_dir / "ckpt.t7"
    torch.save({"net_dict": deploy_sd, "acc": after, "epoch": args.epochs, "cars": len(keys)}, new_ckpt)

    with open(out_dir / "results.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["epoch", "loss", "train_acc", "val_top1"])
        w.writeheader()
        w.writerows(rows or final_rows)

    ok, reason = decide(before, after, len(keys), before_map, after_map)
    deployed = False
    if ok and args.deploy:
        deploy_dir = Path(args.deploy_dir)
        live = deploy_dir / "ckpt.t7"
        original_backup = deploy_dir / "ckpt_original.t7"
        if not original_backup.exists() and live.exists():
            shutil.copy2(live, original_backup)
        if live.exists():
            shutil.copy2(live, deploy_dir / f"ckpt_backup_{int(time.time())}.t7")
        shutil.copy2(new_ckpt, live)
        deployed = True

    summary = {"cars": len(keys), "photos": n_photos, "repeats_dropped": len(repeats), "held_out_cars": held_out, "before": None if before is None else round(before, 4),
               "after": None if after is None else round(after, 4), "best_epoch": args.epochs, "deployed": deployed,
               "passed": ok, "note": reason,
               "check": "cars it never saw", "before_map": None if before_map is None else round(before_map, 4),
               "after_map": None if after_map is None else round(after_map, 4)}
    (out_dir / "metrics.json").write_text(json.dumps(summary, indent=2))
    if before is not None:
        print(f"\n[Result] on {held_out} unseen cars: before={before * 100:.1f}%  after={after * 100:.1f}%")
    if deployed:
        print("[Deploy] New car-matching model is live. Restart the backend to load it.")
    elif ok:
        print("[Deploy] Passed the check but was not deployed (deploy was not requested). File: " + str(new_ckpt))
    else:
        print("[Deploy] NOT deployed: " + reason)
    return 0


if __name__ == "__main__":
    sys.exit(main())
