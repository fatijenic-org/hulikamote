import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_toast.dart';
import '../utils/external_apps.dart';
import '../../features/blueprint/presentation/widgets/code_highlight.dart';

/// One discrete step in an end-to-end execution chain (from UI display to database mutation).
class CodeTraceStage {
  final String stageTitle;
  final String stageRole;
  final String filePath;
  final int startLine;
  final int endLine;
  final String language;
  final String description;
  final String codeSnippet;

  const CodeTraceStage({
    required this.stageTitle,
    required this.stageRole,
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.language,
    required this.description,
    required this.codeSnippet,
  });

  String get fileLine => '$filePath:$startLine-$endLine';
}

/// A comprehensive code-tracking hover tooltip and inspector modal that displays
/// the complete end-to-end code journey from UI widget down to the database.
class CodeInspectorTooltip extends StatelessWidget {
  final String title;
  final List<CodeTraceStage> stages;
  final Widget child;
  final bool showBadge;

  const CodeInspectorTooltip({
    super.key,
    required this.title,
    required this.stages,
    required this.child,
    this.showBadge = false,
  });

  void _openFullTraceModal(BuildContext context, [int initialStage = 0]) {
    showDialog(
      context: context,
      builder: (ctx) => _FullCodeTraceDialog(
        title: title,
        stages: stages,
        initialStage: initialStage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 20),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13161F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF61AFEF).withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      richMessage: TextSpan(
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12,
          height: 1.45,
          color: Color(0xFFE6EDF3),
        ),
        children: [
          // ── Header ───────────────────────────────────────────────────
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_tree, size: 15, color: Color(0xFF61AFEF)),
                const SizedBox(width: 8),
                Text(
                  'COMPLETE CODE TRACKING: ${title.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF61AFEF),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF98C379).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF98C379).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${stages.length} VERIFIED STAGES',
                    style: const TextStyle(
                      color: Color(0xFF98C379),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const TextSpan(text: '\n─────────────────────────────────────────────────────────────────\n'),

          // ── Call Chain Breadcrumbs ───────────────────────────────────
          const TextSpan(
            text: 'CALL CHAIN: ',
            style: TextStyle(color: Color(0xFF7F848E), fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: stages.map((s) => s.stageTitle.replaceFirst(RegExp(r'^\d+\.\s*'), '')).join('  ➔  '),
            style: const TextStyle(color: Color(0xFFD19A66), fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: '\n─────────────────────────────────────────────────────────────────\n\n'),

          // ── Stage Breakdown ──────────────────────────────────────────
          for (int i = 0; i < stages.length; i++) ...[
            TextSpan(
              text: 'STAGE ${i + 1}: ${stages[i].stageTitle.toUpperCase()}  ',
              style: const TextStyle(
                color: Color(0xFFE5C07B),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: '[${stages[i].stageRole}]\n',
              style: const TextStyle(
                color: Color(0xFF61AFEF),
                fontSize: 11,
              ),
            ),
            TextSpan(
              text: '  📍 File: ${stages[i].fileLine}\n',
              style: const TextStyle(
                color: Color(0xFF56B6C2),
                fontSize: 11.5,
              ),
            ),
            TextSpan(
              text: '  ℹ️  ${stages[i].description}\n\n',
              style: const TextStyle(
                color: Color(0xFFABB2BF),
                fontSize: 11,
              ),
            ),
          ],

          const TextSpan(
            text: '💡 Action: Right-Click or click 🔍 to view complete verbatim code & open in VS Code.',
            style: TextStyle(
              color: Color(0xFF98C379),
              fontStyle: FontStyle.italic,
              fontSize: 11,
            ),
          ),
        ],
      ),
      child: GestureDetector(
        onSecondaryTap: () => _openFullTraceModal(context),
        child: showBadge
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  Positioned(
                    top: -4,
                    right: -4,
                    child: InkWell(
                      onTap: () => _openFullTraceModal(context),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF61AFEF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.code, size: 11, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              )
            : child,
      ),
    );
  }
}

/// Full interactive modal showing all stages with syntax highlighting, 4-space tab indentation,
/// real line numbers, and "Open in VS Code" capability.
class _FullCodeTraceDialog extends StatefulWidget {
  final String title;
  final List<CodeTraceStage> stages;
  final int initialStage;

  const _FullCodeTraceDialog({
    required this.title,
    required this.stages,
    this.initialStage = 0,
  });

  @override
  State<_FullCodeTraceDialog> createState() => _FullCodeTraceDialogState();
}

class _FullCodeTraceDialogState extends State<_FullCodeTraceDialog> {
  late int _activeStage = widget.initialStage.clamp(0, widget.stages.length - 1);
  bool _copied = false;

  CodeTraceStage get _stage => widget.stages[_activeStage];

  Future<void> _openInVsCode() async {
    final err = await ExternalApps.openInVsCode(_stage.filePath, line: _stage.startLine);
    if (!mounted) return;
    AppToast.show(
      context,
      err ?? 'Opened ${_stage.filePath.split('/').last}:${_stage.startLine} in VS Code',
      isError: err != null,
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _stage.codeSnippet));
    if (!mounted) return;
    setState(() => _copied = true);
    AppToast.show(context, 'Copied Stage ${_activeStage + 1} code snippet to clipboard');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final lines = stage.codeSnippet.replaceAll('\t', '    ').split('\n');
    final isDart = stage.language.toLowerCase() == 'dart';
    const monoStyle = TextStyle(
      fontFamily: 'Consolas',
      fontSize: 12.5,
      height: 1.55,
      color: Color(0xFFE6EDF3),
    );
    final highlightedSpans = highlight(lines, dart: isDart, base: monoStyle);

    return Dialog(
      backgroundColor: const Color(0xFF12151D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF61AFEF).withValues(alpha: 0.35), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Header ───────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF61AFEF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_tree, color: Color(0xFF61AFEF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMPLETE CODE TRACKING: ${widget.title.toUpperCase()}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'End-to-end execution pipeline trace · ${widget.stages.length} connected stages',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF7F848E), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    tooltip: 'Close Inspector',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Stage Navigation Stepper ─────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(widget.stages.length, (i) {
                    final s = widget.stages[i];
                    final isSelected = _activeStage == i;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: CircleAvatar(
                          radius: 11,
                          backgroundColor: isSelected ? const Color(0xFF61AFEF) : const Color(0xFF2B313C),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isSelected ? Colors.black87 : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        label: Text(s.stageTitle),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFFABB2BF),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        backgroundColor: isSelected
                            ? const Color(0xFF61AFEF).withValues(alpha: 0.22)
                            : const Color(0xFF1B2029),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF61AFEF)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        onPressed: () => setState(() => _activeStage = i),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),

              // ── Active Stage Meta Banner ─────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F29),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF61AFEF).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stage.stageRole.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF61AFEF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.folder_open, size: 15, color: Color(0xFF56B6C2)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            stage.fileLine,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF56B6C2),
                              fontFamily: 'Consolas',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _openInVsCode,
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('Open in VS Code', style: TextStyle(fontSize: 11)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF252D3D),
                            foregroundColor: const Color(0xFF61AFEF),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 30),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _copyCode,
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 13,
                            color: _copied ? const Color(0xFF98C379) : Colors.white70,
                          ),
                          label: Text(
                            _copied ? 'Copied' : 'Copy',
                            style: TextStyle(
                              fontSize: 11,
                              color: _copied ? const Color(0xFF98C379) : Colors.white70,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 30),
                            side: BorderSide(
                              color: _copied
                                  ? const Color(0xFF98C379)
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stage.description,
                      style: const TextStyle(
                        color: Color(0xFFABB2BF),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Code Window with Syntax Highlighting & 4-Space Indentation ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1017),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Line Numbers Gutter (Calculated from stage.startLine)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(lines.length, (idx) {
                                return SizedBox(
                                  height: 20,
                                  child: Text(
                                    '${stage.startLine + idx}',
                                    style: const TextStyle(
                                      color: Color(0xFF4B5263),
                                      fontFamily: 'Consolas',
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            Container(
                              width: 1,
                              height: lines.length * 20.0,
                              color: Colors.white.withValues(alpha: 0.08),
                              margin: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            // Syntax-highlighted code lines with 4-space indent
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: List.generate(lines.length, (idx) {
                                return SizedBox(
                                  height: 20,
                                  child: SelectableText.rich(
                                    TextSpan(children: highlightedSpans[idx]),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Bottom Stage Walkthrough Bar ─────────────────────────────
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _activeStage > 0
                        ? () => setState(() => _activeStage--)
                        : null,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Previous'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Stage ${_activeStage + 1} of ${widget.stages.length}',
                    style: const TextStyle(color: Color(0xFF7F848E), fontSize: 12),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _activeStage < widget.stages.length - 1
                        ? () => setState(() => _activeStage++)
                        : null,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(
                      _activeStage < widget.stages.length - 1
                          ? 'Next Stage'
                          : 'End of Chain',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF61AFEF),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
