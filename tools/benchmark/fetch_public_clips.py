"""
fetch_public_clips.py - Download the public clips / datasets that other studies used to test traffic-violation systems.

The list (licences, caveats, what each one is good for) is benchmarks/public_sources.yaml. This is EVALUATION material: it goes to
benchmarks/public_clips/<id>/ (git-ignored) and must never be mixed into training_lab/datasets/, or the test stops being honest.

    python tools/benchmark/fetch_public_clips.py --list                  what exists: size class, host, violations
    python tools/benchmark/fetch_public_clips.py --coverage              what public test material exists for each of the 25 violations
    python tools/benchmark/fetch_public_clips.py --dry-run               look up sizes and licences, download nothing
    python tools/benchmark/fetch_public_clips.py                         the lean core set, sample files only (shows the plan, asks first)
    python tools/benchmark/fetch_public_clips.py --tier large --sample   also the large ones, but only their sample files
    python tools/benchmark/fetch_public_clips.py --only idiap_traffic_junction atg_pvd
    python tools/benchmark/fetch_public_clips.py --only ridesafe_400 --max-gb 40     the whole of one source (about 38 GB)

Run it with the backend's python (needs requests and PyYAML, installs nothing). It writes nothing inside hulikamote_backend/.
Downloads resume when interrupted: run the same command again. Sources that need an account (Kaggle, Roboflow, gated Hugging Face,
registration forms) are never bypassed: the script prints what to do by hand.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import zipfile
from datetime import date
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))                         # tools.benchmark.violations (the live list of violations)
sys.path.insert(0, str(REPO / "training_lab"))
from data_tools.sources import UA, download_file, extract_zip  # noqa: E402  resumable download + safe unzip, shared with the dataset fetcher

MANIFEST = REPO / "benchmarks" / "public_sources.yaml"
OUT = REPO / "benchmarks" / "public_clips"
TIERS = ["small", "medium", "large", "huge"]
DEFAULT_MAX_GB = 20.0


# --------------------------------------------------------------------------- the list

def load(path: Path = MANIFEST) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def select(sources: list[dict], only: list[str] | None = None, tier: str | None = None) -> list[dict]:
    """--only wins; then --tier (everything up to that size class); otherwise the sources marked default. Manual ones never download."""
    if only:
        by_id = {s["id"]: s for s in sources}
        unknown = [i for i in only if i not in by_id]
        if unknown:
            raise SystemExit(f"Unknown source id: {', '.join(unknown)}  (see --list)")
        return [by_id[i] for i in only]
    chosen = []
    for s in sources:
        if s["host"] == "manual":
            continue
        if tier is not None:
            if TIERS.index(s["tier"]) <= TIERS.index(tier):
                chosen.append(s)
        elif s.get("default"):
            chosen.append(s)
    return chosen


def pick(paths: list[str], patterns: list[str] | None) -> list[str]:
    """Keep the paths that match one of the glob patterns (all of them when there are none)."""
    if not patterns:
        return list(paths)
    return [p for p in paths if any(fnmatch.fnmatch(p, pat) for pat in patterns)]


# --------------------------------------------------------------------------- looking things up

def _get_json(url: str):
    import requests
    r = requests.get(url, headers=UA, timeout=60)
    r.raise_for_status()
    return r.json()


def _head_size(url: str) -> int | None:
    """Size of a file from its response headers (a streamed GET that is closed at once: some hosts refuse HEAD)."""
    import requests
    try:
        with requests.get(url, headers=UA, timeout=30, stream=True, allow_redirects=True) as r:
            return int(r.headers["Content-Length"]) if r.ok and "Content-Length" in r.headers else None
    except Exception:
        return None


def hf_listing(repo: str) -> tuple[list[dict], str | None]:
    """Files of a public Hugging Face dataset repo (path, real size) and its licence. A gated repo raises PermissionError."""
    info = _get_json(f"https://huggingface.co/api/datasets/{repo}")
    if info.get("gated"):
        raise PermissionError(f"{repo} is gated: log in on huggingface.co, accept its terms and download it with your own account")
    tree = _get_json(f"https://huggingface.co/api/datasets/{repo}/tree/main?recursive=true")
    files = [{"path": t["path"], "size": (t.get("lfs") or {}).get("size") or t.get("size")}
             for t in tree if t.get("type") == "file" and t["path"] != ".gitattributes"]
    return files, (info.get("cardData") or {}).get("license")


def osf_listing(node: str) -> tuple[list[dict], str | None]:
    """Files of a public OSF project (path, size, download link) and its licence name."""
    base = "https://api.osf.io/v2"
    try:
        info = _get_json(f"{base}/nodes/{node}/?embed=license")
        license_name = ((((info["data"].get("embeds") or {}).get("license") or {}).get("data") or {}).get("attributes") or {}).get("name")
    except Exception:
        license_name = None
    files, folders = [], [f"{base}/nodes/{node}/files/osfstorage/"]
    while folders:
        url = folders.pop()
        while url:
            page = _get_json(url)
            for item in page.get("data", []):
                a = item["attributes"]
                if a["kind"] == "folder":
                    folders.append(item["relationships"]["files"]["links"]["related"]["href"])
                else:
                    files.append({"path": a["materialized_path"].lstrip("/"), "size": a.get("size"), "url": item["links"]["download"]})
            url = (page.get("links") or {}).get("next")
    return files, license_name


def plan(src: dict, sample: bool = False) -> dict:
    """What a download would fetch: {'files': [{name, url, size|None}], 'license': str|None}. Looks things up, downloads nothing."""
    host, license_found = src["host"], None
    if host == "http":
        files = [{"name": f["name"], "url": f["url"], "size": _head_size(f["url"])} for f in src["files"]]
    elif host == "mendeley":
        version = src.get("version", 1)
        url = f"https://data.mendeley.com/public-api/zip/{src['dataset']}/download/{version}"
        files = [{"name": f"{src['dataset']}_v{version}.zip", "url": url, "size": _head_size(url)}]
    elif host == "zenodo":
        rec = _get_json(f"https://zenodo.org/api/records/{src['record']}")
        files = [{"name": f["key"], "url": f["links"]["self"], "size": f.get("size")} for f in rec.get("files", [])]
        license_found = ((rec.get("metadata") or {}).get("license") or {}).get("id")
    elif host == "figshare":
        art = _get_json(f"https://api.figshare.com/v2/articles/{src['article']}")
        files = [{"name": f["name"], "url": f["download_url"], "size": f.get("size")} for f in art.get("files", [])]
        license_found = (art.get("license") or {}).get("name")
    elif host in ("hf", "osf"):
        if host == "hf":
            listing, license_found = hf_listing(src["repo"])
            for f in listing:
                f["url"] = f"https://huggingface.co/datasets/{src['repo']}/resolve/main/{f['path']}"
        else:
            listing, license_found = osf_listing(src["node"])
        patterns = src.get("sample_include") if sample and src.get("sample_include") else src.get("include")
        wanted = set(pick([f["path"] for f in listing], patterns))
        files = [{"name": f["path"], "size": f["size"], "url": f["url"]} for f in listing if f["path"] in wanted]
    else:                                                     # kaggle / roboflow: fetched by their own tools at download time
        files = []
    return {"files": files, "license": license_found}


# --------------------------------------------------------------------------- downloading

def fetch_kaggle(src: dict, out_dir: Path) -> bool:
    exe, have_login = shutil.which("kaggle"), (Path.home() / ".kaggle" / "kaggle.json").exists() or os.environ.get("KAGGLE_USERNAME")
    if not exe or not have_login:
        print(f"    needs your Kaggle login: open {src['page']}, download it, and put the files in {out_dir}\n"
              f"    (or in a separate Python, not the backend venv: pip install kaggle, save your token to ~/.kaggle/kaggle.json, rerun)")
        return False
    subprocess.run([exe, "datasets", "download", "-d", src["slug"], "-p", str(out_dir), "--unzip"], check=True)
    return True


def fetch_roboflow(src: dict, out_dir: Path) -> bool:
    key = os.environ.get("ROBOFLOW_API_KEY")
    if not key:
        print("    needs your own Roboflow key: set ROBOFLOW_API_KEY in this terminal and rerun this source")
        return False
    try:
        from roboflow import Roboflow
    except ImportError:
        print("    the roboflow package is not installed: install it in a separate Python (NOT the backend venv, it restarts the backend)")
        return False
    project = Roboflow(api_key=key).workspace(src["workspace"]).project(src["project"])
    project.version(max(int(v.version) for v in project.versions())).download("coco", location=str(out_dir), overwrite=True)
    return True


def fetch(src: dict, files: list[dict], out_dir: Path) -> bool:
    """Download one source into out_dir. Returns False when something has to be done by hand."""
    if src["host"] == "manual":
        print(f"    by hand: {src['how']}")
        return False
    out_dir.mkdir(parents=True, exist_ok=True)
    if src["host"] == "kaggle":
        return fetch_kaggle(src, out_dir)
    if src["host"] == "roboflow":
        return fetch_roboflow(src, out_dir)
    for f in files:
        dest = out_dir / f["name"]
        download_file(f["url"], dest, expected_size=f.get("size"))
        if src.get("extract") and zipfile.is_zipfile(dest):
            print(f"    unzipping {dest.name} ...")
            extract_zip(dest, out_dir / dest.stem)
    return True


def write_notes(src: dict, out_dir: Path, files: list[dict], license_found: str | None) -> None:
    """Where it came from, under which licence: the thesis needs this for credits (benchmarks/public_clips/SOURCES.md)."""
    note = {"id": src["id"], "title": src["title"], "page": src["page"], "license": src["license"], "license_on_host": license_found,
            "violations": src["violations"], "fetched": date.today().isoformat(), "files": [f["name"] for f in files]}
    (out_dir / "SOURCE.json").write_text(json.dumps(note, indent=2), encoding="utf-8")
    lines = ["# Public evaluation sources downloaded here", "",
             "Evaluation only: never train on these. Credit the authors; most licences are non-commercial.", ""]
    for p in sorted(out_dir.parent.glob("*/SOURCE.json")):
        n = json.loads(p.read_text(encoding="utf-8"))
        lines += [f"## {n['title']}", f"- page: {n['page']}", f"- licence: {n['license']}", f"- violations: {', '.join(n['violations'])}",
                  f"- fetched: {n['fetched']}", ""]
    (out_dir.parent / "SOURCES.md").write_text("\n".join(lines), encoding="utf-8")


# --------------------------------------------------------------------------- command line

def gb(n: float | None) -> str:
    return "size unknown" if n is None else f"{n / 1e9:,.2f} GB" if n >= 1e8 else f"{n / 1e6:,.1f} MB"


def show_list(data: dict) -> None:
    print(f"{'id':<26}{'size':<8}{'host':<10}{'default':<9}violations")
    for s in data["sources"]:
        print(f"{s['id']:<26}{s['tier']:<8}{s['host']:<10}{'yes' if s.get('default') else '':<9}{', '.join(s['violations'])}")
        print(f"    {s['title']}")
    print("\nsize classes: small < 2 GB, medium 2-10 GB, large 10-40 GB, huge > 40 GB, manual = needs an account / form (instructions are printed).")


def coverage_rows(data: dict, needs) -> list[dict]:
    """Per violation (from the live list in tools/benchmark/violations.py): where its public test material is, or what to do without it."""
    rows = []
    for n in needs:
        have = [s for s in data["sources"] if n.key in s["violations"]]
        core = [s["id"] for s in have if s["host"] != "manual" and s.get("default")]
        optin = [s["id"] for s in have if s["host"] != "manual" and not s.get("default")]
        downloadable, by_hand = core + optin, [s["id"] for s in have if s["host"] == "manual"]
        if core:
            status = "PUBLIC"
        elif optin:
            status = "OPT-IN"                   # downloadable, but huge or needs your own key / login: not in the lean core download
        elif by_hand:
            status = "BY HAND"
        elif n.kind == "zone rule":
            status = "ANY FIXED CLIP"          # the zone you draw defines the violation: any fixed-camera clip with the right vehicles will do
        else:
            status = "FILM OWN"
        rows.append({"key": n.key, "status": status, "core": core, "downloadable": downloadable, "by_hand": by_hand,
                     "note": data["coverage"].get(n.key, "")})
    return rows


def show_coverage(data: dict) -> None:
    from tools.benchmark.violations import NEEDS
    rows = coverage_rows(data, NEEDS)
    print(f"{'violation':<26}{'status':<16}public material")
    for r in rows:
        sources = [i + ("*" if i in r["core"] else "") for i in r["downloadable"]] + [h + " (by hand)" for h in r["by_hand"]]
        print(f"{r['key']:<26}{r['status']:<16}{', '.join(sources)}")
        print(f"    {r['note'] or '(no note yet: add one under coverage: in benchmarks/public_sources.yaml)'}")
    counts = {s: sum(1 for r in rows if r["status"] == s) for s in ("PUBLIC", "OPT-IN", "BY HAND", "ANY FIXED CLIP", "FILM OWN")}
    print(f"\n{len(rows)} violations: " + ", ".join(f"{n} {s}" for s, n in counts.items()))
    print("PUBLIC = in the lean core download (* marks those sources; read the note: often partial). OPT-IN = downloadable but huge or needs your\n"
          "own Kaggle / Roboflow login. BY HAND = needs an account or a form.\n"
          "ANY FIXED CLIP = no public set, but a zone rule is defined by the zone you draw: label the real events on any fixed-camera clip\n"
          "  where the right vehicles pass (your own Zamboanga clip first). FILM OWN = no public set and not a zone rule: see benchmarks/CLIP_CHECKLIST.md.")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Download public evaluation clips (see the top of this file).")
    ap.add_argument("--list", action="store_true", help="show every source")
    ap.add_argument("--coverage", action="store_true", help="what public test material exists per violation")
    ap.add_argument("--only", nargs="+", metavar="ID", help="exactly these sources (whole source unless --sample)")
    ap.add_argument("--tier", choices=TIERS, help="every source up to this size class (default: only the sources marked default)")
    ap.add_argument("--sample", action="store_true", help="for sources that list sample files (RideSafe-400), fetch only those")
    ap.add_argument("--dry-run", action="store_true", help="look up sizes and licences, download nothing")
    ap.add_argument("--yes", action="store_true", help="do not ask before downloading")
    ap.add_argument("--max-gb", type=float, default=DEFAULT_MAX_GB, help=f"refuse a plan bigger than this (default {DEFAULT_MAX_GB:g})")
    ap.add_argument("--out", type=Path, default=OUT, help="where to put the downloads")
    args = ap.parse_args(argv)

    data = load()
    if args.list:
        show_list(data)
        return 0
    if args.coverage:
        show_coverage(data)
        return 0
    if "hulikamote_backend" in args.out.resolve().parts:
        raise SystemExit("Refusing to write inside hulikamote_backend/ (a write there restarts the running backend).")

    chosen = select(data["sources"], args.only, args.tier)
    if not chosen:
        raise SystemExit("Nothing selected. Try --list.")
    use_sample = args.sample or (not args.only and not args.tier)      # a plain run is the lean core set: sample files only
    plans, known = {}, 0
    print("Looking things up ...")
    for s in chosen:
        try:
            plans[s["id"]] = plan(s, sample=use_sample)
        except PermissionError as e:
            print(f"- {s['id']}: skipped. {e}")
            continue
        except Exception as e:
            print(f"- {s['id']}: could not be looked up ({e}); skipped")
            continue
        p = plans[s["id"]]
        size = sum(f["size"] or 0 for f in p["files"])
        known += size
        unknown = sum(1 for f in p["files"] if f["size"] is None)
        print(f"- {s['id']}: {s['title']}\n    host {s['host']}, {len(p['files'])} file(s), {gb(size) if size else 'size unknown'}"
              f"{f' (+{unknown} of unknown size)' if size and unknown else ''}\n    licence: {s['license']}"
              + (f"\n    licence on the host: {p['license']}" if p["license"] else ""))
    print(f"\nKnown total: {gb(known)}   (evaluation only: never train on these)")
    if known / 1e9 > args.max_gb:
        raise SystemExit(f"That is more than --max-gb {args.max_gb:g}. Use --sample, --only, or raise --max-gb on purpose.")
    if args.dry_run:
        return 0
    if not args.yes:
        if not sys.stdin.isatty():
            raise SystemExit("Not an interactive terminal: add --yes to download.")
        if input("Download now? [y/N] ").strip().lower() not in ("y", "yes"):
            return 0

    args.out.mkdir(parents=True, exist_ok=True)
    not_finished = []
    for s in chosen:
        if s["id"] not in plans:
            continue
        print(f"\n== {s['id']}")
        try:
            done = fetch(s, plans[s["id"]]["files"], args.out / s["id"])
        except Exception as e:
            print(f"    FAILED: {e}\n    (run the same command again to resume)")
            not_finished.append(s["id"])
            continue
        if done:
            write_notes(s, args.out / s["id"], plans[s["id"]]["files"], plans[s["id"]]["license"])
        else:
            not_finished.append(s["id"])
    if not args.only:
        print("\n== By hand (needs an account, a form or a Drive folder):")
        for s in (s for s in data["sources"] if s["host"] == "manual"):
            print(f"- {s['id']}: {s['title']}\n    {s['how']}")
    if not_finished:
        print(f"\nNot finished: {', '.join(not_finished)}")
    print(f"\nDone. Files are in {args.out}. Next: write what really happens in each clip, then add it to the benchmark (benchmarks/README.md).")
    return 1 if not_finished else 0


if __name__ == "__main__":
    sys.exit(main())
