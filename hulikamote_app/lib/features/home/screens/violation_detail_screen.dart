import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/photo_source.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/widgets/frame_gallery.dart';
import '../../appeals/screens/appeal_screen.dart';
import '../models/appeal_state.dart';
import '../models/violation.dart';

/// One ticket: its photos, the facts, what happened so far, and (while allowed) the way to appeal it.
class ViolationDetailScreen extends StatefulWidget {
  const ViolationDetailScreen({super.key, required this.violation, this.appealStatus, this.api});

  final Violation violation;

  /// null, pending, accepted or rejected.
  final String? appealStatus;
  final PortalApi? api;

  @override
  State<ViolationDetailScreen> createState() => _ViolationDetailScreenState();
}

class _ViolationDetailScreenState extends State<ViolationDetailScreen> {
  late String? _status = widget.appealStatus;
  bool _changed = false;                // an appeal was sent from here, so the list should refresh

  Violation get v => widget.violation;

  Future<void> _appeal() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AppealScreen(violation: v, api: widget.api)));
    if (sent == true && mounted) {
      setState(() {
        _status = 'pending';
        _changed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppealState.of(_status);
    final hasPhotos = v.evidencePaths.isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        body: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: hasPhotos ? 260 : 0,
            backgroundColor: context.colors.surface,
            leading: Padding(
              padding: const EdgeInsets.all(Sp.x2),
              child: CircleAvatar(
                backgroundColor: context.colors.surface.withValues(alpha: 0.9),
                child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop(_changed)),
              ),
            ),
            flexibleSpace: hasPhotos
                ? FlexibleSpaceBar(
                    background: Semantics(
                      button: true,
                      label: 'Open the photos of this ticket',
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FrameViewer(names: v.evidencePaths))),
                        child: Image.network(
                          PhotoSource.url(v.evidencePaths.first),
                          headers: PhotoSource.headers,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: context.colors.primaryContainer, child: Icon(iconForViolation(v.cls), size: 56, color: context.colors.onPrimaryContainer)),
                          loadingBuilder: (c, child, progress) => progress == null ? child : const Skeleton(height: 260, radius: 0),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x5, Sp.page, Sp.x6),
            sliver: SliverList.list(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Semantics(header: true, child: Text(v.displayClass, style: context.text.headlineSmall))),
                const SizedBox(width: Sp.x3),
                StatusChip(label: state.label, tone: state.tone, icon: state.icon),
              ]),
              const SizedBox(height: Sp.x1),
              Text(dateTimeOf(v.time, v.timestamp), style: context.text.bodyLarge?.copyWith(color: context.muted)),
              const SizedBox(height: Sp.x5),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x1),
                  child: Column(children: [
                    if (v.plate.isNotEmpty) ...[FactRow(label: 'Plate', value: v.plate), const Divider()],
                    FactRow(
                      label: 'Case number',
                      value: v.caseNo,
                      trailing: IconButton(
                        tooltip: 'Copy case number',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: v.caseNo));
                          if (context.mounted) AppToast.show(context, 'Case number copied.');
                        },
                      ),
                    ),
                  ]),
                ),
              ),
              if (hasPhotos) ...[
                const SizedBox(height: Sp.x6),
                FrameGallery(names: v.evidencePaths),
              ],
              const SizedBox(height: Sp.x6),
              const SectionTitle('What happened'),
              Card(child: Padding(padding: const EdgeInsets.all(Sp.x4), child: _Timeline(violation: v, state: state))),
            ]),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x3),
            decoration: BoxDecoration(color: context.colors.surface, border: Border(top: BorderSide(color: context.colors.outlineVariant))),
            child: state.open
                ? AppButton(label: 'Appeal this ticket', icon: Icons.gavel_rounded, onPressed: _appeal)
                : Row(children: [
                    StatusChip(label: state.label, tone: state.tone, icon: state.icon),
                    const SizedBox(width: Sp.x3),
                    Expanded(child: Text(state.explain, style: context.text.bodyMedium?.copyWith(color: context.muted))),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// The ticket's story, top to bottom: what is done, and what is next.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.violation, required this.state});

  final Violation violation;
  final AppealState state;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _Step('Seen by the camera', dateTimeOf(violation.time, violation.timestamp), Icons.videocam_outlined, _Mark.done),
      const _Step('Confirmed by a reviewer', 'A person checked the photos.', Icons.verified_outlined, _Mark.done),
      const _Step('You were notified', 'The notice is in your Inbox.', Icons.notifications_active_outlined, _Mark.done),
      _Step(
        state.open ? 'Your appeal' : state.label,
        state.open ? 'Not sent. You can appeal this ticket once.' : state.explain,
        state.icon,
        switch (state.status) {
          'accepted' => _Mark.done,
          'rejected' => _Mark.bad,
          _ => _Mark.next,
        },
      ),
    ];
    return Column(children: [
      for (var i = 0; i < steps.length; i++) _StepRow(step: steps[i], last: i == steps.length - 1),
    ]);
  }
}

enum _Mark { done, next, bad }

class _Step {
  const _Step(this.title, this.detail, this.icon, this.mark);

  final String title;
  final String detail;
  final IconData icon;
  final _Mark mark;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});

  final _Step step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final (Color back, Color front) = switch (step.mark) {
      _Mark.done => (s.success, s.onSuccess),
      _Mark.bad => (s.danger, s.onDanger),
      _Mark.next => (context.colors.surfaceContainerHighest, context.colors.onSurfaceVariant),
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 36,
          child: Column(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: back, shape: BoxShape.circle), child: Icon(step.icon, size: 18, color: front)),
            if (!last) Expanded(child: Container(width: 2, color: context.colors.outlineVariant)),
          ]),
        ),
        const SizedBox(width: Sp.x3),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : Sp.x4, top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: context.text.titleMedium),
              const SizedBox(height: 2),
              Text(step.detail, style: context.text.bodyMedium?.copyWith(color: context.muted)),
            ]),
          ),
        ),
      ]),
    );
  }
}
