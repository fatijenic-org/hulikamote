"""report.py - Turn scored clips into one comparable report (markdown + json), and compare two reports."""
from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

from .scoring import ClipResult, overall, summarize
from .violations import BY_KEY, KEYS


def pct(x) -> str:
    return "-" if x is None else f"{100 * x:.0f}%"


def build(label: str, results: list[ClipResult], defaults: dict, meta: dict) -> dict:
    summary = summarize(results, defaults)
    covered = {k for k, v in summary.items() if v["events"]}
    return {"label": label, "created": datetime.now().isoformat(timespec="seconds"), "meta": meta,
            "defaults": defaults, "summary": summary, "overall": overall(summary),
            "not_benchmarked": [k for k in KEYS if k not in covered],
            "clips": [{**asdict(r), "enabled": sorted(r.enabled)} for r in results]}


def markdown(rep: dict) -> str:
    s, o = rep["summary"], rep["overall"]
    minutes = sum((c["seconds"] or 0) for c in rep["clips"]) / 60
    lines = [f"# Benchmark report: {rep['label']}", "",
             f"Run {rep['created']} on {len(rep['clips'])} clips ({minutes:.1f} min of footage). "
             f"Models / overrides: {rep['meta'].get('overrides') or 'as configured in the backend'}.", "",
             "Caught = a ticket matched a real event. False alarm = a ticket with no real event. Missed = a real event with no ticket. "
             f"Pass target per violation: precision {pct(rep['defaults']['pass']['precision'])}, recall {pct(rep['defaults']['pass']['recall'])}, "
             f"at least {rep['defaults']['min_events']} real events.", "",
             "## Per violation", "",
             "| violation | clips | real events | Caught | False alarms | Missed | precision | recall | F1 | false alarms / min | LOAR | verdict |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for k in KEYS:
        if k not in s:
            continue
        v = s[k]
        exp = " (experimental)" if k == "signal_light" else ""
        fa = "-" if v["false_alarms_per_min"] is None else "%.2f" % v["false_alarms_per_min"]
        lines.append(f"| {k}{exp} | {v['clips']} | {v['events']} | {v['caught']} | {v['false_alarms']} | {v['missed']} | {pct(v['precision'])} | "
                     f"{pct(v['recall'])} | {pct(v['f1'])} | {fa} | {pct(v['plates']['loar'])} ({v['plates']['loar_correct']}/{v['plates']['loar_n']}) | {v['status']} |")
    lines += ["", "## Overall", "",
              f"Caught {o['caught']}, False alarms {o['false_alarms']}, Missed {o['missed']}. Precision {pct(o['precision'])}, recall {pct(o['recall'])}. "
              f"False alarm share (false alarms / tickets) {pct(o['false_alarm_share'])}. Miss rate (missed / real events) {pct(o['miss_rate'])}. "
              "", "**LOAR** (the thesis' strict record check: violation type, vehicle and plate string all right; only Caught events whose true plate is "
              f"written in the registry can be checked): {pct(o['loar'])} over {o['plates_checked']} events. "
              f"**Plate reading:** CER {pct(o['cer'])}, WER {pct(o['wer'])} on the same events. "
              f"Evidence picture, plate and vehicle all recorded correctly (every check that applies): {pct(o['logging_rate'])}.", ""]
    if rep["not_benchmarked"]:
        lines += ["## Not benchmarked yet (no real event in any clip)", "",
                  ", ".join(rep["not_benchmarked"]), "",
                  "What to film for each: `benchmarks/CLIP_CHECKLIST.md`.", ""]
    lines += ["## Clip by clip", ""]
    for c in rep["clips"]:
        lines += [f"### {c['clip_id']}", ""]
        if c.get("skipped"):
            lines.append(f"Not judged (not switched on in the settings): {', '.join(c['skipped'])}.")
        for title, key in (("Caught", "caught"), ("Missed", "missed"), ("False alarms", "false_alarms")):
            rows = c[key]
            if not rows:
                continue
            lines.append(f"**{title}**")
            for x in rows:
                when = (f"{x['start']:.1f}-{x['end']:.1f} s" if "start" in x else
                        ("no time" if x.get("ticket_start") is None else f"{x['ticket_start']:.1f}-{x['ticket_end']:.1f} s"))
                extra = ""
                if key == "caught":
                    bad = [n for n, v in x["checks"].items() if n != "ok" and v is False]
                    extra = f" (track {x['track']}; logging wrong: {', '.join(bad)})" if bad else f" (track {x['track']})"
                elif key == "false_alarms":
                    extra = f" (track {x['track']}, plate {x['plate'] or 'none'})"
                lines.append(f"- {x['violation']} at {when}{extra}")
            lines.append("")
    return "\n".join(lines)


def save(rep: dict, folder: Path) -> tuple[Path, Path]:
    folder.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in rep["label"]) or "run"
    j, m = folder / f"{stamp}_{name}.json", folder / f"{stamp}_{name}.md"
    j.write_text(json.dumps(rep, indent=2, default=list), encoding="utf-8")
    m.write_text(markdown(rep), encoding="utf-8")
    return j, m


def compare(a: dict, b: dict) -> str:
    """Two reports side by side (for example a baseline model and a fine-tuned one on the same clips)."""
    la, lb = a["label"], b["label"]
    lines = [f"# {la} vs {lb}", "", f"| violation | recall {la} | recall {lb} | change | precision {la} | precision {lb} | change | false alarms {la} | {lb} |",
             "|---|---|---|---|---|---|---|---|---|"]

    def delta(x, y):
        return "-" if x is None or y is None else f"{100 * (y - x):+.0f} pts"

    for k in KEYS:
        va, vb = a["summary"].get(k), b["summary"].get(k)
        if not va and not vb:
            continue
        va, vb = va or {}, vb or {}
        lines.append(f"| {k} | {pct(va.get('recall'))} | {pct(vb.get('recall'))} | {delta(va.get('recall'), vb.get('recall'))} | "
                     f"{pct(va.get('precision'))} | {pct(vb.get('precision'))} | {delta(va.get('precision'), vb.get('precision'))} | "
                     f"{va.get('false_alarms', '-')} | {vb.get('false_alarms', '-')} |")
    oa, ob = a["overall"], b["overall"]
    lines += ["", f"Overall recall {pct(oa['recall'])} -> {pct(ob['recall'])}, precision {pct(oa['precision'])} -> {pct(ob['precision'])}, "
                  f"logging {pct(oa['logging_rate'])} -> {pct(ob['logging_rate'])}.", ""]
    return "\n".join(lines)
