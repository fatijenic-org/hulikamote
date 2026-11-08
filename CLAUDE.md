# HULI-KAMOTE - notes for AI sessions

Follow `docs/ORCHESTRATION_START.md` at the start and `docs/ORCHESTRATION_END.md` at the end of every session.
Use `hulikamote_backend/venv/Scripts/python.exe` as `python`.

## Look things up in the project map before reading many files

Run these from the repo root (instant, no LLM; they read `docs/project_map/graph.json`):

- What is X, who calls it, what does it call (with file:line):  `python tools/project_map/ask.py explain "<exact name>"`
- Backend call chain from A to B:                               `python tools/project_map/ask.py path "<A>" "<B>"`
- Keyword search (use EXACT names, not sentences):              `python tools/project_map/ask.py query "<name> <name>"`

Other maps:

- "What happens when the user presses X?" / which screen calls which endpoint: `../project_mapper/outputs/huli-kamote/map.json`
  (features -> actions -> api calls -> endpoints -> backend call trees; `index.html` next to it is the visual version).
  `ask.py` cannot cross from Flutter to Python; the Project Mapper can. **Do not edit `../project_mapper`** (separate project).
- Files that are connected but poorly tested: `docs/project_map/RISK_TABLE.md`.

The maps are only as fresh as the last rebuild (date at the top of `docs/project_map/GRAPH_REPORT.md`; the wrap-up rebuilds them).
Edges marked INFERRED, or a `?` in the Project Mapper, are guesses. Verify anything important in the code itself.
