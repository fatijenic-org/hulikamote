"""
harvest.py - Turn the system's mistakes and confirmations into training data.

    python training_lab/harvest.py status            what is waiting, in plain words
    python training_lab/harvest.py gallery           refresh the snapshot the Forensic Analyzer's Harvest tab shows
    python training_lab/harvest.py collect           gather pictures from saved analyses
    python training_lab/harvest.py serve             open the check & label page in your browser
    python training_lab/harvest.py accept helmet_specialist   add finished pictures to the dataset
    python training_lab/harvest.py cut-plates        make "one vehicle" plate pictures from plate photos
    python training_lab/harvest.py protect <task_id> keep a benchmark clip out of the harvest
    python training_lab/harvest.py reid-fill         file every car nobody opened as one car (then fix the odd ones in the dashboard)
    python training_lab/harvest.py reid-export OUT   car folders -> train/ + val/ the ReID trainer reads (resized copy)

Runs at low priority, on the CPU, and never writes inside hulikamote_backend/, so it is safe to
use while the backend and a training are running. See training_lab/harvest_tool/README.md.
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harvest_tool.config import MODELS, Paths  # noqa: E402


def low_priority() -> None:
    """Stay out of the training's way."""
    try:
        import psutil
        proc = psutil.Process()
        if os.name == "nt":
            proc.nice(psutil.BELOW_NORMAL_PRIORITY_CLASS)
        else:
            proc.nice(10)
    except Exception:
        pass


def model_arg(value: str) -> str:
    aliases = {m["title"].lower(): key for key, m in MODELS.items()}
    key = aliases.get(value.lower(), value)
    if key not in MODELS:
        raise argparse.ArgumentTypeError(f"unknown model '{value}'. Choose: {', '.join(MODELS)}")
    return key


def publish(paths: Paths) -> None:
    """Refresh harvest_inbox/gallery.json (what the Forensic Analyzer's Harvest tab shows)."""
    try:
        from harvest_tool.accept import training_models
        from harvest_tool.gallery import write_gallery
        write_gallery(paths, busy=training_models())
    except Exception as e:                       # a derived file: never fail the command over it
        print(f"(could not refresh the Harvest tab's snapshot: {e})")


def cmd_gallery(args) -> int:
    from harvest_tool.accept import training_models
    from harvest_tool.gallery import write_gallery
    paths = Paths()
    out = write_gallery(paths, busy=training_models())
    import json
    data = json.loads(out.read_text(encoding="utf-8"))
    for c in data["categories"]:
        if c["kind"] == "detector":
            n = c["counts"]
            print(f"{c['title']:18} {n['total']:5} picture(s): {n['needs_eyes']} to check, {n['ready']} ready, "
                  f"{n['skipped']} skipped, {n['accepted']} added")
        else:
            print(f"{c['title']:18} {c['count']:5} {c['unit']} (need about {c['need']})")
    print(f"Wrote {out}")
    return 0


def cmd_status(args) -> int:
    from harvest_tool.web import HarvestApp
    board = HarvestApp(Paths()).board()
    publish(Paths())
    for m in board["models"]:
        c = m["counts"]
        tag = "  [TRAINING NOW]" if m["training"] else ""
        print(f"{m['title']:9} needs your eyes: {c['needs_eyes']:5}   ready: {c['ready']:5}   "
              f"added so far: {c['accepted']:5}   dataset: {m['dataset_images']:6}{tag}")
    for a in board["automatic"]:
        print(f"{a['title']:18} automatic: {a['count']} {a['unit']} (need about {a['need']})")
    if board["protected"]:
        print(f"{board['protected']} benchmark clip(s) protected from harvesting")
    return 0


def cmd_collect(args) -> int:
    from harvest_tool.collect import collect
    low_priority()
    s = collect(Paths(), task_ids=args.task or None, dry_run=args.dry_run)
    print(("DRY RUN - nothing written\n" if args.dry_run else "") +
          f"Looked at {s['tickets']} ticket(s) in {s['tasks']} analysis(es)"
          f" ({s['protected_tasks']} protected clip(s) skipped).")
    for model, b in s["added"].items():
        print(f"  {MODELS[model]['title']:8} +{b['check']} to check, +{b['label']} to label")
    for key, label in (("already_have", "already collected before"), ("no_picture", "tickets without a usable picture"),
                       ("unreadable", "unreadable pictures"), ("too_small", "vehicles too small to show a plate")):
        if s.get(key):
            print(f"  {s[key]} {label}")
    if s.get("upgraded"):
        print(f"  {s['upgraded']} waiting picture(s) got a model suggestion")
    if not args.dry_run:
        publish(Paths())
    return 0


def cmd_serve(args) -> int:
    from harvest_tool.web import serve
    serve(Paths(), port=args.port, open_browser=not args.no_open, idle_exit_min=args.idle_exit)
    return 0


