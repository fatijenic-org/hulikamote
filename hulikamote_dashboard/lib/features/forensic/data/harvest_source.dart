import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../domain/harvest_models.dart';

/// Thrown when the harvest folder cannot be found or read; [message] is safe to show.
class HarvestException implements Exception {
  HarvestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where the Harvest tab gets its data. The app reads the Training Lab's inbox straight from
/// disk (the dashboard and the lab live on the same computer), so it works with the backend
/// busy or off, and during a training.
abstract class HarvestSource {
  /// The snapshot the harvest tool wrote, or null when it has not been made yet.
  /// Throws [HarvestException] when the Training Lab folder cannot be found.
  Future<HarvestGallery?> load();

  /// Asks the harvest tool for a fresh snapshot (`harvest.py gallery`). Returns a message when
  /// that failed, null on success.
  Future<String?> rebuild();

  /// A picture of the inbox (path relative to the inbox folder), decoded no wider than [width].
  ImageProvider inboxImage(String relative, {int? width});

  /// A picture of the Training Lab's datasets (path relative to the lab folder).
  ImageProvider labImage(String relative, {int? width});
}

/// Finds `training_lab/` by walking up from where the app runs (or from `HULIKAMOTE_LAB`).
class LocalHarvestSource implements HarvestSource {
  LocalHarvestSource({this.labDir, this.searchFrom});

  /// A folder that is known to be the Training Lab (skips the search).
  final String? labDir;

  /// Folders to start the search from (default: where the app runs).
  final List<String>? searchFrom;

  String? _lab;

  static bool _isLab(String dir) =>
      File('$dir/harvest.py').existsSync() && Directory('$dir/harvest_tool').existsSync();

  /// The Training Lab folder, or null.
  String? findLab() {
    if (_lab != null) return _lab;
    final env = Platform.environment['HULIKAMOTE_LAB'];
    for (final fixed in [labDir, env]) {
      if (fixed != null && fixed.isNotEmpty && _isLab(fixed)) return _lab = fixed.replaceAll('\\', '/');
    }
    final starts = searchFrom ??
        [Directory.current.path, File(Platform.resolvedExecutable).parent.path];
    for (final start in starts) {
      var dir = Directory(start).absolute;
      for (var i = 0; i < 10; i++) {
        final here = dir.path.replaceAll('\\', '/');
        for (final candidate in ['$here/training_lab', here]) {
          if (_isLab(candidate)) return _lab = candidate;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  /// The python that runs the harvest tool: the backend's own environment when it exists, else the one on the PATH.
  static String pythonFor(String repo) => [
        '$repo/hulikamote_backend/venv/Scripts/python.exe',
        '$repo/hulikamote_backend/venv/bin/python',
      ].firstWhere((p) => File(p).existsSync(), orElse: () => Platform.isWindows ? 'python' : 'python3');

  /// Like [findLab], but says what to do when it is missing.
  String requireLab() => _requireLab();

  String _requireLab() {
    final lab = findLab();
    if (lab == null) {
      throw HarvestException(
        'Could not find the training_lab folder. Start the dashboard from the project, or set '
        'HULIKAMOTE_LAB to the full path of training_lab.',
      );
    }
    return lab;
  }

  @override
  Future<HarvestGallery?> load() async {
    final lab = _requireLab();
    final file = File('$lab/harvest_inbox/gallery.json');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) throw const FormatException('not an object');
      return HarvestGallery.fromJson(Map<String, dynamic>.from(json));
    } on FormatException catch (e) {
      throw HarvestException('The harvest snapshot could not be read (${e.message}). Press Update to rebuild it.');
    }
  }

  @override
  Future<String?> rebuild() async {
    final String lab;
    try {
      lab = _requireLab();
    } on HarvestException catch (e) {
      return e.message;
    }
    final repo = Directory(lab).parent.path.replaceAll('\\', '/');
    final python = pythonFor(repo);
    try {
      final r = await Process.run(python, ['$lab/harvest.py', 'gallery'], workingDirectory: repo)
          .timeout(const Duration(seconds: 90));
      if (r.exitCode == 0) return null;
      final text = '${r.stderr}'.trim().isNotEmpty ? '${r.stderr}' : '${r.stdout}';
      final lines = text.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      return lines.isEmpty ? 'The harvest tool stopped with code ${r.exitCode}.' : lines.last.trim();
    } on TimeoutException {
      return 'The harvest tool took too long to answer.';
    } on ProcessException catch (e) {
      return 'Could not start Python: ${e.message}';
    }
  }

  ImageProvider _file(String path, int? width) {
    final provider = FileImage(File(path));
    return width == null ? provider : ResizeImage(provider, width: width);
  }

  @override
  ImageProvider inboxImage(String relative, {int? width}) {
    final lab = findLab() ?? '.';
    return _file('$lab/harvest_inbox/$relative', width);
  }

  @override
  ImageProvider labImage(String relative, {int? width}) {
    final lab = findLab() ?? '.';
    return _file('$lab/$relative', width);
  }
}
