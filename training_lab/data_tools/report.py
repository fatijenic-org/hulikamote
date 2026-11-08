"""
report.py - Write the human-readable dataset cards (datasets/<model>/DATASET_CARD.md) and datasets/CATALOG.md.

The numbers come from the curator's report.json, the sources from configs/datasets_manifest.yaml and the
SOURCE.json file every download leaves behind. Re-run after every fetch / curate:  python data.py report
"""
from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import yaml

from .common import DATASETS, DOWNLOADS, LAB, SPLITS

MANIFEST = LAB / "configs" / "datasets_manifest.yaml"
YOLO_MODELS = ["primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist"]
TRUST = {"A": "A (official / peer-reviewed host)", "B": "B (community, open licence, named author)",
         "C": "C (origin unclear or weak)",
         None: "own data (reviewed CCTV)"}
MIN_EVAL = 100          # fewer val / test pictures than this and a score is mostly noise
MIN_CLASS_EVAL = 50     # fewer val / test boxes of one class than this and that class's score is unreliable


def _manifest() -> dict:
    return yaml.safe_load(MANIFEST.read_text(encoding="utf-8")) or {}


def _source_info(model: str) -> dict[str, dict]:
    out = {}
    for src in (_manifest().get(model) or []):
        meta = {}
        f = DOWNLOADS / src["id"] / "SOURCE.json"
        if f.exists():
            meta = json.loads(f.read_text(encoding="utf-8"))
        out[src["id"]] = {**src, "url": meta.get("url"), "doi": meta.get("doi"), "retrieved": meta.get("retrieved")}
    return out


def _link(info: dict) -> str:
    if info.get("url"):
        return info["url"]
    if info.get("workspace"):
        return f"https://universe.roboflow.com/{info['workspace']}/{info['project']}"
    return ""


def _purpose(model: str) -> str:
    f = DATASETS / model / "data.yaml"
    if not f.exists():
        return ""
    lines = []
    for l in f.read_text(encoding="utf-8").splitlines():
        if l.startswith("#"):
            lines.append(l.lstrip("# ").rstrip())
        elif lines:
            break
    return "\n".join(lines)


