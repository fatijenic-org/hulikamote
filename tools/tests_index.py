"""
Which tests protect which code?  This builds the data behind "How it's tested" in the dashboard's Code Reference.

    hulikamote_backend/venv/Scripts/python.exe tools/tests_index.py             # Python tests (backend + training_lab)
    hulikamote_backend/venv/Scripts/python.exe tools/tests_index.py --flutter   # also run the dashboard's Flutter tests
    ... --out some.json                                                          # write somewhere else

How it knows (Python): the tests run under coverage.py with `dynamic_context = test_function`, so for every line it
records WHICH test executed it. A function's tests are the tests that ran one of its lines. A test is "direct" when
its test file names the function (written for it), otherwise the function only ran inside the test (through a helper).
Flutter has no per-line data here, so a Dart file lists the test files that import it (an approximation, said so in the UI).

Output: docs/project_map/tests_index.json (committed like graph.json; refreshed by the wrap-up).
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BACKEND = REPO / "hulikamote_backend"
LAB = REPO / "training_lab"
DASH = REPO / "hulikamote_dashboard"
DEFAULT_OUT = REPO / "docs" / "project_map" / "tests_index.json"

BACKEND_INCLUDE = "engine/*,routers/*,inference/*,store.py,database.py,main.py,yolo_inference.py,tracker.py"
BACKEND_OMIT = "*/tests/*,*/venv/*,engine/deep_sort/*"
# Patterns must not start with "*": coverage leaves those unanchored, so "*.py" would also measure the standard library.
LAB_INCLUDE = "data.py,gui.py,harvest.py,lab_tui.py,scripts/*,harvest_tool/*,data_tools/*"
LAB_OMIT = "*/tests/*,*/venv/*,*/datasets/*,*/runs/*"
MAX_SHOWN = 8          # tests listed per function (the true count is always stored)


# ─── small helpers ───────────────────────────────────────────────────────────

def rel(p: Path) -> str:
    return p.resolve().relative_to(REPO).as_posix()


def sentence(name: str) -> str:
    """test_pedestrian_lane_ignores_short_stop -> 'pedestrian lane ignores short stop'."""
    return re.sub(r"^test_?", "", name.split("[")[0]).replace("_", " ").strip() or name


_text_cache: dict[Path, str] = {}


def read_text(p: Path) -> str:
    if p not in _text_cache:
        _text_cache[p] = p.read_text(encoding="utf-8", errors="replace")
    return _text_cache[p]


# ─── 1. run the Python tests, one coverage context per test ──────────────────

def run_python_tests(cwd: Path, include: str, omit: str, datafile: Path, rc: Path, junit: Path, append: bool) -> float:
    cmd = [sys.executable, "-m", "coverage", "run", f"--rcfile={rc}", f"--include={include}", f"--omit={omit}"]
    if append:
        cmd.append("-a")
    cmd += ["-m", "pytest", "tests", "-q", "-p", "no:cacheprovider", f"--junitxml={junit}"]
    started = time.time()
    r = subprocess.run(cmd, cwd=cwd, env={**os.environ, "COVERAGE_FILE": str(datafile)},
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    last = (r.stdout or "").strip().splitlines()[-1:] or [r.stderr.strip()[-200:]]
    print(f"  {cwd.name}: {last[0]}")
    if not junit.exists():
        sys.exit(f"The test run in {cwd} produced no result file. Is coverage installed in this Python?\n{r.stderr[-600:]}")
    return time.time() - started


def split_classname(classname: str, cwd: Path):
    """'tests.engine.test_ledger.TestX' -> (file, module parts, class parts)."""
    parts = classname.split(".")
    for i in range(len(parts), 0, -1):
        f = cwd.joinpath(*parts[:i]).with_suffix(".py")
        if f.exists():
            return f, parts[:i], parts[i:]
    return None, parts, []


def test_line_numbers(file: Path) -> dict[str, int]:
    lines: dict[str, int] = {}
    for node in ast.parse(read_text(file)).body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            lines[node.name] = node.lineno
        elif isinstance(node, ast.ClassDef):
            for sub in node.body:
                if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    lines[f"{node.name}.{sub.name}"] = sub.lineno
    return lines


class PyTests:
    """Every Python test that ran, found again from a coverage context label."""

    def __init__(self):
        self.records: list[dict] = []
        self.by_full: dict[str, dict] = {}
        self.by_tail: dict[str, list[dict]] = {}
        self.summary: dict[str, dict] = {}

    def add_run(self, label: str, junit: Path, cwd: Path, seconds: float):
        counts = {"tests": 0, "passed": 0, "failed": 0, "skipped": 0}
        for tc in ET.parse(junit).getroot().iter("testcase"):
            counts["tests"] += 1
            bad = tc.find("failure") is not None or tc.find("error") is not None
            skipped = tc.find("skipped") is not None
            outcome = "failed" if bad else "skipped" if skipped else "passed"
            counts[outcome] += 1
            file, module, cls = split_classname(tc.get("classname", ""), cwd)
            if file is None:
                continue
            qual = ".".join(cls + [tc.get("name", "").split("[")[0]])
            full = ".".join(module + [qual])
            rec = self.by_full.get(full)
            if rec is None:
                rec = {"file": rel(file), "line": test_line_numbers(file).get(qual, 1), "name": qual,
                       "sentence": sentence(qual.split(".")[-1]), "outcome": outcome}
                self.by_full[full] = rec
                self.records.append(rec)
                self.by_tail.setdefault(f"{module[-1]}.{qual}", []).append(rec)
            elif outcome == "failed" or (outcome == "skipped" and rec["outcome"] == "passed"):
                rec["outcome"] = outcome       # a parametrized test is as bad as its worst case
        counts["seconds"] = round(seconds, 1)
        self.summary[label] = counts

    def find(self, context: str) -> dict | None:
        if context in self.by_full:
            return self.by_full[context]
        parts = context.split(".")
        for i in range(1, len(parts)):
            hit = self.by_tail.get(".".join(parts[i:]))
            if hit and len(hit) == 1:
                return hit[0]
        return None


# ─── 2. read coverage: functions -> tests ────────────────────────────────────

def snake(name: str) -> str:
    """PedestrianLane -> pedestrian_lane."""
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def units_of(tree: ast.Module):
    """Top-level functions, classes, and methods, with what a class is called and what it is built on."""
    out = []

    def add(node, qual, kind):
        unit = {"qual": qual, "bare": node.name, "kind": kind, "body_start": node.body[0].lineno,
                "end": node.end_lineno, "def_line": node.lineno, "bases": [], "aliases": [], "has_methods": False}
        if kind == "class":
            unit["bases"] = [getattr(b, "id", getattr(b, "attr", "")) for b in node.bases]
            unit["has_methods"] = any(isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)) for m in node.body)
            strings = [m.value.value for m in node.body if isinstance(m, ast.Assign) and isinstance(m.value, ast.Constant)
                       and isinstance(m.value.value, str) and len(m.value.value) >= 4]
            unit["aliases"] = [node.name, snake(node.name), *strings]    # the names a test would use for it
        out.append(unit)

    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            add(node, node.name, "function")
        elif isinstance(node, ast.ClassDef):
            add(node, node.name, "class")
            for sub in node.body:
                if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    add(sub, f"{node.name}.{sub.name}", "method")
    return out


_test_source_cache: dict[tuple[str, str], str] = {}


def test_source(rec: dict) -> str:
    """The text of one test function (to see what it names)."""
    key = (rec["file"], rec["name"])
    if key not in _test_source_cache:
        text, found = read_text(REPO / rec["file"]), ""
        for node in ast.walk(ast.parse(text)):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.lineno == rec["line"]:
                found = ast.get_source_segment(text, node) or ""
                break
        _test_source_cache[key] = found
    return _test_source_cache[key]


def names_it(rec: dict, aliases: list[str]) -> bool:
    """True when the test's name or body uses one of these names."""
    pattern = re.compile("|".join(re.escape(a) for a in aliases), re.IGNORECASE)
    return bool(pattern.search(rec["name"] + "\n" + test_source(rec)))


