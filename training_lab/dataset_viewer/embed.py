"""
embed.py - turn small pictures into 512 numbers each, with the car matcher's network (the ReID net the tracker already uses).

It runs as its own process (so the viewer never loads torch) and needs nothing that is not already installed:

    python training_lab/dataset_viewer/embed.py --list in.json --out out.npy [--progress progress.json]

`in.json` is a list of picture paths; `out.npy` gets one row per picture (length 1 each, so rows compare with a dot product).
The same 96x192 stretch as the live tracker (engine/deep_sort/deep/feature_extractor.py) is used.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

LAB = Path(__file__).resolve().parents[1]
BACKEND = LAB.parent / "hulikamote_backend"
CKPT = BACKEND / "engine" / "deep_sort" / "deep" / "checkpoint" / "ckpt.t7"
SIZE = (192, 96)                         # (height, width), like the tracker
BATCH = 64
THREADS = 2                              # be polite: a backend may be analysing a video at the same time


def load_net(ckpt: Path = CKPT):
    import torch
    spec = importlib.util.spec_from_file_location("reid_model", BACKEND / "engine" / "deep_sort" / "deep" / "model.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    net = mod.Net(reid=True)
    net.load_state_dict(torch.load(ckpt, map_location="cpu", weights_only=False)["net_dict"])
    net.eval()
    return net


def embed(paths: list[str], progress=None, ckpt: Path = CKPT):
    import numpy as np
    import torch
    import torchvision.transforms as T
    from PIL import Image
    torch.set_num_threads(THREADS)
    net = load_net(ckpt)
    tf = T.Compose([T.Resize(SIZE), T.ToTensor(), T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])])
    out = []
    with torch.no_grad():
        for start in range(0, len(paths), BATCH):
            batch = []
            for p in paths[start:start + BATCH]:
                try:
                    with Image.open(p) as im:
                        batch.append(tf(im.convert("RGB")))
                except Exception:
                    batch.append(torch.zeros(3, *SIZE))          # an unreadable picture gets a neutral row, never a crash
            feats = net(torch.stack(batch))
            feats = feats / feats.norm(dim=1, keepdim=True).clamp_min(1e-8)
            out.append(feats.cpu().numpy().astype("float32"))
            if progress:
                progress(min(len(paths), start + BATCH), len(paths))
    return np.concatenate(out) if out else np.zeros((0, 512), dtype="float32")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--progress")
    args = ap.parse_args(argv)
    import numpy as np
    paths = json.loads(Path(args.list).read_text(encoding="utf-8"))

    def report(done, total):
        if args.progress:
            Path(args.progress).write_text(json.dumps({"done": done, "total": total}), encoding="utf-8")

    np.save(args.out, embed(paths, report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
