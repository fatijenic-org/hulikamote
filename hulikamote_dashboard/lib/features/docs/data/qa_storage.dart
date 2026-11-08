import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../../core/utils/external_apps.dart';
import '../domain/models/qa_item.dart';

class QaStorage {
  static Directory? resolveDocSiteDir([Directory? root]) {
    final base = root ?? ExternalApps.repoRoot();
    if (base == null) return null;
    return Directory([base.path, 'tools', 'doc_site'].join(Platform.pathSeparator));
  }

  static File? getQaFile([Directory? root]) {
    final dir = resolveDocSiteDir(root);
    if (dir == null) return null;
    return File([dir.path, 'data', 'qa.json'].join(Platform.pathSeparator));
  }

  static File? getSeedFile([Directory? root]) {
    final dir = resolveDocSiteDir(root);
    if (dir == null) return null;
    return File([dir.path, 'qa_seed.json'].join(Platform.pathSeparator));
  }

  static List<QaItem> loadItems([Directory? root]) {
    try {
      final qaFile = getQaFile(root);
      if (qaFile != null && qaFile.existsSync()) {
        final text = qaFile.readAsStringSync();
        final map = jsonDecode(text) as Map<String, dynamic>;
        final list = (map['items'] as List<dynamic>?) ?? [];
        return list
            .map((item) => QaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      final seedFile = getSeedFile(root);
      if (seedFile != null && seedFile.existsSync()) {
        final text = seedFile.readAsStringSync();
        final map = jsonDecode(text) as Map<String, dynamic>;
        final list = (map['items'] as List<dynamic>?) ?? [];
        final items = list
            .map((item) => QaItem.fromJson(item as Map<String, dynamic>))
            .toList();

        // Auto-seed to tools/doc_site/data/qa.json
        saveItems(items, root);
        return items;
      }
    } catch (e) {
      debugPrint('QaStorage.loadItems error: $e');
    }
    return [];
  }

  static bool saveItems(List<QaItem> items, [Directory? root]) {
    try {
      final qaFile = getQaFile(root);
      if (qaFile == null) return false;

      qaFile.parent.createSync(recursive: true);
      final jsonStr = const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'items': items.map((i) => i.toJson()).toList(),
      });

      // Atomic write via temp file
      final tmpFile = File('${qaFile.path}.tmp');
      tmpFile.writeAsStringSync('$jsonStr\n', flush: true);

      // Keep .bak backup of previous version
      if (qaFile.existsSync()) {
        final bakFile = File('${qaFile.path}.bak');
        try {
          if (bakFile.existsSync()) bakFile.deleteSync();
          qaFile.copySync(bakFile.path);
        } catch (_) {}
      }

      tmpFile.renameSync(qaFile.path);
      return true;
    } catch (e) {
      debugPrint('QaStorage.saveItems error: $e');
      return false;
    }
  }

  static String exportJsonString(List<QaItem> items) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'items': items.map((i) => i.toJson()).toList(),
    });
  }

  static ({int added, int replaced, List<QaItem> merged})? importJson(
    String jsonString,
    List<QaItem> currentItems,
  ) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      if (map['version'] != 1 || map['items'] is! List) return null;

      final byId = {for (final item in currentItems) item.id: item};
      var added = 0;
      var replaced = 0;

      for (final raw in map['items'] as List<dynamic>) {
        if (raw is! Map<String, dynamic>) continue;
        final imported = QaItem.fromJson(raw);
        if (imported.id.isEmpty) continue;
        if (byId.containsKey(imported.id)) {
          replaced++;
        } else {
          added++;
        }
        byId[imported.id] = imported;
      }

      return (
        added: added,
        replaced: replaced,
        merged: byId.values.toList(),
      );
    } catch (_) {
      return null;
    }
  }
}