def card(model: str) -> str:
    rep_path = DATASETS / model / "report.json"
    if not rep_path.exists():
        return f"# {model}\n\nNo curation report yet: run `python data.py curate --model {model} --apply`.\n"
    rep = json.loads(rep_path.read_text(encoding="utf-8"))
    info = _source_info(model)
    names = rep["classes"]
    lines = [f"# {model} - dataset card", "",
             f"Generated {date.today().isoformat()} by `python data.py report`. Do not edit by hand.", "",
             "```", _purpose(model), "```", "",
             "## Layout", "",
             f"`images/{{train,val,test}}/` + `labels/{{train,val,test}}/` (YOLO txt: `class cx cy w h`, normalised) + `data.yaml`. "
             f"{len(names)} classes: " + ", ".join(f"`{i}` {n}" for i, n in enumerate(names)) + ".", "",
             "## Contents", "",
             "| split | pictures | " + " | ".join(names) + " |", "|---|---|" + "---|" * len(names)]
    for s in SPLITS:
        per = rep["boxes_per_class"].get(s, {})
        lines.append(f"| {s} | {rep['images_per_split'].get(s, 0):,} | " + " | ".join(f"{per.get(n, 0):,}" for n in names) + " |")
    lb, ba = rep["long_side_px"], rep["box_area_share"]
    lines += ["", f"Longest side of a picture: min {lb['min']} / median {lb['median']} / max {lb['max']} px. "
                  f"A box covers (10th pct / median / 90th pct of the picture): {ba['p10']:.4f} / {ba['median']:.4f} / {ba['p90']:.4f}.", "",
              "## Where the pictures come from", "",
              "| source | train | val | test | licence | country | Philippine | trust | link |", "|---|---|---|---|---|---|---|---|---|"]
    total = ph = mixed = 0
    for sid, c in rep["per_source"].items():
        n = c.get("train", 0) + c.get("val", 0) + c.get("test", 0)
        if not n:
            continue
        meta = info.get(sid, {})
        flag = meta.get("ph")                                   # True = Philippine pictures, "mixed" = some are, False = no
        total += n
        ph += n if flag is True else 0
        mixed += n if flag == "mixed" else 0
        if sid == "legacy":
            lic, country, trust, link = "as committed in git (Roboflow exports)", "mixed", "B", ""
        elif sid.startswith("harvest"):
            lic, country, trust, link = "own CCTV frames", "Zamboanga", None, ""
        else:
            lic, country, trust, link = meta.get("license", "?"), meta.get("country") or "?", meta.get("trust"), _link(meta)
        lines.append(f"| {sid} | {c.get('train', 0):,} | {c.get('val', 0):,} | {c.get('test', 0):,} | {lic} | {country} | "
                     f"{'yes' if flag is True else 'mixed' if flag == 'mixed' else 'no'} | {TRUST.get(trust, trust)} | {link} |")
    pct = lambda n: (100 * n / total) if total else 0
    lines += ["", f"Philippine pictures: **{ph:,} of {total:,} ({pct(ph):.0f}%)**"
              + (f", plus {mixed:,} ({pct(mixed):.0f}%) from a source that mixes real Philippine photos with generic web pictures" if mixed else "")
              + ". Everything else is foreign imagery: fine for learning what the object looks like, not proof of field accuracy.", ""]

    warn = []
    train_boxes = rep["boxes_per_class"].get("train", {})
    for n in names:
        if not train_boxes.get(n):
            warn.append(f"No training boxes for class `{n}`: the trained model cannot detect it.")
    for s in ("val", "test"):
        if rep["images_per_split"].get(s, 0) < MIN_EVAL:
            warn.append(f"Only {rep['images_per_split'].get(s, 0)} pictures in `{s}`: scores on it are mostly noise (below {MIN_EVAL}).")
    for s in ("val", "test"):
        for n in names:
            k = rep["boxes_per_class"].get(s, {}).get(n, 0)
            if train_boxes.get(n) and k < MIN_CLASS_EVAL:
                warn.append(f"Class `{n}` has only {k} boxes in `{s}`: its score is unreliable (below {MIN_CLASS_EVAL}).")
    if total and (ph + mixed) / total < 0.25:
        warn.append("Less than a quarter of the pictures are Philippine: collect and review Zamboanga footage (`python harvest.py`).")
    for k, v in rep.get("issues_kept", {}).items():
        warn.append(f"{v} kept pictures flagged `{k}` (your own harvest__ files are never changed automatically).")
    for sid, meta in info.items():
        if meta.get("notes"):
            warn.append(f"`{sid}`: {meta['notes']}")
    lines += ["## Known limits", ""] + ([f"- {w}" for w in warn] or ["- none found"]) + [""]

    dropped = rep.get("dropped", {})
    twin = rep.get("eval_twins_before_first_cleaning") or rep.get("eval_pictures_with_train_twin", {})
    lines += ["## Cleaning log", "",
              f"Checked {rep['checked']:,} pictures, kept {rep['kept']:,}. Moved to `datasets/_quarantine/{model}/` (not deleted): "
              + (", ".join(f"{k} {v}" for k, v in dropped.items()) or "nothing")
              + f". Label files fixed: {rep['fixed_labels']}. Pictures re-saved as upright RGB JPEG: {rep['resaved_pictures']}.",
              "A picture that sits in both train and val/test keeps its val/test copy; the train copy is the one quarantined."]
    if twin.get("val") or twin.get("test"):
        about = "about " if twin.get("approx") else ""
        lines.append(f"**Before the first cleaning, {about}{twin.get('val', 0)} val and {about}{twin.get('test', 0)} test pictures had a "
                     "near-identical twin in train (same scene or video frame), so scores measured on this data earlier were optimistic.**")
    lines += ["", "## Rebuild", "",
              "```", "python scripts/fetch_datasets.py --model " + model, f"python data.py curate --model {model} --apply",
              "python data.py report", "```", ""]
    return "\n".join(lines)


def ocr_card() -> str:
    root = DATASETS / "plate_ocr"
    counts = {s: len(list((root / "images" / s).glob("*.jpg"))) if (root / "images" / s).exists() else 0 for s in SPLITS}
    by_src: dict[str, int] = {}
    for s in SPLITS:
        d = root / "images" / s
        if d.exists():
            for p in d.glob("*.jpg"):
                k = p.name.split("__", 1)[0] if "__" in p.name else "pop_quiz (own corrections)"
                by_src[k] = by_src.get(k, 0) + 1
    info = _source_info("plate_ocr")
    lines = ["# plate_ocr - dataset card", "", f"Generated {date.today().isoformat()} by `python data.py report`. Do not edit by hand.", "",
             "Plate crops with their text. `images/<split>/<name>.jpg` + `labels/<split>/<name>.txt` containing `0 TEXT` "
             "(upper-case letters and digits). The OCR trainer (`scripts/train_ocr.py`) reads `train`; `val` / `test` are for scoring.", "",
             "| split | pictures |", "|---|---|"] + [f"| {s} | {n} |" for s, n in counts.items()] + ["",
             "| source | pictures | licence | country | trust |", "|---|---|---|---|---|"]
    for k, n in by_src.items():
        meta = info.get(k, {})
        lines.append(f"| {k} | {n} | {meta.get('license', 'own data')} | {meta.get('country') or 'Philippines'} | "
                     f"{TRUST.get(meta.get('trust'), meta.get('trust'))} |")
    lines += ["", "## Known limits", "",
              "- No Philippine plate text yet except the Pop Quiz corrections; the EasyOCR pip package has no trainer, so these crops "
              "are for scoring and for a future trainer.",
              "- Most useful next: RodoSol-ALPR / UFPR-ALPR (request by e-mail, see the manifest `_manual` notes) and your own reviewed plates.", ""]
    return "\n".join(lines)


