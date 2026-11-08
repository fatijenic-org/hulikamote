import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/benchmark_models.dart';

/// One saved report: the headline numbers, a row per violation, and what happened clip by clip.
/// Words: Caught = a ticket matched a real event. False alarm = a ticket with no real event. Missed = a real event with no ticket.
class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.report});

  final ReportDetail report;

  @override
  Widget build(BuildContext context) {
    final o = report.overall;
    double? ratio(String k) => (o[k] as num?)?.toDouble();
    final plates = (o['plates_checked'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
          StatusPill(label: 'Caught ${o['caught'] ?? 0}', color: Fx.success, icon: Icons.check_circle_outline),
          StatusPill(label: 'False alarms ${o['false_alarms'] ?? 0}', color: Fx.danger, icon: Icons.notification_important_outlined),
          StatusPill(label: 'Missed ${o['missed'] ?? 0}', color: Fx.warning, icon: Icons.visibility_off_outlined),
          StatusPill(label: 'Precision ${percentText(ratio('precision'))}', color: Fx.accent),
          StatusPill(label: 'Recall ${percentText(ratio('recall'))}', color: Fx.accent),
          if (plates > 0) ...[
            StatusPill(label: 'LOAR ${percentText(ratio('loar'))}', color: Fx.accent),
            StatusPill(label: 'Plate CER ${percentText(ratio('cer'))}', color: Fx.accent),
            StatusPill(label: 'Plate WER ${percentText(ratio('wer'))}', color: Fx.accent),
          ],
        ]),
        const SizedBox(height: Fx.s8),
        Text(
          'Pass needs precision ${percentText(report.passPrecision)} and recall ${percentText(report.passRecall)}, '
          'with at least ${report.minEvents} real events. Precision: of what it flagged, how much was real. '
          'Recall: of the real violations, how many it found.'
          '${plates > 0 ? ' LOAR: type, vehicle and plate all right (over $plates events with a known plate).' : ''}',
          style: Fx.caption(context),
        ),
        const SizedBox(height: Fx.s12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: Fx.s24,
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 44,
            columns: const [
              DataColumn(label: Text('Violation')),
              DataColumn(label: Text('Real events'), numeric: true),
              DataColumn(label: Text('Caught'), numeric: true),
              DataColumn(label: Text('False alarms'), numeric: true),
              DataColumn(label: Text('Missed'), numeric: true),
              DataColumn(label: Text('Precision'), numeric: true),
              DataColumn(label: Text('Recall'), numeric: true),
              DataColumn(label: Text('Verdict')),
            ],
            rows: [
              for (final s in report.scores)
                DataRow(cells: [
                  DataCell(ViolationChip(s.key, dense: true)),
                  DataCell(Text('${s.events}')),
                  DataCell(Text('${s.caught}')),
                  DataCell(Text('${s.falseAlarms}')),
                  DataCell(Text('${s.missed}')),
                  DataCell(Text(percentText(s.precision))),
                  DataCell(Text(percentText(s.recall))),
                  DataCell(_verdict(s)),
                ]),
            ],
          ),
        ),
        if (report.notBenchmarked.isNotEmpty) ...[
          const SizedBox(height: Fx.s12),
          Text('Not benchmarked yet (no real event in any clip)', style: Fx.label(context)),
          const SizedBox(height: Fx.s8),
          Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
            for (final k in report.notBenchmarked) Opacity(opacity: 0.6, child: ViolationChip(k, dense: true)),
          ]),
        ],
        const SizedBox(height: Fx.s12),
        Text('Clip by clip', style: Fx.label(context)),
        for (final c in report.clips) _clipTile(context, c),
      ],
    );
  }

  Widget _verdict(ViolationScore s) {
    if (s.pass) return const StatusPill(label: 'PASS', color: Fx.success, dense: true);
    if (s.fail) return const StatusPill(label: 'FAIL', color: Fx.danger, dense: true);
    return StatusPill(label: s.status, color: const Color(0xFF9AA5B1), dense: true);
  }

  Widget _clipTile(BuildContext context, Map<String, dynamic> c) {
    List<Map<String, dynamic>> rows(String k) => [for (final x in (c[k] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final caught = rows('caught'), missed = rows('missed'), alarms = rows('false_alarms');
    String when(Map<String, dynamic> x) {
      final s = (x['start'] ?? x['ticket_start']) as num?;
      final e = (x['end'] ?? x['ticket_end']) as num?;
      return s == null ? 'no time' : '${secondsText(s)}-${secondsText(e)} s';
    }

    Widget group(String title, Color color, List<Map<String, dynamic>> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: Fx.s8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          for (final x in items)
            Text('${ViolationCatalog.of('${x['violation']}').label} at ${when(x)}'
                '${x['track'] != null ? '  (track ${x['track']})' : ''}'),
        ]),
      );
    }

    final skipped = [for (final k in (c['skipped'] as List? ?? const [])) '$k'];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: Fx.s8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: Text('${c['clip_id']}', style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('Caught ${caught.length}  ·  False alarms ${alarms.length}  ·  Missed ${missed.length}', style: Fx.caption(context)),
      children: [
        group('Caught', Fx.success, caught),
        group('False alarms', Fx.danger, alarms),
        group('Missed', Fx.warning, missed),
        if (skipped.isNotEmpty)
          Text('Not judged here (not switched on): ${skipped.map((k) => ViolationCatalog.of(k).label).join(', ')}', style: Fx.caption(context)),
        if (caught.isEmpty && alarms.isEmpty && missed.isEmpty && skipped.isEmpty) Text('Nothing to report.', style: Fx.caption(context)),
      ],
    );
  }
}
