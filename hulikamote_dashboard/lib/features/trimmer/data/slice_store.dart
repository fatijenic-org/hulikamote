import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Keeps the slices a person marked on each video in a small file, so closing or restarting the app (or a crash) never loses them.
/// One file for all videos: `%LOCALAPPDATA%\\hulikamote\\trimmer_slices.json`, `{ "<video path>": [ {slice}, ... ] }`.
/// Under `flutter test` nothing is read or written.
class SliceStore {
  SliceStore({File? file, bool? enabled})
      : _file = file ?? _defaultFile(),
        enabled = enabled ?? (file != null || !Platform.environment.containsKey('FLUTTER_TEST'));

  final File _file;
  final bool enabled;
  Future<void> _queue = Future.value();           // writes take turns, so two saves never mix

  static File _defaultFile() {
    final base = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['XDG_DATA_HOME'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return File('$base${Platform.pathSeparator}hulikamote${Platform.pathSeparator}trimmer_slices.json');
  }

  Future<Map<String, dynamic>> _readAll() async {
    try {
      if (!await _file.exists()) return {};
      final data = jsonDecode(await _file.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};                                   // a damaged file must never stop the trimmer: it starts empty
    }
  }

  /// The slices saved for this video (empty when none).
  Future<List<Map<String, dynamic>>> load(String videoPath) async {
    if (!enabled) return const [];
    final all = await _readAll();
    final list = all[videoPath];
    return list is List ? [for (final s in list) if (s is Map) Map<String, dynamic>.from(s)] : const [];
  }

  /// Replaces the slices saved for this video. An empty list removes the entry.
  Future<void> save(String videoPath, List<Map<String, dynamic>> slices) {
    if (!enabled) return Future.value();
    _queue = _queue.then((_) async {
      try {
        final all = await _readAll();
        if (slices.isEmpty) {
          all.remove(videoPath);
        } else {
          all[videoPath] = slices;
        }
        await _file.parent.create(recursive: true);
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(all));
        await tmp.rename(_file.path);              // written whole, then swapped in: a crash cannot leave half a file
      } catch (_) {
        // saving is a safety net: a failure must not disturb the person's work
      }
    });
    return _queue;
  }
}
