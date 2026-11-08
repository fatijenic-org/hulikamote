import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Opens things that live outside the dashboard: the progress deck (in the default
/// browser) and the educational visualizer (a separate Flutter desktop app).
///
/// Paths are found relative to the repository, so this works for `flutter run` from the
/// dashboard folder and for a release build inside it.
class ExternalApps {
  ExternalApps._();

  static const _visualizerExeName = 'hulikamote_visualizer.exe';

  /// The repository root: the nearest parent that holds both the dashboard and the visualizer.
  static Directory? repoRoot() {
    final starts = <Directory>[Directory.current, File(Platform.resolvedExecutable).parent];
    for (final start in starts) {
      var dir = start.absolute;
      for (var i = 0; i < 10; i++) {
        if (Directory(_join(dir.path, ['hulikamote_visualizer'])).existsSync() &&
            Directory(_join(dir.path, ['hulikamote_dashboard'])).existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  static String _join(String base, List<String> parts) => [base, ...parts].join(Platform.pathSeparator);

  // ── Progress report ──────────────────────────────────────────────────────

  static File? get progressReportFile {
    final root = repoRoot();
    if (root == null) return null;
    final file = File(_join(root.path, ['Progress Report', 'index.html']));
    return file.existsSync() ? file : null;
  }

  /// Opens the progress deck in the default browser. Returns an error message, or null on success.
  static Future<String?> openProgressReport() async {
    final file = progressReportFile;
    if (file == null) return 'Progress Report/index.html was not found in the repository.';
    return _openInBrowser(file.uri.toString());
  }

  static Future<String?> _openInBrowser(String url) async {
    try {
      if (Platform.isWindows) {
        // The URL form avoids quoting problems with the space in "Progress Report"
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      }
      return null;
    } catch (e) {
      return 'Could not open the browser: $e';
    }
  }

  // ── Visualizer ───────────────────────────────────────────────────────────

  static Directory? get visualizerDir {
    final root = repoRoot();
    if (root == null) return null;
    final dir = Directory(_join(root.path, ['hulikamote_visualizer']));
    return dir.existsSync() ? dir : null;
  }

  static File? get visualizerExe {
    final dir = visualizerDir;
    if (dir == null) return null;
    final file = File(_join(dir.path, ['build', 'windows', 'x64', 'runner', 'Release', _visualizerExeName]));
    return file.existsSync() ? file : null;
  }

  /// True when source files changed after the exe was built, so the exe is out of date.
  static bool visualizerBuildIsStale() {
    final exe = visualizerExe;
    final dir = visualizerDir;
    if (exe == null || dir == null) return false;
    final built = exe.lastModifiedSync();
    final lib = Directory(_join(dir.path, ['lib']));
    if (!lib.existsSync()) return false;
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is File && entity.lastModifiedSync().isAfter(built)) return true;
    }
    return false;
  }

  static Future<bool> isVisualizerRunning() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('tasklist', ['/FI', 'IMAGENAME eq $_visualizerExeName', '/NH']);
      return r.stdout.toString().toLowerCase().contains(_visualizerExeName);
    } catch (_) {
      return false;
    }
  }

  /// Starts the built visualizer as its own process (it keeps running if the dashboard is closed).
  /// Returns an error message, or null on success (also when it was already open).
  static Future<String?> launchVisualizer() async {
    if (await isVisualizerRunning()) return null;
    final exe = visualizerExe;
    if (exe == null) {
      return 'The visualizer is not built yet. Use "Build it" below, or run "flutter build windows" in hulikamote_visualizer.';
    }
    try {
      await Process.start(exe.path, const [], workingDirectory: exe.parent.path, mode: ProcessStartMode.detached);
      return null;
    } catch (e) {
      return 'Could not start the visualizer: $e';
    }
  }

  /// Builds the visualizer in a visible console window (takes a few minutes).
  static Future<String?> buildVisualizer() async {
    final dir = visualizerDir;
    if (dir == null) return 'hulikamote_visualizer was not found in the repository.';
    if (!Platform.isWindows) return 'Run "flutter build" inside hulikamote_visualizer.';
    try {
      await Process.start(
        'cmd',
        ['/c', 'start', 'Build visualizer', 'cmd', '/k', 'flutter build windows'],
        workingDirectory: dir.path,
        mode: ProcessStartMode.detached,
      );
      return null;
    } catch (e) {
      return 'Could not start the build: $e';
    }
  }

  // ── Dataset viewer ───────────────────────────────────────────────────────

  static const datasetViewerIdleMinutes = 30;

  static Future<DatasetViewerEndpoint> connectDatasetViewer() async {
    final root = repoRoot();
    if (root == null) throw StateError('Repository root not found.');

    var endpoint = await _readDatasetViewerEndpoint(root);
    if (endpoint != null) return endpoint;

    final script = File(
      _join(root.path, ['training_lab', 'dataset_viewer.py']),
    );
    if (!script.existsSync())
      throw StateError('training_lab/dataset_viewer.py was not found.');
    final scripts = _join(root.path, ['hulikamote_backend', 'venv', 'Scripts']);
    final candidates = [
      _join(scripts, ['pythonw.exe']),
      _join(scripts, ['python.exe']),
      _join(root.path, ['hulikamote_backend', 'venv', 'bin', 'python']),
    ];
    final python = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => Platform.isWindows ? 'python' : 'python3',
    );
    try {
      await Process.start(
        python,
        [script.path, '--no-open', '--idle-exit', '$datasetViewerIdleMinutes'],
        workingDirectory: root.path,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      throw StateError(
        'Could not start Python for the dataset viewer: ${e.message}',
      );
    }

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (endpoint == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      endpoint = await _readDatasetViewerEndpoint(root);
    }
    if (endpoint == null) {
      throw StateError(
        'The dataset viewer did not start. Try "python training_lab/dataset_viewer.py" in a terminal.',
      );
    }
    return endpoint;
  }

  static File? _datasetViewerServerJson(Directory root) {
    final file = File(
      _join(root.path, ['training_lab', 'dataset_viewer_cache', 'server.json']),
    );
    return file.existsSync() ? file : null;
  }

  static Future<DatasetViewerEndpoint?> _readDatasetViewerEndpoint(
    Directory root, {
    http.Client? client,
  }) async {
    final file = _datasetViewerServerJson(root);
    if (file == null) return null;
    final c = client ?? http.Client();
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map;
      final url = '${j['url']}';
      final parsed = Uri.parse(url);
      final token = parsed.queryParameters['t'];
      final port = int.tryParse('${j['port']}');
      if (token == null ||
          port == null ||
          parsed.host != '127.0.0.1' ||
          parsed.port != port)
        return null;
      final r = await c
          .get(
            Uri.parse('http://127.0.0.1:$port/api/ping'),
            headers: {'X-Viewer-Token': token},
          )
          .timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) return null;
      final ping = jsonDecode(r.body);
      if (ping is! Map || ping['ok'] != true || ping['api'] != 1) return null;
      return DatasetViewerEndpoint('http://127.0.0.1:$port', token);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  // ── Source Code & VS Code Integration ────────────────────────────────────

  /// Opens a source file directly in VS Code at the specified line number.
  /// Returns null on success, or an error message if VS Code or the file cannot be opened.
  static Future<String?> openInVsCode(String relativePath, {int? line}) async {
    final root = repoRoot();
    if (root == null) return 'Repository root not found.';
    final fullPath = _join(root.path, relativePath.split('/'));
    final file = File(fullPath);
    if (!file.existsSync()) {
      return 'File not found: $relativePath';
    }
    final target = line != null ? '${file.path}:$line' : file.path;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'code', '-g', target], mode: ProcessStartMode.detached);
      } else {
        await Process.start('code', ['-g', target], mode: ProcessStartMode.detached);
      }
      return null;
    } catch (e) {
      return 'Could not launch VS Code: $e';
    }
  }
}

class DatasetViewerEndpoint {
  final String baseUrl;
  final String token;

  const DatasetViewerEndpoint(this.baseUrl, this.token);

  Map<String, String> get headers => {'X-Viewer-Token': token};
}
