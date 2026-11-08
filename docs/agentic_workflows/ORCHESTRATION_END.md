# HULI-KAMOTE - SESSION WRAP-UP ORCHESTRATION PROMPT
==================================================
FEED THIS ENTIRE FILE TO ANY AI MODEL AT THE END OF A SESSION.
THIS PROMPT COMMANDS THE AI TO ARCHIVE THE CURRENT STATE, UPDATE THE HANDOVER,
AND APPEND THE AUDIT LOG BEFORE CLOSING THE SESSION.

--------------------------------------------------------------------------------
1. PROJECT CONTEXT & REPOSITORY MAP
--------------------------------------------------------------------------------
HULI-KAMOTE is an undergraduate thesis system developed at the College of Computing
Studies in Zamboanga City. It is an automated, computer vision-based traffic violation
detection system designed for non-contact apprehension (YOLO + DeepSORT + EasyOCR).

Repository Structure:
- hulikamote_backend    : FastAPI server hosting inference, tracking, API, and SQLite database.
- hulikamote_dashboard  : Flutter Admin Dashboard for LTO traffic enforcement operators.
- hulikamote_app        : Flutter Violator Portal for motorists (view records, file appeals).
- hulikamote_visualizer : Flutter desktop educational visualizer for thesis defense.
- training_lab/         : YOLO model training environment, datasets, and custom trainer scripts.
- dataset-images/       : Raw image assets collected for model training.
- tools/                : Standalone utility scripts (e.g., video downloaders).
- hulikamote_web_trial/ : Experimental/trial project sandbox.
- docs/                 : Thesis reference, ledger, handovers, and session history.

Domain reference: docs/PROJECT_CONTEXT.md (Constant canonical source of truth).

--------------------------------------------------------------------------------
2. THE LEDGER SYSTEM ARCHITECTURE
--------------------------------------------------------------------------------
1. docs/PROJECT_CONTEXT.md                : Constant thesis reference. Never edit.
2. docs/ORCHESTRATION_START.md            : Fed at the start of a session.
3. docs/ORCHESTRATION_END.md (This file)  : Fed at the end of a session.
4. docs/HANDOVER.md                       : Active whiteboard for the incoming builder.
5. docs/ledger/handovers/HANDOVER_SESSION_XXX.md : Immutable archive of past handovers.
6. docs/SESSION_LOG.md                    : Append-only audit log of all completed work.

--------------------------------------------------------------------------------
3. SESSION WRAP-UP PROTOCOL (EXECUTE IMMEDIATELY)
--------------------------------------------------------------------------------
You must now execute the complete session handoff lifecycle in this exact sequence:

Step 1: Determine the current Session Number.
        Read the latest entry in docs/SESSION_LOG.md and increment the session count by 1
        (e.g., if SESSION 003 is the last entry, the current session is SESSION 004).

Step 2: Archive the current handover before making any changes.
        Copy docs/HANDOVER.md to docs/ledger/handovers/HANDOVER_SESSION_XXX.md
        (e.g., docs/ledger/handovers/HANDOVER_SESSION_004.md).
        CRITICAL: Never overwrite docs/HANDOVER.md without archiving the previous state first!

Step 3: Update Orchestration Prompts (if applicable):
        - If any new directories, subprojects, or major repository changes were added during the session,
          update the "1. PROJECT CONTEXT & REPOSITORY MAP" section in BOTH docs/ORCHESTRATION_START.md
          and docs/ORCHESTRATION_END.md to reflect the new structure.

Step 4: Update docs/HANDOVER.md for the incoming builder:
        - Update LAST UPDATED header with current date and model name.
        - Refresh the VIOLATION STATUS TABLE (mark newly completed phases as DONE).
        - Update KNOWN ISSUES AND QUIRKS with any new blockers or quirks found.
        - Update DESIGN RULES LOCKED IN if new architectural patterns were finalized.
        - Set a prioritized, highly actionable "NEXT TASK FOR INCOMING BUILDER".

Step 5: Append a new session entry to docs/SESSION_LOG.md using this exact template:

        ---

        ## SESSION XXX
        DATE: YYYY-MM-DD
        BUILDER: [Model / Name]

        WORK DONE
        - [Concise bullet of feature, fix, or investigation completed]
        - [Concise bullet of feature, fix, or investigation completed]

        FILES TOUCHED
        - [filepath] | [one-line summary of change]
        - [filepath] | [one-line summary of change]

        BUGS FIXED
        - [bug description] | [how it was resolved]

        DECISIONS MADE
        - [any locked-in architectural or product decisions]

        LEFT INCOMPLETE
        - [anything partially done or waiting on review]

        END OF SESSION XXX

Step 6: Rebuild the project maps so the next builder starts with a fresh map.
        Do this LAST, after all code and ledger changes are committed, so the maps match the final code.
        This step must never block the wrap-up: if something below is missing, say so in the report and continue.
        a. Run `git status --short` and remember the result.
        b. From the repo root run (about 2 minutes):
              hulikamote_backend/venv/Scripts/python.exe tools/project_map/build_map.py
           It rebuilds docs/project_map/ (graph.html, graph.json, GRAPH_REPORT.md, RISK_TABLE.md). It needs graphify in
           ~/.graphify_env (install lines are in the header of tools/project_map/build_map.py). It runs the backend tests under
           coverage and restores any test debris itself.
        c. If the folder ../project_mapper exists, also run:
              hulikamote_backend/venv/Scripts/python.exe ../project_mapper/pm.py huli-kamote
           This only reads this project and refreshes ../project_mapper/outputs/huli-kamote/. Never edit ../project_mapper itself.
        d. Run `git status --short` again. The rebuild may only add changes inside docs/project_map/. If anything else changed,
           do NOT commit it; report it. Otherwise commit:
              git add docs/project_map && git commit -m "docs: refresh project maps"

Step 7: Output a concise final report (max 7 lines) to the user:
        - Confirmation that docs/ledger/handovers/HANDOVER_SESSION_XXX.md was created.
        - Confirmation that docs/HANDOVER.md was updated.
        - Confirmation that docs/SESSION_LOG.md was appended.
        - Confirmation of ORCHESTRATION docs updates (if any).
        - Confirmation that the project maps were rebuilt and committed (or why that step was skipped).
        - Summary of the primary next task for the incoming builder.

================================================================================
END OF WRAP-UP ORCHESTRATION PROMPT