def mirror_test_for(path: Path) -> str | None:
    """engine/ledger.py -> tests/engine/test_ledger.py (the backend's tests mirror its source tree)."""
    try:
        sub = path.resolve().relative_to(BACKEND)
    except ValueError:
        return None
    candidate = BACKEND / "tests" / sub.parent / f"test_{sub.stem}.py"
    return rel(candidate) if candidate.exists() else None


def build_python_entries(datafile: Path, rc: Path, tests: PyTests):
    import coverage

    cov = coverage.Coverage(data_file=str(datafile), config_file=str(rc))
    cov.load()
    data = cov.get_data()
    raw: dict[str, dict] = {}

    for path in sorted(data.measured_files()):
        p = Path(path)
        try:
            p.resolve().relative_to(REPO)
        except ValueError:
            continue                              # not our code (e.g. the standard library)
        if "venv" in p.parts or "site-packages" in p.parts:
            continue
        try:
            _, executable, _excluded, missing, _ = cov.analysis2(path)
            tree = ast.parse(read_text(p))
        except Exception:
            continue
        miss = set(missing)
        ctx_by_line = data.contexts_by_lineno(path)
        mirror = mirror_test_for(p)
        stem_words = re.compile(rf"\b{re.escape(p.stem)}\b")

        def tests_of(lines):
            found: dict[int, tuple[dict, int]] = {}
            for ln in lines:
                if ln in miss:
                    continue
                for ctx in ctx_by_line.get(ln, ()):
                    if not ctx:
                        continue
                    rec = tests.find(ctx)
                    if rec is not None:
                        old = found.get(id(rec))
                        found[id(rec)] = (rec, (old[1] if old else 0) + 1)
            return found

        symbols = {}
        for u in units_of(tree):
            lines = [l for l in executable if u["body_start"] <= l <= u["end"]]
            recs = [rec for rec, _ in tests_of(lines).values()]
            if u["kind"] == "class":
                is_direct = lambda rec, a=u["aliases"]: names_it(rec, a)
            else:
                pat = re.compile(rf"\b{re.escape(u['bare'])}\b")
                is_direct = lambda rec, pat=pat: bool(pat.search(read_text(REPO / rec["file"])))
            ranked = sorted(recs, key=lambda r: (0 if is_direct(r) else 1, 0 if r["file"] == mirror else 1, r["file"], r["line"]))
            entry = {
                "qualname": u["qual"], "kind": u["kind"], "line": u["def_line"],
                "coverage_pct": round(100 * sum(1 for l in lines if l not in miss) / len(lines), 1) if lines else None,
                "tests_total": len(ranked), "tests_direct": sum(1 for r in ranked if is_direct(r)),
                "_all": ranked, "_bases": u["bases"], "_aliases": u["aliases"],
                "_config_only": u["kind"] == "class" and not u["has_methods"],
            }
            symbols.setdefault(u["bare"], entry)        # anchors point at the first definition of a name
            if u["qual"] != u["bare"]:
                symbols.setdefault(u["qual"], entry)

        every = tests_of(executable)
        top = sorted(every.values(), key=lambda rc_: (
            0 if rc_[0]["file"] == mirror or stem_words.search(read_text(REPO / rc_[0]["file"])) else 1, -rc_[1], rc_[0]["file"]))
        raw[rel(p)] = {
            "lang": "python",
            "coverage_pct": round(100 * sum(1 for l in executable if l not in miss) / len(executable), 1) if executable else None,
            "mirror_test": mirror,
            "tests_total": len(top),
            "_tests": [rec for rec, _ in top[:MAX_SHOWN]],
            "_symbols": symbols,
        }

    inherit_from_bases(raw)
    for entry in raw.values():
        for sym in entry["_symbols"].values():
            sym["_tests"] = sym["_all"][:MAX_SHOWN]
    return raw


