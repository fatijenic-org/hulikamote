import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';
import 'package:hulikamote_dashboard/features/datasets/data/dataset_viewer_api.dart';
import 'package:hulikamote_dashboard/features/datasets/presentation/screens/dataset_viewer_screen.dart';

void main() {
  testWidgets('Dataset viewer renders natively inside the dashboard route', (
    tester,
  ) async {
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/api/datasets':
          return _json({
            'datasets': [
              {
                'name': 'primary_anchor',
                'classes': ['motorcycle', 'car'],
                'training': false,
                'index': {'state': 'ready'},
                'images': {'train': 12, 'val': 2, 'test': 1},
                'total': 15,
                'ph_share': 0.6,
                'card_stale': false,
                'warnings': [],
              },
            ],
          });
        case '/api/facets':
          return _json({
            'classes': {'0': 6, '1': 3},
            'sources': {'sample': 15},
            'counts': {
              'all': 15,
              'nobox': 0,
              'many': 0,
              'tiny': 0,
              'mine': 0,
              'flagged': 0,
              'relabeled': 0,
            },
          });
        case '/api/items':
          return _json({
            'total': 0,
            'offset': 0,
            'items': [],
            'can_undo': false,
          });
        case '/api/keys':
          return _json({
            'total': 1,
            'keys': [
              ['train', 'sample.jpg'],
            ],
          });
        case '/api/labels':
          return _json({
            'items': [
              {
                'split': 'train',
                'name': 'sample.jpg',
                'index': 0,
                'class_id': 0,
                'class_name': 'motorcycle',
                'box': [0.5, 0.5, 0.4, 0.4],
                'source': 'sample',
                'width': 40,
                'height': 30,
                'harvest': false,
                'relabeled': false,
              },
            ],
            'total': 1,
            'offset': 0,
            'size_pending': false,
            'sources': ['sample'],
          });
        case '/api/relabel/preview':
          return _json({
            'boxes': 1,
            'pictures': 1,
            'target_class': 1,
            'target_name': 'car',
            'harvest_count': 0,
            'samples': [
              {'split': 'train', 'name': 'sample.jpg', 'index': 0},
            ],
          });
        case '/api/relabel':
          return _json({'ok': true, 'boxes': 1, 'pictures': 1});
        case '/api/sizes':
          return _json({'state': 'ready', 'done': 0, 'total': 0});
        case '/api/overview':
          return _json({
            'dataset': 'primary_anchor',
            'classes': ['motorcycle', 'car'],
            'images': 15,
            'images_per_split': {'train': 12, 'val': 2, 'test': 1},
            'boxes_per_class': {
              'train': [7, 4],
              'val': [1, 1],
              'test': [0, 0],
            },
            'per_source': {},
            'ph': {'ph': 9, 'foreign': 6, 'mixed': 0, 'unknown': 0},
            'empty': 0,
            'boxes_per_image': [],
            'box_area': [],
            'warnings': [],
            'sizes': {
              'state': 'ready',
              'have': 0,
              'of': 0,
              'long_side': [],
              'aspect': [],
              'box_aspect': [],
            },
            'report': {'match': true, 'when': '2026-10-31'},
          });
        case '/api/about':
          return _json({
            'dataset': 'primary_anchor',
            'card':
                '# Dataset card\n\nThis **dataset** is ready.\n\n| Split | Images |\n| --- | ---: |\n| train | 12 |',
            'classes': ['motorcycle', 'car'],
            'sources': [],
            'catalog': null,
            'notes': '',
          });
        case '/api/quarantine':
          return _json({'reasons': []});
        default:
          return _json({'error': 'unexpected request'}, status: 404);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DatasetViewerScreen(
          connect: () async => DatasetViewerApi(
            const DatasetViewerEndpoint('http://127.0.0.1:8766', 'test-token'),
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('primary_anchor'), findsNWidgets(2));
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Could not connect to the dataset service'), findsNothing);

    await tester.tap(find.text('Select all matching'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.ensureVisible(find.text('Relabel'));
    await tester.tap(find.text('Relabel'));
    await tester.pumpAndSettle();
    expect(
      find.text('Review individual boxes and correct their class labels.'),
      findsOneWidget,
    );
    expect(find.text('sample.jpg'), findsOneWidget);
    expect(find.text('No boxes match these filters.'), findsNothing);
    expect(find.text('motorcycle'), findsWidgets);

    final selectPage = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Select page'),
    );
    expect(selectPage.onPressed, isNotNull);
    selectPage.onPressed!();
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Preview class change'));
    await tester.pumpAndSettle();
    expect(find.text('Review label changes'), findsOneWidget);
    await tester.tap(find.text('Confirm and relabel'));
    await tester.pumpAndSettle();
    expect(find.text('Relabeled 1 boxes in 1 pictures.'), findsOneWidget);

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Boxes per class and split'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Dataset notes'), findsOneWidget);
    expect(find.text('Dataset card'), findsOneWidget);
    expect(find.text('This dataset is ready.'), findsOneWidget);
    expect(find.text('**dataset**'), findsNothing);
    expect(find.text('Images'), findsWidgets);

    await tester.ensureVisible(find.text('Quarantine'));
    await tester.tap(find.text('Quarantine'));
    await tester.pumpAndSettle();
    expect(find.text('Quarantine is empty for this reason.'), findsOneWidget);
  });
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
