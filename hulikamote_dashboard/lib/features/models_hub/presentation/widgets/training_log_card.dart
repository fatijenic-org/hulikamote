import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hulikamote_dashboard/core/constants/api_constants.dart';
import 'package:hulikamote_dashboard/core/utils/visible_poller.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';

import '../hub_format.dart';

/// The newest training log of one model, under the training bar: however the training was started (the Train panel,
/// Continue, or the terminal Training Lab). Closed it costs the backend one small read when the page opens; open and
/// training it follows the log every few seconds, only while the page is on screen. Shows nothing when the model has
/// never been trained.
class TrainingLogCard extends StatefulWidget {
  const TrainingLogCard({super.key, required this.modelKey, this.client, this.openSignal = 0});

  final String modelKey;

  /// Injected by tests.
  final http.Client? client;

  /// Changing it opens the log (the page raises it after Continue, so the log is where the eye already is).
  final int openSignal;

  @override
  State<TrainingLogCard> createState() => _TrainingLogCardState();
}

class _TrainingLogCardState extends State<TrainingLogCard> {
  late final http.Client _client = widget.client ?? http.Client();
  bool _open = false, _training = false, _loaded = false;
  String _logs = '';
  String? _file, _error;
  double? _updated;
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 3), onTick: _load, initiallyActive: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context);
  }

  @override
  void didUpdateWidget(TrainingLogCard old) {
    super.didUpdateWidget(old);
    if (old.openSignal != widget.openSignal) _setOpen(true);
  }

  @override
  void dispose() {
    _poller.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _setOpen(bool open) {
    setState(() => _open = open);
    _poller.active = _open && _training;
    if (open) _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client.get(Uri.parse('${ApiConstants.baseUrl}/api/train/log/model/${widget.modelKey}'));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _file = j['file'] as String?;
        _logs = j['logs'] as String? ?? '';
        _training = j['training'] == true;
        _updated = (j['updated'] as num?)?.toDouble();
        _error = null;
        _loaded = true;
      });
      _poller.active = _open && _training;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_file == null && !_training)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s16),
      child: Container(
        decoration: BoxDecoration(
          color: Fx.panel(context),
          borderRadius: BorderRadius.circular(Fx.radius),
          border: Border.all(color: Fx.border(context)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(Fx.radius),
            onTap: () => _setOpen(!_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
              child: Row(children: [
                Icon(Icons.article_outlined, size: 20, color: Fx.muted(context)),
                const SizedBox(width: Fx.s12),
                Text('Training log', style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: Fx.s12),
                if (_training) const StatusPill(label: 'Training now', color: Fx.accent, dense: true),
                if (!_training && _updated != null)
                  Text('last written ${fmtDate(_updated)}', style: Fx.caption(context)),
                const Spacer(),
                Icon(_open ? Icons.expand_less : Icons.expand_more, color: Fx.muted(context)),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(Fx.s16, 0, Fx.s16, Fx.s16),
              child: Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(Fx.s12),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(Fx.radiusSm)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    _error != null ? 'Could not read the log: $_error' : (_logs.isEmpty ? 'The log is empty so far.' : _logs),
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
