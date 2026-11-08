import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/features/docs/data/qa_storage.dart';
import 'package:hulikamote_dashboard/features/docs/domain/models/qa_item.dart';

void main() {
  group('QaStorage', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('qa_storage_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('auto-seeds from qa_seed.json when data/qa.json does not exist', () {
      final docSiteDir = Directory('${tempDir.path}/tools/doc_site')..createSync(recursive: true);
      final seedFile = File('${docSiteDir.path}/qa_seed.json');
      seedFile.writeAsStringSync(jsonEncode({
        'version': 1,
        'items': [
          {
            'id': 'seed-1',
            'q': 'What is this?',
            'a': 'It is **test**.',
            'tags': ['test', 'unit'],
            'created': '2026-10-28T00:00:00.000Z',
            'updated': '2026-10-28T00:00:00.000Z',
          }
        ]
      }));

      final items = QaStorage.loadItems(tempDir);
      expect(items.length, 1);
      expect(items.first.id, 'seed-1');
      expect(items.first.q, 'What is this?');
      expect(items.first.tags, ['test', 'unit']);

      // Should have auto-created data/qa.json
      final qaFile = File('${docSiteDir.path}/data/qa.json');
      expect(qaFile.existsSync(), isTrue);
    });

    test('saves items atomically and creates .bak backup on subsequent saves', () {
      final docSiteDir = Directory('${tempDir.path}/tools/doc_site')..createSync(recursive: true);
      final qaFile = File('${docSiteDir.path}/data/qa.json');

      final initial = [
        const QaItem(
          id: 'q-1',
          q: 'Initial question',
          a: 'Initial answer',
          tags: ['initial'],
          created: '2026-10-28T00:00:00.000Z',
          updated: '2026-10-28T00:00:00.000Z',
        ),
      ];

      expect(QaStorage.saveItems(initial, tempDir), isTrue);
      expect(qaFile.existsSync(), isTrue);

      final second = [
        ...initial,
        const QaItem(
          id: 'q-2',
          q: 'Second question',
          a: 'Second answer',
          tags: ['second'],
          created: '2026-10-28T01:00:00.000Z',
          updated: '2026-10-28T01:00:00.000Z',
        ),
      ];

      expect(QaStorage.saveItems(second, tempDir), isTrue);
      final loaded = QaStorage.loadItems(tempDir);
      expect(loaded.length, 2);
      expect(loaded[1].id, 'q-2');

      // Backup file should exist
      final bakFile = File('${docSiteDir.path}/data/qa.json.bak');
      expect(bakFile.existsSync(), isTrue);
      final bakContent = bakFile.readAsStringSync();
      expect(bakContent.contains('Initial question'), isTrue);
    });

    test('importJson merges new items and updates matching IDs', () {
      final current = [
        const QaItem(
          id: 'q-1',
          q: 'Old Title',
          a: 'Old Answer',
          tags: ['old'],
          created: '2026-10-28T00:00:00.000Z',
          updated: '2026-10-28T00:00:00.000Z',
        ),
      ];

      final importJson = jsonEncode({
        'version': 1,
        'items': [
          {
            'id': 'q-1',
            'q': 'Updated Title',
            'a': 'Updated Answer',
            'tags': ['updated'],
            'created': '2026-10-28T00:00:00.000Z',
            'updated': '2026-10-28T02:00:00.000Z',
          },
          {
            'id': 'q-new',
            'q': 'Brand New',
            'a': 'Brand New Answer',
            'tags': ['new'],
            'created': '2026-10-28T02:00:00.000Z',
            'updated': '2026-10-28T02:00:00.000Z',
          }
        ]
      });

      final result = QaStorage.importJson(importJson, current);
      expect(result, isNotNull);
      expect(result!.added, 1);
      expect(result.replaced, 1);
      expect(result.merged.length, 2);

      final updated = result.merged.firstWhere((i) => i.id == 'q-1');
      expect(updated.q, 'Updated Title');
      final brandNew = result.merged.firstWhere((i) => i.id == 'q-new');
      expect(brandNew.q, 'Brand New');
    });
  });
}
