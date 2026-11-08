"""Start the Dataset Viewer:  python training_lab/dataset_viewer.py [--port 8766] [--no-open] [--idle-exit MINUTES]"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dataset_viewer.server import serve   # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8766)
    ap.add_argument("--no-open", action="store_true", help="do not open the browser")
    ap.add_argument("--idle-exit", type=float, default=0, metavar="MINUTES", help="stop after this many idle minutes")
    a = ap.parse_args()
    serve(a.port, not a.no_open, a.idle_exit)


if __name__ == "__main__":
    main()
