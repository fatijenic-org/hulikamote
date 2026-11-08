import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/external_apps.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/code_reader.dart';
import '../../domain/reference_models.dart';
import '../../domain/tests_index.dart';
import 'code_highlight.dart';
import 'tests_section.dart';

/// The real code behind a slice: a few lines, with a button that opens the exact place in VS Code.
/// More than one place shows as small tabs. Long blocks start folded. When the tests index is known, "How it's
/// tested" sits under the code of whichever tab is open.
class CodePanel extends StatefulWidget {
  const CodePanel({super.key, required this.anchors, required this.root, this.tests, this.foldAt = 16});

  final List<CodeAnchor> anchors;

  /// The repository, or null when the app is not running from one.
  final Directory? root;

  /// Which tests protect which code. Null hides the "How it's tested" section.
  final TestsIndex? tests;

  /// Lines shown before "Show all".
  final int foldAt;

  @override
  State<CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<CodePanel> {
  int _tab = 0;
  bool _all = false;

  static const _mono = TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Courier New', 'monospace'], fontSize: 13, height: 1.55);

  @override
  void didUpdateWidget(CodePanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.anchors, widget.anchors)) {
      _tab = 0;
      _all = false;
    }
  }

  CodeAnchor get _anchor => widget.anchors[_tab.clamp(0, widget.anchors.length - 1)];

  Future<void> _open(CodeSnippet snippet) async {
    final error = await ExternalApps.openInVsCode(_anchor.file, line: snippet.startLine);
    if (!mounted) return;
    AppToast.show(context, error ?? 'Opened ${_anchor.file.split('/').last} in VS Code', isError: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final snippet = widget.root == null ? null : CodeReader.read(widget.root!, _anchor);
    return Container(
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, snippet),
          Divider(height: 1, color: Fx.border(context)),
          if (snippet == null) _missing(context) else _body(context, snippet),
          if (widget.tests != null) TestsSection(info: widget.tests!.forAnchor(_anchor), index: widget.tests!),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, CodeSnippet? snippet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s8, Fx.s8, Fx.s8),
      child: Row(
        children: [
          if (widget.anchors.length > 1)
            for (var i = 0; i < widget.anchors.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: Fx.s16),
                child: InkWell(
                  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  onTap: () => setState(() {
                    _tab = i;
                    _all = false;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Fx.s8),
                    child: Text(
                      widget.anchors[i].label.isEmpty ? widget.anchors[i].symbol : widget.anchors[i].label,
                      style: Fx.body(context).copyWith(
                        fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w400,
                        color: i == _tab ? Theme.of(context).colorScheme.onSurface : Fx.muted(context),
                      ),
                    ),
                  ),
                ),
              ),
          Expanded(
            child: Tooltip(
              message: _anchor.file,
              child: Text(
                snippet == null ? _anchor.file.split('/').last : '${_anchor.file.split('/').last}  ·  line ${snippet.startLine}',
                overflow: TextOverflow.ellipsis,
                textAlign: widget.anchors.length > 1 ? TextAlign.right : TextAlign.left,
                style: Fx.caption(context).copyWith(fontFamily: 'Consolas', fontFamilyFallback: const ['Courier New', 'monospace']),
              ),
            ),
          ),
          const SizedBox(width: Fx.s8),
          TextButton.icon(
            onPressed: snippet == null ? null : () => _open(snippet),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in VS Code'),
          ),
        ],
      ),
    );
  }

  Widget _missing(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Fx.s16),
        child: Text(
          widget.root == null
              ? 'The code is read from the repository files, so it shows when the app runs from the repository.'
              : 'Could not find "${_anchor.symbol}" in this file. The code may have moved.',
          style: Fx.caption(context),
        ),
      );

  Widget _body(BuildContext context, CodeSnippet snippet) {
    final folded = !_all && snippet.lines.length > widget.foldAt;
    final shown = folded ? snippet.lines.sublist(0, widget.foldAt) : snippet.lines;
    final base = _mono.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.88));
    final lines = highlight(shown, dart: _anchor.isDart, base: base);
    final gutter = _mono.copyWith(color: Fx.muted(context).withValues(alpha: 0.55));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s12, Fx.s16, Fx.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  [for (var i = 0; i < shown.length; i++) '${snippet.startLine + i}'].join('\n'),
                  textAlign: TextAlign.right,
                  style: gutter,
                ),
              ),
              const SizedBox(width: Fx.s16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                    TextSpan(children: [
                      for (var i = 0; i < lines.length; i++) ...[
                        ...lines[i],
                        if (i < lines.length - 1) const TextSpan(text: '\n'),
                      ],
                    ]),
                    style: base,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (snippet.lines.length > widget.foldAt)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: Fx.s8, bottom: Fx.s8),
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all
                    ? 'Show less'
                    : 'Show all ${snippet.lines.length}${snippet.truncated ? '+' : ''} lines'),
              ),
            ),
          ),
      ],
    );
  }
}
