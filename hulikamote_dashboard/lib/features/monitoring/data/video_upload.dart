import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';

/// How many bytes of the file have left so far, of how many.
typedef UploadProgress = void Function(int sent, int total);

/// The operator pressed Cancel while the file was still going out.
class UploadCancelled implements Exception {
  const UploadCancelled();

  @override
  String toString() => 'Upload cancelled';
}

/// A multipart request that counts its bytes as the network takes them (the client pulls one chunk at a time, so the count
/// follows what was really sent) and that its abort trigger can stop.
class _CountingUpload extends http.BaseRequest with http.Abortable {
  _CountingUpload(this._inner, this._onProgress, this.abortTrigger) : super(_inner.method, _inner.url) {
    contentLength = _inner.contentLength;
  }

  final http.MultipartRequest _inner;
  final UploadProgress _onProgress;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    final body = _inner.finalize();
    headers.addAll(_inner.headers); // finalize() fills in the multipart content type with its boundary
    final total = contentLength ?? 0;
    var sent = 0;
    return http.ByteStream(
      body.map((chunk) {
        sent += chunk.length;
        _onProgress(sent, total);
        return chunk;
      }),
    );
  }
}

/// Sends the video at [path] to the backend as the Live Monitor's source ("Video file…").
///
/// [onProgress] follows the bytes going out; complete [cancel] to stop while they still are. Returns the backend's answer
/// (`{message, path, video: {width, height, fps, frames, duration, size_mb}}`). Throws [UploadCancelled], or an
/// Exception that carries the backend's reason.
Future<Map<String, dynamic>> uploadLiveVideo(
  String path, {
  http.Client? client,
  String baseUrl = ApiConstants.baseUrl,
  UploadProgress? onProgress,
  Future<void>? cancel,
}) async {
  final ownClient = client == null;
  final http.Client sender = client ?? http.Client();
  try {
    final inner = http.MultipartRequest('POST', Uri.parse('$baseUrl/settings/video/upload'));
    inner.files.add(await http.MultipartFile.fromPath('file', path));
    final request = _CountingUpload(inner, onProgress ?? (sent, total) {}, cancel);
    final http.StreamedResponse streamed;
    try {
      streamed = await sender.send(request).timeout(const Duration(minutes: 30));
    } on http.RequestAbortedException {
      throw const UploadCancelled();
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      String? detail;
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) detail = '${body['detail']}';
      } catch (_) {}
      throw Exception(detail ?? 'Upload failed (HTTP ${response.statusCode})');
    }
    final body = jsonDecode(response.body);
    return body is Map<String, dynamic> ? body : <String, dynamic>{};
  } finally {
    if (ownClient) sender.close();
  }
}
