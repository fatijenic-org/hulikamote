import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/constants/api_constants.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/training_report_widget.dart';

/// Training history of ONE model (isolated from every other model).
/// Newest run first; open a run to see its settings, result, log and (for detectors) its curves.
class ModelHistoryPanel extends StatefulWidget {
  final String modelKey;
  final String kind;
  const ModelHistoryPanel({super.key, required this.modelKey, required this.kind});

  @override
  State<ModelHistoryPanel> createState() => _ModelHistoryPanelState();
}

class _ModelHistoryPanelState extends State<ModelHistoryPanel> {
  List<Map<String, dynamic>> _runs = [];
  bool _loading = true;
  String? _error;
  final Set<int> _showCurves = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/train/history/${widget.modelKey}'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      setState(() {
        _runs = (jsonDecode(res.body)['runs'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load history: $e';
        _loading = false;
      });
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _fmt(num? epochSeconds) {
    if (epochSeconds == null) return 'Unknown date';
    final d = DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).toInt());
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${_months[d.month - 1]} ${d.day}, ${d.year}  ${h.toString()}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _duration(Map<String, dynamic> r) {
    final a = r['started'], b = r['finished'];
    if (a is! num || b is! num) return '';
    final s = (b - a).round();
    return s >= 3600 ? '${s ~/ 3600}h ${(s % 3600) ~/ 60}m' : (s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s');
  }

  Map<String, dynamic> _sum(Map<String, dynamic> r) => (r['summary'] as Map?)?.cast<String, dynamic>() ?? {};

  /// A single score used to mark the best run: mAP50 for detectors, held-out accuracy for ReID.
  double? _score(Map<String, dynamic> r) {
    if (r['status'] != 'completed') return null;
    final s = _sum(r);
    return widget.kind == 'reid' ? (s['after'] as num?)?.toDouble() : (s['map50'] as num?)?.toDouble();
  }

  String _result(Map<String, dynamic> r) {
    if (r['status'] == 'failed') return 'Failed';
    final s = _sum(r);
    switch (widget.kind) {
      case 'reid':
        if (s['after'] == null) return 'Completed';
        final b = ((s['before'] as num) * 100).toStringAsFixed(1);
        final a = ((s['after'] as num) * 100).toStringAsFixed(1);
        return 'Right car found $b% -> $a%  -  ${s['deployed'] == true ? 'deployed' : 'not deployed'}';
      case 'yolo':
        if (s['map50'] == null) return 'Completed';
        return 'mAP50 ${(s['map50'] as num).toStringAsFixed(3)}  -  mAP50-95 ${((s['map50_95'] ?? 0) as num).toStringAsFixed(3)}';
      default:
        return 'Completed';
    }
  }

  Future<void> _showLog(String taskId) async {
    String text;
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/train/log/$taskId'));
      text = (jsonDecode(res.body)['logs'] as String?) ?? '';
      if (text.isEmpty) text = 'No log saved for this run.';
    } catch (e) {
      text = 'Could not load the log: $e';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training log'),
        content: SizedBox(
          width: 800,
          height: 480,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12)),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Column(children: [
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]);
    }
    if (_runs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No training runs yet for this model.', style: TextStyle(color: Colors.grey)),
            Text('Runs appear here after you train it.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
      );
    }

    double? bestScore;
    for (final r in _runs) {
      final s = _score(r);
      if (s != null && (bestScore == null || s > bestScore)) bestScore = s;
    }
    final completed = _runs.where((r) => r['status'] == 'completed').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, children: [
        Chip(avatar: const Icon(Icons.history, size: 16), label: Text('${_runs.length} run(s)')),
        Chip(avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green), label: Text('$completed completed')),
        if (bestScore != null)
          Chip(
            avatar: const Icon(Icons.emoji_events, size: 16, color: Colors.amber),
            label: Text(widget.kind == 'reid' ? 'Best: ${(bestScore * 100).toStringAsFixed(1)}%' : 'Best mAP50: ${bestScore.toStringAsFixed(3)}'),
          ),
        Chip(avatar: const Icon(Icons.schedule, size: 16), label: Text('Last: ${_fmt(_runs.first['finished'] as num?)}')),
      ]),
      const SizedBox(height: 12),
      for (var i = 0; i < _runs.length; i++) _runCard(i, _runs[i], bestScore),
    ]);
  }

  Widget _runCard(int i, Map<String, dynamic> r, double? bestScore) {
    final ok = r['status'] == 'completed';
    final isBest = ok && bestScore != null && _score(r) == bestScore;
    final cfg = (r['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final folder = _sum(r)['run_folder'] as String?;
    final dur = _duration(r);
    return Card(
      child: ExpansionTile(
        leading: Icon(ok ? Icons.check_circle : Icons.error, color: ok ? Colors.green : Colors.redAccent),
        title: Row(children: [
          Flexible(child: Text(_fmt(r['finished'] as num?), style: const TextStyle(fontWeight: FontWeight.bold))),
          if (isBest) ...[
            const SizedBox(width: 8),
            const Chip(label: Text('Best'), visualDensity: VisualDensity.compact, avatar: Icon(Icons.emoji_events, size: 14, color: Colors.amber)),
          ],
          if (r['legacy'] == true) ...[
            const SizedBox(width: 8),
            const Chip(label: Text('older run'), visualDensity: VisualDensity.compact),
          ],
        ]),
        subtitle: Text(_result(r) + (dur.isEmpty ? '' : '   -   took $dur')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cfg.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final e in cfg.entries) Chip(label: Text('${e.key}: ${e.value}'), visualDensity: VisualDensity.compact),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            if (r['task_id'] != null)
              OutlinedButton.icon(icon: const Icon(Icons.article), label: const Text('View log'), onPressed: () => _showLog(r['task_id'] as String)),
            if (widget.kind == 'yolo' && folder != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.show_chart),
                label: Text(_showCurves.contains(i) ? 'Hide training curves' : 'Show training curves'),
                onPressed: () => setState(() => _showCurves.contains(i) ? _showCurves.remove(i) : _showCurves.add(i)),
              ),
            ],
          ]),
          if (_showCurves.contains(i) && folder != null) ...[
            const SizedBox(height: 12),
            TrainingReportWidget(key: ValueKey('${widget.modelKey}-$folder'), modelName: widget.modelKey, run: folder),
          ],
        ],
      ),
    );
  }
}