def cmd_accept(args) -> int:
    from harvest_tool.accept import TrainingBusy, accept
    from harvest_tool.store import Store
    paths = Paths()
    try:
        r = accept(paths, Store(paths), args.model, dry_run=args.dry_run)
    except TrainingBusy as e:
        print(f"Not now: {e}")
        return 1
    verb = "Would add" if args.dry_run else "Added"
    print(f"{verb} {r['train'] + r['val']} of {r['ready']} ready picture(s): {r['train']} for training, "
          f"{r['val']} for checking ({r['empty_labels']} 'nothing here' examples).")
    if not args.dry_run:
        publish(paths)
    return 0


def cmd_cut(args) -> int:
    from harvest_tool.cut_plates import cut_plates
    low_priority()
    paths = Paths()
    if args.redo:
        from harvest_tool.store import Store
        n = Store(paths).forget("plate_specialist", "plate_photo_cut")
        print(f"Removed {n} earlier cut picture(s) that were not added to the dataset yet.")
    r = cut_plates(paths, limit=args.limit)
    print(f"Looked at {r['photos']} plate photo(s): {r['crops']} vehicle picture(s) made, "
          f"{r['no_vehicle']} photo(s) without a vehicle, {r['already_cut']} done before.")
    print("They are marked ready. Add them with: python training_lab/harvest.py accept plate_specialist")
    publish(paths)
    return 0


def cmd_probe(args) -> int:
    from harvest_tool.probe import run
    low_priority()
    run(Paths(), photos=args.photos)
    return 0


def cmd_reid_fill(args) -> int:
    from harvest_tool.cars import fill_cars
    from harvest_tool.sources import forensic_task_ids, load_protected
    from harvest_tool.store import Store
    paths = Paths()
    store = Store(paths)
    protected = load_protected(paths)
    tasks = args.task or [t for t in forensic_task_ids(paths) if t not in protected]
    total = 0
    for task in tasks:
        try:
            total += fill_cars(paths, store, task)["filled"]
        except KeyError:
            print(f"Skipped {task}: no report")
    print(f"Filed {total} car(s) of {len(tasks)} analysis(es) as one car each. Cars you opened before were left alone.")
    return 0


def cmd_reid_export(args) -> int:
    from harvest_tool.reid_export import reid_export
    try:
        r = reid_export(Paths(), Path(args.out), val_every=args.val_every, min_photos=args.min_photos,
                        include_public=args.public)
    except ValueError as e:
        print(f"Not now: {e}")
        return 1
    print(f"{r['cars']} cars: {r['train']} pictures for training, {r['val']} for checking, written to {r['out']}")
    print(f"Left out: {r['skipped_cars']} car(s) with too few pictures; {r['unreadable']} unreadable picture(s).")
    if r["cars"]:
        print(f"How to train on it: {Path(r['out']) / 'HOW_TO_TRAIN.txt'}")
    return 0


def cmd_protect(args) -> int:
    from harvest_tool.sources import set_protected
    now = set_protected(Paths(), args.task_id, on=not args.remove)
    print(f"{len(now)} protected clip(s): {', '.join(sorted(now)) or '-'}")
    return 0


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("gallery", help="refresh the snapshot the Forensic Analyzer's Harvest tab shows").set_defaults(
        fn=cmd_gallery)
    p = sub.add_parser("collect")
    p.add_argument("--task", action="append", help="only this analysis (task id); repeatable")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_collect)
    p = sub.add_parser("serve")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--no-open", action="store_true")
    p.add_argument("--idle-exit", type=float, default=0, metavar="MINUTES",
                   help="stop by itself after this many minutes without a request (the dashboard starts it this way)")
    p.set_defaults(fn=cmd_serve)
    p = sub.add_parser("accept")
    p.add_argument("model", type=model_arg)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_accept)
    p = sub.add_parser("cut-plates")
    p.add_argument("--limit", type=int, default=None, help="only the first N plate photos (quick trial)")
    p.add_argument("--redo", action="store_true", help="first remove earlier cut pictures not yet added to a dataset")
    p.set_defaults(fn=cmd_cut)
    p = sub.add_parser("probe-input", help="measure how the way images are fed to the plate model changes results")
    p.add_argument("--photos", type=int, default=160)
    p.set_defaults(fn=cmd_probe)
    p = sub.add_parser("reid-fill", help="file every car nobody opened as one car each (the tracker was right)")
    p.add_argument("--task", action="append", help="only this analysis (task id); repeatable")
    p.set_defaults(fn=cmd_reid_fill)
    p = sub.add_parser("reid-export", help="write the car folders as resized train/ + val/ for the ReID trainer")
    p.add_argument("out", help="a new, empty folder (never inside datasets/reid)")
    p.add_argument("--public", action="store_true", help="also include datasets/reid_public (public car identities)")
    p.add_argument("--val-every", type=int, default=5, help="every Nth picture of a car is for checking (default 5)")
    p.add_argument("--min-photos", type=int, default=4, help="leave out cars with fewer pictures (default 4)")
    p.set_defaults(fn=cmd_reid_export)
    p = sub.add_parser("protect")
    p.add_argument("task_id")
    p.add_argument("--remove", action="store_true")
    p.set_defaults(fn=cmd_protect)
    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
