import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../domain/harvest_labeling_models.dart';
import '../domain/harvest_models.dart';
import 'harvest_source.dart';

/// Thrown when the harvest helper cannot be reached or refuses; [message] is safe to show.
class HarvestLabelingException implements Exception {
  HarvestLabelingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the Harvest tab and the labeler need from the harvest tool: what can be harvested, the pictures to check, and
/// saving a person's answer. The pictures are read from disk; the answers go through the tool's own helper, so the tool
/// stays the only thing that writes its inbox and its dataset.
abstract class HarvestLabeling {
  /// The harvest of one analysis, or of every analysis when [taskId] is null.
  Future<LabelSession> session(String? taskId);

  /// Gathers the pictures of one analysis (or of all of them) and returns when that is finished.
  Future<LabelSession> collect(String? taskId);

  /// The pictures that still need a person, most likely wrong first.
  Future<LabelQueue> queue(String model, {String? taskId});

  ImageProvider image(String model, String id, {int? width});

  /// A person decided: these boxes (an empty list = "nothing here").
  Future<void> save(String itemId, List<HarvestBox> boxes);

  /// A person was not sure: the picture stays out of training.
  Future<void> skip(String itemId);

  /// The "same car?" questions still open, likeliest first.
  Future<PairQueue> pairs({String? taskId});

  /// A person's answer about two cars. Same and different teach the car matcher; not sure only closes the question.
  Future<void> answerPair(String pairId, PairAnswer answer);

  /// One of the two pictures of a question; [side] is `a` or `b`.
  ImageProvider pairImage(String pairId, String side);

  /// The ticketed cars of one analysis, by number, with where each stands.
  Future<CarList> cars(String taskId);

  /// One car with all its photos in the order they were taken.
  Future<CarDetail> car(String taskId, String uid);

  /// A person walked along a car's photos: [different] are the ones that show another car than the first photo.
  /// An empty list = all one car. Nothing about the ticket changes; this only makes training data.
  Future<void> checkCar(String taskId, String uid, List<String> different);

  /// "The rest are fine": every car nobody opened is filed as one car (the tracker was right). Returns how many.
  Future<int> fillCars(String taskId);

  /// A photo of a car; [width] makes a small copy for the strip.
  ImageProvider carPhoto(String evidenceDir, String file, {int? width});
}

class _Helper {
  const _Helper(this.base, this.token, [this.pid]);

  final String base;
  final String token;
  final int? pid;
}

/// Talks to `harvest.py serve` on this computer: reuses a helper that is already running, or starts one that stops by
/// itself when it has been idle for a while.
class LocalHarvestLabeling implements HarvestLabeling {
  LocalHarvestLabeling({LocalHarvestSource? lab, http.Client? client, this.startTimeout = const Duration(seconds: 30)})
      : _lab = lab ?? LocalHarvestSource(),
        _client = client ?? http.Client();

  final LocalHarvestSource _lab;
  final http.Client _client;
  final Duration startTimeout;
  _Helper? _live;

  static const _idleMinutes = 30;

  /// What the helper must know: 4 = "the rest are fine" (3 = the cars one by one, 2 = the "same car?" questions and the clip's own pictures).
  static const _apiNeeded = 4;

  String _labDir() {
    try {
      return _lab.requireLab();
    } on HarvestException catch (e) {
      throw HarvestLabelingException(e.message);
    }
  }

  _Helper? _readInfo(String lab) {
    final file = File('$lab/harvest_inbox/server.json');
    if (!file.existsSync()) return null;
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map;
      final token = Uri.parse('${j['url']}').queryParameters['t'];
      if (token == null || j['port'] == null) return null;
      return _Helper('http://127.0.0.1:${j['port']}', token, (j['pid'] as num?)?.toInt());
    } catch (_) {
      return null;
    }
  }

  /// On Windows a detached `python.exe` opens a black console window; `pythonw.exe` (same interpreter) does not.
  static String _windowlessPython(String repo) {
    final python = LocalHarvestSource.pythonFor(repo);
    if (!Platform.isWindows) return python;
    final windowless = python.replaceFirst(RegExp(r'python\.exe$'), 'pythonw.exe');
    return File(windowless).existsSync() ? windowless : python;
  }

