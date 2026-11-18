import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/road_detect.dart';
import 'road_zone_editor.dart';

/// "Detect road": the frame that was frozen when the button was pressed, shown large, and every step the road finder takes swept
/// over it from left to right, one at a time, until the crosswalk and the lines it found are drawn. The pictures are the finder's
/// own (see engine/road_lines.py WALKTHROUGH), so what is shown is what was really done, as each step finishes.
///
/// After the last step: Apply (the crosswalk becomes the Pedestrian lane rule of the live monitor) or Discard.
class RoadDetectView extends StatefulWidget {
  const RoadDetectView({
    super.key,
    required this.api,
    required this.onClose,
    this.reserveTopRight,
    this.onEditingChanged,
    this.scan = false,
    this.onFound,
    this.pollEvery = const Duration(milliseconds: 600),
    this.sweepTime = const Duration(milliseconds: 1500),
    this.dwell = const Duration(milliseconds: 700),
  });

  final CameraApi api;

  /// The setup's road scan (started with [CameraApi.startRoadScan]) instead of the Live Monitor's "Detect road". The button then reads
  /// "Use these" and hands what was found to [onFound] (in the picture's pixels, with the picture's size) instead of applying it.
  final bool scan;
  final void Function(List<RoadArea> areas, Size size)? onFound;

  /// The corner the live video takes (the screen draws it there): the header leaves that room free.
  final Size? reserveTopRight;

  /// Told when the operator starts or stops correcting. While correcting, the picture gets the whole page (no step header, no room kept
  /// for the live video): the screen hides the small live window then.
  final ValueChanged<bool>? onEditingChanged;

  /// Called when the walkthrough is over: [applied] says whether the result was applied (false: discarded or failed).
  final void Function({required bool applied}) onClose;
  final Duration pollEvery;
  final Duration sweepTime;
  final Duration dwell; // how long a finished step stays before the next sweep starts

  @override
  State<RoadDetectView> createState() => _RoadDetectViewState();
}

