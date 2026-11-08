import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';

class DatasetViewerApiException implements Exception {
  final String message;
  final int statusCode;
  final String? needsConfirm;
  final Object? detail;

  const DatasetViewerApiException(
    this.message, {
    required this.statusCode,
    this.needsConfirm,
    this.detail,
  });

  @override
  String toString() => message;
}

class DatasetViewerApi {
  final DatasetViewerEndpoint endpoint;
  final http.Client _client;

  DatasetViewerApi(this.endpoint, {http.Client? client})
    : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    return Uri.parse(
      '${endpoint.baseUrl}$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final response = await _client
        .get(_uri(path, query), headers: endpoint.headers)
        .timeout(const Duration(seconds: 60));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(
          _uri(path),
          headers: {...endpoint.headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode != 200) {
      final data = decoded is Map ? decoded : const <String, dynamic>{};
      throw DatasetViewerApiException(
        '${data['error'] ?? 'Dataset viewer returned ${response.statusCode}.'}',
        statusCode: response.statusCode,
        needsConfirm: data['needs_confirm'] as String?,
        detail: data['detail'],
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Dataset viewer returned an unexpected response.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> datasets() async {
    final result = await get('/api/datasets');
    return maps(result['datasets']);
  }

  Future<Map<String, dynamic>> overview(String dataset) =>
      get('/api/overview', {'dataset': dataset});

  Future<Map<String, dynamic>> startSizes(String dataset) =>
      get('/api/sizes', {'dataset': dataset});

  Future<Map<String, dynamic>> facets(String dataset, {String? split}) => get(
    '/api/facets',
    {'dataset': dataset, if (split != null && split != 'all') 'split': split},
  );

  Future<Map<String, dynamic>> items(
    String dataset, {
    String split = 'all',
    List<int> classes = const [],
    List<String> sources = const [],
    String q = '',
    String sort = 'name',
    String filter = 'all',
    int offset = 0,
    int limit = 150,
  }) {
    return get('/api/items', {
      'dataset': dataset,
      if (split != 'all') 'split': split,
      if (classes.isNotEmpty) 'classes': classes.join(','),
      if (sources.isNotEmpty) 'source': sources.join(','),
      if (q.isNotEmpty) 'q': q,
      'sort': sort,
      if (filter == 'flagged') 'flag': '1',
      if (filter == 'mine') 'mine': '1',
      if (filter == 'no_boxes') 'nobox': '1',
      if (filter == 'many') 'many': '1',
      if (filter == 'tiny') 'tiny': '1',
      if (filter == 'relabeled') 'relabeled': '1',
      'offset': '$offset',
      'limit': '$limit',
    });
  }

  Future<Map<String, dynamic>> keys(
    String dataset, {
    String split = 'all',
    List<int> classes = const [],
    List<String> sources = const [],
    String q = '',
    String sort = 'name',
    String filter = 'all',
  }) {
    return get('/api/keys', {
      'dataset': dataset,
      if (split != 'all') 'split': split,
      if (classes.isNotEmpty) 'classes': classes.join(','),
      if (sources.isNotEmpty) 'source': sources.join(','),
      if (q.isNotEmpty) 'q': q,
      'sort': sort,
      if (filter == 'flagged') 'flag': '1',
      if (filter == 'mine') 'mine': '1',
      if (filter == 'no_boxes') 'nobox': '1',
      if (filter == 'many') 'many': '1',
      if (filter == 'tiny') 'tiny': '1',
      if (filter == 'relabeled') 'relabeled': '1',
    });
  }

  Future<Map<String, dynamic>> labelItems(
    String dataset, {
    String split = 'all',
    String source = 'all',
    int? classId,
    int minBoxPx = 0,
    int offset = 0,
    int limit = 100,
  }) => get('/api/labels', {
    'dataset': dataset,
    'split': split,
    'source': source,
    if (classId != null) 'class': '$classId',
    'min_box_px': '$minBoxPx',
    'offset': '$offset',
    'limit': '$limit',
  });

  Future<Map<String, dynamic>> item(
    String dataset,
    String split,
    String name,
  ) => get('/api/item', {'dataset': dataset, 'split': split, 'name': name});

  Future<Map<String, dynamic>> about(String dataset) =>
      get('/api/about', {'dataset': dataset});

  Future<Map<String, dynamic>> quarantine(
    String dataset, {
    String? reason,
    int offset = 0,
    int limit = 150,
  }) {
    final query = {'dataset': dataset, 'offset': '$offset', 'limit': '$limit'};
    if (reason != null) query['reason'] = reason;
    return get('/api/quarantine', query);
  }

  Future<Map<String, dynamic>> job(String id) => get('/api/job', {'id': id});

  Uri imageUri(
    String dataset,
    String split,
    String name, {
    bool thumbnail = false,
  }) => _uri(thumbnail ? '/api/thumb' : '/api/image', {
    'dataset': dataset,
    'split': split,
    'name': name,
  });

  Uri cropUri(String dataset, String split, String name, int index) => _uri(
    '/api/crop',
    {'dataset': dataset, 'split': split, 'name': name, 'i': '$index'},
  );

  Uri quarantineImageUri(
    String dataset,
    String reason,
    String name, {
    bool thumbnail = false,
  }) => _uri(thumbnail ? '/api/qthumb' : '/api/qimage', {
    'dataset': dataset,
    'reason': reason,
    'name': name,
  });

  Future<Map<String, dynamic>> quarantineItems(
    String dataset,
    List<Map<String, String>> items, {
    bool confirmHarvest = false,
  }) => post('/api/quarantine', {
    'dataset': dataset,
    'items': items,
    'confirm_harvest': confirmHarvest,
  });

  Future<Map<String, dynamic>> restoreItems(
    String dataset,
    String reason,
    List<Map<String, String>> items, {
    bool confirmHarvest = false,
    bool confirmLeak = false,
  }) => post('/api/restore', {
    'dataset': dataset,
    'reason': reason,
    'items': items,
    'confirm_harvest': confirmHarvest,
    'confirm_leak': confirmLeak,
  });

  Future<Map<String, dynamic>> setFlag(
    String dataset,
    List<Map<String, String>> items,
    bool value,
  ) => post('/api/flag', {'dataset': dataset, 'items': items, 'value': value});

  Future<Map<String, dynamic>> editBox(
    String dataset,
    String split,
    String name,
    int index, {
    int? classId,
    bool remove = false,
    bool confirmHarvest = false,
  }) {
    final body = <String, Object?>{
      'dataset': dataset,
      'split': split,
      'name': name,
      'i': index,
      'remove': remove,
      'confirm_harvest': confirmHarvest,
    };
    if (classId != null) body['cls'] = classId;
    return post('/api/box', body);
  }

  Future<Map<String, dynamic>> previewRelabel(
    String dataset,
    int classId, {
    List<Map<String, Object?>>? items,
    Map<String, Object?>? rule,
  }) {
    final body = <String, Object?>{'dataset': dataset, 'class_id': classId};
    if (items != null) body['items'] = items;
    if (rule != null) body['rule'] = rule;
    return post('/api/relabel/preview', body);
  }

  Future<Map<String, dynamic>> relabel(
    String dataset,
    int classId, {
    List<Map<String, Object?>>? items,
    Map<String, Object?>? rule,
    bool confirmHarvest = false,
  }) {
    final body = <String, Object?>{
      'dataset': dataset,
      'class_id': classId,
      'confirm_harvest': confirmHarvest,
    };
    if (items != null) body['items'] = items;
    if (rule != null) body['rule'] = rule;
    return post('/api/relabel', body);
  }

  Future<Map<String, dynamic>> undo(String dataset) =>
      post('/api/undo', {'dataset': dataset});

  Future<Map<String, dynamic>> startReport(String dataset) =>
      post('/api/report', {'dataset': dataset});

  Future<Map<String, dynamic>> reveal(
    String dataset,
    String split,
    String name,
  ) => post('/api/reveal', {'dataset': dataset, 'split': split, 'name': name});

  Future<Map<String, dynamic>> saveNotes(String dataset, String text) =>
      post('/api/notes', {'dataset': dataset, 'text': text});

  Future<Map<String, dynamic>> startClean(String dataset) =>
      post('/api/clean', {'dataset': dataset});

  Future<Map<String, dynamic>> applyClean(String dataset) =>
      post('/api/clean/apply', {'dataset': dataset, 'confirm': true});

  // ---- Car matcher (ReID) manager: datasets/reid is folders of car photos, not YOLO boxes

  Future<Map<String, dynamic>> reidSummary() => get('/api/reid/summary');

  Future<Map<String, dynamic>> reidCars({
    String? analysis,
    String filter = 'all',
    String q = '',
  }) => get('/api/reid/cars', {
    'analysis': ?analysis,
    'filter': filter,
    if (q.isNotEmpty) 'q': q,
  });

  Future<Map<String, dynamic>> reidCar(String key) =>
      get('/api/reid/car', {'key': key});

  Future<Map<String, dynamic>> reidRemoved() => get('/api/reid/removed');

  Uri reidPhotoUri(String key, String name, {bool thumbnail = false}) =>
      _uri('/api/reid/photo', {
        'key': key,
        'name': name,
        if (thumbnail) 'thumb': '1',
      });

  Uri reidRemovedPhotoUri(
    Map<String, dynamic> item, {
    bool thumbnail = false,
  }) => _uri('/api/reid/removed_photo', {
    'reason': '${item['reason']}',
    'analysis': '${item['analysis']}',
    'car': '${item['car']}',
    'name': '${item['name']}',
    if (thumbnail) 'thumb': '1',
  });

  Future<Map<String, dynamic>> reidMove(
    List<Map<String, String>> photos, {
    String? to,
  }) => post('/api/reid/move', {'photos': photos, 'to': to});

  Future<Map<String, dynamic>> reidMerge(List<String> cars, String into) =>
      post('/api/reid/merge', {'cars': cars, 'into': into});

  Future<Map<String, dynamic>> reidRemove(
    List<Map<String, String>> photos,
    String reason,
  ) => post('/api/reid/remove', {'photos': photos, 'reason': reason});

  Future<Map<String, dynamic>> reidRemoveCars(
    List<String> cars,
    String reason,
  ) => post('/api/reid/remove_cars', {'cars': cars, 'reason': reason});

  Future<Map<String, dynamic>> reidRestore(
    List<Map<String, dynamic>> items,
  ) => post('/api/reid/restore', {'items': items});

  Future<Map<String, dynamic>> reidDismiss(String a, String b) =>
      post('/api/reid/dismiss', {'a': a, 'b': b});

  Future<Map<String, dynamic>> reidUndo() => post('/api/reid/undo', {});

  Future<Map<String, dynamic>> reidScan() => post('/api/reid/scan', {});

  Future<Map<String, dynamic>> reidJob(String id) =>
      get('/api/reid/job', {'id': id});

  void close() => _client.close();

  static List<Map<String, dynamic>> maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
