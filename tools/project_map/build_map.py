"""
build_map.py - Map the project and show where the tests are thin.

What it does (all local, no LLM calls):
  1. Copies ONLY our code to a temp folder (allowlist: *.py, *.dart, *.md; no venv, data, models, keys).
  2. Runs `graphify update` on the copy -> graph.html (interactive map), GRAPH_REPORT.md.
  3. Runs the backend tests under `coverage` -> coverage_html/ (line + branch coverage).
  4. Joins the two: for every file, how connected it is (other files it touches) vs how well it is tested
     -> RISK_TABLE.md. Connected AND untested = test these first.

Usage (from the repo root):
    python tools/project_map/build_map.py --graphify <path-to-graphify> [--skip-tests]

Setup once (isolated env, graphify is not a project dependency):
    python -m venv .graphify_env && .graphify_env/Scripts/pip install graphifyy==0.9.74
Coverage must be installed in the backend venv:  hulikamote_backend/venv/Scripts/pip install coverage
Outputs go to docs/project_map/.
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
BACKEND = REPO / "hulikamote_backend"
OUT = REPO / "docs" / "project_map"

BACKEND_SKIP = {"venv", "venv_old", "snapshots", "models", "media", "videos", "tmp_yolo", "tools",
                "__pycache__", ".pytest_cache"}
COVERAGE_INCLUDE = "engine/*,routers/*,store.py,database.py,main.py,yolo_inference.py,tracker.py"
COVERAGE_OMIT = "*/tests/*,*/venv/*,engine/deep_sort/*"


def copy_tree(src: Path, dst: Path, suffix: str, skip: set[str]) -> None:
    for p in src.rglob("*"):
        if p.is_file() and p.suffix == suffix and not (set(p.relative_to(src).parts[:-1]) & skip):
            target = dst / p.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)


def stage_code(stage: Path) -> None:
    copy_tree(BACKEND, stage / "hulikamote_backend", ".py", BACKEND_SKIP)
    copy_tree(REPO / "training_lab" / "scripts", stage / "training_lab" / "scripts", ".py", {"__pycache__", "_esrgan_temp"})
    copy_tree(REPO / "hulikamote_dashboard" / "lib", stage / "hulikamote_dashboard" / "lib", ".dart", set())
    copy_tree(REPO / "docs", stage / "docs", ".md", {"ledger", "files", "project_map"})


def run_graphify(graphify: str, stage: Path) -> Path:
    subprocess.run([graphify, "update", "."], cwd=stage, check=True)
    return stage / "graphify-out"


def run_coverage(py: Path, out_json: Path) -> bool:
    """Runs the backend tests under coverage. Returns False if the run could not produce data."""
    cmds = [
        [str(py), "-m", "coverage", "erase"],
        # The upload / model-switch / database tests run in temp folders now, so the whole suite is safe to run here.
        [str(py), "-m", "coverage", "run", "--branch", f"--include={COVERAGE_INCLUDE}", f"--omit={COVERAGE_OMIT}",
         "-m", "pytest", "tests", "-q", "-p", "no:cacheprovider"],
    ]
    try:
        for c in cmds:
            r = subprocess.run(c, cwd=BACKEND)
            if c[3] == "run" and r.returncode not in (0, 1):   # 1 = some tests failed; data is still valid
                print(f"[warn] test run exited with {r.returncode}")
        subprocess.run([str(py), "-m", "coverage", "json", "-o", str(out_json)], cwd=BACKEND, check=True)
        subprocess.run([str(py), "-m", "coverage", "html", "-d", str(OUT / "coverage_html")], cwd=BACKEND, check=True)
    finally:
        restore_test_debris()
    return out_json.exists()


def restore_test_debris() -> None:
    """The test suite rewrites a tracked test DB and (in the past) models/. Put TRACKED files back exactly as git has them,
    so a rebuild never leaves the working tree dirty or changes the active model."""
    paths = ["hulikamote_backend/test_hulikamote.db", "hulikamote_backend/models"]
    st = subprocess.run(["git", "status", "--porcelain", "--", *paths], cwd=REPO, capture_output=True, text=True).stdout
    for line in st.splitlines():
        flag, path = line[:2], line[3:].strip().strip('"')
        if flag in (" M", "M ", " D", "MM"):
            subprocess.run(["git", "checkout", "--", path], cwd=REPO)
            print(f"[restore] {path} put back as committed")
        elif flag == "??":
            print(f"[warn] untracked test debris left for you to review: {path}")


def default_graphify() -> str:
    """graphify on PATH, else the permanent env created by the setup steps in this file's header."""
    import shutil as _sh
    found = _sh.which("graphify")
    if found:
        return found
    home = Path.home() / ".graphify_env"
    for cand in (home / "Scripts" / "graphify.exe", home / "bin" / "graphify"):
        if cand.exists():
            return str(cand)
    return "graphify"