class _RoadDetectViewState extends State<RoadDetectView> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  Timer? _poller;
  RoadDetectStatus? _status;
  Uint8List? _frame; // the frozen picture
  Uint8List? _base; // replaces the frame once the traffic has been taken away
  Uint8List? _layer; // the last finished step's picture, kept on screen
  Uint8List? _incoming; // the picture being swept in now
  bool _sweeping = false;
  bool _running = false;
  bool _busy = false;
  String? _error;
  List<RoadArea> _draft = const []; // what the scan found
  List<RoadArea> _areas = const []; // what will be applied (the draft, or the operator's corrections)
  bool _loadedAreas = false;
  bool _editing = false;
  bool _edited = false;
  bool _counterflow = false; // also make the incoming / outgoing sides of the road Counterflow zones (traffic against the arrow is flagged)
  String? _current;
  final _queue = <String>[];
  final _queued = <String>{};
  final _swept = <String>{};

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: widget.sweepTime); // made now, not on first use: dispose may come before any sweep
    _tick();
    _poller = Timer.periodic(widget.pollEvery, (_) => _tick());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final status = await widget.api.roadDetectStatus(scan: widget.scan);
      if (!mounted) return;
      if (_frame == null && status.state != 'none') {
        _frame = await widget.api.roadDetectFrame(scan: widget.scan);
        if (!mounted) return;
      }
      setState(() {
        _status = status;
        if (status.state == 'done' && !_loadedAreas) {
          _loadedAreas = true;
          _draft = _areas = status.zones;
        }
      });
      for (final step in status.steps) {
        if (step.state == 'done' && _queued.add(step.id)) _queue.add(step.id);
      }
      _drain();
      if (status.finished && _queue.isEmpty && !_running) _poller?.cancel();
    } catch (_) {
      // the next tick tries again
    }
  }

  /// Plays the finished steps one after the other: fetch the step's picture, sweep it in, keep it, pause, next.
  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && mounted) {
        final id = _queue.removeAt(0);
        final step = _status!.steps.firstWhere((s) => s.id == id);
        final bytes = step.hasOverlay ? await widget.api.roadDetectStep(id, scan: widget.scan) : null;
        if (!mounted) return;
        setState(() {
          _current = id;
          _incoming = bytes;
          _sweeping = true;
        });
        await _sweep.forward(from: 0);
        if (!mounted) return;
        setState(() {
          if (id == 'empty' && bytes != null) {
            _base = bytes; // the traffic is gone: everything after this is drawn on the empty road
            _layer = null;
          } else if (bytes != null) {
            _layer = bytes;
          }
          _incoming = null;
          _sweeping = false;
          _swept.add(id);
        });
        await Future<void>.delayed(widget.dwell);
      }
    } catch (_) {
      // disposed while a sweep was running
    } finally {
      _running = false;
      if (mounted) {
        setState(() {});
        if (_status?.finished == true && _queue.isEmpty) _poller?.cancel();
      }
    }
  }

  Future<void> _apply() async {
    if (widget.scan) {
      // the setup's scan: the markings go to the setup's Road step, nothing is saved for the camera here
      final size = _status != null && _status!.size.length == 2 ? Size(_status!.size[0].toDouble(), _status!.size[1].toDouble()) : const Size(1280, 720);
      widget.onFound?.call(_areas, size);
      widget.onClose(applied: true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_edited) {
        final fixed = await widget.api.correctRoadDetect(_areas);
        if (!mounted) return;
        if (fixed['ok'] != true) {
          setState(() {
            _busy = false;
            _error = (fixed['reason'] ?? 'Could not save the corrections') as String;
          });
          return;
        }
      }
      final result = await widget.api.applyRoadDetect(counterflow: _counterflow && _hasDirections);
      if (!mounted) return;
      if (result['ok'] == true) {
        widget.onClose(applied: true);
      } else {
        setState(() {
          _busy = false;
          _error = (result['reason'] ?? 'Could not apply') as String;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _discard() async {
    setState(() => _busy = true);
    try {
      await widget.api.discardRoadDetect(scan: widget.scan);
    } catch (_) {
      // closing is what matters
    }
    if (mounted) widget.onClose(applied: false);
  }

  bool get _playedAll => _queue.isEmpty && !_running;

  /// Some road area has a direction (incoming / outgoing), so there is something to mark and to use for Counterflow.
  bool get _hasDirections => _areas.any((a) => a.kind == 'road' && a.flow != null);

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Container(
      decoration: BoxDecoration(
        color: Fx.panel(context),
        borderRadius: BorderRadius.circular(Fx.radius),
        border: Border.all(color: Fx.border(context)),
      ),
      padding: const EdgeInsets.all(Fx.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_editing) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _stepChips(status),
                  const SizedBox(height: Fx.s8),
                  _caption(status),
                ]),
              ),
              if (widget.reserveTopRight != null)
                SizedBox.fromSize(size: Size(widget.reserveTopRight!.width + Fx.s16, widget.reserveTopRight!.height)),
            ]),
            const SizedBox(height: Fx.s12),
          ],
          Expanded(child: _editing ? _editor(status) : _picture(status)),
          const SizedBox(height: Fx.s12),
          _footer(status),
        ],
      ),
    );
  }

  // ── the strip of steps ──
  Widget _stepChips(RoadDetectStatus? status) {
    if (status == null || status.steps.isEmpty) return const SizedBox(height: 28);
    return Wrap(
      spacing: Fx.s8,
      runSpacing: Fx.s8,
      children: [
        for (final (i, step) in status.steps.indexed)
          _StepChip(
            key: ValueKey('road-step-${step.id}'),
            index: i + 1,
            step: step,
            sweeping: _sweeping && _current == step.id,
            swept: _swept.contains(step.id),
          ),
      ],
    );
  }

  Widget _caption(RoadDetectStatus? status) {
    final steps = status?.steps ?? const <RoadStep>[];
    final current = steps.where((s) => s.id == _current).firstOrNull;
    String text;
    if (status == null || status.state == 'none') {
      text = 'Capturing the frame...';
    } else if (status.state == 'collecting') {
      text = widget.scan
          ? 'Taking ${status.needS.round()} seconds of the video (${status.progressS.round()}/${status.needS.round()} s). The road is found from how vehicles move.'
          : 'Watching the traffic ${status.progressS.round()}/${status.needS.round()} s. The road is read from the last '
              '${status.needS.round()} seconds, because it is found from how vehicles move.';
    } else if (current != null && (_sweeping || !_playedAll)) {
      text = '${steps.indexOf(current) + 1}/${steps.length}  ${current.title}: ${current.about}';
    } else if (status.state == 'analysing') {
      text = 'Reading the road...';
    } else {
      text = '';
    }
    return SizedBox(
      height: 40,
      child: Text(text, key: const ValueKey('road-caption'), style: Fx.body(context), maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  // ── correcting the draft ──
  Widget _editor(RoadDetectStatus? status) {
    final size = status != null && status.size.length == 2 ? Size(status.size[0].toDouble(), status.size[1].toDouble()) : const Size(1280, 720);
    return RoadZoneEditor(
      frame: _base ?? _frame,
      size: size,
      areas: _areas,
      onChanged: (areas) => setState(() {
        _areas = areas;
        _edited = true;
      }),
      onReset: () => setState(() {
        _areas = _draft;
        _edited = false;
      }),
    );
  }

  // ── the frozen frame with the sweep over it ──
  Widget _picture(RoadDetectStatus? status) {
    final shown = _base ?? _frame;
    return Center(
      child: AspectRatio(
        aspectRatio: status?.aspect ?? 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Fx.radiusSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (shown != null) Image.memory(shown, fit: BoxFit.fill, gaplessPlayback: true),
              if (_layer != null) Image.memory(_layer!, fit: BoxFit.fill, gaplessPlayback: true),
              if (status?.state == 'collecting')
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    key: const ValueKey('road-collect-progress'),
                    value: status!.needS > 0 ? (status.progressS / status.needS).clamp(0.0, 1.0) : null,
                    minHeight: 4,
                  ),
                ),
              if (_sweeping) _sweepLayer(),
            ],
          ),
        ),
      ),
    );
  }

  /// The wipe: the step's picture is revealed up to a bright edge that travels from left to right, with a soft trail behind it.
  Widget _sweepLayer() {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_sweep.value);
        return LayoutBuilder(
          builder: (context, box) {
            final x = t * box.maxWidth;
            return Stack(
              children: [
                if (_incoming != null)
                  ClipRect(
                    clipper: _LeftOf(x),
                    child: Image.memory(_incoming!, fit: BoxFit.fill, width: box.maxWidth, height: box.maxHeight, gaplessPlayback: true),
                  ),
                Positioned(
                  left: x - 140,
                  top: 0,
                  bottom: 0,
                  width: 140,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.cyanAccent.withValues(alpha: 0), Colors.cyanAccent.withValues(alpha: 0.28)]),
                    ),
                  ),
                ),
                Positioned(
                  left: x - 1.5,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.9), blurRadius: 14, spreadRadius: 3)],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── result and buttons ──
  Widget _footer(RoadDetectStatus? status) {
    if (status == null) return const SizedBox(height: 40);
    if (status.state == 'failed') {
      return Row(children: [
        const Icon(Icons.error_outline, color: Fx.warning, size: 20),
        const SizedBox(width: Fx.s8),
        Expanded(child: Text(status.reason ?? 'The road could not be read.', key: const ValueKey('road-failed'), style: Fx.body(context))),
        const SizedBox(width: Fx.s12),
        OutlinedButton(onPressed: _busy ? null : _discard, child: const Text('Close')),
      ]);
    }
    if (status.state == 'done' && _playedAll) {
      final crosswalks = _areas.where((a) => a.kind == 'crosswalk').length;
      final others = _areas.where((a) => a.kind == 'road' || a.kind == 'sidewalk').length;
      final usable = widget.scan ? _areas.isNotEmpty : (status.rules.isNotEmpty || _areas.isNotEmpty);
      final directions = roadDirectionsText(_areas);
      final lines = <String>[
        if (widget.scan) ...[
          if (_areas.isNotEmpty) 'Found: ${[if (status.foundText.isNotEmpty) status.foundText, if (others > 0) '$others road or sidewalk area${others == 1 ? '' : 's'}'].join(', ')}.' else 'No clear crosswalk or line was found. Mark the road by hand.',
          if (directions.isNotEmpty) directions,
          'These are proposals. After "Use these" you can move, delete and add markings, and set the direction and type of each.',
        ] else if (_editing)
          'Drag a point to move it. Tap an edge to add a point. Right-click a point to remove it. Apply saves your version for this camera.'
        else ...[
          if (status.foundText.isNotEmpty || _areas.isNotEmpty) 'Found: ${[if (status.foundText.isNotEmpty) status.foundText, if (others > 0) '$others road or sidewalk area${others == 1 ? '' : 's'}'].join(', ')}.' else 'No clear crosswalk or line was found.',
          if (directions.isNotEmpty) directions,
          if (crosswalks > 0) 'Apply makes the crosswalk the Pedestrian lane rule of the live monitor.',
          if (others > 0) 'Road and sidewalk are a draft: press Correct to fix them. Saved for this camera.',
          if (status.hints.isNotEmpty) 'Lines are only hints: they are shown, not used as rules. In Correct, switch a solid line on to use it.',
        ],
        ?_error,
      ];
      return Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(lines.join(' '), key: const ValueKey('road-result'), maxLines: 3, overflow: TextOverflow.ellipsis, style: Fx.body(context)),
            if (_hasDirections && !widget.scan)
              Tooltip(
                message: 'Traffic that goes against the arrow of its side of the road is flagged as Counterflow. Check the arrows in Correct first.',
                child: InkWell(
                  onTap: _busy ? null : () => setState(() => _counterflow = !_counterflow),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                      key: const ValueKey('road-counterflow'),
                      visualDensity: VisualDensity.compact,
                      value: _counterflow,
                      onChanged: _busy ? null : (v) => setState(() => _counterflow = v ?? false),
                    ),
                    Flexible(child: Text('Use for Counterflow', maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.caption(context))),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(width: Fx.s12),
        if (!widget.scan) ...[
          OutlinedButton.icon(
            key: const ValueKey('road-correct'),
            onPressed: _busy
                ? null
                : () {
                    setState(() => _editing = !_editing);
                    widget.onEditingChanged?.call(_editing);
                  },
            icon: Icon(_editing ? Icons.visibility_outlined : Icons.edit_outlined),
            label: Text(_editing ? 'Done correcting' : 'Correct'),
          ),
          const SizedBox(width: Fx.s8),
        ],
        OutlinedButton(key: const ValueKey('road-discard'), onPressed: _busy ? null : _discard, child: const Text('Discard')),
        const SizedBox(width: Fx.s8),
        FilledButton.icon(
          key: const ValueKey('road-apply'),
          onPressed: (_busy || !usable) ? null : _apply,
          icon: const Icon(Icons.check),
          label: Text(widget.scan ? 'Use these' : 'Apply'),
        ),
      ]);
    }
    return Row(children: [
      const Spacer(),
      TextButton(key: const ValueKey('road-cancel'), onPressed: _busy ? null : _discard, child: const Text('Cancel')),
    ]);
  }
}

