import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';

/// "Re-detect a part": run the detection again on a stretch of a saved run's video, with the rules you choose. It is a Forensic analysis of
/// that stretch with the setup the run was saved with: its result (evidence video with boxes, tickets, plates) is in the Forensic Library.
/// The live monitoring must be stopped (both use the same detector); the video file itself is never changed.
class RedetectDialog extends StatefulWidget {
  const RedetectDialog({super.key, required this.api, required this.run, this.pollEvery = const Duration(seconds: 2)});

  final CameraApi api;
  final String run; // the run's folder name
  final Duration pollEvery;

  @override
  State<RedetectDialog> createState() => _RedetectDialogState();
}

class _RedetectDialogState extends State<RedetectDialog> {
  final _start = TextEditingController(text: '0:00');
  final _end = TextEditingController(text: '1:00');
  bool _loading = true;
  bool _busy = false;
  bool _can = false;
  String? _message;
  double _duration = 0;
  String _source = '';
  List<String> _rules = const [];
  final Set<String> _on = {};
  String? _task;
  Timer? _timer;
  double _progress = 0;
  String _state = '';
  int _tickets = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  static String _say(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final info = await widget.api.replayInfo(widget.run);
      if (!mounted) return;
      setState(() {
        _duration = (info['duration'] as num?)?.toDouble() ?? 0;
        _source = '${info['source'] ?? ''}';
        _rules = [for (final r in (info['rules'] as List? ?? const [])) '$r'];
        _on.addAll(_rules);
        _can = info['can'] == true;
        _message = _can ? null : '${info['why'] ?? ''}';
        _end.text = _clock(_duration < 60 ? _duration : 60);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = _say(e);
          _loading = false;
        });
      }
    }
  }

  static String _clock(double s) {
    final t = s.round();
    final h = t ~/ 3600, m = (t % 3600) ~/ 60, sec = t % 60;
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  /// "130", "2:10" or "1:02:10" -> seconds (null when it is not a time).
  static double? _parse(String text) {
    final parts = text.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    var total = 0.0;
    for (final p in parts) {
      final v = double.tryParse(p.trim());
      if (v == null || v < 0) return null;
      total = total * 60 + v;
    }
    return total;
  }

  Future<void> _go() async {
    final a = _parse(_start.text), b = _parse(_end.text);
    if (a == null || b == null || b - a < 1) {
      setState(() => _message = 'Give the start and the end like 2:10 and 3:00 (the end after the start).');
      return;
    }
    if (_on.isEmpty) {
      setState(() => _message = 'Choose at least one rule.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final got = await widget.api.startRedetect(widget.run, a, b, [for (final r in _rules) if (_on.contains(r)) r]);
      if (!mounted) return;
      setState(() {
        _task = '${got['task_id']}';
        _state = 'processing';
      });
      _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    final id = _task;
    if (id == null) return;
    try {
      final s = await widget.api.forensicStatus(id);
      if (!mounted) return;
      setState(() {
        _state = '${s['status'] ?? 'processing'}';
        _progress = ((s['progress'] as num?)?.toDouble() ?? 0) / 100;
        _tickets = (s['ticket_count'] as num?)?.toInt() ?? 0;
        final m = '${s['message'] ?? ''}';
        if (m.isNotEmpty) _message = m;
        if (_state == 'failed') _message = 'It failed: ${s['error'] ?? 'unknown error'}';
      });
      if (_state != 'processing') _timer?.cancel();
    } catch (_) {
      // the backend does not answer for a moment: asked again
    }
  }

  Future<void> _cancel() async {
    final id = _task;
    if (id == null) return;
    try {
      await widget.api.stopForensic(id, cancel: true);
    } catch (e) {
      if (mounted) setState(() => _message = _say(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _task != null && _state == 'processing';
    final done = _task != null && _state == 'completed';
    return AlertDialog(
      title: const Text('Re-detect a part'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_source.isEmpty ? widget.run : _source}  ·  ${_clock(_duration)} saved', style: Fx.caption(context)),
                  const SizedBox(height: Fx.s12),
                  Row(children: [
                    Expanded(child: TextField(key: const ValueKey('redetect-start'), controller: _start, enabled: !running && !done, decoration: const InputDecoration(labelText: 'From (m:ss)', isDense: true))),
                    const SizedBox(width: Fx.s12),
                    Expanded(child: TextField(key: const ValueKey('redetect-end'), controller: _end, enabled: !running && !done, decoration: const InputDecoration(labelText: 'To (m:ss)', isDense: true))),
                  ]),
                  const SizedBox(height: Fx.s12),
                  Text('Rules to run again', style: Fx.label(context)),
                  Wrap(spacing: Fx.s8, runSpacing: 4, children: [
                    for (final r in _rules)
                      FilterChip(
                        key: ValueKey('redetect-rule-$r'),
                        visualDensity: VisualDensity.compact,
                        label: Text(ViolationCatalog.of(r).label),
                        selected: _on.contains(r),
                        onSelected: (running || done) ? null : (v) => setState(() => v ? _on.add(r) : _on.remove(r)),
                      ),
                  ]),
                  const SizedBox(height: Fx.s12),
                  Text(
                    'The part is analyzed again with the setup of this run. The result is a Forensic analysis (video with boxes, tickets, plates) in the '
                    'Forensic Library; your saved run and the video file are not changed. Stop the live monitoring first.',
                    style: Fx.caption(context),
                  ),
                  if (running) ...[
                    const SizedBox(height: Fx.s12),
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                    const SizedBox(height: 4),
                    Text('${(_progress * 100).round()} %  ·  $_tickets tickets so far', style: Fx.caption(context)),
                  ],
                  if (done) ...[
                    const SizedBox(height: Fx.s12),
                    Text('Done: $_tickets ticket${_tickets == 1 ? '' : 's'}. Open Forensic → Library to see the video with its boxes and the tickets.', style: Fx.body(context)),
                  ],
                  if (_message != null) ...[const SizedBox(height: Fx.s8), Text(_message!, style: Fx.caption(context))],
                ]),
              ),
      ),
      actions: [
        if (running) TextButton(key: const ValueKey('redetect-cancel'), onPressed: _cancel, child: const Text('Cancel the analysis')),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(running ? 'Hide' : 'Close')),
        if (!running && !done)
          FilledButton(key: const ValueKey('redetect-go'), onPressed: (_busy || !_can) ? null : _go, child: const Text('Re-detect')),
      ],
    );
  }
}
