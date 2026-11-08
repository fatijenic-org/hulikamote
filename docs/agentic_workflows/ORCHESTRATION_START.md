# HULI-KAMOTE - SESSION STARTUP ORCHESTRATION PROMPT
===================================================
FEED THIS ENTIRE FILE TO ANY AI MODEL AT THE VERY BEGINNING OF A SESSION.
THIS PROMPT GOVERNS THE COLD-START PROTOCOL, REPOSITORY MAPPING, AND EXECUTION RULES.

--------------------------------------------------------------------------------
1. PROJECT CONTEXT & REPOSITORY MAP
--------------------------------------------------------------------------------
HULI-KAMOTE is an undergraduate thesis system developed at the College of Computing
Studies in Zamboanga City. It is an automated, computer vision-based traffic violation
detection system designed for non-contact apprehension.

Primary Focus: Computer vision model development and validation.
- Detection: YOLO (single-frame object detection for vehicles, helmets, plates)
- Tracking: DeepSORT (spatiotemporal multi-object tracking for movement violations)
- Recognition: EasyOCR with preprocessing (license plate character extraction)

Repository Structure:
- hulikamote_backend    : FastAPI server hosting inference, tracking, API, and SQLite database.
- hulikamote_dashboard  : Flutter Admin Dashboard for LTO traffic enforcement operators.
- hulikamote_app        : Flutter Violator Portal for motorists (view records, file appeals).
- hulikamote_visualizer : Flutter desktop educational visualizer for thesis defense & non-technical audiences.
- training_lab/         : YOLO model training environment, datasets, and custom trainer scripts.
- dataset-images/       : Raw image assets collected for model training.
- tools/                : Standalone utility scripts (e.g., video downloaders).
- hulikamote_web_trial/ : Experimental/trial project sandbox.
- docs/                 : Thesis reference, ledger, handovers, and session history.

For complete thesis background, target violations, pipeline specifications, and evaluation metrics, see:
--> docs/PROJECT_CONTEXT.md (Constant canonical source of truth).
    Contains: Thesis objectives, target users (LTO operators/motorists), full violation list,
    3-stage pipeline (YOLO -> DeepSORT -> EasyOCR), metrics (mAP@50), and Zamboanga City road context.

--------------------------------------------------------------------------------
2. THE LEDGER SYSTEM & FILE ROLES
--------------------------------------------------------------------------------
1. docs/PROJECT_CONTEXT.md
   - Role: Permanent canonical source of truth for thesis, violations, and architecture.
   - Frequency: Constant. Never modified unless thesis scope formally changes.

2. docs/ORCHESTRATION_START.md (This file)
   - Role: Startup controller prompt fed at the beginning of each session.

3. docs/ORCHESTRATION_END.md
   - Role: Wrap-up controller prompt fed at the end of each session.

4. docs/HANDOVER.md
   - Role: Active whiteboard for the immediate builder. Holds current module status,
     technical quirks, and the exact next task to execute.
   - Frequency: Updated at the end of every session.

5. docs/ledger/handovers/HANDOVER_SESSION_XXX.md
   - Role: Immutable archive snapshots of every past handover.
   - Frequency: Created at the end of every session before updating HANDOVER.md.

6. docs/SESSION_LOG.md
   - Role: Complete chronological audit trail of all work done across all sessions.
   - Frequency: Append-only. A new entry is appended every session.

--------------------------------------------------------------------------------
3. SESSION STARTUP PROTOCOL (EXECUTE IMMEDIATELY)
--------------------------------------------------------------------------------
As an incoming AI builder, execute these steps right now before writing any code:

Step 1: Refer to docs/PROJECT_CONTEXT.md for canonical thesis scope, violation definitions,
        and system boundaries (LTO admin vs violator portal vs visualizer).
Step 2: Read docs/HANDOVER.md to identify the active subproject, current progress, and pending tasks.
Step 3: Read the last entry in docs/SESSION_LOG.md to see what the previous builder completed.
Step 4: Output a concise (max 4 lines) startup confirmation to the user:
        - Active Subproject (Backend / Dashboard / App / Visualizer)
        - Session Number (e.g., Session 004)
        - Task to execute (from HANDOVER.md or user request)
        - Ready status.
Step 5: Await user instruction or begin the specified task immediately if the user already gave a command.

--------------------------------------------------------------------------------
4. CORE OPERATIONAL RULES (DURING EXECUTION)
--------------------------------------------------------------------------------
1. User Authorization Rule (CRITICAL):
   Never proceed with implementing any new features or modules without explicit
   instruction from the user. After completing a task (like a fix or review), stop and
   wait for the user's specific command before starting the next phase of development.

2. Engineering Quality Goals:
   - Optimization: High performance, efficient algorithms, low latency.
   - Consistency: Maintain established patterns across subprojects.
   - Security: Data and logic safety, compliance with RA10173 (Data Privacy Act).
   - Robustness: Comprehensive error handling, graceful fallbacks.
   - Maintainability: Clean, readable, well-commented code.
   - Testability: Code designed to be easily verified and mocked.

3. Core Architectural Principles:
   - KISS: Keep It Simple, Stupid. Avoid over-engineering.
   - DRY: Don't Repeat Yourself. Reuse shared models, styles, and logic.
   - SRP: Single Responsibility Principle. One job per function, class, or widget file.

4. Subproject Scope Respect:
   - If working on the backend, adhere to FastAPI / PyTorch / ONNX best practices.
   - If working on the visualizer, follow the 4-step layman educational pipeline defined in HANDOVER.md.
   - If working on the dashboard, maintain the LTO operator workflow.

5. Thesis Scope Alignment:
   All detection logic, violation classes, and architectural decisions must strictly
   reflect the specifications in docs/PROJECT_CONTEXT.md. Do not invent new violation
   classes or alter the 3-stage pipeline (YOLO -> DeepSORT -> EasyOCR) without explicit user direction.

================================================================================
END OF STARTUP ORCHESTRATION PROMPT
