import 'dart:async';

import 'package:flutter/services.dart';

/// What the phone broadcasts: its camera, or a video from the gallery.
enum SourceMode { camera, video }

class PickedVideo {
  const PickedVideo({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// One address the laptop can use (only listed when "Also allow Wi-Fi / USB tethering" is on).
class PhoneAddress {
  const PhoneAddress({required this.label, required this.url});

  final String label;
  final String url;
}

/// What the broadcast is doing right now (asked once a second).
class BroadcastStatus {
  const BroadcastStatus({
    this.running = false,
    this.clients = 0,
    this.fps = 0,
    this.port = 8080,
    this.error,
    this.addresses = const [],
  });

  final bool running;
  final int clients;
  final double fps;
  final int port;
  final String? error;
  final List<PhoneAddress> addresses;

  factory BroadcastStatus.fromMap(Map<dynamic, dynamic> m) => BroadcastStatus(
    running: m['running'] == true,
    clients: (m['clients'] as num?)?.toInt() ?? 0,
    fps: (m['fps'] as num?)?.toDouble() ?? 0,
    port: (m['port'] as num?)?.toInt() ?? 8080,
    error: m['error'] as String?,
    addresses: [
      for (final a in (m['addresses'] as List? ?? const []))
        PhoneAddress(label: '${(a as Map)['label']}', url: '${a['url']}'),
    ],
  );

  /// What the laptop opens through the USB cable (adb forward makes the phone's port 8080 the laptop's port 8080).
  String get usbUrl => 'http://127.0.0.1:$port/video';
}

/// The only place that talks to the Kotlin side (android/app/src/main/kotlin/.../MainActivity.kt).
class CameraBridge {
  static const _control = MethodChannel('hulikamote_camera/control');
  static const _preview = EventChannel('hulikamote_camera/preview');

  /// A small JPEG a few times a second while broadcasting: what the laptop receives.
  Stream<Uint8List> get preview => _preview.receiveBroadcastStream().map((e) => e as Uint8List);

  /// Returns null when the broadcast runs, or the reason it could not start.
  Future<String?> start({
    required SourceMode mode,
    bool front = false,
    String quality = 'medium',
    bool wifi = false,
    String? video,
  }) async {
    final r = await _control.invokeMapMethod<String, dynamic>('start', {
      'mode': mode == SourceMode.video ? 'video' : 'camera',
      'front': front,
      'quality': quality,
      'wifi': wifi,
      'video': video,
    });
    return r?['ok'] == true ? null : (r?['error'] as String? ?? 'The broadcast could not start.');
  }

  Future<void> stop() => _control.invokeMethod<void>('stop');

  /// What was chosen last time (empty the first time). The app uses it to start broadcasting by itself.
  Future<Map<String, dynamic>> loadPrefs() async => await _control.invokeMapMethod<String, dynamic>('loadPrefs') ?? <String, dynamic>{};

  Future<void> savePrefs(Map<String, dynamic> prefs) => _control.invokeMethod<void>('savePrefs', prefs);

  Future<PickedVideo?> pickVideo() async {
    final r = await _control.invokeMapMethod<String, dynamic>('pickVideo');
    if (r == null) return null;
    return PickedVideo(uri: '${r['uri']}', name: '${r['name']}');
  }

  Future<BroadcastStatus> status() async {
    final r = await _control.invokeMapMethod<dynamic, dynamic>('status');
    return r == null ? const BroadcastStatus() : BroadcastStatus.fromMap(r);
  }
}
