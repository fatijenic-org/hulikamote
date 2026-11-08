import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';

/// A saved camera address. The backend never sends passwords back: they show as `***`.
class CameraProfile {
  const CameraProfile({required this.name, required this.url, this.kind = ''});

  final String name;
  final String url;
  final String kind; // rtsp | http | stream | webcam | file | invalid

  factory CameraProfile.fromJson(Map<String, dynamic> json) =>
      CameraProfile(name: json['name'] as String, url: json['url'] as String, kind: (json['kind'] ?? '') as String);
}

/// What the Test button found.
class CameraTestResult {
  const CameraTestResult({required this.ok, this.message = '', this.width = 0, this.height = 0, this.fps = 0, this.firstFrameMs = 0});

  final bool ok;
  final String message;
  final int width;
  final int height;
  final double fps;
  final int firstFrameMs;

  factory CameraTestResult.fromJson(Map<String, dynamic> json) => CameraTestResult(
        ok: json['ok'] == true,
        message: (json['error'] ?? '') as String,
        width: (json['width'] ?? 0) as int,
        height: (json['height'] ?? 0) as int,
        fps: ((json['fps'] ?? 0) as num).toDouble(),
        firstFrameMs: (json['first_frame_ms'] ?? 0) as int,
      );

  /// "1280x720 at 15 fps, first picture after 3.5 s" or the reason it failed.
  String get summary => ok
      ? '${width}x$height at ${fps.toStringAsFixed(0)} fps, first picture after ${(firstFrameMs / 1000).toStringAsFixed(1)} s'
      : message;
}

/// The backend's camera-input endpoints (see hulikamote_backend/routers/settings.py).
class CameraApi {
  CameraApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _json(http.Response res) async {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw Exception(detail ?? 'Request failed (${res.statusCode})');
    }
    return body as Map<String, dynamic>;
  }

  Future<List<CameraProfile>> profiles() async {
    final body = await _json(await _client.get(_uri('/settings/camera-profiles')));
    return [for (final p in (body['profiles'] as List)) CameraProfile.fromJson(p as Map<String, dynamic>)];
  }

  Future<void> saveProfiles(List<CameraProfile> profiles) async {
    final res = await _client.put(
      _uri('/settings/camera-profiles'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'profiles': [for (final p in profiles) {'name': p.name, 'url': p.url}],
      }),
    );
    await _json(res);
  }

  /// Test a typed address, or a saved profile by name (so a hidden password is still used).
  Future<CameraTestResult> test({String? address, String? profile}) async {
    final res = await _client.post(
      _uri('/settings/video/test', address != null ? {'path': address} : {'name': profile!}),
    );
    return CameraTestResult.fromJson(await _json(res));
  }

  /// Make an address, or a saved profile by name, the live monitor's source. Returns the masked label.
  Future<String> use({String? address, String? profile}) async {
    final res = address != null
        ? await _client.post(_uri('/settings/video/source', {'path': address}))
        : await _client.post(_uri('/settings/camera-profiles/use', {'name': profile!}));
    return ((await _json(res))['label'] ?? '') as String;
  }

  /// Learn the road paint of the connected camera again from the live stream.
  Future<void> relearnRoad() async => _json(await _client.post(_uri('/settings/video/road/relearn')));

  /// Remove what was learned for the connected camera (also from the saved file).
  Future<void> forgetRoad() async => _json(await _client.post(_uri('/settings/video/road/forget')));

  /// state: live | connecting | offline | file | idle ...
  Future<Map<String, dynamic>> status() async => _json(await _client.get(_uri('/settings/video/status')));
}