def catalog() -> str:
    man = _manifest()
    lines = ["# Dataset catalog", "", f"Generated {date.today().isoformat()} by `python data.py report`.", "",
             "One standard layout everywhere (`images/<split>`, `labels/<split>`, `data.yaml`). Per-model details are in "
             "`datasets/<model>/DATASET_CARD.md`; sources and licences in `configs/datasets_manifest.yaml`.", "",
             "| dataset | train | val | test | classes | Philippine share | sources |", "|---|---|---|---|---|---|---|"]
    for model in YOLO_MODELS:
        p = DATASETS / model / "report.json"
        if not p.exists():
            lines.append(f"| {model} | - | - | - | - | - | not curated yet |")
            continue
        rep = json.loads(p.read_text(encoding="utf-8"))
        info = _source_info(model)
        n = {s: rep["images_per_split"].get(s, 0) for s in SPLITS}
        tot = sum(sum(c.get(s, 0) for s in SPLITS) for c in rep["per_source"].values())
        ph = sum(sum(c.get(s, 0) for s in SPLITS) for sid, c in rep["per_source"].items() if info.get(sid, {}).get("ph") is True)
        mixed = sum(sum(c.get(s, 0) for s in SPLITS) for sid, c in rep["per_source"].items() if info.get(sid, {}).get("ph") == "mixed")
        srcs = [sid for sid, c in rep["per_source"].items() if sum(c.get(s, 0) for s in SPLITS)]
        lines.append(f"| {model} | {n['train']:,} | {n['val']:,} | {n['test']:,} | {len(rep['classes'])} | "
                     f"{(100 * ph / tot) if tot else 0:.0f}%" + (f" (+{100 * mixed / tot:.0f}% mixed)" if mixed else "") + f" | {', '.join(srcs)} |")
    for extra, what in (("plate_ocr", "plate crops + text"), ("reid", "own review decisions (real Zamboanga cars)"),
                        ("reid_public", "public vehicle identities (synthetic pre-training)"), ("sr_plates", "sharp plate crops for the enhancer")):
        d = DATASETS / extra
        if d.exists():
            n = sum(1 for _ in d.rglob("*.jpg"))
            lines.append(f"| {extra} | {n:,} pictures in total | | | {what} | | |")
    queued = [s["id"] for m, ss in man.items() if not m.startswith("_") for s in (ss or [])
              if s.get("source", "roboflow") == "roboflow" and not (DOWNLOADS / s["id"] / "data.yaml").exists()]
    lines += ["", "## Waiting for your action", ""]
    if queued:
        lines.append("Roboflow sets that are verified and listed in the manifest but not downloaded yet (set `ROBOFLOW_API_KEY`, then "
                     "`python scripts/fetch_datasets.py` and `python data.py curate --apply`):")
        lines += [f"- `{q}`" for q in queued]
    for k, v in (man.get("_manual") or {}).items():
        lines.append(f"- **{k}**: {v}")
    lines.append("")
    return "\n".join(lines)


def write_all(log=print) -> None:
    for model in YOLO_MODELS:
        if (DATASETS / model / "report.json").exists():
            (DATASETS / model / "DATASET_CARD.md").write_text(card(model), encoding="utf-8")
            log(f"  wrote datasets/{model}/DATASET_CARD.md")
    if (DATASETS / "plate_ocr").exists():
        (DATASETS / "plate_ocr" / "DATASET_CARD.md").write_text(ocr_card(), encoding="utf-8")
    (DATASETS / "CATALOG.md").write_text(catalog(), encoding="utf-8")
    log("  wrote datasets/CATALOG.md")
