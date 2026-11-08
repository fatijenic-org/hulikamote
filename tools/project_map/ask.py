"""
ask.py - ask the saved project map (docs/project_map/graph.json) a question. No LLM, no server, instant.

    python tools/project_map/ask.py explain "merge_forensic_tickets"   # what it is, who calls it, what it calls (file:line)
    python tools/project_map/ask.py path "merge_forensic_tickets" "_crop_file"   # shortest call chain between two names
    python tools/project_map/ask.py query "ticket_merge merge_tickets" --budget 1500   # keyword search; use EXACT names

Tips: use real names from the code (functions, classes, files). Plain-English questions match poorly.
It cannot link Flutter to Python (no HTTP link in the graph): for "what happens when I press this button" use the
Project Mapper (../project_mapper/outputs/huli-kamote/index.html, or search its map.json).
The map is as old as the last rebuild (date at the top of docs/project_map/GRAPH_REPORT.md).
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_map import REPO, default_graphify          # noqa: E402

GRAPH = REPO / "docs" / "project_map" / "graph.json"


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("explain", "path", "query"):
        print(__doc__)
        return 2
    if not GRAPH.exists():
        print(f"no graph yet: {GRAPH}\nbuild it first: python tools/project_map/build_map.py")
        return 2
    exe = default_graphify()
    return subprocess.run([exe, *sys.argv[1:], "--graph", str(GRAPH)]).returncode


if __name__ == "__main__":
    sys.exit(main())
