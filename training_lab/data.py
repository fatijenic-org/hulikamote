"""
data.py - Dataset toolbox. Run from training_lab/ (downloading itself lives in scripts/fetch_datasets.py).

    python data.py curate [--model M] [--apply]     check + clean + standard layout. Dry run unless --apply.
    python data.py report                           write datasets/<model>/DATASET_CARD.md and datasets/CATALOG.md
    python data.py sheet --staged ID                picture grid with boxes drawn: one downloaded source, before merging
    python data.py sheet --model M [--source ID]    the same for what is already merged into a dataset
    python data.py sr-build                         sharp plate crops for the enhancer -> datasets/sr_plates/clean

Do not curate a model while it is training (the Training Studio / lab_tui show which runs are active).
"""
import argparse
import sys
from pathlib import Path

LAB = Path(__file__).resolve().parent
if str(LAB) not in sys.path:
    sys.path.insert(0, str(LAB))

from data_tools import curate, report, sheet, sr              # noqa: E402
from data_tools.common import DATASETS                        # noqa: E402

MODELS = ["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("curate", help="check and clean a dataset")
    c.add_argument("--model", choices=MODELS, help="only this dataset (default: all four)")
    c.add_argument("--apply", action="store_true", help="really change files (default is a dry run)")
    c.add_argument("--max-side", type=int, default=1280, help="longest side of re-saved public pictures")
    sub.add_parser("report", help="write dataset cards and the catalog")
    sub.add_parser("sr-build", help="sharp plate crops for the enhancer")
    s = sub.add_parser("sheet", help="contact sheet with boxes")
    s.add_argument("--staged", help="a downloaded source id (datasets/_downloads/<id>)")
    s.add_argument("--model", choices=MODELS)
    s.add_argument("--source", help="only pictures of this source id (with --model)")
    s.add_argument("--split", choices=["train", "val", "test"])
    s.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    if args.cmd == "curate":
        for model in ([args.model] if args.model else MODELS):
            curate.curate_model(model, apply=args.apply, max_side=args.max_side)
    elif args.cmd == "report":
        report.write_all()
    elif args.cmd == "sr-build":
        sr.build()
    elif args.cmd == "sheet":
        if args.staged:
            pairs, names = sheet.collect_staged(args.staged)
            out = DATASETS / "_sheets" / f"{args.staged}.png"
        elif args.model:
            pairs, names = sheet.collect_merged(args.model, args.source, args.split)
            out = DATASETS / "_sheets" / f"{args.model}_{args.source or 'all'}.png"
        else:
            ap.error("give --staged ID or --model M")
        print(f"{len(pairs):,} pictures; sheet -> {sheet.make_sheet(pairs, names, out, seed=args.seed)}")


if __name__ == "__main__":
    main()
