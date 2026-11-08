"""
organize_ready.py - give every folder under ready/ its <origin>__<violations> name, fix INDEX.csv, write BY_VIOLATION.md and README.md.

    python tools/benchmark/organize_ready.py              default: benchmarks/public_clips/ready (may be a link to the external drive)
    python tools/benchmark/organize_ready.py --dry-run    show what would be renamed

Safe to run again: renames only what still has an old name, rewrites INDEX.csv and the two markdown files from what is on disk.
"""
from __future__ import annotations

import argparse
import collections
import csv
import re
import sys
from pathlib import Path

import yaml

from ready_names import MANIFEST, ready

REPO = MANIFEST.parents[1]
sys.path.insert(0, str(REPO))
COLUMNS = ["source", "file", "seconds", "fps", "violations", "truth", "note"]


def minutes(seconds: float) -> str:
    return f"{seconds / 60:,.0f} min" if seconds >= 120 else f"{seconds:,.0f} s"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=REPO / "benchmarks" / "public_clips" / "ready")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    out = args.out.resolve()
    data = yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))
    sources = {s["id"]: s for s in data["sources"]}

    for sid in sources:                                                    # 1. old id folder -> <origin>__<violations>
        old, new = out / sid, out / ready(sid)
        if old.exists() and old != new:
            print(f"rename {old.name}  ->  {new.name}")
            if not args.dry_run:
                if new.exists():
                    for f in old.iterdir():
                        f.rename(new / f.name)
                    old.rmdir()
                else:
                    old.rename(new)
    if args.dry_run:
        return 0

    path = out / "INDEX.csv"                                               # 2. paths in INDEX.csv
    rows = list(csv.DictReader(path.open(encoding="utf-8"))) if path.exists() else []
    for r in rows:
        for col in ("file", "truth"):
            for sid in sources:
                if r[col].startswith(sid + "/"):
                    r[col] = ready(sid) + r[col][len(sid):]
    rows = [r for r in rows if (out / r["file"]).exists()]                 # drop rows whose clip is gone
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: r["file"]))

    from tools.benchmark.violations import NEEDS                           # 3. BY_VIOLATION.md
    keys = [n.key for n in NEEDS]
    per_folder: dict[str, list[dict]] = collections.defaultdict(list)
    for r in rows:
        per_folder[r["file"].split("/")[0]].append(r)
    by_violation: dict[str, dict[str, int]] = {k: {} for k in keys}
    for folder, rs in per_folder.items():
        for r in rs:
            for k in re.findall(r"[a-z_]+", r["violations"]):
                if k in by_violation:
                    by_violation[k][folder] = by_violation[k].get(folder, 0) + 1
    lines = ["# Benchmark clips by violation", "",
             "Folder names are `<origin>__<violations>`. Evaluation only: never train on these. See README.md for how each folder was made.", ""]
    for k in keys:
        folders = by_violation[k]
        lines.append(f"## {k}")
        if folders:
            lines += [f"- `{f}/`: {n} clips" for f, n in sorted(folders.items())]
        else:
            lines.append("- no public video exists: film your own (benchmarks/CLIP_CHECKLIST.md)")
        lines.append("")
    (out / "BY_VIOLATION.md").write_text("\n".join(lines), encoding="utf-8")

    by_id = {ready(s): s for s in sources}                                 # 4. README.md
    table = ["| Folder | Clips | Length | Violations | What it is |", "|---|---|---|---|---|"]
    for folder in sorted(per_folder):
        rs = per_folder[folder]
        secs = sum(float(r["seconds"] or 0) for r in rs)
        viol = sorted({k for r in rs for k in re.findall(r"[a-z_]+", r["violations"]) if k in by_violation})
        s = sources.get(by_id.get(folder, ""), {})
        what = (s.get("camera", "") + (". " + s["caveat"] if s.get("caveat") else "")).replace("|", "/")
        table.append(f"| `{folder}/` | {len(rs)} | {minutes(secs) if secs else 'varies'} | {', '.join(viol)} | {what} |")
    (out / "README.md").write_text(
        "# Ready clips (evaluation only: never train on these)\n\n"
        "Upload any `.mp4` in the dashboard (Forensic Analyzer). `INDEX.csv` lists every clip (source, violations it can test, truth file). "
        "`BY_VIOLATION.md` lists the folders per violation.\n\n"
        "Folder names are `<origin>__<violations>`. Photos of one fixed camera are stitched in time order (each held about 1.5 s, dissolved into the next): "
        "every photo is a separate spot check, not a tracked scene. Real frame sequences keep their own frame rate (10 fps for HELMET): no in-between frames are generated, because that made heads wobble. "
        "A `_truth.txt` next to a clip holds what the dataset says is in it, where the dataset has labels.\n\n"
        + "\n".join(table) + "\n\n"
        "Rebuild: `tools/benchmark/make_ready_clips.py`, `make_stitched_clips.py`, `pull_remaining.py`, then `organize_ready.py`. "
        "No public video exists for parking, loading, pickup passengers, riding outside the vehicle, distracted driving or missing mirrors: film them.\n",
        encoding="utf-8")
    print(f"{len(rows)} clips in {len(per_folder)} folders; wrote INDEX.csv, BY_VIOLATION.md, README.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