/// Reveals everything left of [x].
class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.x);
  final double x;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, x.clamp(0, size.width), size.height);

  @override
  bool shouldReclip(covariant _LeftOf old) => old.x != x;
}

class _StepChip extends StatelessWidget {
  const _StepChip({super.key, required this.index, required this.step, required this.sweeping, required this.swept});

  final int index;
  final RoadStep step;
  final bool sweeping;
  final bool swept;

  @override
  Widget build(BuildContext context) {
    final working = !swept && step.state == 'running';
    final Widget leading = swept
        ? const Icon(Icons.check_circle, size: 14, color: Fx.success)
        : working
        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
        : step.state == 'skipped'
        ? const Icon(Icons.remove_circle_outline, size: 14, color: Colors.grey)
        : Icon(step.state == 'done' ? Icons.hourglass_empty : Icons.circle_outlined, size: 14, color: Colors.grey);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: Fx.s8, vertical: 4),
      decoration: BoxDecoration(
        color: sweeping ? Colors.cyanAccent.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: sweeping ? Colors.cyanAccent : Fx.border(context)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading,
        const SizedBox(width: 6),
        Text('$index  ${step.title}', style: Fx.caption(context).copyWith(color: swept || sweeping ? null : Colors.grey)),
      ]),
    );
  }
}
