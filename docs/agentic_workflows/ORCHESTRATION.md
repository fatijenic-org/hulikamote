# HULI-KAMOTE - ORCHESTRATION OVERVIEW
======================================

The orchestration protocol is divided into two self-contained prompt files:

1. **[`docs/ORCHESTRATION_START.md`](./ORCHESTRATION_START.md)**
   - **When to use:** At the very beginning of a new session.
   - **What it does:** Feeds full project context, thesis background, operational rules, and commands the AI to read `docs/HANDOVER.md` and `docs/SESSION_LOG.md` to cold-start immediately.

2. **[`docs/ORCHESTRATION_END.md`](./ORCHESTRATION_END.md)**
   - **When to use:** At the end of a session when you want to wrap up and hand off.
   - **What it does:** Commands the AI to archive the current handover to `docs/ledger/handovers/`, update the active `docs/HANDOVER.md`, and append a new audit entry to `docs/SESSION_LOG.md`.

Both files are completely self-contained and reference **[`docs/PROJECT_CONTEXT.md`](./PROJECT_CONTEXT.md)** for canonical thesis scope and definitions.
