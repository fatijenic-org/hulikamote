import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'forensic_api.dart';

/// An overlay object as the backend drew it (a hydrant, a sign on a pole ...), ready to paint, and where it sits relative to the spot it
/// stands on, in pixels of a picture 1920 wide.
class ObjectPreview {
  const ObjectPreview(this.image, this.dx, this.dy);

  final ui.Image image;
  final double dx;
  final double dy;
}

/// Asks the backend for the pictures of overlay objects and keeps them, so the zone editor shows exactly what the evidence photos will show.
/// Ask with [peek]: it answers at once from what is kept, or returns null and fetches the picture; listeners are told when it arrives.
/// Without an API (or when the backend cannot draw the object) nothing is ever kept and the editor shows a dot instead.
class ObjectPreviews extends ChangeNotifier {
  ObjectPreviews(this.api);

  final ForensicApi? api;
  final Map<String, ObjectPreview> _kept = {};
  final Set<String> _asked = {};
  bool _disposed = false;

  static String keyOf(String kind, double scale, double angle, double tilt, String stand, bool realistic) =>
      '$kind|${scale.toStringAsFixed(2)}|${angle.round()}|${tilt.round()}|$stand|$realistic';

  ObjectPreview? peek(String kind, {double scale = 1, double angle = 0, double tilt = 0, String stand = '', bool realistic = true}) {
    return peekKeyed(
      keyOf(kind, scale, angle, tilt, stand, realistic),
      (api) => api.overlayObject(kind, scale: scale, angle: angle.roundToDouble(), tilt: tilt.roundToDouble(), stand: stand, realistic: realistic),
    );
  }

  /// A solid line painted like road paint along [points] (1920x1080 reference space), the way the evidence photos will show it.
  ObjectPreview? peekLine(List<List<double>> points, Map<String, dynamic> look, bool realistic) {
    final rounded = [for (final p in points) [p[0].round(), p[1].round()]];
    return peekKeyed('line|${jsonEncode(rounded)}|${jsonEncode(look)}|$realistic', (api) => api.overlayLine(points, look, realistic: realistic));
  }

  /// The kept picture for [key], or null while [fetch] is asking the backend for it (listeners hear when it arrives).
  ObjectPreview? peekKeyed(String key, Future<OverlayObjectImage?> Function(ForensicApi api) fetch) {
    final kept = _kept[key];
    if (kept != null || api == null || !_asked.add(key)) return kept;
    _fetchKeyed(key, fetch);
    return null;
  }

  Future<void> _fetchKeyed(String key, Future<OverlayObjectImage?> Function(ForensicApi api) fetch) async {
    try {
      final got = await fetch(api!);
      if (got == null || _disposed) return;
      final codec = await ui.instantiateImageCodec(got.bytes);
      final frame = await codec.getNextFrame();
      if (_disposed) return;
      _kept[key] = ObjectPreview(frame.image, got.dx, got.dy);
      notifyListeners();
    } catch (_) {
      // no picture: the editor keeps showing a dot
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final p in _kept.values) {
      p.image.dispose();
    }
    _kept.clear();
    super.dispose();
  }
}
