import 'dart:async';

import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';

/// The live switch: one chip per rule of the setup. Tapping a chip turns that rule on or off in the RUNNING backend: from the next picture on
/// it judges only the rules that are on and runs only the models they need, so the delay falls when a heavy rule is switched off. Each chip
/// shows what the rule costs per picture (the backend measures it); the detector and the trackers always run. A rule that is not in the
/// setup cannot be switched on here (it has no zones or settings): change the setup for that.
class LiveRulesBar extends StatefulWidget {
  const LiveRulesBar({super.key, required this.api, this.pollEvery = const Duration(seconds: 3)});

  final CameraApi api;
  final Duration pollEvery;

  @override
  State<LiveRulesBar> createState() => _LiveRulesBarState();
}

class _LiveRulesBarState extends State<LiveRulesBar> {
  Timer? _timer;
  bool _ready = false;
  List<String> _setup = const [];
  Set<String> _active = {};
  Map<String, double> _cost = {};
  Map<String, String> _needs = {};
  bool _stabOn = true;
  double _holdS = 0.8;
  double _keepConf = 0.25;
  int _ghosts = 0;
  final Set<String> _busy = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _take(Map<String, dynamic> s) {
    _ready = s['ready'] == true;
    _setup = [for (final k in (s['setup'] as List? ?? const [])) '$k'];
    _active = {for (final k in (s['active'] as List? ?? const [])) '$k'};
    _cost = {for (final e in ((s['cost_ms'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toDouble()};
    _needs = {for (final e in ((s['needs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
    final stab = s['stabilizer'];
    if (stab is Map) {
      _stabOn = stab['on'] != false;
      _holdS = (stab['hold_s'] as num?)?.toDouble() ?? _holdS;
      _keepConf = (stab['keep_conf'] as num?)?.toDouble() ?? _keepConf;
      _ghosts = (stab['ghost_boxes'] as num?)?.toInt() ?? 0;
    }
  }

  Future<void> _setStab({bool? on, double? holdS, double? keepConf}) async {
    setState(() {
      if (on != null) _stabOn = on;
      if (holdS != null) _holdS = holdS;
      if (keepConf != null) _keepConf = keepConf;
    });
    try {
      final s = await widget.api.setStabilizer(on: on, holdS: holdS, keepConf: keepConf);
      if (mounted) {
        setState(() {
          _stabOn = s['on'] != false;
          _holdS = (s['hold_s'] as num?)?.toDouble() ?? _holdS;
          _keepConf = (s['keep_conf'] as num?)?.toDouble() ?? _keepConf;
          _ghosts = (s['ghost_boxes'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _poll() async {
    if (_busy.isNotEmpty) return;
    try {
      final s = await widget.api.liveRules();
      if (mounted) setState(() => _take(s));
    } catch (_) {
      // the backend does not answer for a moment: the chips stay as they were
    }
  }

  Future<void> _toggle(String key) async {
    if (_busy.contains(key)) return;
    final next = {..._active};
    if (!next.remove(key)) next.add(key);
    setState(() {
      _busy.add(key);
      _message = null;
    });
    try {
      final s = await widget.api.setLiveRules([for (final k in _setup) if (next.contains(k)) k]);
      if (mounted) setState(() => _take(s));
    } catch (e) {
      if (mounted) setState(() => _message = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  String _ms(double v) => v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    if (!_ready || _setup.isEmpty) return const SizedBox.shrink();
    final total = _active.fold<double>(0, (sum, k) => sum + (_cost[k] ?? 0));
    return Container(
      key: const ValueKey('live-rules-bar'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Fx.s12, Fx.s8, Fx.s12, Fx.s8),
      decoration: BoxDecoration(color: Fx.panel(context), border: Border(top: BorderSide(color: Fx.border(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: Fx.s8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tooltip(
            message: 'Switch a rule off and the backend stops running it and its model: less work, less delay. The detector always runs.',
            child: Text('Rules on: ${_active.length} of ${_setup.length}  ·  about ${_ms(total)} ms per picture', style: Fx.label(context)),
          ),
          for (final k in _setup)
            Tooltip(
              message: _needs[k] == null ? ViolationCatalog.of(k).label : '${ViolationCatalog.of(k).label}: needs the ${_needs[k]}',
              child: FilterChip(
                key: ValueKey('rule-chip-$k'),
                visualDensity: VisualDensity.compact,
                avatar: _busy.contains(k)
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(ViolationCatalog.of(k).icon, size: 16, color: ViolationCatalog.of(k).color),
                label: Text('${ViolationCatalog.of(k).label}${_active.contains(k) && _cost[k] != null ? '  ·  ${_ms(_cost[k]!)} ms' : ''}'),
                selected: _active.contains(k),
                onSelected: _busy.contains(k) ? null : (_) => _toggle(k),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Tooltip(
              message: 'When the detector loses a vehicle for a moment, its box stays on the screen (fainter) for a short time, along the way the vehicle was going. '
                  'Only the screen: no ticket or photo is ever made from a kept box.',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(key: const ValueKey('stabilizer-switch'), value: _stabOn, onChanged: (v) => _setStab(on: v)),
                const Text('Keep lost boxes'),
              ]),
            ),
            if (_stabOn)
              DropdownButton<double>(
                key: const ValueKey('stabilizer-hold'),
                isDense: true,
                value: const [0.3, 0.5, 0.8, 1.0, 1.5, 2.0].contains(_holdS) ? _holdS : 0.8,
                items: [for (final v in const [0.3, 0.5, 0.8, 1.0, 1.5, 2.0]) DropdownMenuItem(value: v, child: Text('hold ${v.toStringAsFixed(1)} s'))],
                onChanged: (v) => v == null ? null : _setStab(holdS: v),
              ),
            if (_stabOn) Text('$_ghosts boxes kept so far', style: Fx.caption(context)),
            Tooltip(
              message: 'A vehicle that is tracked keeps its box while the detector still gives it this score or more (a new vehicle still needs the normal cutoff). '
                  'Lower = the box sticks harder, but a weak guess may stay. Off = every box needs the normal cutoff on every picture.',
              child: DropdownButton<double>(
                key: const ValueKey('keep-conf'),
                isDense: true,
                value: const [0.0, 0.35, 0.25, 0.18, 0.12].contains(_keepConf) ? _keepConf : 0.25,
                items: [
                  for (final v in const [0.0, 0.35, 0.25, 0.18, 0.12])
                    DropdownMenuItem(value: v, child: Text(v == 0 ? 'keep score: off' : 'keep score ${v.toStringAsFixed(2)}')),
                ],
                onChanged: (v) => v == null ? null : _setStab(keepConf: v),
              ),
            ),
          ]),
        ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_message!, style: Fx.caption(context))),
      ]),
    );
  }
}