def file_stats(graph: dict) -> dict:
    """file -> {nodes, links_out (to other files), links_in (from other files), neighbours}"""
    node_file = {n["id"]: n.get("source_file") for n in graph["nodes"]}
    stats = defaultdict(lambda: {"nodes": 0, "neighbours": set(), "links": 0})
    for n in graph["nodes"]:
        if n.get("source_file"):
            stats[n["source_file"]]["nodes"] += 1
    for e in graph["links"]:
        a, b = node_file.get(e["source"]), node_file.get(e["target"])
        if a and b and a != b:
            for f, other in ((a, b), (b, a)):
                stats[f]["neighbours"].add(other)
                stats[f]["links"] += 1
    return stats


def write_risk_table(stats: dict, cov: dict | None, path: Path) -> None:
    rows = []
    for f, s in stats.items():
        if not (f.endswith(".py") or f.endswith(".dart")):
            continue
        if f.endswith(".py") and "/tests/" in f or Path(f).name.startswith("test_"):
            continue
        pct = None
        if f.endswith(".py") and cov is not None:
            key = f.removeprefix("hulikamote_backend/")
            entry = cov["files"].get(key) or cov["files"].get(key.replace("/", "\\"))
            pct = entry["summary"]["percent_covered"] if entry else None
        rows.append((f, len(s["neighbours"]), s["links"], pct))

    def risk(r):
        f, nbrs, _links, pct = r
        untested = 1.0 if pct is None else 1 - pct / 100
        return nbrs * untested

    rows.sort(key=risk, reverse=True)
    lines = [
        f"# Project risk table  (generated {date.today()})",
        "",
        "Risk = (how many other files it touches) x (how little of it the tests run). "
        "Connected AND untested files are the ones to test first.",
        "",
        "- Coverage % is line+branch coverage from the backend test run (engine/routers/store/etc.).",
        "- `none` = the file is not in the coverage run (Dart files have no tests yet; some Python files are not imported by any test).",
        "",
        "| # | File | Files it touches | Cross-file links | Test coverage | Risk |",
        "|---|------|------------------|------------------|---------------|------|",
    ]
    for i, r in enumerate(rows[:40], 1):
        f, nbrs, links, pct = r
        if pct is not None:
            shown = f"{pct:.0f}%"
        elif "/deep_sort/" in f:
            shown = "not measured (vendored library)"
        else:
            shown = "none"
        lines.append(f"| {i} | `{f}` | {nbrs} | {links} | {shown} | {risk(r):.1f} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_index(path: Path, have_cov: bool) -> None:
    cov_link = '<li><a href="coverage_html/index.html">Test coverage (per file, per line)</a></li>' if have_cov else ""
    path.write_text(f"""<!doctype html><meta charset="utf-8"><title>Project map</title>
<body style="font-family:sans-serif;max-width:720px;margin:40px auto">
<h1>HULI-KAMOTE project map</h1><p>Generated {date.today()}. Rebuild: <code>python tools/project_map/build_map.py</code></p>
<ul><li><a href="graph.html">Interactive project map (graphify)</a></li>
<li><a href="GRAPH_REPORT.md">Map summary (hubs, groups)</a></li>
{cov_link}
<li><a href="RISK_TABLE.md">Risk table: connected but untested files</a></li></ul></body>""", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--graphify", default=default_graphify(), help="path to the graphify executable (default: PATH, else ~/.graphify_env)")
    ap.add_argument("--python", default=str(BACKEND / "venv" / "Scripts" / "python.exe"), help="backend venv python (has coverage)")
    ap.add_argument("--skip-tests", action="store_true", help="map only, no coverage")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        stage = Path(tmp) / "code"
        stage.mkdir()
        stage_code(stage)
        print(f"[stage] copied code to {stage}")
        gout = run_graphify(args.graphify, stage)
        # graph.json is what `graphify query/explain/path --graph docs/project_map/graph.json` reads (no LLM, no server)
        for name in ("graph.html", "GRAPH_REPORT.md", "graph.json"):
            shutil.copy2(gout / name, OUT / name)
        graph = json.loads((gout / "graph.json").read_text(encoding="utf-8"))

        cov = None
        if not args.skip_tests:
            cov_json = Path(tmp) / "cov.json"
            if run_coverage(Path(args.python), cov_json):
                cov = json.loads(cov_json.read_text(encoding="utf-8"))

    write_risk_table(file_stats(graph), cov, OUT / "RISK_TABLE.md")
    write_index(OUT / "index.html", cov is not None)
    (OUT / ".gitignore").write_text("coverage_html/\ncache/\n", encoding="utf-8")      # cache/ is written by graphify query/explain
    print(f"[done] outputs in {OUT}")


if __name__ == "__main__":
    sys.exit(main())
