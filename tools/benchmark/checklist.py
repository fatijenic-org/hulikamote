"""checklist.py - benchmarks/CLIP_CHECKLIST.md: what to film or collect for each violation, and the camera spec (generated)."""
from __future__ import annotations

from datetime import date

from .violations import CAMERA_SPEC, NEEDS


def markdown(min_events: int = 10) -> str:
    lines = ["# Clip checklist", "", f"Generated {date.today().isoformat()} by `python -m tools.benchmark checklist`. Do not edit by hand: "
             "change `tools/benchmark/violations.py`.", "",
             "Every violation needs real clips with known answers before it can be scored. For each clip you note WHEN each violation "
             "happens (see `benchmarks/README.md`).", "",
             "**Safety first.** Use footage of violations that really happened, or stage them only on a closed or private road with "
             "permission. Never ask anyone to break traffic rules on a public road.", "",
             "## Camera and clip rules (all violations)", ""]
    lines += [f"- {c}" for c in CAMERA_SPEC]
    lines += ["", f"Aim for at least **{min_events} real events per violation** spread over at least 3 clips (different days or places), "
              "plus normal traffic in the same clips: the cars that do nothing wrong are what show false alarms. Add one clean clip "
              "(no violation at all) for every camera setup.", "",
              "## Per violation", "",
              "| violation | kind | a clip that SHOWS it | a clip that must NOT trigger it | camera view | wizard setup | limits |",
              "|---|---|---|---|---|---|---|"]
    for n in NEEDS:
        lines.append(f"| `{n.key}` | {n.kind} | {n.film} | {n.negative} | {n.view} | {n.setup} | {n.limit or '-'} |")
    lines += ["", "## Where to get clips", "",
              "- Your own camera, phone on a tripod, or footage from the barangay (with their permission and the Data Privacy Act in mind).",
              "- Clips you already analysed in the Forensic Analyzer: `python -m tools.benchmark adopt <task id> <clip id>` copies the video and "
              "the wizard settings into the registry for you.",
              "- Keep benchmark clips out of training: `python harvest.py protect <task id>` for clips that came from a forensic run.", ""]
    return "\n".join(lines)
