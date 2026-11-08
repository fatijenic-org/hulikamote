import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/constants/api_constants.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/core/utils/visible_poller.dart';

/// Pause / Continue for a YOLO model's training, whoever started it (Studio or the terminal
/// Training Lab). Pause stops the training to free the GPU; Continue resumes from the last
/// finished epoch. Polls `/api/train/state/{model}` every few seconds, only while it is on screen.
class TrainingStateBar extends StatefulWidget {
  final String modelKey;

  /// Called with the new task id after Continue, so the screen can show the run's log.
  final void Function(String taskId) onResumed;

  const TrainingStateBar({super.key, required this.modelKey, required this.onResumed});

  @override
  State<TrainingStateBar> createState() => _TrainingStateBarState();
}

class _TrainingStateBarState extends State<TrainingStateBar> {
  Map<String, dynamic>? _state;
  bool _busy = false;

  // Asks the backend every few seconds, but only while this page is shown.
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 5), onTick: _load);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);
  }

  @override
  void didUpdateWidget(TrainingStateBar old) {
    super.didUpdateWidget(old);
    if (old.modelKey != widget.modelKey) {
      setState(() => _state = null);
      _load();
    }
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('${ApiConstants.baseUrl}/api/train/state/${widget.modelKey}'));
      if (res.statusCode == 200 && mounted) setState(() => _state = jsonDecode(res.body));
    } catch (_) {}
  }

  Future<void> _pause() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pause training?'),
        content: const Text('This stops the training and frees the GPU. Every finished epoch is kept; '
            'Continue resumes from the last one (the epoch in progress restarts).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pause')),
        ],
      ),
    );
    if (ok == true) await _post('pause');
  }

  Future<void> _post(String action) async {
    setState(() => _busy = true);
    try {
      final res = await http.post(Uri.parse('${ApiConstants.baseUrl}/api/train/$action/${widget.modelKey}'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) throw body['detail'] ?? 'HTTP ${res.statusCode}';
      if (mounted) AppToast.show(context, body['detail']?.toString() ?? 'Done.');
      if (action == 'resume' && body['task_id'] != null) widget.onResumed(body['task_id']);
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) return const SizedBox.shrink();
    final training = s['training'] == true;
    final resumable = s['resumable'] == true;
    if (!training && !resumable) return const SizedBox.shrink(); // idle: nothing to pause or continue

    final done = (s['epochs_done'] as num?)?.toInt() ?? 0;
    final total = (s['epochs_total'] as num?)?.toInt() ?? 0;
    final color = training ? Colors.blueAccent : Colors.orange;
    return Card(
      color: color.withAlpha(25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(training ? Icons.play_circle : Icons.pause_circle, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(training ? 'Training now' : 'Paused',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Text('Run ${s['run']} · epoch $done of $total finished',
                  style: const TextStyle(color: Colors.grey)),
              if (total > 0) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: done / total, color: color, minHeight: 6,
                    borderRadius: BorderRadius.circular(3)),
              ],
            ]),
          ),
          const SizedBox(width: 16),
          if (training)
            FilledButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _busy ? null : _pause,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continue'),
              onPressed: _busy ? null : () => _post('resume'),
            ),
        ]),
      ),
    );
  }
}