def inherit_from_bases(raw: dict) -> None:
    """A class that only holds settings (PedestrianLane: key, zone, limit) has no code of its own to run; its rule is
    the base class (StoppedInZone). Give it the base's tests, those that name it first, and say where they come from."""
    classes = {name: sym for entry in raw.values() for name, sym in entry["_symbols"].items() if sym["kind"] == "class"}
    for entry in raw.values():
        for sym in entry["_symbols"].values():
            if not sym["_config_only"]:
                continue
            base = next((classes[b] for b in sym["_bases"] if b in classes and classes[b]["_all"]), None)
            if base is None:
                continue
            ranked = sorted(base["_all"], key=lambda r: (0 if names_it(r, sym["_aliases"]) else 1, r["file"], r["line"]))
            sym["_all"] = ranked
            sym["tests_total"] = len(ranked)
            sym["tests_direct"] = sum(1 for r in ranked if names_it(r, sym["_aliases"]))
            sym["inherited_from"] = base["qualname"]


def add_unmeasured(raw: dict) -> None:
    """Coverage only lists files that some test imported. A file nobody imports is the clearest gap of all, so it
    gets an entry too: every function in it, with no tests and 0% of its lines run."""
    layouts = [
        (BACKEND, ["engine", "routers", "inference"], ["store.py", "database.py", "main.py", "yolo_inference.py", "tracker.py"]),
        (LAB, ["scripts", "harvest_tool", "data_tools"], ["data.py", "gui.py", "harvest.py", "lab_tui.py"]),
    ]
    skip = {"deep_sort", "tests", "venv", "__pycache__"}
    for base, folders, tops in layouts:
        files = [base / t for t in tops] + [f for d in folders for f in sorted((base / d).rglob("*.py"))
                                            if not skip & set(f.relative_to(base).parts)]
        for f in files:
            if not f.exists() or f.name == "__init__.py" or rel(f) in raw:
                continue
            try:
                tree = ast.parse(read_text(f))
            except SyntaxError:
                continue
            symbols = {}
            for u in units_of(tree):
                entry = {"qualname": u["qual"], "kind": u["kind"], "line": u["def_line"], "coverage_pct": 0.0,
                         "tests_total": 0, "tests_direct": 0, "_tests": []}
                symbols.setdefault(u["bare"], entry)
                if u["qual"] != u["bare"]:
                    symbols.setdefault(u["qual"], entry)
            raw[rel(f)] = {"lang": "python", "coverage_pct": 0.0, "mirror_test": mirror_test_for(f), "tests_total": 0,
                           "_tests": [], "_symbols": symbols}


