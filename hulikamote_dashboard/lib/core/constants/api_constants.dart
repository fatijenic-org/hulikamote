class ApiConstants {
  ApiConstants._();
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const String wsVideoFeed = 'ws://127.0.0.1:8000/ws/video-feed';
  static const String violations = '$baseUrl/violations';
  static const String uploadModel = '$baseUrl/upload-model';
  static const String models = '$baseUrl/models';
  static const String setActiveModel = '$baseUrl/models/active';
  static const String status = '$baseUrl/status';
}
