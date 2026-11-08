"""
python -m tools.benchmark <command>      (run from the repo root, with the backend's python)

    status                         which violations have clips and how many real events (no backend needed)
    validate                       problems in the registry (missing files, events that cannot be judged)
    adopt TASK_ID CLIP_ID [--video FILE]   take a forensic run you did in the dashboard into the registry (video + settings);
                                   --video = the original clip, needed when the run did not keep its own copy
    run [--label L] [--clip ID]... score the clips through the RUNNING backend; writes benchmarks/reports/
    compare A.json B.json          two reports side by side (for example baseline model vs fine-tuned)
    checklist                      rewrite benchmarks/CLIP_CHECKLIST.md
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import checklist, registry, report, runner, scoring, service
from .violations import BY_KEY, KEYS

ROOT = registry.ROOT
BENCH = registry.BENCH
FORENSIC = service.FORENSIC_DIR
EVIDENCE = service.EVIDENCE_DIR


def cmd_status(args) -> int:
    reg = registry.load(args.registry)
    print(f"{len(reg.clips)} clips in the registry. Needed: {reg.defaults['min_events']} real events per violation.\n")
    print(f"{'violation':24} {'events':>7} {'clips':>6}  state")
    for r in service.coverage(reg):
        print(f"{r['key']:24} {r['events']:>7} {r['clips']:>6}  {r['state']}")
    print("\nWhat to film: benchmarks/CLIP_CHECKLIST.md")
    return 0


def cmd_validate(args) -> int:
    probs = registry.problems(registry.load(args.registry))
    print("\n".join(probs) if probs else "registry is fine")
    return 1 if probs else 0


def cmd_adopt(args) -> int:
    """Copy a forensic run's video + wizard settings into benchmarks/ and print the tickets it made as event suggestions."""
    try:
        service.copy_run(args.task_id, args.clip_id, FORENSIC, BENCH, args.video)
    except service.ServiceError as e:
        print(e)
        return 1
    reg_file = BENCH / "registry.yaml"
    raw = registry.load_raw(reg_file)
    if any(str(c.get("id")) == args.clip_id for c in raw.get("clips") or []):
        print(f"Clip id {args.clip_id} is already in the registry; files were refreshed, entry kept.")
    else:
        service.upsert_clip(raw, args.clip_id, args.note, False, [])          # events: [] = fill in what REALLY happens
        registry.save_raw(raw, reg_file)
    print(f"Copied the video and settings. Registry entry added: {args.clip_id}")
    found = service.suggestions(args.task_id, FORENSIC)["suggestions"]
    if found:
        print("\nThe run flagged these. WATCH THE VIDEO and keep only what really happened (that is Caught); "
              "add anything it missed (Missed). Paste real ones under `events:`:\n")
        for s in found:
            span = f"start: {s['start']:.1f}, end: {s['end']:.1f}" if s["start"] is not None else "start: ?, end: ?"
            plate_part = f", plate: \"{s['plate']}\"" if s["plate"] else ""
            print(f"      - {{violation: {s['violation']}, {span}{plate_part}}}      # track {s['track']}")
    print(f"\nIf this clip must stay out of training: python training_lab/harvest.py protect {args.task_id}")
    return 0


def cmd_run(args) -> int:
    import requests
    reg = registry.load(args.registry)
    probs = [p for p in registry.problems(reg) if "no events and not marked clean" not in p]
    clips = [c for c in reg.clips if not args.clip or c.id in args.clip]
    if not clips:
        print("No clips to run. Add clips to benchmarks/registry.yaml (see benchmarks/README.md).")
        return 1
    blocking = [p for p in probs if any(p.startswith(c.id + ":") for c in clips)]
    if blocking:
        print("Fix these first:\n  " + "\n  ".join(blocking))
        return 1
    overrides = {}
    for kv in args.set or []:
        k, _, v = kv.partition("=")
        try:
            overrides[k] = json.loads(v)
        except ValueError:
            overrides[k] = v
    runner.check_backend(args.url, requests)
    results = []
    for c in clips:
        print(f"[{c.id}] {len(c.events)} real events" + (" (clean clip)" if c.clean else ""))
        meta = runner.probe(c.file)
        out = runner.run_clip(c, args.url, overrides)
        tol = reg.defaults["tolerance_s"]
        frame = (meta["width"], meta["height"]) if meta["width"] and meta["height"] else None
        res = scoring.score_clip(c, out["tickets"], tol, meta["seconds"], frame, EVIDENCE)
        print(f"    Caught {len(res.caught)}, False alarms {len(res.false_alarms)}, Missed {len(res.missed)} "
              f"(task {out['task_id'][:8]}, {out['wall_s']} s)")
        results.append(res)
    rep = report.build(args.label, results, reg.defaults, {"overrides": overrides, "backend": args.url})
    j, m = report.save(rep, Path(args.out) if args.out else BENCH / "reports")
    print("\n" + report.markdown(rep).split("## Clip by clip")[0])
    print(f"Saved: {m}\n       {j}")
    return 0


def cmd_compare(args) -> int:
    a, b = (json.loads(Path(p).read_text(encoding="utf-8")) for p in (args.a, args.b))
    print(report.compare(a, b))
    return 0


def cmd_checklist(args) -> int:
    reg = registry.load() if (BENCH / "registry.yaml").exists() else None
    out = BENCH / "CLIP_CHECKLIST.md"
    out.write_text(checklist.markdown(reg.defaults["min_events"] if reg else 10), encoding="utf-8")
    print(f"wrote {out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python -m tools.benchmark", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, fn in (("status", cmd_status), ("validate", cmd_validate)):
        sub.add_parser(name).set_defaults(fn=fn)
    sub.add_parser("checklist").set_defaults(fn=cmd_checklist)
    a = sub.add_parser("adopt")
    a.add_argument("task_id")
    a.add_argument("clip_id")
    a.add_argument("--note", default="")
    a.add_argument("--video", type=Path, help="the original clip, when the run did not keep its own copy of the video")
    a.set_defaults(fn=cmd_adopt)
    r = sub.add_parser("run")
    r.add_argument("--label", default="run")
    r.add_argument("--clip", action="append", help="only this clip id (repeatable)")
    r.add_argument("--url", default=runner.DEFAULT_URL)
    r.add_argument("--set", action="append", help="override a setting, e.g. --set primary_model=yolo11_primary.onnx")
    r.add_argument("--out", help="folder for the report (default benchmarks/reports)")
    r.set_defaults(fn=cmd_run)
    c = sub.add_parser("compare")
    c.add_argument("a")
    c.add_argument("b")
    c.set_defaults(fn=cmd_compare)
    for sp in sub.choices.values():
        sp.add_argument("--registry", type=Path, default=None, help="another registry.yaml (default benchmarks/registry.yaml)")
    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except (registry.RegistryError, runner.RunError) as e:
        print(f"ERROR: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
