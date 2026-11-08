import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/external_apps.dart';
import '../domain/models/doc_page.dart';

class DocTabSpec {
  final String id;
  final String label;
  final String fileName;

  const DocTabSpec({
    required this.id,
    required this.label,
    required this.fileName,
  });
}

class DocsLoader {
  static const String buildCommand =
      'hulikamote_backend/venv/Scripts/python.exe tools/doc_site/build_site.py';

  static const List<DocTabSpec> tabs = [
    DocTabSpec(id: 'start', label: 'Start', fileName: 'index.json'),
    DocTabSpec(id: 'datasets', label: 'Datasets', fileName: '1-datasets.json'),
    DocTabSpec(id: 'models', label: 'Models', fileName: '2-models.json'),
    DocTabSpec(id: 'pipeline', label: 'Training pipeline', fileName: '3-training-pipeline.json'),
    DocTabSpec(id: 'violations', label: 'Violations', fileName: '4-violations.json'),
    DocTabSpec(id: 'qa', label: 'Q&A', fileName: '5-qa.json'),
  ];

  static Directory? resolveDataDir([Directory? root]) {
    final base = root ?? ExternalApps.repoRoot();
    if (base == null) return null;
    final dir = Directory([
      base.path,
      'docs',
      'documentation_site',
      'data',
    ].join(Platform.pathSeparator));
    return dir;
  }

  static bool isSiteBuilt([Directory? root]) {
    final dir = resolveDataDir(root);
    if (dir == null || !dir.existsSync()) return false;
    final indexFile = File([dir.path, 'index.json'].join(Platform.pathSeparator));
    return indexFile.existsSync();
  }

  static Map<String, String> loadGlossary([Directory? root]) {
    final dir = resolveDataDir(root);
    if (dir == null || !dir.existsSync()) return {};
    final file = File([dir.path, 'glossary.json'].join(Platform.pathSeparator));
    if (!file.existsSync()) return {};
    try {
      final text = file.readAsStringSync();
      final Map<String, dynamic> raw = jsonDecode(text);
      return raw.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static DocPage? loadPage(String fileName, [Directory? root]) {
    final dir = resolveDataDir(root);
    if (dir == null || !dir.existsSync()) return null;
    final file = File([dir.path, fileName].join(Platform.pathSeparator));
    if (!file.existsSync()) return null;
    try {
      final text = file.readAsStringSync();
      final Map<String, dynamic> raw = jsonDecode(text);
      return DocPage.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
}
