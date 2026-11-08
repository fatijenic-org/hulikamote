import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../domain/forensic_gateway.dart';
import '../domain/forensic_models.dart';
import '../domain/holding_models.dart';
import '../domain/plate_tools_models.dart';

/// Thrown when the backend answers with an error; [message] is safe to show.
class ForensicApiException implements Exception {
  ForensicApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// The result of reading the first frame of a video.
class FrameInfo {
  const FrameInfo({required this.url, required this.fps, required this.frames, this.duration = 0});

  final String url;
  final double fps;
  final int frames;

  /// Seconds (0 when the backend did not say).
  final double duration;
}

/// The model files per job (`vehicles`, `helmet`, `plate`, `cabin`) and which one is active.
class ModelChoices {
  const ModelChoices(this._byType);

  final Map<String, ({String? active, List<String> names})> _byType;

  static const empty = ModelChoices({});

  /// The catalog was reachable (an empty answer means "unknown", not "no models").
  bool get loaded => _byType.isNotEmpty;

  String? active(String type) => _byType[type]?.active;

  List<String> names(String type) => _byType[type]?.names ?? const [];

  /// A trained model exists for [type] (helmet / cabin checks need one).
  bool ready(String type) => active(type) != null;
}

/// All HTTP calls of the forensic feature, in one place.
class ForensicApi implements ReviewGateway {
  ForensicApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _timeout = Duration(seconds: 30);
  static const _slow = Duration(minutes: 5); // reading a dozen plates takes a while

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Never _fail(http.Response r, String what) {
    var detail = '';
    try {
      final body = jsonDecode(r.body);
      detail = '${body is Map ? (body['detail'] ?? body['error'] ?? '') : ''}';
    } catch (_) {}
    throw ForensicApiException(
      detail.isNotEmpty ? detail : '$what failed (HTTP ${r.statusCode}).',
      statusCode: r.statusCode,
    );
  }

