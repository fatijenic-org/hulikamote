import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/analysis_setup.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';

/// Opens the setup of one analysis as a panel on the right: the file, the violations, the models and the review options.
Future<void> showAnalysisSetup(BuildContext context, AnalysisSetup setup, {required String analyzedAt}) {
  return showDialog<void>(
    context: context,
    barrierLabel: 'Close the analysis setup',
    builder: (_) => Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(Fx.radius)),
      ),
      child: SizedBox(
        width: 460,
        height: double.infinity,
        child: AnalysisSetupPanel(setup: setup, analyzedAt: analyzedAt),
      ),
    ),
  );
}

/// The content of the setup panel (also usable on its own).
class AnalysisSetupPanel extends StatelessWidget {
  const AnalysisSetupPanel({super.key, required this.setup, required this.analyzedAt});

  final AnalysisSetup setup;
  final String analyzedAt;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Fx.page(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s12, Fx.s8, Fx.s12),
            child: Row(
              children: [
                Expanded(child: Text('Analysis setup', style: Fx.heading(context))),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Fx.border(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Fx.s16),
              children: [
                _FileCard(setup: setup, analyzedAt: analyzedAt),
                const SizedBox(height: Fx.s24),
                SectionLabel('Violations (${setup.violations.length})'),
                if (setup.violations.isEmpty)
                  Text('None saved for this analysis.', style: Fx.caption(context))
                else
                  Wrap(
                    spacing: Fx.s8,
                    runSpacing: Fx.s8,
                    children: [for (final v in setup.violations) ViolationChip(v)],
                  ),
                for (final s in setup.sections) ...[
                  const SizedBox(height: Fx.s24),
                  SectionLabel(s.title),
                  _RowsCard(rows: s.rows),
                ],
                if (setup.perViolation.isNotEmpty) ...[
                  const SizedBox(height: Fx.s24),
                  const SectionLabel('Rule settings'),
                  for (final v in setup.perViolation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Fx.s8),
                      child: _RuleTile(setup: v, open: setup.perViolation.length <= 3),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The file name in full (selectable) with the analysis id under it.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.setup, required this.analyzedAt});

  final AnalysisSetup setup;
  final String analyzedAt;

  @override
  Widget build(BuildContext context) {
    final name = setup.videoName;
    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Fx.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.movie_outlined, color: Fx.accent, size: 20),
              ),
              const SizedBox(width: Fx.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      name ?? 'File name not saved for this analysis',
                      key: const Key('setup-file-name'),
                      style: Fx.heading(context).copyWith(color: name == null ? Fx.muted(context) : null),
                    ),
                    const SizedBox(height: 2),
                    Text('Analyzed $analyzedAt', style: Fx.caption(context)),
                  ],
                ),
              ),
              if (name != null) _CopyButton(text: name, tooltip: 'Copy the file name'),
            ],
          ),
          const SizedBox(height: Fx.s12),
          Divider(height: 1, color: Fx.border(context)),
          const SizedBox(height: Fx.s8),
          Row(
            children: [
              SizedBox(width: 110, child: Text('Analysis ID', style: Fx.caption(context))),
              Expanded(child: SelectableText(setup.taskId, style: Fx.caption(context).copyWith(fontFamily: 'monospace'))),
              _CopyButton(text: setup.taskId, tooltip: 'Copy the ID'),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card of label / value lines.
class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.rows});

  final List<SetupRow> rows;

  @override
  Widget build(BuildContext context) {
    return FxCard(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
      child: _RowLines(rows: rows),
    );
  }
}

class _RowLines extends StatelessWidget {
  const _RowLines({required this.rows});

  final List<SetupRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 150, child: Text(r.label, style: Fx.caption(context))),
                Expanded(child: SelectableText(r.value, style: Fx.body(context))),
              ],
            ),
          ),
      ],
    );
  }
}

/// One violation with the settings it was given; folded away when there are many.
class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.setup, required this.open});

  final ViolationSetup setup;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final v = ViolationCatalog.of(setup.key);
    return FxCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('setup-rule-${setup.key}'),
          initiallyExpanded: open,
          tilePadding: const EdgeInsets.symmetric(horizontal: Fx.s16),
          childrenPadding: const EdgeInsets.fromLTRB(Fx.s16, 0, Fx.s16, Fx.s12),
          leading: Icon(v.icon, color: v.color, size: 20),
          title: Text(v.label, style: Fx.body(context)),
          children: [_RowLines(rows: setup.rows)],
        ),
      ),
    );
  }
}

/// Copies a text; the icon turns into a tick for a moment.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text, required this.tooltip});

  final String text;
  final String tooltip;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(_done ? Icons.check : Icons.copy_outlined, size: 18, color: _done ? Fx.success : null),
      onPressed: _copy,
    );
  }
}

/// Under the title of an open analysis: the first violations as chips; a tap opens the full setup.
class AnalysisSetupStrip extends StatelessWidget {
  const AnalysisSetupStrip({super.key, required this.violations, required this.onOpen, this.show = 3});

  final List<String> violations;
  final VoidCallback onOpen;
  final int show;

  @override
  Widget build(BuildContext context) {
    if (violations.isEmpty) return const SizedBox.shrink();
    final extra = violations.length - show;
    return Tooltip(
      message: 'See the full setup',
      child: InkWell(
        key: const Key('setup-strip'),
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final v in violations.take(show)) ViolationChip(v, dense: true),
              if (extra > 0) StatusPill(label: '+$extra', color: Fx.muted(context), dense: true),
            ],
          ),
        ),
      ),
    );
  }
}
