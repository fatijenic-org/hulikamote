# HULI-KAMOTE SYSTEM GOAL AUDIT

## Purpose
This document records the current status of the project against the end goal:

"Complete the system so that only data collection and model training remain before the project is operational for local use and ready for future online deployment."

This audit is intended as a practical reference for planning the remaining work across the backend, dashboard, mobile app, AI training pipeline, and violation detection system.

---

## Target End State
The project should support the following:

1. Dashboard for enforcers
   - Live detection from CCTV / RTSP / camera stream
   - Non-live detection from opened video files
   - Violation selection before running inference
   - ROI setup where required
   - Detection from injected trained models
   - Logging to database
   - History and review screens
   - User linkage by plate number / identified offender

2. Mobile user app
   - Receives violation notifications
   - Receives evidence proof of violation
   - Reads violation records and status

3. Backend
   - Connects dashboard and mobile app
   - Runs locally for now
   - Ready for online deployment later
   - Handles inference, database, logging, notifications, user data, and config

4. AI training pipeline
   - Training for required specialist models
   - Export to ONNX or compatible formats
   - Model injection into backend registry

5. Violation detection pipeline
   - Full coverage across all defined violations
   - Real detection logic for 13+ violation classes
   - ROI / tracking / OCR / ledger integration working together

---

## Current Reality
The system has already achieved a strong foundation, but it is not yet at the final milestone where only data collection and model training remain.

### What is already achieved

#### Backend
- FastAPI server structure exists and is operational in [hulikamote_backend/main.py](../hulikamote_backend/main.py)
- Core API routes exist for upload, violations, websocket feed, status, notifications, auth, and settings
- Live video stream endpoint exists in [hulikamote_backend/routers/stream.py](../hulikamote_backend/routers/stream.py)
- Database layer exists and supports violation storage and user records
- Snapshot serving for evidence images is enabled
- The decoupled pipeline exists in [hulikamote_backend/engine/pipeline.py](../hulikamote_backend/engine/pipeline.py)
- Model registry / slicer / ledger architecture is implemented
- Specialist model injection logic is present
- OCR plate extraction logic is present

#### Dashboard
- Dashboard routing and shell are implemented in [hulikamote_dashboard/lib/core/routers/app_router.dart](../hulikamote_dashboard/lib/core/routers/app_router.dart)
- Live monitoring and offline-video navigation are included
- Inbox verification UI exists in [hulikamote_dashboard/lib/features/violations/presentation/screens/inbox_screen.dart](../hulikamote_dashboard/lib/features/violations/presentation/screens/inbox_screen.dart)
- Violation review / verification flow has been built at a prototype level
- ROI configuration tooling is planned and partially represented in the project docs and UI structure

#### Visualizer
- Desktop educational visualizer exists and is useful for thesis explanation and demos
- It demonstrates violation logic and helps explain the AI pipeline to non-technical audiences

#### Architecture and project documentation
- Thesis context is documented in [docs/PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)
- Handover and session tracking are in place
- Roadmap and checklist are in [TODO.md](../TODO.md)
- Decoupled cascading pipeline documentation exists in [docs/files/AI_ENGINEERING_PLAN.md](files/AI_ENGINEERING_PLAN.md)

---

## What is still incomplete

### 1. Full enforcer dashboard workflow is not completed
The project does not yet provide a polished, end-to-end enforcer experience with:
- camera source connection
- violation selection
- ROI drawing and saving
- running inference on live stream
- running inference on offline video
- database logging in a consistent operational workflow
- history review

The current backend supports a video stream and DB logging, but the complete admin operational user flow still needs to be refined into a stable single product flow.

### 2. Live detection and non-live detection are not equally polished
The repository includes a live stream workflow and offline route structure, but not a fully integrated user-facing dashboard process for both modes in the same polished flow.

### 3. Real user notification flow is not fully complete
The mobile app contains a notifications screen, but true notification delivery from backend to user app with proof-of-violation payloads is not yet fully implemented in a complete end-to-end way.

### 4. Specialist training pipeline is not complete
The repo documents the intended training approach, but there is no confirmed end-to-end training and export workflow completed for:
- helmet_specialist.pt
- plate_specialist.pt
- cabin_specialist.pt

The project still needs actual training data preparation, specialist model training, export, and injection into the backend registry.

### 5. Full violation coverage is not yet proven
The project has architecture and documentation for multiple violations, but the system still has missing elements across the detection logic and UI for the full set of violations.

This is explicitly noted in the project TODO and handover docs, which still leave gaps for more complete violation implementations.

---

## Assessment against the goal

### Status: Partially complete, not final
We are not yet at the milestone where the only remaining tasks are:
- gather data
- train the model

Instead, the repository is currently at the stage of:
- architecture complete
- backend and dashboard scaffolding present
- detection pipeline prototyped
- some workflows implemented
- remaining system integration, UI polish, real notification flow, and model training still needed

---

## Key evidence from repo

### Project todo
The root checklist in [TODO.md](../TODO.md) explicitly says the software architecture is complete only once the remaining Django/Flutter tasks are ticked, and then the remaining step is real-world data collection and YOLO model training.

This confirms the project is not yet finished, and still has remaining work beyond data collection and training.

### Handover note
The handover document states that the next task is specifically:
- Model Training & Specialist Weights Injection

This means that the project has advanced enough to identify training as the next major step, but it has not yet fully completed the operational system surrounding it.

---

## Recommended current milestone
The project should be framed as being in the following state:

"Prototype enforcement system with strong backend architecture, partial dashboard and inbox functionality, live stream infrastructure, and detection pipeline scaffolding; remaining major work includes completing the operational end-to-end dashboard flow, real user notification delivery, specialist training and ONNX integration, and finalizing full violation coverage."

---

## Immediate conclusion
The project is well-positioned architecturally, but not yet at the target end state.

The next proper milestone after this audit is to complete the remaining integration work required to make the dashboard, backend, and mobile app operate as one coherent local system before concentrating on data gathering and model training.

---

## Summary
- Strong architecture: yes
- Full functional enforcement system: not yet
- Training-ready environment: partially ready
- Only data collection + model training remain: not yet

The system is advanced, but it still needs deeper implementation work before it reaches the final thesis-ready milestone.
