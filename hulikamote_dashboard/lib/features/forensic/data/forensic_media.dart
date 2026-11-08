import 'package:flutter/widgets.dart';

import '../../../core/constants/api_constants.dart';

/// Where evidence photos, crops and the result video come from, and how they are loaded.
/// Widgets take this instead of building URLs, so tests can supply in-memory images.
class ForensicMedia {
  const ForensicMedia({this.baseUrl = ApiConstants.baseUrl});

  final String baseUrl;

  String evidenceUrl(String name) => '$baseUrl/snapshots/evidence/$name';

  /// A path the backend returned ("/snapshots/...") or an absolute URL, as an absolute URL.
  String absolute(String path) =>
      path.startsWith('http') ? path : '$baseUrl$path';

  /// Full-size evidence photo (1920x1080 JPEGs, ~250 KB).
  ImageProvider evidence(String name) => NetworkImage(evidenceUrl(name));

  /// A small, cheap-to-decode version for lists and filmstrips. The file still downloads
  /// whole (the backend has no thumbnails), but is decoded at [width] and cached.
  ImageProvider thumb(String name, {int width = 240}) => ResizeImage(
    NetworkImage(evidenceUrl(name)),
    width: width,
    policy: ResizeImagePolicy.fit,
  );

  /// The analysed frame the zones are drawn on.
  ImageProvider frame(String path) => NetworkImage(absolute(path));
}
