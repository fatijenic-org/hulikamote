import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../demerit/data/demerit_api.dart';
import '../../demerit/domain/demerit_models.dart';
import '../../registry/data/registry_api.dart';
import '../../violations/domain/models/violation.dart';

/// The numbers on the Overview page. A number that could not be loaded is null (shown as a dash), never a made-up
/// zero, and [problems] says why in plain words, one sentence per source that failed.
class OverviewData {
  const OverviewData({
    this.toReview,
    this.confirmed,
    this.plates,
    this.points,
    this.motorists,
    this.recent = const [],
    this.problems = const [],
  });

  final int? toReview;
  final int? confirmed;
  final int? plates;
  final int? points;
  final int? motorists;
  final List<Violation> recent;
  final List<String> problems;

  bool get hasProblems => problems.isNotEmpty;
}

/// Reads the four things an officer wants at a glance from the backend. Each one is asked on its own, so one that
/// fails does not hide the others.
class OverviewApi {
  OverviewApi({http.Client? client, this.baseUrl = ApiConstants.baseUrl, DemeritApi? demerit, RegistryApi? registry})
      : _client = client ?? http.Client(),
        _demerit = demerit ?? DemeritApi(baseUrl: baseUrl),
        _registry = registry ?? RegistryApi(baseUrl: baseUrl);

  final http.Client _client;
  final String baseUrl;
  final DemeritApi _demerit;
  final RegistryApi _registry;

  static const _timeout = Duration(seconds: 8);

  Future<OverviewData> load() async {
    final results = await Future.wait([
      _try('the Inbox', _pending),
      _try('the confirmed violations', _confirmed),
      _try('the demerit points', _demerit.standings),
      _try('the motorists', _registry.motorists),
    ]);
    final pending = results[0];
    final confirmed = results[1];
    final standings = results[2];
    final motorists = results[3];
    final page = confirmed.value as ViolationPage?;
    final entries = standings.value as List<DemeritEntry>?;
    return OverviewData(
      toReview: pending.value as int?,
      confirmed: page?.total,
      recent: page?.items ?? const [],
      plates: entries?.length,
      points: entries?.fold<int>(0, (sum, e) => sum + e.points),
      motorists: (motorists.value as List?)?.length,
      problems: [for (final r in results) ?r.problem],
    );
  }

  Future<int> _pending() async {
    final r = await _client.get(Uri.parse('$baseUrl/violations/sessions')).timeout(_timeout);
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    final body = jsonDecode(r.body) as Map;
    var count = 0;
    for (final source in body.values) {
      if (source is Map) {
        for (final tickets in source.values) {
          if (tickets is List) count += tickets.length;
        }
      }
    }
    return count;
  }

  Future<ViolationPage> _confirmed() async {
    final r = await _client.get(Uri.parse('$baseUrl/violations?status=approved&page=1&size=5')).timeout(_timeout);
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
    return ViolationPage.fromJson(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
  }

  Future<_Part> _try(String what, Future<Object?> Function() read) async {
    try {
      return _Part(await read(), null);
    } catch (_) {
      return _Part(null, 'Could not load $what.');
    }
  }
}

class _Part {
  const _Part(this.value, this.problem);

  final Object? value;
  final String? problem;
}
