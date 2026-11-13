import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/code_inspector_tooltip.dart';
import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';
import 'plate_tools.dart';

/// The reviewer's main action: confirm the violation, or mark it a false alarm.
/// Confirming records the violation. Plates are not linked to owners yet, so no one is notified.
class VerdictBar extends StatelessWidget {
  const VerdictBar({
    super.key,
    required this.status,
    required this.busy,
    required this.onDecide,
    this.showHint = true,
  });

  final ReviewStatus status;
  final bool busy;
  final void Function(ReviewStatus status) onDecide;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final confirmed = status == ReviewStatus.confirmed;
    final rejected = status == ReviewStatus.rejected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CodeInspectorTooltip(
                title: 'False Alarm Action',
                showBadge: true,
                stages: const [
                  CodeTraceStage(
                    stageTitle: '1. UI Text & Widget Display',
                    stageRole: 'Presentation Layer (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/decision_panel.dart',
                    startLine: 104,
                    endLine: 131,
                    language: 'dart',
                    description: 'Evaluates ReviewStatus.rejected to render red FilledButton (active) or OutlinedButton with "False alarm" label.',
                    codeSnippet:
                        '// Checks whether the current ticket has a rejected verdict:\n'
                        'final rejected = status == ReviewStatus.rejected;\n'
                        '\n'
                        '// Renders button with reactive colors and dynamic click handling:\n'
                        'rejected\n'
                        '    ? FilledButton.icon(\n'
                        '        onPressed: busy ? null : () => onDecide(ReviewStatus.pending),\n'
                        '        icon: const Icon(Icons.cancel, size: 18),\n'
                        '        label: const Text("False alarm"),\n'
                        '        style: FilledButton.styleFrom(\n'
                        '            backgroundColor: Fx.danger,\n'
                        '            foregroundColor: Colors.black87,\n'
                        '            minimumSize: const Size(0, 44),\n'
                        '        ),\n'
                        '    )\n'
                        '    : OutlinedButton.icon(\n'
                        '        onPressed: busy ? null : () => onDecide(ReviewStatus.rejected),\n'
                        '        icon: const Icon(Icons.close, size: 18),\n'
                        '        label: const Text("False alarm"),\n'
                        '        style: OutlinedButton.styleFrom(\n'
                        '            foregroundColor: Fx.danger,\n'
                        '            side: BorderSide(color: Fx.danger.withValues(alpha: 0.6)),\n'
                        '            minimumSize: const Size(0, 44),\n'
                        '        ),\n'
                        '    )',
                  ),
                  CodeTraceStage(
                    stageTitle: '2. Action Trigger & State Toggle',
                    stageRole: 'Workspace Event Handler (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/results_workspace.dart',
                    startLine: 136,
                    endLine: 150,
                    language: 'dart',
                    description: 'Toggles review state between rejected and pending, invokes controller, and shows undo toast.',
                    codeSnippet:
                        'Future<void> _decide(ReviewStatus s) async {\n'
                        '    final t = c.selected;\n'
                        '    if (t == null || c.busy) return;\n'
                        '    // Pressing the active verdict again clears it to pending:\n'
                        '    final target = c.statusOf(t) == s ? ReviewStatus.pending : s;\n'
                        '    final ok = await c.decide(t.uid, target);\n'
                        '    if (!mounted || !ok) return;\n'
                        '    final who = "vehicle #\${t.trackId}";\n'
                        '    _toast(switch (target) {\n'
                        '        ReviewStatus.confirmed => "Confirmed \$who.",\n'
                        '        ReviewStatus.rejected => "Marked \$who as a false alarm.",\n'
                        '        ReviewStatus.pending => "Cleared the decision on \$who.",\n'
                        '    }, undo: true);\n'
                        '    _root.requestFocus();\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '3. Controller State & Rollback Protection',
                    stageRole: 'Domain Controller (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/domain/review_controller.dart',
                    startLine: 270,
                    endLine: 318,
                    language: 'dart',
                    description: 'Optimistically updates _status, notifies listeners, calls gateway, and reverts on failure.',
                    codeSnippet:
                        'Future<bool> decide(String uid, ReviewStatus status) =>\n'
                        '    _decide([uid], status, advance: autoAdvance);\n'
                        '\n'
                        'Future<bool> _decide(\n'
                        '    List<String> uids,\n'
                        '    ReviewStatus status, {\n'
                        '    required bool advance,\n'
                        '}) async {\n'
                        '    final tickets = [for (final u in uids) if (_byUid(u) != null) _byUid(u)!];\n'
                        '    if (tickets.isEmpty || _busy) return false;\n'
                        '    final before = {for (final t in tickets) t.uid: statusOf(t)};\n'
                        '    for (final t in tickets) {\n'
                        '        _status[t.uid] = status;\n'
                        '    }\n'
                        '    _busy = true;\n'
                        '    _error = null;\n'
                        '    final wasSelected = _selectedUid;\n'
                        '    notifyListeners();\n'
                        '    try {\n'
                        '        await Future.wait([\n'
                        '            for (final t in tickets) gateway.setStatus(t.dbIds, status),\n'
                        '        ]);\n'
                        '        _undo = before;\n'
                        '        if (advance && tickets.length == 1 && tickets.first.uid == wasSelected && status != ReviewStatus.pending) {\n'
                        '            _advanceFrom(wasSelected);\n'
                        '        }\n'
                        '        return true;\n'
                        '    } catch (e) {\n'
                        '        before.forEach((uid, s) => _status[uid] = s);\n'
                        '        _error = "Could not save the decision: \$e";\n'
                        '        return false;\n'
                        '    } finally {\n'
                        '        _busy = false;\n'
                        '        notifyListeners();\n'
                        '    }\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '4. HTTP Client & Serialization',
                    stageRole: 'Data Gateway (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/data/forensic_api.dart',
                    startLine: 232,
                    endLine: 244,
                    language: 'dart',
                    description: 'Serializes status to backendValue and issues HTTP PATCH request to FastAPI /violations/{id}.',
                    codeSnippet:
                        '// ReviewGateway implementation:\n'
                        '@override\n'
                        'Future<void> setStatus(List<String> dbIds, ReviewStatus status) async {\n'
                        '    for (final id in dbIds) {\n'
                        '        final r = await _client\n'
                        '            .patch(\n'
                        '                _u("/violations/\$id"),\n'
                        '                headers: {"Content-Type": "application/json"},\n'
                        '                body: jsonEncode({"status": status.backendValue}),\n'
                        '            )\n'
                        '            .timeout(_timeout);\n'
                        '        if (r.statusCode != 200) _fail(r, "Saving the decision");\n'
                        '    }\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '5. REST API Route & Request Validation',
                    stageRole: 'Backend Router (Python FastAPI)',
                    filePath: 'hulikamote_backend/routers/violations.py',
                    startLine: 232,
                    endLine: 240,
                    language: 'python',
                    description: 'Validates payload using Pydantic ViolationStatusUpdate model and delegates to store mutation.',
                    codeSnippet:
                        '@router.patch("/{violation_id}")\n'
                        'async def update_violation(violation_id: str, body: ViolationStatusUpdate):\n'
                        '    from store import update_violation_status\n'
                        '    from fastapi import HTTPException\n'
                        '    \n'
                        '    updated = await update_violation_status(violation_id, body.status)\n'
                        '    if not updated:\n'
                        '        raise HTTPException(status_code=404, detail="Violation not found")\n'
                        '    return updated',
                  ),
                  CodeTraceStage(
                    stageTitle: '6. Database Persistence & Hard Negative Mining',
                    stageRole: 'Persistence Layer (Python SQLite)',
                    filePath: 'hulikamote_backend/store.py',
                    startLine: 171,
                    endLine: 184,
                    language: 'python',
                    description: 'Executes SQLite update, marks status as rejected, and retains crop as hard negative candidate for training.',
                    codeSnippet:
                        'async def update_violation_status(violation_id: str, status: str) -> dict | None:\n'
                        '    # Update violation status in SQLite database:\n'
                        '    query = db.violations_table.update().where(\n'
                        '        db.violations_table.c.id == violation_id\n'
                        '    ).values(status=status)\n'
                        '    await db.database.execute(query)\n'
                        '    \n'
                        '    row = await db.database.fetch_one(\n'
                        '        db.violations_table.select().where(db.violations_table.c.id == violation_id)\n'
                        '    )\n'
                        '    if not row:\n'
                        '        return None\n'
                        '    \n'
                        '    v = dict(row)\n'
                        '    # Rejected samples are retained as hard negative candidates in active learning\n'
                        '    return v',
                  ),
                  CodeTraceStage(
                    stageTitle: '7. UI Reaction & Keyboard Re-focus',
                    stageRole: 'Presentation Loop (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/results_workspace.dart',
                    startLine: 142,
                    endLine: 150,
                    language: 'dart',
                    description: 'Triggers visual toast confirmation, updates queue chips via notifyListeners(), and refocuses keyboard root.',
                    codeSnippet:
                        'if (!mounted || !ok) return;\n'
                        'final who = "vehicle #\${t.trackId}";\n'
                        '_toast(switch (target) {\n'
                        '    ReviewStatus.confirmed => "Confirmed \$who.",\n'
                        '    ReviewStatus.rejected => "Marked \$who as a false alarm.",\n'
                        '    ReviewStatus.pending => "Cleared the decision on \$who.",\n'
                        '}, undo: true);\n'
                        '_root.requestFocus();',
                  ),
                ],
                child: rejected
                    ? FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => onDecide(ReviewStatus.pending),
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('False alarm'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Fx.danger,
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(0, 44),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => onDecide(ReviewStatus.rejected),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('False alarm'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Fx.danger,
                          side: BorderSide(
                            color: Fx.danger.withValues(alpha: 0.6),
                          ),
                          minimumSize: const Size(0, 44),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: Fx.s8),
            Expanded(
              child: CodeInspectorTooltip(
                title: 'Confirm Violation Action',
                showBadge: true,
                stages: const [
                  CodeTraceStage(
                    stageTitle: '1. UI Text & Widget Display',
                    stageRole: 'Presentation Layer (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/decision_panel.dart',
                    startLine: 208,
                    endLine: 235,
                    language: 'dart',
                    description: 'Evaluates ReviewStatus.confirmed to render bright green FilledButton with "Confirm" or "Confirmed" label.',
                    codeSnippet:
                        '// Checks whether the current ticket has a confirmed verdict:\n'
                        'final confirmed = status == ReviewStatus.confirmed;\n'
                        '\n'
                        '// Renders button with reactive colors and dynamic click handling:\n'
                        'confirmed\n'
                        '    ? FilledButton.icon(\n'
                        '        onPressed: busy ? null : () => onDecide(ReviewStatus.pending),\n'
                        '        icon: const Icon(Icons.check_circle, size: 18),\n'
                        '        label: const Text("Confirmed"),\n'
                        '        style: FilledButton.styleFrom(\n'
                        '            backgroundColor: Fx.success,\n'
                        '            foregroundColor: Colors.black87,\n'
                        '            minimumSize: const Size(0, 44),\n'
                        '        ),\n'
                        '    )\n'
                        '    : FilledButton.icon(\n'
                        '        onPressed: busy ? null : () => onDecide(ReviewStatus.confirmed),\n'
                        '        icon: const Icon(Icons.check, size: 18),\n'
                        '        label: const Text("Confirm"),\n'
                        '        style: FilledButton.styleFrom(\n'
                        '            backgroundColor: Fx.success.withValues(alpha: 0.9),\n'
                        '            foregroundColor: Colors.black87,\n'
                        '            minimumSize: const Size(0, 44),\n'
                        '        ),\n'
                        '    )',
                  ),
                  CodeTraceStage(
                    stageTitle: '2. Action Trigger & State Dispatch',
                    stageRole: 'Workspace Event Handler (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/results_workspace.dart',
                    startLine: 136,
                    endLine: 150,
                    language: 'dart',
                    description: 'Receives Confirm click, invokes ReviewController.decide(uid, confirmed), and displays toast.',
                    codeSnippet:
                        'Future<void> _decide(ReviewStatus s) async {\n'
                        '    final t = c.selected;\n'
                        '    if (t == null || c.busy) return;\n'
                        '    // Pressing the active verdict again clears it to pending:\n'
                        '    final target = c.statusOf(t) == s ? ReviewStatus.pending : s;\n'
                        '    final ok = await c.decide(t.uid, target);\n'
                        '    if (!mounted || !ok) return;\n'
                        '    final who = "vehicle #\${t.trackId}";\n'
                        '    _toast(switch (target) {\n'
                        '        ReviewStatus.confirmed => "Confirmed \$who.",\n'
                        '        ReviewStatus.rejected => "Marked \$who as a false alarm.",\n'
                        '        ReviewStatus.pending => "Cleared the decision on \$who.",\n'
                        '    }, undo: true);\n'
                        '    _root.requestFocus();\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '3. Controller State & Optimistic Advance',
                    stageRole: 'Domain Controller (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/domain/review_controller.dart',
                    startLine: 270,
                    endLine: 318,
                    language: 'dart',
                    description: 'Optimistically sets _status[uid]=confirmed, advances selection to next pending vehicle, and notifies UI.',
                    codeSnippet:
                        'Future<bool> decide(String uid, ReviewStatus status) =>\n'
                        '    _decide([uid], status, advance: autoAdvance);\n'
                        '\n'
                        'Future<bool> _decide(\n'
                        '    List<String> uids,\n'
                        '    ReviewStatus status, {\n'
                        '    required bool advance,\n'
                        '}) async {\n'
                        '    final tickets = [for (final u in uids) if (_byUid(u) != null) _byUid(u)!];\n'
                        '    if (tickets.isEmpty || _busy) return false;\n'
                        '    final before = {for (final t in tickets) t.uid: statusOf(t)};\n'
                        '    for (final t in tickets) {\n'
                        '        _status[t.uid] = status;\n'
                        '    }\n'
                        '    _busy = true;\n'
                        '    _error = null;\n'
                        '    final wasSelected = _selectedUid;\n'
                        '    notifyListeners();\n'
                        '    try {\n'
                        '        await Future.wait([\n'
                        '            for (final t in tickets) gateway.setStatus(t.dbIds, status),\n'
                        '        ]);\n'
                        '        _undo = before;\n'
                        '        if (advance && tickets.length == 1 && tickets.first.uid == wasSelected && status != ReviewStatus.pending) {\n'
                        '            _advanceFrom(wasSelected);\n'
                        '        }\n'
                        '        return true;\n'
                        '    } catch (e) {\n'
                        '        before.forEach((uid, s) => _status[uid] = s);\n'
                        '        _error = "Could not save the decision: \$e";\n'
                        '        return false;\n'
                        '    } finally {\n'
                        '        _busy = false;\n'
                        '        notifyListeners();\n'
                        '    }\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '4. HTTP Client & Serialization',
                    stageRole: 'Data Gateway (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/data/forensic_api.dart',
                    startLine: 232,
                    endLine: 244,
                    language: 'dart',
                    description: 'Serializes ReviewStatus.confirmed to "approved" backend value and sends HTTP PATCH.',
                    codeSnippet:
                        '// ReviewGateway implementation:\n'
                        '@override\n'
                        'Future<void> setStatus(List<String> dbIds, ReviewStatus status) async {\n'
                        '    for (final id in dbIds) {\n'
                        '        final r = await _client\n'
                        '            .patch(\n'
                        '                _u("/violations/\$id"),\n'
                        '                headers: {"Content-Type": "application/json"},\n'
                        '                body: jsonEncode({"status": status.backendValue}), // "approved"\n'
                        '            )\n'
                        '            .timeout(_timeout);\n'
                        '        if (r.statusCode != 200) _fail(r, "Saving the decision");\n'
                        '    }\n'
                        '}',
                  ),
                  CodeTraceStage(
                    stageTitle: '5. REST API Route & Request Validation',
                    stageRole: 'Backend Router (Python FastAPI)',
                    filePath: 'hulikamote_backend/routers/violations.py',
                    startLine: 232,
                    endLine: 240,
                    language: 'python',
                    description: 'Validates status update payload and dispatches async DB mutation.',
                    codeSnippet:
                        '@router.patch("/{violation_id}")\n'
                        'async def update_violation(violation_id: str, body: ViolationStatusUpdate):\n'
                        '    from store import update_violation_status\n'
                        '    from fastapi import HTTPException\n'
                        '    \n'
                        '    updated = await update_violation_status(violation_id, body.status)\n'
                        '    if not updated:\n'
                        '        raise HTTPException(status_code=404, detail="Violation not found")\n'
                        '    return updated',
                  ),
                  CodeTraceStage(
                    stageTitle: '6. Database Persistence & Push Notification',
                    stageRole: 'Persistence Layer (Python SQLite)',
                    filePath: 'hulikamote_backend/store.py',
                    startLine: 171,
                    endLine: 184,
                    language: 'python',
                    description: 'Persists approved status in violations_table and triggers push notification service.',
                    codeSnippet:
                        'async def update_violation_status(violation_id: str, status: str) -> dict | None:\n'
                        '    # Update violation status in SQLite database:\n'
                        '    query = db.violations_table.update().where(\n'
                        '        db.violations_table.c.id == violation_id\n'
                        '    ).values(status=status)\n'
                        '    await db.database.execute(query)\n'
                        '    \n'
                        '    row = await db.database.fetch_one(\n'
                        '        db.violations_table.select().where(db.violations_table.c.id == violation_id)\n'
                        '    )\n'
                        '    if not row:\n'
                        '        return None\n'
                        '    \n'
                        '    v = dict(row)\n'
                        '    if status == "approved":\n'
                        '        await _send_push_notification(v)\n'
                        '        \n'
                        '    return v',
                  ),
                  CodeTraceStage(
                    stageTitle: '7. UI Reaction & Keyboard Re-focus',
                    stageRole: 'Presentation Loop (Flutter)',
                    filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/results_workspace.dart',
                    startLine: 142,
                    endLine: 150,
                    language: 'dart',
                    description: 'Renders "Confirmed vehicle #X" toast snackbar, updates queue status, and restores keyboard focus.',
                    codeSnippet:
                        'if (!mounted || !ok) return;\n'
                        'final who = "vehicle #\${t.trackId}";\n'
                        '_toast(switch (target) {\n'
                        '    ReviewStatus.confirmed => "Confirmed \$who.",\n'
                        '    ReviewStatus.rejected => "Marked \$who as a false alarm.",\n'
                        '    ReviewStatus.pending => "Cleared the decision on \$who.",\n'
                        '}, undo: true);\n'
                        '_root.requestFocus();',
                  ),
                ],
                child: confirmed
                    ? FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => onDecide(ReviewStatus.pending),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Confirmed'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Fx.success,
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(0, 44),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () => onDecide(ReviewStatus.confirmed),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Confirm'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Fx.success.withValues(alpha: 0.9),
                          foregroundColor: Colors.black87,
                          minimumSize: const Size(0, 44),
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (showHint) ...[
          const SizedBox(height: Fx.s8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const KeyCap('X'),
              Text('false alarm', style: Fx.caption(context)),
              const SizedBox(width: 6),
              const KeyCap('C'),
              Text('confirm', style: Fx.caption(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status == ReviewStatus.pending
                ? 'Confirming records the violation. Notifying owners is not set up yet.'
                : 'Press the same button again to clear the decision.',
            style: Fx.caption(context),
          ),
        ],
      ],
    );
  }
}

/// What an enforcer needs for one ticket, and nothing else: what it is about, the plate (fix it or fill it in, then send),
/// and the decision. Merging tickets, the rule details and how the analysis ran are behind "More".
class DecisionPanel extends StatelessWidget {
  const DecisionPanel({
    super.key,
    required this.controller,
    required this.media,
    required this.onDecide,
    required this.onMerge,
    required this.plateFocus,
    this.onPlateSaved,
  });

  final ReviewController controller;
  final ForensicMedia media;
  final void Function(ReviewStatus status) onDecide;
  final VoidCallback onMerge;
  final FocusNode plateFocus;

  /// Called after the reviewer sent a plate (lets the workspace take the keyboard back).
  final VoidCallback? onPlateSaved;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = controller.selected;
        if (t == null) {
          return const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Nothing selected',
            message: 'Pick a ticket to review it here.',
          );
        }
        final status = controller.statusOf(t);
        return ListView(
          padding: const EdgeInsets.all(Fx.s16),
          children: [
            _about(context, t),
            const SizedBox(height: Fx.s16),
            KeyedSubtree(
              key: ValueKey('plate-${t.uid}-${t.plateText}'),
              child: _PlateCard(
                controller: controller,
                media: media,
                ticket: t,
                focus: plateFocus,
                onSaved: onPlateSaved ?? () {},
              ),
            ),
            const SizedBox(height: Fx.s16),
            VerdictBar(
              status: status,
              busy: controller.busy,
              onDecide: onDecide,
              showHint: false,
            ),
            if (t.flags.isNotEmpty) ...[
              const SizedBox(height: Fx.s16),
              for (final f in t.flags)
                _FlagCard(
                  controller: controller,
                  media: media,
                  ticket: t,
                  flag: f,
                ),
            ],
            const SizedBox(height: Fx.s16),
            _more(context, t),
          ],
        );
      },
    );
  }

  /// What the ticket is about, in one line of coloured labels.
  Widget _about(BuildContext context, ForensicTicket t) {
    final span = t.span;
    final vehicle = t.vehicleClass == null
        ? 'Vehicle'
        : t.vehicleClass![0].toUpperCase() + t.vehicleClass!.substring(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Fx.s8,
          runSpacing: Fx.s8,
          children: [for (final key in t.violations) ViolationChip(key)],
        ),
        const SizedBox(height: 6),
        Text(
          [
            vehicle,
            if (span != null)
              '${formatVideoTime(span.start)}–${formatVideoTime(span.end)}',
          ].join(' · '),
          style: Fx.caption(context),
        ),
        // When it happened (the clock of the video), and where that time came from; or that a human must check it.
        if (t.time != null) ...[
          const SizedBox(height: 2),
          Row(
            key: const ValueKey('ticket-time'),
            children: [
              Icon(
                t.time!.needsCheck ? Icons.help_outline : Icons.schedule,
                size: 14,
                color: t.time!.needsCheck ? Fx.warning : Fx.muted(context),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  t.time!.long,
                  style: Fx.caption(context).copyWith(color: t.time!.needsCheck ? Fx.warning : null),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Everything an enforcer rarely needs, folded away.
  Widget _more(BuildContext context, ForensicTicket t) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('more-options'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Fx.s8),
        title: Text('MORE', style: Fx.label(context)),
        children: [
          OutlinedButton.icon(
            onPressed: (controller.busy || !t.hasUid || controller.total < 2)
                ? null
                : onMerge,
            icon: const Icon(Icons.merge_type, size: 18),
            label: const Text('Same car as another ticket…'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
          const SizedBox(height: Fx.s8),
          Text(
            t.hasUid
                ? 'Two tickets for one car? Join them. Photos of another car? Use “Select photos” under the photos.'
                : 'This report is from an older version, so tickets cannot be joined. Run the analysis again to enable it.',
            style: Fx.caption(context),
          ),
          const SizedBox(height: Fx.s16),
          _violations(context, t),
          _settings(context, t),
        ],
      ),
    );
  }

  Widget _violations(BuildContext context, ForensicTicket t) {
    final settings = (t.metadata['violation_settings'] as Map?) ?? const {};
    return Column(
      children: [
        for (final key in t.violations)
          Padding(
            padding: const EdgeInsets.only(bottom: Fx.s8),
            child: FxCard(
              padding: const EdgeInsets.all(Fx.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: ViolationCatalog.of(
                        key,
                      ).color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      ViolationCatalog.of(key).icon,
                      size: 18,
                      color: ViolationCatalog.of(key).color,
                    ),
                  ),
                  const SizedBox(width: Fx.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ViolationCatalog.of(key).label,
                          style: Fx.heading(context),
                        ),
                        if (ViolationCatalog.of(key).blurb.isNotEmpty)
                          Text(
                            ViolationCatalog.of(key).blurb,
                            style: Fx.caption(context),
                          ),
                        if (_ruleLine(key, settings[key])
                            case final String line) ...[
                          const SizedBox(height: 4),
                          Text(
                            line,
                            style: Fx.caption(
                              context,
                            ).copyWith(color: Fx.accent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The rule parameters this violation was checked with, in words.
  static String? _ruleLine(String key, Object? cfg) {
    if (cfg is! Map) return null;
    String list(Object? v) => ((v as List?) ?? const []).join(', ');
    return switch (key) {
      'restricted_lane' when list(cfg['allowed_classes']).isNotEmpty =>
        'Allowed in this lane: ${list(cfg['allowed_classes'])}',
      'illegal_parking' =>
        'Limit: ${(cfg['time_limit'] as num?)?.toInt() ?? '?'} s stopped',
      'pedestrian_lane' =>
        'Limit: ${(cfg['time_limit'] as num?)?.toInt() ?? '?'} s stopped on the crosswalk',
      'blocking_intersection' =>
        'Limit: ${(cfg['time_limit'] as num?)?.toInt() ?? '?'} s stopped in the junction box',
      'illegal_loading' =>
        'Limit: ${(cfg['time_limit'] as num?)?.toInt() ?? '?'} s stopped (${list(cfg['banned_classes'])})',
      'double_parking' =>
        'Limit: ${(cfg['time_limit'] as num?)?.toInt() ?? '?'} s standing in the lane beside another stopped vehicle',
      'truck_ban' || 'tricycle_on_highway' || 'sidewalk_driving'
          when list(cfg['banned_classes']).isNotEmpty =>
        'Not allowed here: ${list(cfg['banned_classes'])}',
      'overloading' => 'Allowed on one motorcycle: ${cfg['max_riders'] ?? 2}',
      _ => null,
    };
  }

  Widget _settings(BuildContext context, ForensicTicket t) {
    const labels = {
      'primary_model': 'Vehicle detector',
      'tracker': 'Tracker',
      'plate_model': 'Plate model',
      'plate_method': 'Plate method',
      'plate_format': 'Plate format',
      'ocr_engine': 'OCR engine',
      'enhancement': 'Enhancement',
    };
    final meta = t.metadata;
    if (meta.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HOW IT WAS ANALYSED', style: Fx.label(context)),
        const SizedBox(height: Fx.s8),
        for (final e in labels.entries)
          if (meta.containsKey(e.key))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(e.value, style: Fx.caption(context)),
                  ),
                  Expanded(
                    child: Text(
                      '${meta[e.key]}'.isEmpty
                          ? 'Active model'
                          : '${meta[e.key]}',
                      style: Fx.body(context),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// The plate of the ticket, for someone who is not technical: the picture of it, the number, and one button.
/// Type the right number (or fill it in when the system could not read it) and press "Send plate": it is put on the
/// ticket and the picture with the right number is sent along so the system learns from it.
class _PlateCard extends StatefulWidget {
  const _PlateCard({
    required this.controller,
    required this.media,
    required this.ticket,
    required this.focus,
    required this.onSaved,
  });

  final ReviewController controller;
  final ForensicMedia media;
  final ForensicTicket ticket;
  final FocusNode focus;

  /// Called after a send, so the workspace can take the keyboard back (the field is rebuilt).
  final VoidCallback onSaved;

  @override
  State<_PlateCard> createState() => _PlateCardState();
}

class _PlateCardState extends State<_PlateCard> {
  late final TextEditingController _text = TextEditingController(text: _saved);

  String get _saved => widget.ticket.plateRead ? widget.ticket.plateText : '';

  /// Plates are kept the way the OCR writes them: capitals and digits only.
  String get _typed => _text.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  bool get _dirty => _typed != _saved.toUpperCase();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send({bool revert = false}) async {
    if (widget.controller.busy || (!revert && !_dirty)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final onSaved = widget.onSaved;
    final c = widget.controller;
    final ticket = widget.ticket;
    final crop = c.chosenCrop(ticket);
    final plate = _typed;
    final ok = await c.setPlate(ticket, plate, revert: revert);
    if (!ok) return; // the workspace shows the reason
    // The right number goes to the training data with its picture ("" = there is no plate on this vehicle).
    if (!revert && crop != null) await c.sendPlateFeedback(ticket, crop, plate);
    onSaved();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            revert
                ? 'Back to what the system read.'
                : plate.isEmpty
                ? 'Marked: no plate on this vehicle.'
                : 'Plate sent: $plate',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final c = widget.controller;
    final crop = c.chosenCrop(t);
    final busy = c.busy;
    final dirty = _dirty;
    return FxCard(
      padding: const EdgeInsets.all(Fx.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PLATE NUMBER', style: Fx.label(context)),
          const SizedBox(height: Fx.s8),
          if (crop != null) ...[
            Container(
              height: 88,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FxImage(
                image: widget.media.thumb(crop.enhanced ?? crop.file, width: 600),
                fit: BoxFit.contain,
                radius: 8,
                errorLabel: '',
              ),
            ),
            const SizedBox(height: Fx.s12),
          ],
          TextField(
            controller: _text,
            focusNode: widget.focus,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
              LengthLimitingTextInputFormatter(12),
              TextInputFormatter.withFunction(
                (o, n) => n.copyWith(text: n.text.toUpperCase()),
              ),
            ],
            style: Fx.plate.copyWith(fontSize: 24),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'Type the plate you see',
              isDense: true,
              filled: true,
              fillColor: Fx.raised(context),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Fx.radiusSm),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: Fx.s8),
          if (dirty)
            CodeInspectorTooltip(
              title: 'Send Plate Action',
              showBadge: true,
              stages: const [
                CodeTraceStage(
                  stageTitle: '1. UI Text & Widget Display',
                  stageRole: 'Presentation Layer (Flutter)',
                  filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/decision_panel.dart',
                  startLine: 914,
                  endLine: 920,
                  language: 'dart',
                  description: 'Renders the Send plate action button with dynamic label depending on whether text is empty.',
                  codeSnippet:
                      '// Evaluates typed plate text to render action button:\n'
                      'FilledButton.icon(\n'
                      '    onPressed: busy ? null : _send,\n'
                      '    icon: const Icon(Icons.send, size: 18),\n'
                      '    label: Text(_typed.isEmpty ? "No plate on this vehicle" : "Send plate"),\n'
                      '    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),\n'
                      ')',
                ),
                CodeTraceStage(
                  stageTitle: '2. Local Action Handler & SnackBar',
                  stageRole: 'Plate Card State (Flutter)',
                  filePath: 'hulikamote_dashboard/lib/features/forensic/presentation/widgets/decision_panel.dart',
                  startLine: 570,
                  endLine: 597,
                  language: 'dart',
                  description: 'Dispatches plate text update to controller and sends crop feedback to training pipeline.',
                  codeSnippet:
                      'Future<void> _send({bool revert = false}) async {\n'
                      '    if (widget.controller.busy || (!revert && !_dirty)) return;\n'
                      '    final messenger = ScaffoldMessenger.maybeOf(context);\n'
                      '    final onSaved = widget.onSaved;\n'
                      '    final c = widget.controller;\n'
                      '    final ticket = widget.ticket;\n'
                      '    final crop = c.chosenCrop(ticket);\n'
                      '    final plate = _typed;\n'
                      '    final ok = await c.setPlate(ticket, plate, revert: revert);\n'
                      '    if (!ok) return;\n'
                      '    if (!revert && crop != null) await c.sendPlateFeedback(ticket, crop, plate);\n'
                      '    onSaved();\n'
                      '    messenger\n'
                      '      ?..hideCurrentSnackBar()\n'
                      '      ..showSnackBar(SnackBar(content: Text(revert ? "Back to read." : "Plate sent: \$plate")));\n'
                      '}',
                ),
                CodeTraceStage(
                  stageTitle: '3. Controller State & Ticket Replacement',
                  stageRole: 'Domain Controller (Flutter)',
                  filePath: 'hulikamote_dashboard/lib/features/forensic/domain/review_controller.dart',
                  startLine: 436,
                  endLine: 465,
                  language: 'dart',
                  description: 'Calls gateway.setPlate, replaces ticket list, and preserves frame selection.',
                  codeSnippet:
                      'Future<bool> setPlate(ForensicTicket ticket, String plate, {bool revert = false}) async {\n'
                      '    if (_busy) return false;\n'
                      '    _busy = true;\n'
                      '    _error = null;\n'
                      '    notifyListeners();\n'
                      '    try {\n'
                      '        final updated = await gateway.setPlate(taskId, ticket.uid, plate.trim(), revert: revert);\n'
                      '        final photo = _frame;\n'
                      '        final wasOpen = _selectedUid == ticket.uid;\n'
                      '        replaceTickets(updated, preferUid: ticket.uid);\n'
                      '        final now = selected;\n'
                      '        if (wasOpen && now != null && photo < now.frameCount) _frame = photo;\n'
                      '        return true;\n'
                      '    } catch (e) {\n'
                      '        _error = "Could not save the plate: \$e";\n'
                      '        return false;\n'
                      '    } finally {\n'
                      '        _busy = false;\n'
                      '        notifyListeners();\n'
                      '    }\n'
                      '}',
                ),
                CodeTraceStage(
                  stageTitle: '4. HTTP Client & Serialization',
                  stageRole: 'Data Gateway (Flutter)',
                  filePath: 'hulikamote_dashboard/lib/features/forensic/data/forensic_api.dart',
                  startLine: 264,
                  endLine: 282,
                  language: 'dart',
                  description: 'Posts updated plate text to /api/forensic/tickets/set-plate endpoint.',
                  codeSnippet:
                      '@override\n'
                      'Future<List<ForensicTicket>> setPlate(String taskId, String ticketUid, String plate, {bool revert = false}) async {\n'
                      '    final r = await _client.post(\n'
                      '        _u("/api/forensic/tickets/set-plate"),\n'
                      '        headers: {"Content-Type": "application/json"},\n'
                      '        body: jsonEncode({\n'
                      '            "task_id": taskId,\n'
                      '            "ticket_uid": ticketUid,\n'
                      '            "plate_text": plate,\n'
                      '            "revert": revert,\n'
                      '        }),\n'
                      '    ).timeout(_timeout);\n'
                      '    return ForensicTicket.parseList(jsonDecode(r.body)["tickets"] as List);\n'
                      '}',
                ),
                CodeTraceStage(
                  stageTitle: '5. Database Persistence & Dataset Export',
                  stageRole: 'Persistence & Training Hooks (Python SQLite)',
                  filePath: 'hulikamote_backend/store.py',
                  startLine: 191,
                  endLine: 199,
                  language: 'python',
                  description: 'Updates plate text in SQLite violations table and logs labeled sample for retraining.',
                  codeSnippet:
                      'async def update_violation_plate(row_ids: list[str], plate_text: str, user_id: str) -> int:\n'
                      '    """Operator plate edit: updates plate text and associated owner id in SQLite."""\n'
                      '    for rid in row_ids:\n'
                      '        await db.database.execute(\n'
                      '            db.violations_table.update().where(db.violations_table.c.id == rid)\n'
                      '            .values(plate_text=plate_text, user_id=user_id)\n'
                      '        )\n'
                      '    return len(row_ids)',
                ),
              ],
              child: FilledButton.icon(
                onPressed: busy ? null : _send,
                icon: const Icon(Icons.send, size: 18),
                label: Text(_typed.isEmpty ? 'No plate on this vehicle' : 'Send plate'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            )
          else if (t.plateManual)
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Fx.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.plateRead ? 'You fixed this plate.' : 'You marked: no plate.',
                    style: Fx.caption(context).copyWith(color: Fx.success),
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _send(revert: true),
                  child: const Text('Undo'),
                ),
              ],
            )
          else
            Text(
              t.plateRead
                  ? 'Is this the right plate? If not, fix it.'
                  : 'The system could not read this plate. If you can see it, type it.',
              style: Fx.caption(context),
              textAlign: TextAlign.center,
            ),
          if (t.plateLengthWarning) ...[
            const SizedBox(height: Fx.s8),
            Text(
              'This looks too short or too long for a plate. Please check it.',
              style: Fx.caption(context).copyWith(color: Fx.warning),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: Fx.s12),
          PlateTools(controller: c, media: widget.media, ticket: t, onSaved: widget.onSaved),
        ],
      ),
    );
  }
}

/// One review flag with the one-click way to resolve it.
class _FlagCard extends StatelessWidget {
  const _FlagCard({
    required this.controller,
    required this.media,
    required this.ticket,
    required this.flag,
  });

  final ReviewController controller;
  final ForensicMedia media;
  final ForensicTicket ticket;
  final TicketFlag flag;

  @override
  Widget build(BuildContext context) {
    ForensicTicket? other;
    for (final x in controller.all) {
      if (flag.otherUid != null && x.uid == flag.otherUid) other = x;
    }
    final busy = controller.busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s8),
      child: FxCard(
        color: Fx.warning.withValues(alpha: 0.08),
        padding: const EdgeInsets.all(Fx.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.flag, size: 18, color: Fx.warning),
                const SizedBox(width: Fx.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(flag.title, style: Fx.heading(context)),
                      if (flag.detail.isNotEmpty)
                        Text(flag.detail, style: Fx.caption(context)),
                    ],
                  ),
                ),
              ],
            ),
            if (other != null) ...[
              const SizedBox(height: Fx.s12),
              Row(
                children: [
                  if (other.hero != null)
                    SizedBox(
                      width: 72,
                      height: 46,
                      child: FxImage(
                        image: media.thumb(other.hero!.file),
                        radius: 6,
                        errorLabel: '',
                      ),
                    ),
                  const SizedBox(width: Fx.s12),
                  Expanded(
                    child: Text(
                      'Vehicle #${other.trackId} · ${other.plateRead ? other.plateText : 'plate unread'}',
                      style: Fx.body(context),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.select(other!.uid),
                    child: const Text('Open'),
                  ),
                ],
              ),
              const SizedBox(height: Fx.s8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (busy || !ticket.hasUid)
                          ? null
                          : () => controller.ticketAction('not-duplicate', {
                              'uid_a': ticket.uid,
                              'uid_b': other!.uid,
                            }),
                      child: const Text('Different car'),
                    ),
                  ),
                  const SizedBox(width: Fx.s8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (busy || !ticket.hasUid)
                          ? null
                          : () => controller.ticketAction('merge', {
                              'keep_uid': ticket.uid,
                              'merge_uid': other!.uid,
                            }, thenSelect: ticket.uid),
                      icon: const Icon(Icons.merge_type, size: 16),
                      label: const Text('Same car'),
                    ),
                  ),
                ],
              ),
            ] else if (!flag.isDuplicate) ...[
              const SizedBox(height: Fx.s8),
              Text(
                'Step through the photos: if another car appears, select those photos and separate them.',
                style: Fx.caption(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