  /// The helper's version (1 for one that does not say), or null when nothing answers.
  Future<int?> _ping(_Helper h) async {
    try {
      final r = await _client.get(Uri.parse('${h.base}/api/ping'), headers: {'X-Harvest-Token': h.token}).timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body);
      return j is Map ? (j['api'] as num?)?.toInt() ?? 1 : 1;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _alive(_Helper h) async => await _ping(h) != null;

  /// A helper from before an update would not know the newer questions: stop it, a fresh one starts next.
  Future<void> _retire(_Helper h) async {
    final pid = h.pid;
    if (pid == null) return;
    Process.killPid(pid);
    for (var i = 0; i < 15 && await _alive(h); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<_Helper> _helper() async {
    final cached = _live;
    if (cached != null && await _alive(cached)) return cached;
    final lab = _labDir();
    final running = _readInfo(lab);
    if (running != null) {
      final api = await _ping(running);
      if (api != null && api >= _apiNeeded) return _live = running;
      if (api != null) await _retire(running);
    }
    final repo = Directory(lab).parent.path.replaceAll('\\', '/');
    try {
      await Process.start(
        _windowlessPython(repo),
        ['$lab/harvest.py', 'serve', '--no-open', '--idle-exit', '$_idleMinutes'],
        workingDirectory: repo,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      throw HarvestLabelingException('Could not start Python for the harvest helper: ${e.message}');
    }
    final deadline = DateTime.now().add(startTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final started = _readInfo(lab);
      if (started != null && await _alive(started)) return _live = started;
    }
    throw HarvestLabelingException('The harvest helper did not start. Open it once from the Training Lab (Harvest), then try again.');
  }

  Future<Map<String, dynamic>> _call(String method, String path, {Map<String, String>? query, Object? body}) async {
    final h = await _helper();
    final uri = Uri.parse('${h.base}$path').replace(queryParameters: query);
    final headers = {'X-Harvest-Token': h.token, if (body != null) 'Content-Type': 'application/json'};
    try {
      final r = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(const Duration(seconds: 60))
          : await _client.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(const Duration(seconds: 60));
      final decoded = r.body.isEmpty ? const <String, dynamic>{} : jsonDecode(r.body);
      if (r.statusCode != 200) {
        final message = decoded is Map && decoded['error'] != null ? '${decoded['error']}' : 'The harvest helper answered ${r.statusCode}.';
        throw HarvestLabelingException(message);
      }
      return Map<String, dynamic>.from(decoded as Map);
    } on TimeoutException {
      _live = null;
      throw HarvestLabelingException('The harvest helper took too long to answer.');
    } on SocketException {
      _live = null;
      throw HarvestLabelingException('The harvest helper stopped. Try again.');
    }
  }

  @override
  Future<LabelSession> session(String? taskId) async =>
      LabelSession.fromJson(await _call('GET', '/api/session', query: taskId == null ? null : {'task': taskId}));

  @override
  Future<LabelSession> collect(String? taskId) async {
    await _call('POST', '/api/collect', body: {'task': taskId});
    // Collecting runs in the helper; look every second until it says it is done (a long analysis can take minutes).
    final until = DateTime.now().add(const Duration(minutes: 20));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final s = await session(taskId);
      if (!s.collecting) {
        if (s.collectError != null) throw HarvestLabelingException(s.collectError!);
        return s;
      }
    }
    throw HarvestLabelingException('Getting the pictures is taking very long. Try again in a few minutes.');
  }

  @override
  Future<LabelQueue> queue(String model, {String? taskId}) async =>
      LabelQueue.fromJson(await _call('GET', '/api/queue', query: {'model': model, 'task': ?taskId}));

  @override
  Future<PairQueue> pairs({String? taskId}) async =>
      PairQueue.fromJson(await _call('GET', '/api/pairs', query: taskId == null ? null : {'task': taskId}));

  @override
  Future<void> answerPair(String pairId, PairAnswer answer) async {
    await _call('POST', '/api/pair', body: {'id': pairId, 'answer': answer.wire});
  }

  @override
  Future<CarList> cars(String taskId) async => CarList.fromJson(await _call('GET', '/api/cars', query: {'task': taskId}));

  @override
  Future<CarDetail> car(String taskId, String uid) async =>
      CarDetail.fromJson(await _call('GET', '/api/car', query: {'task': taskId, 'uid': uid}));

  @override
  Future<void> checkCar(String taskId, String uid, List<String> different) async {
    await _call('POST', '/api/car', body: {'task': taskId, 'uid': uid, 'different': different});
  }

  @override
  Future<int> fillCars(String taskId) async {
    final r = await _call('POST', '/api/cars/fill', body: {'task': taskId});
    return (r['filled'] as num?)?.toInt() ?? 0;
  }

  @override
  ImageProvider carPhoto(String evidenceDir, String file, {int? width}) {
    final provider = FileImage(File('$evidenceDir/$file'));
    return width == null ? provider : ResizeImage(provider, width: width);
  }

  @override
  ImageProvider pairImage(String pairId, String side) {
    final lab = _lab.findLab() ?? '.';
    return FileImage(File('$lab/harvest_inbox/reid_pairs/images/${pairId}_$side.jpg'));
  }

  @override
  ImageProvider image(String model, String id, {int? width}) {
    final lab = _lab.findLab() ?? '.';
    final provider = FileImage(File('$lab/harvest_inbox/$model/images/$id.jpg'));
    return width == null ? provider : ResizeImage(provider, width: width);
  }

  @override
  Future<void> save(String itemId, List<HarvestBox> boxes) async {
    await _call('POST', '/api/save', body: {
      'id': itemId,
      'boxes': [for (final b in boxes) [b.cls, b.cx, b.cy, b.w, b.h]],
    });
  }

  @override
  Future<void> skip(String itemId) async {
    await _call('POST', '/api/skip', body: {'id': itemId});
  }
}
