import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/forensic/domain/analysis_draft.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/violation_params.dart';

Future<void> pumpParams(WidgetTester tester, AnalysisDraft draft, String key) {
  // The wizard rebuilds the params after every edit (onChanged); a StatefulBuilder does the same here.
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: ViolationParams(draft: draft, violationKey: key, onChanged: () => setState(() {})),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('illegal turn lets the enforcer choose which turns are banned', (tester) async {
    final draft = AnalysisDraft();
    await pumpParams(tester, draft, 'illegal_turn');
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    expect(draft.config('illegal_turn')['banned_turns'], ['left']); // default: no left turn

    await tester.tap(find.text('Right'));
    await tester.pump();
    expect(draft.config('illegal_turn')['banned_turns'], ['left', 'right']);
    await tester.tap(find.text('Left'));
    await tester.pump();
    expect(draft.config('illegal_turn')['banned_turns'], ['right']);
  });

  testWidgets('a truck ban has no vehicle-type picker (it bans trucks), a sidewalk rule still has one', (tester) async {
    final draft = AnalysisDraft();
    await pumpParams(tester, draft, 'truck_ban');
    expect(find.text('Truck'), findsNothing);
    expect(find.text('Left'), findsNothing); // the turn chips belong to illegal turn only
    expect(draft.config('truck_ban')['banned_classes'], ['truck']); // what the backend gets is still the trucks
    await pumpParams(tester, draft, 'sidewalk_driving');
    expect(find.text('Truck'), findsOneWidget);
  });
}
