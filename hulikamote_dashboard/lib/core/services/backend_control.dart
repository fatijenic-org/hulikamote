import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../utils/external_apps.dart';

/// Where the backend is now.
enum BackendState {
  /// Not asked yet.
  unknown,

  /// Answers on its port.
  running,

  /// Was started from here and does not answer yet (the models load for a while).
  starting,

  /// A stop or a restart is under way.
  stopping,

  /// Does not answer.
  offline,

  /// Was started from here, but did not come up in time (see [BackendControl.logPath]).
  failed,
}

/// Starts, stops and restarts the backend (`hulikamote_backend`, uvicorn on port 8000) from the dashboard, and tells whether it answers.
/// Replaces the manual steps: open a terminal, go to the folder, use the venv, run uvicorn.
///
/// Start uses the venv of the repository and keeps running when the dashboard is closed. Its output goes to
/// `hulikamote_backend/backend_run.log`. Stop and Restart end whatever listens on the port (also a backend that was started by hand,
/// and one that hangs), with its child processes.
class BackendControl extends ChangeNotifier {
  BackendControl({http.Client? client, this.port = 8000, this.startTimeout = const Duration(seconds: 150)}) : _client = client ?? http.Client();

  /// The one the app uses.
  static final BackendControl instance = BackendControl();

  /// Polling is off under `flutter test` (a timer and real network calls would stay behind).
  static final bool pollsByDefault = !Platform.environment.containsKey('FLUTTER_TEST');

  final http.Client _client;
  final int port;
  final Duration startTimeout;

  BackendState state = BackendState.unknown;

  /// What went wrong the last time, in words; null when nothing did.
  String? error;

  DateTime? _startedAt;
  Timer? _timer;
  bool _busy = false;
  int _listeners = 0;

  bool get busy => _busy;

  /// The backend's own output since the last start from here.
  String? get logPath {
    final root = ExternalApps.repoRoot();
    return root == null ? null : _join(root.path, ['hulikamote_backend', 'backend_run.log']);
  }

  // ── watching ─────────────────────────────────────────────────────────────

  /// Starts asking every few seconds. Call [unwatch] with it. More than one widget may watch.
  void watch() {
    _listeners++;
    if (_timer != null) return;
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  void unwatch() {
    if (_listeners > 0) _listeners--;
    if (_listeners == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Asks the backend once and updates [state].
  Future<void> refresh() async {
    final up = await _answers();
    if (state == BackendState.stopping) return;               // a stop or restart sets its own state
    if (up) {
      _set(BackendState.running);
      _startedAt = null;
      error = null;
      return;
    }
    final started = _startedAt;
    if (started != null) {
      if (DateTime.now().difference(started) > startTimeout) {
        _startedAt = null;
        error = 'The backend did not come up in ${startTimeout.inSeconds} s. See ${logPath ?? 'backend_run.log'}.';
        _set(BackendState.failed);
      } else {
        _set(BackendState.starting);
      }
      return;
    }
    if (state != BackendState.failed) _set(BackendState.offline);
  }

  Future<bool> _answers() async {
    try {
      final res = await _client.get(Uri.parse(ApiConstants.status)).timeout(const Duration(seconds: 2));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void _set(BackendState next) {
    if (state == next) return;
    state = next;
    notifyListeners();
  }

  // ── actions ──────────────────────────────────────────────────────────────

  /// Starts the backend, unless it already answers. Returns at once; [state] shows "starting" until it answers.
  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    try {
      error = null;
      if (await _answers()) {
        _set(BackendState.running);
        return;
      }
      await _spawn();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ends the backend, whatever it is doing. Returns when the port is free (or after about 10 s).
  Future<void> stop() async {
    if (_busy) return;
    _busy = true;
    try {
      await _kill();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ends the backend no matter what, then starts it again.
  Future<void> restart() async {
    if (_busy) return;
    _busy = true;
    try {
      await _kill();
      if (error == null) await _spawn();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _kill() async {
    error = null;
    _startedAt = null;
    _set(BackendState.stopping);
    try {
      for (var round = 0; round < 3; round++) {
        final pids = await _listeningPids();
        if (pids.isEmpty) break;
        for (final pid in pids) {
          await _killTree(pid);
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      // wait until the port is really free
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) && (await _listeningPids()).isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if ((await _listeningPids()).isNotEmpty) {
        error = 'Something still uses port $port and could not be ended. Close it by hand.';
        _set(BackendState.failed);
        return;
      }
      _set(BackendState.offline);
    } catch (e) {
      error = 'Could not stop the backend: $e';
      _set(BackendState.failed);
    }
  }

  Future<void> _spawn() async {
    final root = ExternalApps.repoRoot();
    if (root == null) {
      error = 'The repository folder was not found. Start the dashboard from inside the repository.';
      _set(BackendState.failed);
      return;
    }
    final backend = Directory(_join(root.path, ['hulikamote_backend']));
    final python = [
      _join(backend.path, ['venv', 'Scripts', 'python.exe']),
      _join(backend.path, ['venv', 'bin', 'python']),
    ].where((p) => File(p).existsSync()).firstOrNull;
    if (python == null) {
      error = 'The Python environment was not found: hulikamote_backend/venv. Create it first.';
      _set(BackendState.failed);
      return;
    }
    try {
      final args = ['-m', 'uvicorn', 'main:app', '--port', '$port'];
      if (Platform.isWindows) {
        // cmd keeps the redirection of the output into a file; the process is detached and survives the dashboard
        await Process.start('cmd', ['/c', python, ...args, '>', 'backend_run.log', '2>&1'],
            workingDirectory: backend.path, mode: ProcessStartMode.detached);
      } else {
        await Process.start('sh', ['-c', '"\$0" "\$@" > backend_run.log 2>&1', python, ...args],
            workingDirectory: backend.path, mode: ProcessStartMode.detached);
      }
      _startedAt = DateTime.now();
      _set(BackendState.starting);
    } catch (e) {
      error = 'Could not start the backend: $e';
      _set(BackendState.failed);
    }
  }

  // ── the port ─────────────────────────────────────────────────────────────

  /// The processes that listen on the backend's port.
  Future<Set<int>> _listeningPids() async {
    final pids = <int>{};
    if (Platform.isWindows) {
      final out = (await Process.run('netstat', ['-ano', '-p', 'tcp'])).stdout.toString();
      for (final line in out.split('\n')) {
        final cols = line.trim().split(RegExp(r'\s+'));
        // Proto  Local  Foreign  State  PID
        if (cols.length >= 5 && cols[3] == 'LISTENING' && cols[1].endsWith(':$port')) {
          final pid = int.tryParse(cols[4]);
          if (pid != null && pid > 4) pids.add(pid);
        }
      }
    } else {
      final res = await Process.run('lsof', ['-ti', 'tcp:$port', '-sTCP:LISTEN']);
      for (final l in res.stdout.toString().split('\n')) {
        final pid = int.tryParse(l.trim());
        if (pid != null) pids.add(pid);
      }
    }
    return pids;
  }

  Future<void> _killTree(int pid) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    } else {
      await Process.run('kill', ['-9', '$pid']);
    }
  }

  static String _join(String base, List<String> parts) => [base, ...parts].join(Platform.pathSeparator);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
