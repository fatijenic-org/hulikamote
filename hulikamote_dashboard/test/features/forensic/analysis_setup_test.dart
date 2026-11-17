import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_setup.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/analysis_setup_panel.dart';

Map<String, dynamic> _config() => {
  'video_name': '15m_allviolations-3.mp4',
  'active_violations': ['counterflow', 'illegal_parking', 'truck_ban', 'overloading'],
  'tracker': 'deepsort',
  'plate_format': 'ph_standard',
  'ocr_engine': 'easyocr',
  'use_sahi': false,
  'keep_input_video': true,
  'trim_end': 901.4,
  'video_native_width': 1920,
  'video_native_height': 1080,
  'per_violation_configs': {
    'counterflow': {'rois': [], 'time_limit': 180.0, 'max_riders': 2},
    'illegal_parking': {'rois': [1, 2], 'time_limit': 3.0},
    'truck_ban': {'banned_classes': ['truck'], 'ban_windows': [['06:00', '18:00']]},
    'overloading': {'max_riders': 1},
  },
};

void main() {
  test('reads the file name, the violations and only the settings each rule uses', () {
    final s = AnalysisSetup.fromJson(_config(), taskId: 'abc');
    expect(s.videoName, '15m_allviolations-3.mp4');
    expect(s.violations.length, 4);
    expect(s.sections.map((e) => e.title), ['Video', 'Detection', 'Review']);
    final rows = {for (final v in s.perViolation) v.key: {for (final r in v.rows) r.label: r.value}};
    expect(rows['counterflow']!.containsKey('Time limit'), isFalse); // a leftover key, not a counterflow setting
    expect(rows['illegal_parking']!['Time limit'], '3 s');
    expect(rows['illegal_parking']!['Area'], '2 drawn');
    expect(rows['truck_ban']!['Ban hours'], '06:00–18:00');
    expect(rows['overloading']!['Most riders allowed'], '1');
  });

  test('an old analysis without a file name says so', () {
    final s = AnalysisSetup.fromJson({'active_violations': <String>[]}, taskId: 'abc');
    expect(s.videoName, isNull);
  });

  testWidgets('the panel shows the full file name and the violations', (tester) async {
    final s = AnalysisSetup.fromJson(_config(), taskId: 'abc-123');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AnalysisSetupPanel(setup: s, analyzedAt: 'today'))),
    );
    final name = tester.widget<SelectableText>(find.byKey(const Key('setup-file-name')));
    expect(name.data, '15m_allviolations-3.mp4');
    expect(find.text('Counterflow'), findsWidgets);
    expect(find.text('Violations (4)'.toUpperCase()), findsOneWidget);
  });
}