  // ── library ──
  Future<List<RunSummary>> history() async {
    final r = await _client.get(_u('/api/forensic/history')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Loading the library');
    return [
      for (final j in jsonDecode(r.body) as List)
        RunSummary.fromJson(Map<String, dynamic>.from(j as Map)),
    ];
  }

  /// The settings a past run used (forensic_config.json). Empty when unavailable.
  Future<Map<String, dynamic>> runConfig(String taskId) async {
    try {
      final r = await _client
          .get(
            _u(
              '/snapshots/evidence/forensic/$taskId/output/forensic_config.json',
            ),
          )
          .timeout(_timeout);
      if (r.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      }
    } catch (_) {}
    return {};
  }

  Future<List<ForensicTicket>> report(String reportUrl) async {
    final r = await _client
        .get(_u(reportUrl))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _fail(r, 'Loading the report');
    return ForensicTicket.parseList(jsonDecode(r.body) as List);
  }

  /// Review decisions saved earlier, matched by violation row id. Pages through the
  /// approved and rejected lists (a few hundred rows at most in practice).
  Future<Map<String, ReviewStatus>> savedStatuses(
    Set<String> dbIds, {
    int maxPages = 8,
  }) async {
    final out = <String, ReviewStatus>{};
    if (dbIds.isEmpty) return out;
    for (final status in const ['approved', 'rejected']) {
      for (var page = 1; page <= maxPages; page++) {
        try {
          final r = await _client
              .get(_u('/violations?status=$status&size=100&page=$page'))
              .timeout(_timeout);
          if (r.statusCode != 200) break;
          final body = jsonDecode(r.body) as Map;
          final items = (body['items'] as List?) ?? const [];
          for (final it in items) {
            final id = '${(it as Map)['id']}';
            if (dbIds.contains(id)) out[id] = ReviewStatus.fromBackend(status);
          }
          if (items.length < 100) break;
        } catch (_) {
          break;
        }
      }
    }
    return out;
  }

  // ── new analysis ──
  /// A frame of the video at [seconds], with its speed and length, found by its path: nothing is uploaded, so it answers
  /// at once even for a huge file. Null when this backend is too old to know the call (use [extractFrame] then).
  Future<FrameInfo?> videoFrame(String videoPath, {double seconds = 0}) async {
    final uri = _u('/api/forensic/video-frame').replace(queryParameters: {'file_path': videoPath, 'seconds': '$seconds'});
    final r = await _client.get(uri).timeout(_timeout);
    if (r.statusCode == 404 && (jsonDecode(r.body) as Map)['detail'] == 'Not Found') return null;
    if (r.statusCode != 200) _fail(r, 'Reading the video');
    final j = jsonDecode(r.body) as Map;
    return FrameInfo(
      url: '${j['frame_url']}',
      fps: (j['fps'] as num?)?.toDouble() ?? 30,
      frames: (j['frame_count'] as num?)?.toInt() ?? 0,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Zone suggestions found from the painted lines of the video (stop line, crosswalk, solid line), by its path:
  /// `{'zones': {violation: [zone, ...]}, 'found': {...counts}}`. Zones come in the wizard's own shape (1920x1080 points).
  Future<Map<String, dynamic>> roadMarkings(String videoPath) async {
    final uri = _u('/api/forensic/road-markings').replace(queryParameters: {'file_path': videoPath});
    final r = await _client.get(uri).timeout(const Duration(seconds: 180));
    if (r.statusCode != 200) _fail(r, 'Looking for the painted lines');
    return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
  }

  Future<FrameInfo> extractFrame(String videoPath) async {
    final req = http.MultipartRequest('POST', _u('/api/forensic/extract-frame'))
      ..files.add(await http.MultipartFile.fromPath('file', videoPath));
    final streamed = await _client
        .send(req)
        .timeout(const Duration(seconds: 60));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) _fail(r, 'Reading the video');
    final j = jsonDecode(r.body) as Map;
    return FrameInfo(
      url: '${j['frame_url']}',
      fps: (j['fps'] as num?)?.toDouble() ?? 30,
      frames: (j['frame_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Uploads the video with its config; returns the task id.
  Future<String> submit(String videoPath, Map<String, dynamic> config) async {
    final req = http.MultipartRequest('POST', _u('/api/forensic/upload'))
      ..files.add(await http.MultipartFile.fromPath('file', videoPath))
      ..fields['config_json'] = jsonEncode(config);
    final streamed = await _client.send(req);
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) _fail(r, 'Starting the analysis');
    return '${(jsonDecode(r.body) as Map)['task_id']}';
  }

  /// Progress of a run. A running analysis only sends its (growing) ticket list when [tickets] is true.
  Future<RunStatus> status(String taskId, {bool tickets = false}) async {
    final r = await _client
        .get(_u('/api/forensic/status/$taskId${tickets ? '?include=tickets' : ''}'))
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Checking progress');
    return RunStatus.fromJson(
      Map<String, dynamic>.from(jsonDecode(r.body) as Map),
    );
  }

  @override
  Future<RunStatus> followStatus(String taskId) => status(taskId, tickets: true);

  // ── Holding: photos set aside from a ticket ──
  @override
  Future<HoldingResult> setAside(String taskId, String ticketUid, List<String> frames) async {
    final r = await _client
        .post(
          _u('/api/forensic/tickets/set-aside'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'task_id': taskId, 'ticket_uid': ticketUid, 'frames': frames}),
        )
        .timeout(_timeout);
    if (r.statusCode == 404 && _isUnknownRoute(r)) {
      throw ForensicApiException('This backend has no Holding yet. It needs the latest backend update and a restart.', statusCode: 404);
    }
    if (r.statusCode != 200) _fail(r, 'Setting the photos aside');
    return HoldingResult.fromJson(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
  }

  @override
  Future<List<HoldingBatch>> loadHolding(String taskId) async {
    final r = await _client.get(_u('/api/forensic/holding/$taskId')).timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Loading Holding');
    return HoldingBatch.parseList((jsonDecode(r.body) as Map)['holding'] as List);
  }

  @override
  Future<HoldingResult> holdingAction(String taskId, String action, Map<String, dynamic> body) async {
    final r = await _client
        .post(
          _u('/api/forensic/holding/$action'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'task_id': taskId, ...body}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'That Holding action');
    return HoldingResult.fromJson(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
  }

  /// Ends a running analysis. [keep] = "Stop here": keep everything found so far.
  /// Not [keep] = Cancel: the whole run is thrown away. The run notices within a moment.
  Future<void> stopRun(String taskId, {required bool keep}) async {
    final r = await _client
        .post(_u('/api/forensic/stop/$taskId?mode=${keep ? 'finish' : 'cancel'}'))
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r, keep ? 'Stopping the analysis' : 'Cancelling the analysis');
  }

  // ── models ──
  Future<ModelChoices> models() async {
    try {
      final r = await _client.get(_u('/models/catalog')).timeout(_timeout);
      if (r.statusCode != 200) return ModelChoices.empty;
      final types = (jsonDecode(r.body)['types'] as List).cast<Map>();
      return ModelChoices({
        for (final t in types)
          '${t['type']}': (
            active: t['active'] as String?,
            names: [
              for (final m in (t['models'] as List)) '${(m as Map)['name']}',
            ],
          ),
      });
    } catch (_) {
      return ModelChoices.empty;
    }
  }

  // ── tools ──
  Future<String> convertVideo(String path) async {
    final r = await _client
        .post(
          _u('/api/forensic/convert'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'file_path': path}),
        )
        .timeout(const Duration(minutes: 30));
    if (r.statusCode != 200) _fail(r, 'Converting the video');
    return '${(jsonDecode(r.body) as Map)['output_path']}';
  }

  /// Makes the wizard's zones and settings the Live Monitor's rules, with no analysis run. Returns a message to show.
  Future<String> useForLive(Map<String, dynamic> config) async {
    final r = await _client
        .post(
          _u('/api/forensic/live-config'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(config),
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _fail(r, 'Sending the rules to the Live Monitor');
    return 'Live Monitor rules updated. Open Live Monitoring, pick the camera in Camera input, and press Start.';
  }

  /// Makes a past run's video and rules the Live Monitor source. Returns a message to show.
  Future<String> sendToLive(String taskId) async {
    final r = await _client
        .post(_u('/api/forensic/send-to-live/$taskId'))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _fail(r, 'Sending to the Live Monitor');
    return 'Live Monitor updated. Open Live Monitoring and press Start.';
  }

  // ── ReviewGateway ──
  @override
  Future<void> setStatus(List<String> dbIds, ReviewStatus status) async {
    for (final id in dbIds) {
      final r = await _client
          .patch(
            _u('/violations/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': status.backendValue}),
          )
          .timeout(_timeout);
      if (r.statusCode != 200) _fail(r, 'Saving the decision');
    }
  }

  @override
  Future<List<ForensicTicket>> ticketAction(
    String taskId,
    String action,
    Map<String, dynamic> body,
  ) async {
    final r = await _client
        .post(
          _u('/api/forensic/tickets/$action'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'task_id': taskId, ...body}),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'The ticket change');
    return ForensicTicket.parseList(jsonDecode(r.body)['tickets'] as List);
  }

  @override
  Future<List<ForensicTicket>> setPlate(
    String taskId,
    String ticketUid,
    String plate, {
    bool revert = false,
  }) async {
    final r = await _client
        .post(
          _u('/api/forensic/tickets/set-plate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'task_id': taskId,
            'ticket_uid': ticketUid,
            'plate_text': plate,
            'revert': revert,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode == 404 && _isUnknownRoute(r)) {
      throw ForensicApiException(
        'This backend cannot save plate edits yet. It needs the latest backend update and a restart.',
        statusCode: 404,
      );
    }
    if (r.statusCode != 200) _fail(r, 'Saving the plate');
    return ForensicTicket.parseList(jsonDecode(r.body)['tickets'] as List);
  }

  @override
  Future<RereadResult> rereadPlate(String taskId, String ticketUid, List<String> frames) async {
    final r = await _client
        .post(
          _u('/api/forensic/tickets/reread-plate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'task_id': taskId, 'ticket_uid': ticketUid, 'frames': frames}),
        )
        .timeout(_slow);
    if (r.statusCode == 404 && _isUnknownRoute(r)) {
      throw ForensicApiException('This backend cannot read plates again yet. It needs the latest backend update and a restart.', statusCode: 404);
    }
    if (r.statusCode != 200) _fail(r, 'Reading the plate again');
    return RereadResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  @override
  Future<PlateBoxRead> readPlateBox(String taskId, String image, List<double> box) async {
    final r = await _client
        .post(
          _u('/api/forensic/tickets/read-plate-box'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'task_id': taskId, 'image': image, 'box': box}),
        )
        .timeout(_slow);
    if (r.statusCode == 404 && _isUnknownRoute(r)) {
      throw ForensicApiException('This backend cannot read a drawn plate yet. It needs the latest backend update and a restart.', statusCode: 404);
    }
    if (r.statusCode != 200) _fail(r, 'Reading the drawn plate');
    return PlateBoxRead.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// FastAPI answers an unknown route with {"detail": "Not Found"}; our own 404s carry "error".
  bool _isUnknownRoute(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      return body is Map && body['detail'] == 'Not Found';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> sendPlateFeedback({
    required String imageName,
    required String label,
  }) async {
    final img = await _client
        .get(_u('/snapshots/evidence/$imageName'))
        .timeout(_timeout);
    if (img.statusCode != 200) _fail(img, 'Loading the plate crop');
    final r = await _client
        .post(
          _u('/api/feedback/pop-quiz'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'image_base64': base64Encode(img.bodyBytes),
            'corrected_label': label,
            'class_id': 0,
          }),
        )
        .timeout(_timeout);
    if (r.statusCode != 200) _fail(r, 'Sending the plate feedback');
  }
}
