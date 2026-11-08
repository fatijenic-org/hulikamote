import 'package:flutter/material.dart';

import '../../../../core/utils/app_toast.dart';
import '../../../../core/utils/external_apps.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/tests_index.dart';

/// "How it's tested": the tests that run the code shown above, as plain sentences, with a button that opens each one.
/// It says so plainly when nothing tests the code, and that passing tests are not the same as accuracy on real footage.
class TestsSection extends StatefulWidget {
  const TestsSection({super.key, required this.info, required this.index});

  /// Null when the index does not know this file.
  final AnchorTests? info;
  final TestsIndex index;

  /// Tests listed before "Show more".
  static const int shownFirst = 5;

  @override
  State<TestsSection> createState() => _TestsSectionState();
}

class _TestsSectionState extends State<TestsSection> {
  bool _all = false;

  @override
  void didUpdateWidget(TestsSection old) {
    super.didUpdateWidget(old);
    if (!identical(old.info, widget.info)) _all = false;
  }

  Future<void> _open(TestRef test) async {
    final error = await ExternalApps.openInVsCode(test.file, line: test.line);
    if (!mounted) return;
    AppToast.show(context, error ?? 'Opened ${test.file.split('/').last} in VS Code', isError: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Fx.border(context)))),
      padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s12, Fx.s16, Fx.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(context, info),
          const SizedBox(height: Fx.s8),
          if (info == null)
            Text('This file is not in the tests index yet. Rebuild it with tools/tests_index.py.', style: Fx.caption(context))
          else ...[
            _headline(context, info),
            if (info.tests.isNotEmpty) ...[
              const SizedBox(height: Fx.s8),
              _list(context, info),
            ],
          ],
          const SizedBox(height: Fx.s8),
          _footer(context),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, AnchorTests? info) {
    final pct = info?.coveragePct;
    return Row(
      children: [
        Icon(Icons.fact_check_outlined, size: 18, color: Fx.muted(context)),
        const SizedBox(width: Fx.s8),
        Text("How it's tested", style: Fx.heading(context)),
        const Spacer(),
        if (info != null && info.exact && pct != null)
          Tooltip(
            message: 'Lines of this code that ran while the tests ran. Running a line is not the same as checking it.',
            child: Text('${pct.round()}% of its lines run in tests', style: Fx.caption(context)),
          ),
      ],
    );
  }

  Widget _headline(BuildContext context, AnchorTests info) {
    final style = Fx.body(context);
    if (info.untested) {
      return Text(
        info.exact ? 'No test runs this code.' : 'No test file loads this file.',
        style: style.copyWith(color: Fx.danger, fontWeight: FontWeight.w600),
      );
    }
    final failing = info.tests.where((t) => t.failed).length;
    final n = info.total;
    final tests = n == 1 ? '1 test' : '$n tests';
    final String what;
    if (info.inheritedFrom != null) {
      final names = info.direct == 0 ? 'none names this violation' : '${info.direct} name${info.direct == 1 ? 's' : ''} this violation';
      what = 'This violation only holds settings; its rule is the shared ${info.inheritedFrom}. $tests run that rule, $names.';
    } else if (info.exact) {
      what = info.direct == 0
          ? '$tests run this code, but none is written for it: it only runs inside other tests.'
          : info.direct >= n
              ? '$tests, all written for this code.'
              : '$tests run this code, ${info.direct} written for it.';
    } else {
      what = '$tests in test files that load this file (they may test only part of it).';
    }
    return Text.rich(TextSpan(style: style, children: [
      if (failing > 0) TextSpan(text: '$failing failing. ', style: const TextStyle(color: Fx.danger, fontWeight: FontWeight.w600)),
      TextSpan(text: what),
      if (!info.hasResults) TextSpan(text: ' Not run in this index.', style: TextStyle(color: Fx.muted(context))),
    ]));
  }

  Widget _list(BuildContext context, AnchorTests info) {
    final shown = _all ? info.tests : info.tests.take(TestsSection.shownFirst).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) _row(context, shown[i], written: info.exact && i < info.direct || !info.exact),
        if (info.tests.length > TestsSection.shownFirst)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? 'Show fewer' : 'Show ${info.tests.length - TestsSection.shownFirst} more'),
            ),
          ),
        if (info.total > info.tests.length)
          Padding(
            padding: const EdgeInsets.only(top: Fx.s4),
            child: Text('and ${info.total - info.tests.length} more that run it indirectly', style: Fx.caption(context)),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, TestRef test, {required bool written}) {
    final (icon, color) = switch (test.outcome) {
      'passed' => (Icons.check_circle, Fx.success),
      'failed' => (Icons.cancel, Fx.danger),
      'skipped' => (Icons.remove_circle_outline, Fx.warning),
      _ => (Icons.radio_button_unchecked, Fx.muted(context)),
    };
    final text = test.sentence.isEmpty ? test.name : test.sentence[0].toUpperCase() + test.sentence.substring(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Fx.s8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Fx.body(context).copyWith(color: written ? null : Fx.muted(context)),
            ),
          ),
          IconButton(
            tooltip: 'Open this test in VS Code',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: () => _open(test),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final clips = widget.index.clipsInRegistry;
    final real = clips == 0 ? 'not measured yet (no scored clips)' : '$clips scored clips';
    return Text(
      'Last run ${widget.index.generated}.  Passing tests show the code does what we meant. Accuracy on real footage: $real.',
      style: Fx.caption(context),
    );
  }
}
