import 'package:flutter/material.dart';

import '../../domain/analysis_draft.dart';
import '../../domain/ban_hours.dart';
import 'fx.dart';

/// "Ban hours" of one rule (the truck ban): off = the ban holds all day; on = only inside the hours below.
/// Stored in the rule's config as `ban_windows`: [["06:00", "09:00"], ...]. The backend judges each frame by the time of the video.
class BanHoursEditor extends StatelessWidget {
  const BanHoursEditor({super.key, required this.draft, required this.violationKey, required this.onChanged});

  final AnalysisDraft draft;
  final String violationKey;
  final VoidCallback onChanged;

  Map<String, dynamic> get _cfg => draft.config(violationKey);

  List<List<String>> get _windows => [
    for (final pair in (_cfg['ban_windows'] as List? ?? const []))
      if (pair is List && pair.length >= 2) ['${pair[0]}', '${pair[1]}'],
  ];

  void _save(List<List<String>> windows) {
    _cfg['ban_windows'] = windows;
    draft.touch();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final windows = _windows;
    final on = windows.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Only ban at certain hours', style: Fx.body(context)),
            const SizedBox(height: 2),
            Text(
              on
                  ? 'Trucks are flagged only inside these hours. The time comes from the video: its own clock, its file '
                      'information, or the start time you type in Settings.'
                  : 'Off: the ban holds all day. Turn on to set the hours from the city ordinance.',
              style: Fx.caption(context),
            ),
          ]),
        ),
        const SizedBox(width: Fx.s12),
        Switch(
          key: const ValueKey('ban-hours-switch'),
          value: on,
          onChanged: (v) => _save(v ? [BanHours.example.first] : []),
        ),
      ]),
      if (on) ...[
        const SizedBox(height: Fx.s8),
        for (var i = 0; i < windows.length; i++) _row(context, windows, i),
        const SizedBox(height: Fx.s4),
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, children: [
          if (windows.length < BanHours.maxWindows)
            OutlinedButton.icon(
              key: const ValueKey('ban-hours-add'),
              onPressed: () => _save([
                ...windows,
                // the next window starts where the last one ended, an hour long
                [windows.last[1], _plusHour(windows.last[1])],
              ]),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add hours'),
            ),
          TextButton(
            key: const ValueKey('ban-hours-example'),
            onPressed: () => _save([for (final w in BanHours.example) [...w]]),
            child: const Text('Use example hours (6–9 AM, 4–7 PM)'),
          ),
        ]),
        const SizedBox(height: Fx.s4),
        Text(
          'The example is only an example. Get the real hours from the ordinance (City Traffic or City Legal office).',
          style: Fx.caption(context),
        ),
      ],
    ]);
  }

  static String _plusHour(String hhmm) {
    final total = ((BanHours.minutes(hhmm) ?? 0) + 60) % 1440;
    return BanHours.options.reduce((a, b) => (BanHours.minutes(a)! - total).abs() <= (BanHours.minutes(b)! - total).abs() ? a : b);
  }

  Widget _row(BuildContext context, List<List<String>> windows, int i) {
    void set(int part, String value) {
      final next = [for (final w in windows) [...w]];
      next[i][part] = value;
      _save(next);
    }

    Widget pick(String id, String current, int part) => DropdownButton<String>(
      key: ValueKey('ban-hours-$id-$i'),
      value: BanHours.options.contains(current) ? current : null,
      hint: Text(BanHours.label(current)),
      isDense: true,
      items: [for (final o in BanHours.options) DropdownMenuItem(value: o, child: Text(BanHours.label(o)))],
      onChanged: (v) => v == null ? null : set(part, v),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s4),
      child: Row(children: [
        Text('From', style: Fx.body(context)),
        const SizedBox(width: Fx.s8),
        pick('from', windows[i][0], 0),
        const SizedBox(width: Fx.s12),
        Text('to', style: Fx.body(context)),
        const SizedBox(width: Fx.s8),
        pick('to', windows[i][1], 1),
        const Spacer(),
        IconButton(
          key: ValueKey('ban-hours-remove-$i'),
          tooltip: 'Remove these hours',
          icon: const Icon(Icons.delete_outline, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () => _save([for (var j = 0; j < windows.length; j++) if (j != i) windows[j]]),
        ),
      ]),
    );
  }
}
