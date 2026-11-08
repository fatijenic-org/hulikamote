"""
Where are the tests missing?

    python tools/test_gaps.py             # print the report
    python tools/test_gaps.py --strict    # also exit 1 when something is missing (for CI)

tests/ mirrors the backend source tree, so every source file has one expected test file:
    engine/ledger.py      -> tests/engine/test_ledger.py
    routers/forensic.py   -> tests/routers/test_forensic.py
    store.py              -> tests/test_store.py
A source file with no test file is a gap. A second check lists the violation rules
(`evaluate_*` in engine/ledger.py) that no test calls.
"""
import re
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1] / "hulikamote_backend"
TESTS = BACKEND / "tests"
SOURCE_DIRS = ["engine", "routers", "inference"]          # engine/deep_sort is a vendored library: not listed
TOP_LEVEL = ["database.py", "main.py", "store.py", "yolo_inference.py"]


def sources():
    for name in TOP_LEVEL:
        yield Path(name)
    for d in SOURCE_DIRS:
        for p in sorted((BACKEND / d).glob("*.py")):
            if p.name != "__init__.py":
                yield p.relative_to(BACKEND)


def count_tests(path: Path) -> int:
    return len(re.findall(r"^\s*(?:async )?def test_", path.read_text(encoding="utf-8"), flags=re.M))


def main() -> int:
    missing = []
    print(f"{'source file':34} {'test file':44} tests")
    for src in sources():
        test_file = TESTS / src.parent / f"test_{src.stem}.py"
        shown = test_file.relative_to(BACKEND).as_posix()
        if test_file.exists():
            print(f"{src.as_posix():34} {shown:44} {count_tests(test_file):>5}")
        else:
            print(f"{src.as_posix():34} {'-- NO TEST FILE --':44}     -")
            missing.append(src.as_posix())

    all_tests = "\n".join(p.read_text(encoding="utf-8") for p in TESTS.rglob("*.py"))
    rules = re.findall(r"def (evaluate_\w+)", (BACKEND / "engine" / "ledger.py").read_text(encoding="utf-8"))
    untested = [r for r in rules if r not in all_tests]
    print("\nViolation rules (evaluate_* in engine/ledger.py) that no test calls:")
    print("  " + (", ".join(untested) if untested else "none"))

    print(f"\n{len(missing)} source file(s) without a test file, {len(untested)} untested rule(s).")
    return 1 if ("--strict" in sys.argv and (missing or untested)) else 0


if __name__ == "__main__":
    sys.exit(main())
