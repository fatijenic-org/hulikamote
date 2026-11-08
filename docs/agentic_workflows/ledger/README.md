# Ledger Directory

The ledger and handoff system for Huli-Kamote is organized as follows:

## Active Documents (in `docs/`)
- [`docs/PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md) - Constant thesis reference (scope, pipeline, definitions, metrics)
- [`docs/ORCHESTRATION_START.md`](../ORCHESTRATION_START.md) - Startup controller prompt (feed at the beginning of a session)
- [`docs/ORCHESTRATION_END.md`](../ORCHESTRATION_END.md) - Wrap-up controller prompt (feed at the end of a session)
- [`docs/HANDOVER.md`](../HANDOVER.md) - Active living handover for the incoming builder
- [`docs/SESSION_LOG.md`](../SESSION_LOG.md) - Detailed chronological history of all sessions (append-only)

## Handover Archives (in `docs/ledger/handovers/`)
Every session, before `docs/HANDOVER.md` is updated, the previous state is archived here:
- [`HANDOVER_SESSION_003.md`](./handovers/HANDOVER_SESSION_003.md) - Snapshot from Session 003
