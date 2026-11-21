import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import 'redetect_dialog.dart';

/// "Replay a saved run": the runs saved in the chosen folder (a run is one folder: pictures, boxes and its tickets). Pick one and the Live
/// Monitor plays it in order, with no backend work; its tickets show as they happened and everything done on them is saved back into
/// the run folder. Pops {run} when one was opened, else null.
/// With [forContinue] the list is the monitorings that were saved with "Save and pause", and pressing Continue brings the monitoring back
/// (setup, source, tickets) instead of replaying it: it pops {run, pos_s, source_name, tickets}.
class ReplayDialog extends StatefulWidget {
  const ReplayDialog({super.key, required this.api, this.forContinue = false});

  final CameraApi api;
  final bool forContinue;

  static Future<Map<String, dynamic>?> show(BuildContext context, CameraApi api, {bool forContinue = false}) =>
      showDialog<Map<String, dynamic>>(context: context, builder: (_) => ReplayDialog(api: api, forContinue: forContinue));

  @override
  State<ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<ReplayDialog> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _runs = const [];
  List<String> _roots = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final state = await widget.api.replayRuns();
      if (!mounted) return;
      setState(() {
        _runs = [
          for (final r in (state['runs'] as List? ?? const []))
            if (!widget.forContinue || (r as Map)['session'] != null) Map<String, dynamic>.from(r as Map)
        ];
        _roots = [for (final r in (state['roots'] as List? ?? const [])) '$r'];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Could not read the saved runs: ${_clean(e)}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Map<String, dynamic> run) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (widget.forContinue) {
        final got = await widget.api.continueSession('${run['id']}');
        if (mounted) Navigator.of(context).pop({'run': '${run['id']}', ...got});
        return;
      }
      await widget.api.openReplay('${run['id']}');
      if (mounted) Navigator.of(context).pop({'run': '${run['id']}'});
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _clean(e);
        });
      }
    }
  }

  Future<void> _adopt(Map<String, dynamic> run) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final got = await widget.api.adoptReplayTickets('${run['id']}');
      await _load();
      if (mounted) setState(() => _message = 'Saved ${got['tickets']} tickets from the Live Monitor into that run.');
    } catch (e) {
      if (mounted) setState(() => _message = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clock(double s) => '${s ~/ 60}:${(s.round() % 60).toString().padLeft(2, '0')}';

  String _when(Object? iso) {
    final text = '${iso ?? ''}';
    return text.length >= 16 ? text.substring(0, 16).replaceFirst('T', '  ') : text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.forContinue ? 'Continue a saved monitoring' : 'Replay a saved run'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_roots.isEmpty ? 'No folder for saved runs.' : 'Saved runs in: ${_roots.join('  ·  ')}', style: Fx.caption(context)),
                  const SizedBox(height: Fx.s8),
                  if (_runs.isEmpty)
                    Text(widget.forContinue
                        ? 'No saved monitoring found. Turn on "Save this run" in the last live setup step, start monitoring, then press "Save and pause".'
                        : 'No saved run found. Turn on "Save this run" in the last live setup step and run the Live Monitor once.'),
                  for (final run in _runs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Fx.s8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_when(run['started']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              [
                                if (run['session'] != null)
                                  '${widget.forContinue ? 'paused at' : 'replays, then the monitoring goes on at'} ${_clock((run['session']['pos_s'] as num?)?.toDouble() ?? 0)}',
                                if (run['pictures'] != null) '${run['pictures']} pictures',
                                run['tickets'] == null ? 'no tickets saved yet' : '${run['tickets']} tickets',
                                if (run['source'] != null) '${run['source']}'.split(RegExp(r'[\\/]')).last,
                              ].join('  ·  '),
                              style: Fx.caption(context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        if (run['tickets'] == null && !widget.forContinue)
                          TextButton(
                            key: ValueKey('replay-adopt-${run['id']}'),
                            onPressed: _busy ? null : () => _adopt(run),
                            child: const Text('Keep the live tickets here'),
                          ),
                        if (!widget.forContinue)
                          IconButton(
                            key: ValueKey('replay-redetect-${run['id']}'),
                            tooltip: 'Re-detect a part of this run',
                            onPressed: _busy ? null : () => showDialog<void>(context: context, builder: (_) => RedetectDialog(api: widget.api, run: '${run['id']}')),
                            icon: const Icon(Icons.manage_search, size: 20),
                          ),
                        const SizedBox(width: Fx.s8),
                        FilledButton.icon(
                          key: ValueKey('replay-open-${run['id']}'),
                          onPressed: _busy ? null : () => _open(run),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(widget.forContinue ? 'Continue' : 'Replay'),
                        ),
                      ]),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: Fx.s8),
                    Text(_message!, style: Fx.caption(context)),
                  ],
                ]),
              ),
      ),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