# ─── 3. Dart (file level) ────────────────────────────────────────────────────

TEST_CALL = re.compile(r"""\b(?:testWidgets|test)\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""")
PKG_IMPORT = re.compile(r"import\s+'package:hulikamote_dashboard/([^']+)';")


def run_flutter_tests() -> tuple[dict[str, list[dict]], dict]:
    """Every Flutter test with its result, per test file, plus a summary, from `flutter test --reporter json`."""
    flutter = shutil.which("flutter")
    if not flutter:
        print("  flutter not found on PATH: Flutter test results skipped")
        return {}, {}
    started = time.time()
    r = subprocess.run([flutter, "test", "--reporter", "json"], cwd=DASH, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    suites: dict[int, str] = {}
    tests: dict[int, dict] = {}
    records: dict[str, list[dict]] = {}
    counts = {"tests": 0, "passed": 0, "failed": 0, "skipped": 0}
    for raw in r.stdout.splitlines():
        try:
            ev = json.loads(raw)
        except ValueError:
            continue
        kind = ev.get("type")
        if kind == "suite":
            suites[ev["suite"]["id"]] = ev["suite"].get("path", "")
        elif kind == "testStart":
            t = ev["test"]
            tests[t["id"]] = t
        elif kind == "testDone" and not ev.get("hidden"):
            t = tests.get(ev["testID"])
            if not t or t.get("name", "").startswith("loading ") or "line" not in t:
                continue
            path = suites.get(t.get("suiteID"), "")
            try:
                file = rel(Path(path))
            except ValueError:
                continue
            outcome = "skipped" if ev.get("skipped") else "passed" if ev.get("result") == "success" else "failed"
            counts["tests"] += 1
            counts[outcome] += 1
            records.setdefault(file, []).append(
                {"file": file, "line": t["line"], "name": t["name"], "sentence": t["name"], "outcome": outcome})
    counts["seconds"] = round(time.time() - started, 1)
    print(f"  flutter: {counts['passed']} passed, {counts['failed']} failed, {counts['skipped']} skipped")
    return records, counts


def build_dart_entries(flutter_records: dict[str, list[dict]]):
    test_dir = DASH / "test"
    recs_by_file: dict[str, list[dict]] = {}
    imports_by_test: dict[str, set[str]] = {}
    importers: dict[str, list[str]] = {}
    for tf in sorted(test_dir.rglob("*_test.dart")):
        text = read_text(tf)
        trel = rel(tf)
        recs = []
        if trel in flutter_records:                       # the real run knows every test, even those made in a loop
            recs = sorted(flutter_records[trel], key=lambda r: (r["line"], r["name"]))
        else:                                             # not run: read the names from the file (no result)
            for m in TEST_CALL.finditer(text):
                name = m.group(1) if m.group(1) is not None else m.group(2)
                line = text.count("\n", 0, m.start()) + 1
                recs.append({"file": trel, "line": line, "name": name, "sentence": name, "outcome": None})
        recs_by_file[trel] = recs
        libs = {f"hulikamote_dashboard/lib/{m.group(1)}" for m in PKG_IMPORT.finditer(text)}
        imports_by_test[trel] = libs
        for lib in libs:
            importers.setdefault(lib, []).append(trel)

    out = {}
    for lf in sorted((DASH / "lib").rglob("*.dart")):
        key = rel(lf)
        sub = lf.relative_to(DASH / "lib").with_suffix("")
        mirror = DASH / "test" / (str(sub) + "_test.dart")
        mirror_rel = rel(mirror) if mirror.exists() else None
        files = importers.get(key, [])
        files = sorted(files, key=lambda t: (0 if t == mirror_rel else 1, len(imports_by_test[t]), t))
        every = [rec for t in files for rec in recs_by_file[t]]
        shown = [rec for t in files[:3] for rec in recs_by_file[t]][:MAX_SHOWN]
        out[key] = {"lang": "dart", "coverage_pct": None, "mirror_test": mirror_rel,
                    "tests_total": len(every), "test_files": len(files), "_tests": shown, "_symbols": {}}
    return out


# ─── 4. assemble ─────────────────────────────────────────────────────────────

def real_footage_clips() -> int:
    registry = REPO / "benchmarks" / "registry.yaml"
    if not registry.exists():
        return 0
    text = registry.read_text(encoding="utf-8", errors="replace")
    clips = text.split("clips:", 1)[-1] if "clips:" in text else ""
    return len(re.findall(r"^\s*-\s+id:", clips, flags=re.M))


def assemble(py_raw: dict, dart_raw: dict, runs: dict) -> dict:
    table: list[dict] = []
    position: dict[int, int] = {}

    all_recs = {id(r): r for entry in list(py_raw.values()) + list(dart_raw.values())
                for r in entry["_tests"] + [t for s in entry["_symbols"].values() for t in s["_tests"]]}
    for rec in sorted(all_recs.values(), key=lambda r: (r["file"], r["line"], r["name"])):
        position[id(rec)] = len(table)
        table.append(rec)

    files = {}
    for key, entry in sorted({**py_raw, **dart_raw}.items()):
        out = {k: v for k, v in entry.items() if not k.startswith("_")}
        out["tests"] = [position[id(r)] for r in entry["_tests"]]
        symbols = {}
        for name, sym in entry["_symbols"].items():
            s = {k: v for k, v in sym.items() if not k.startswith("_")}
            s["tests"] = [position[id(r)] for r in sym["_tests"]]
            symbols[name] = s
        out["symbols"] = symbols
        files[key] = out
    return {
        "generated": time.strftime("%Y-%m-%d %H:%M"),
        "about": "Built by tools/tests_index.py. Python: coverage contexts (exact). Dart: test files that import the file.",
        "runs": runs,
        "real_footage": {"clips_in_registry": real_footage_clips()},
        "tests": table,
        "files": files,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--flutter", action="store_true", help="also run the dashboard's Flutter tests (slower)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="tests_index_"))
    try:
        rc = tmp / ".coveragerc"
        rc.write_text("[run]\ndynamic_context = test_function\n", encoding="utf-8")
        datafile = tmp / "cov.data"
        print("Running the Python tests with one coverage context per test ...")
        tests = PyTests()
        sec = run_python_tests(BACKEND, BACKEND_INCLUDE, BACKEND_OMIT, datafile, rc, tmp / "backend.xml", append=False)
        tests.add_run("backend", tmp / "backend.xml", BACKEND, sec)
        sec = run_python_tests(LAB, LAB_INCLUDE, LAB_OMIT, datafile, rc, tmp / "lab.xml", append=True)
        tests.add_run("training_lab", tmp / "lab.xml", LAB, sec)

        py_raw = build_python_entries(datafile, rc, tests)
        add_unmeasured(py_raw)
        flutter_records, flutter_counts = ({}, {})
        if args.flutter:
            print("Running the Flutter tests ...")
            flutter_records, flutter_counts = run_flutter_tests()
        dart_raw = build_dart_entries(flutter_records)

        runs = dict(tests.summary)
        runs["flutter"] = flutter_counts or None
        index = assemble(py_raw, dart_raw, runs)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(index, indent=1, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        size = args.out.stat().st_size / 1024
        print(f"Wrote {args.out} ({size:.0f} KB): {len(index['tests'])} tests, {len(index['files'])} files")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # The tests are isolated now; say so if one of them still dirtied a tracked file.
    dirty = subprocess.run(["git", "status", "--porcelain", "--", "hulikamote_backend/models",
                            "hulikamote_backend/test_hulikamote.db"], cwd=REPO, capture_output=True, text=True).stdout.strip()
    if dirty:
        print("WARNING: the test run changed tracked files:\n" + dirty)
    return 0


if __name__ == "__main__":
    sys.exit(main())
