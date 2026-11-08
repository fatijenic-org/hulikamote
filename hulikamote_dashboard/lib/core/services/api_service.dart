import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../../features/violations/domain/models/violation.dart';

class ApiService {
  final http.Client _client;
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// [status] is pending, approved or rejected; null lists every ticket.
  Future<ViolationPage> fetchViolations({int page = 1, int size = 20, String? status}) async {
    final filter = status == null ? '' : '&status=$status';
    final uri = Uri.parse('${ApiConstants.violations}?page=$page&size=$size$filter');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load violations: ${response.statusCode}');
    }
    return ViolationPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Looks up the persisted violation record for a tracked vehicle, once the
  /// backend has finalized its ticket (vehicle left the ROI/frame).
  Future<Violation?> fetchViolationByTrackId(int trackId) async {
    final uri = Uri.parse(
      '${ApiConstants.violations}?track_id=$trackId&size=1',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load violation: ${response.statusCode}');
    }
    final page = ViolationPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return page.items.isNotEmpty ? page.items.first : null;
  }

  /// Triggers on-demand OCR plate extraction on the backend for a specific violation
  Future<String?> extractPlate(String violationId) async {
    final uri = Uri.parse('${ApiConstants.violations}/$violationId/extract-plate');
    final response = await _client.post(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to extract plate: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['user_name'] as String?;
  }

  Future<void> uploadModel(List<int> bytes, String filename, String category) async {
    final uri = Uri.parse(ApiConstants.uploadModel);
    final request = http.MultipartRequest('POST', uri)
      ..fields['category'] = category
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await _client.send(request);
    if (streamed.statusCode != 201) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Upload failed: $body');
    }
  }

  Future<Map<String, dynamic>> fetchModels() async {
    final uri = Uri.parse(ApiConstants.models);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load models: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> setActiveModel(String modelName) async {
    final uri = Uri.parse(ApiConstants.setActiveModel);
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model_name': modelName}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set active model: ${response.statusCode}');
    }
  }
}
