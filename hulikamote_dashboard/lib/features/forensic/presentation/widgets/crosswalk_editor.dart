import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/crosswalk_overlay.dart';
import '../../domain/zone_geometry.dart';
import 'fx.dart';
import 'violation_params.dart';
import 'zone_editor.dart';

/// "Pedestrian lane": draw a zone as before, or place an overlay crosswalk on the picture to test the rule on a road that has none.
/// Both are crosswalk zones and can be mixed; this widget only chooses which one is being edited.
class PedestrianLaneEditor extends StatefulWidget {
  const PedestrianLaneEditor({super.key, required this.draft, required this.violationKey, required this.frame, this.api});

  final AnalysisDraft draft;
  final String violationKey;
  final ImageProvider frame;
  final ForensicApi? api;

  @override
  State<PedestrianLaneEditor> createState() => _PedestrianLaneEditorState();
}

class _PedestrianLaneEditorState extends State<PedestrianLaneEditor> {
  late bool _overlay = widget.draft.crosswalkCount(widget.violationKey) > 0 && widget.draft.zones(widget.violationKey).isEmpty;

  @override
  Widget build(BuildContext context) {
    final bar = Padding(
      padding: const EdgeInsets.only(bottom: Fx.s12),
      child: SegmentedButton<bool>(
        key: const ValueKey('pl-mode'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.crop_square, size: 18), label: Text('Draw a zone')),
          ButtonSegment(value: true, icon: Icon(Icons.view_week_outlined, size: 18), label: Text('Crosswalk overlay (test)')),
        ],
        selected: {_overlay},
        onSelectionChanged: (s) => setState(() => _overlay = s.first),
      ),
    );
    final body = _overlay
        ? CrosswalkOverlayEditor(key: ValueKey('cw-${widget.violationKey}'), draft: widget.draft, violationKey: widget.violationKey, frame: widget.frame)
        : ZoneEditor(key: ValueKey('zone-${widget.violationKey}'), draft: widget.draft, violationKey: widget.violationKey, frame: widget.frame, api: widget.api);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.hasBoundedHeight) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar, Expanded(child: body)]);
        }
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar, body]);
      },
    );
  }
}

/// What a drag on the canvas is doing to the selected crosswalk.
enum _Grab { none, move, resize, rotate, corner, side }

/// Places overlay crosswalks on the first frame of the video and sets how each one looks. Same ideas as the lane signs of
/// "Restricted lane": click to place, drag to move, drag the corner to resize, drag the knob to turn, right-click to remove.
class CrosswalkOverlayEditor extends StatefulWidget {
  const CrosswalkOverlayEditor({super.key, required this.draft, required this.violationKey, required this.frame});

  final AnalysisDraft draft;
  final String violationKey;
  final ImageProvider frame;

  @override
  State<CrosswalkOverlayEditor> createState() => _CrosswalkOverlayEditorState();
}

class _CrosswalkOverlayEditorState extends State<CrosswalkOverlayEditor> {
  bool _placing = false;
  int? _sel;
  _Grab _grab = _Grab.none;
  int _grip = 0; // which corner / side is held (corner and side grabs)
  Offset _last = Offset.zero; // where the pointer was at the last update (side grabs move by the difference)
  Offset _grabOffset = Offset.zero; // from the pointer to the crosswalk's centre when a move starts (0..1 canvas coordinates)
  double _aspect = 16 / 9;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get key => widget.violationKey;
  List<Map<String, dynamic>> get _items => widget.draft.crosswalks(key);
  bool get _realistic => (widget.draft.config(key)['crosswalks_realistic'] as bool?) ?? true;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(CrosswalkOverlayEditor old) {
    super.didUpdateWidget(old);
    if (old.frame != widget.frame) _resolveAspect();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    super.dispose();
  }

  void _resolveAspect() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = widget.frame.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (mounted && a.isFinite && a > 0.3 && a < 4) setState(() => _aspect = a);
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  // ── canvas input ──
  Offset _norm(Offset p, Size s) => Offset((p.dx / s.width).clamp(0.0, 1.0), (p.dy / s.height).clamp(0.0, 1.0));

  int? _at(Offset local, Size size) {
    final p = _norm(local, size);
    for (var i = _items.length - 1; i >= 0; i--) {
      if (CrosswalkOverlay.onBand(_items[i], p)) return i; // the one placed last wins where they overlap
    }
    return null;
  }

  _Grab _handleAt(Offset local, Size size) {
    final i = _sel;
    if (i == null || i >= _items.length) return _Grab.none;
    if (CrosswalkOverlay.isFree(_items[i])) {            // loose corners: each corner and each side has its own handle
      for (var k = 0; k < 4; k++) {
        if ((CrosswalkOverlay.cornerHandle(_items[i], k, size) - local).distance <= 16) {
          _grip = k;
          return _Grab.corner;
        }
      }
      for (var k = 0; k < 4; k++) {
        if ((CrosswalkOverlay.sideHandle(_items[i], k, size) - local).distance <= 14) {
          _grip = k;
          return _Grab.side;
        }
      }
      return _Grab.none;
    }
    if ((CrosswalkOverlay.rotateKnob(_items[i], size) - local).distance <= 16) return _Grab.rotate;
    if ((CrosswalkOverlay.resizeHandle(_items[i], size) - local).distance <= 16) return _Grab.resize;
    return _Grab.none;
  }

  void _place(Offset local, Size size) {
    _items.add(CrosswalkOverlay.make(_norm(local, size)));
    widget.draft.touch();
    setState(() => _sel = _items.length - 1); // the crosswalk just placed is the one to shape
  }

  void _remove(int i) {
    _items.removeAt(i);
    widget.draft.touch();
    setState(() {
      final s = _sel;
      if (s != null) _sel = s == i ? null : (s > i ? s - 1 : s);
    });
  }

  void _tap(Offset local, Size size) {
    if (_handleAt(local, size) != _Grab.none) return; // a tap on a handle is not a new crosswalk
    final hit = _at(local, size);
    if (hit != null) {
      setState(() => _sel = hit);
    } else if (_placing) {
      _place(local, size);
    }
  }

  void _panStart(Offset local, Size size) {
    final handle = _handleAt(local, size);
    if (handle != _Grab.none) {
      _grab = handle;
      _last = local;
      return;
    }
    final i = _at(local, size);
    if (i == null) {
      _grab = _Grab.none;
      return;
    }
    _grab = _Grab.move;
    _grabOffset = CrosswalkOverlay.centerOf(_items[i]) - _norm(local, size);
    setState(() => _sel = i);
  }

  void _panUpdate(Offset local, Size size) {
    final i = _sel;
    if (i == null || i >= _items.length) return;
    final c = _items[i];
    switch (_grab) {
      case _Grab.move:
        final n = _norm(local, size) + _grabOffset;
        c['x'] = n.dx.clamp(0.0, 1.0) * ZoneGeometry.refWidth;
        c['y'] = n.dy.clamp(0.0, 1.0) * ZoneGeometry.refHeight;
      case _Grab.resize:
        c['scale'] = CrosswalkOverlay.scaleFor(c, size, local);
      case _Grab.rotate:
        c['angle'] = CrosswalkOverlay.angleFor(c, size, local);
      case _Grab.corner:
        CrosswalkOverlay.moveCorner(c, _grip, size, local);
      case _Grab.side:
        CrosswalkOverlay.moveSide(c, _grip, size, local - _last);
        _last = local;
      case _Grab.none:
        return;
    }
    setState(() {});
  }

  void _panEnd() {
    if (_grab != _Grab.none) widget.draft.touch(); // a moved, sized or turned crosswalk is saved
    _grab = _Grab.none;
  }

  void _setLook(String field, num value) {
    final i = _sel;
    if (i == null || i >= _items.length) return;
    _items[i][field] = value;
    widget.draft.touch();
    setState(() {});
  }

  void _reset() {
    final i = _sel;
    if (i == null || i >= _items.length) return;
    final centre = Offset(CrosswalkOverlay.centerOf(_items[i]).dx, CrosswalkOverlay.centerOf(_items[i]).dy);
    _items[i]
      ..clear()
      ..addAll(CrosswalkOverlay.make(centre));
    widget.draft.touch();
    setState(() {});
  }

  void _clearAll() {
    _items.clear();
    widget.draft.touch();
    setState(() => _sel = null);
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final canvas = _canvasCard(context);
        final panel = _panel(context);
        if (box.maxWidth >= 780 && box.hasBoundedHeight) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Align(alignment: Alignment.topCenter, child: canvas)),
              const SizedBox(width: Fx.s16),
              SizedBox(width: 340, child: SingleChildScrollView(child: panel)),
            ],
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [canvas, const SizedBox(height: Fx.s16), panel]);
      },
    );
  }

  Widget _canvasCard(BuildContext context) {
    return LayoutBuilder(
      builder: (context, outer) {
        var w = outer.maxWidth;
        if (outer.hasBoundedHeight && w / _aspect > outer.maxHeight) w = outer.maxHeight * _aspect;
        return SizedBox(
          width: w,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Fx.radius),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _placing ? Fx.accent : Fx.border(context), width: 2),
                borderRadius: BorderRadius.circular(Fx.radius),
              ),
              child: AspectRatio(
                aspectRatio: _aspect,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.biggest;
                    return MouseRegion(
                      cursor: _placing ? SystemMouseCursors.precise : SystemMouseCursors.basic,
                      child: GestureDetector(
                        key: const ValueKey('cw-canvas'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: (d) => _tap(d.localPosition, size),
                        onSecondaryTapUp: (d) {
                          final i = _at(d.localPosition, size);
                          if (i != null) _remove(i);
                        },
                        onPanStart: (d) => _panStart(d.localPosition, size),
                        onPanUpdate: (d) => _panUpdate(d.localPosition, size),
                        onPanEnd: (_) => _panEnd(),
                        onPanCancel: _panEnd,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(image: widget.frame, fit: BoxFit.fill, gaplessPlayback: true),
                            CustomPaint(
                              painter: _CrosswalkPainter(
                                items: [for (final c in _items) Map<String, dynamic>.of(c)],
                                selected: _sel,
                                realistic: _realistic,
                              ),
                            ),
                            if (_items.isEmpty)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(Fx.radiusSm)),
                                  child: const Text(
                                    'Press “Place a crosswalk”, then click the road.\nIt is painted on the photos and the video of this test only.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panel(BuildContext context) {
    final i = _sel;
    final selected = i != null && i < _items.length ? _items[i] : null;
    final limit = ((widget.draft.config(key)['time_limit'] as num?) ?? 3).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxCard(
          key: const ValueKey('crosswalk-card'),
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.view_week_outlined, size: 18),
                const SizedBox(width: Fx.s8),
                Expanded(child: Text('Crosswalk overlay (temporary)', style: Fx.heading(context))),
              ]),
              const SizedBox(height: 4),
              Text(
                'For testing on a road with no crosswalk. A vehicle that stops on it for more than ${limit.toStringAsFixed(limit % 1 == 0 ? 0 : 1)} '
                'seconds is flagged. It is only drawn on the photos and the result video, never written into the video.',
                style: Fx.caption(context),
              ),
              const SizedBox(height: Fx.s12),
              FilledButton.icon(
                key: const ValueKey('cw-place'),
                onPressed: () => setState(() => _placing = !_placing),
                icon: Icon(_placing ? Icons.check : Icons.add_road, size: 18),
                label: Text(_placing ? 'Done placing' : 'Place a crosswalk'),
              ),
              if (_items.isNotEmpty) ...[
                const SizedBox(height: Fx.s12),
                for (var n = 0; n < _items.length; n++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: FxCard(
                      key: ValueKey('cw-item-$n'),
                      selected: _sel == n,
                      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s4),
                      onTap: () => setState(() => _sel = n),
                      child: Row(children: [
                        Expanded(child: Text('Crosswalk ${n + 1}  ·  ${CrosswalkOverlay.stripesOf(_items[n])} stripes', style: Fx.body(context))),
                        IconButton(
                          key: ValueKey('cw-remove-$n'),
                          tooltip: 'Remove',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _remove(n),
                        ),
                      ]),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Fx.s12),
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: selected == null
              ? Text('Select a crosswalk (click it) to set its size, angle and paint.', key: const ValueKey('cw-hint'), style: Fx.caption(context))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Crosswalk ${i! + 1}', style: Fx.heading(context)),
                    const SizedBox(height: Fx.s8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('cw-free'),
                        onPressed: () {
                          if (CrosswalkOverlay.isFree(selected)) {
                            CrosswalkOverlay.unfreeze(selected);
                          } else {
                            CrosswalkOverlay.freeze(selected);
                          }
                          widget.draft.touch();
                          setState(() {});
                        },
                        icon: Icon(CrosswalkOverlay.isFree(selected) ? Icons.crop_square : Icons.polyline, size: 18),
                        label: Text(CrosswalkOverlay.isFree(selected) ? 'Back to the simple shape' : 'Move the corners'),
                      ),
                    ),
                    const SizedBox(height: Fx.s8),
                    if (CrosswalkOverlay.isFree(selected))
                      Text('Drag a corner to reshape it. Drag the dot in the middle of a side to stretch the crosswalk that way. '
                          'Drag the crosswalk itself to move it.', key: const ValueKey('cw-free-hint'), style: Fx.caption(context))
                    else ...[
                      _slider('Size', 'scale', CrosswalkOverlay.scaleOf(selected), CrosswalkOverlay.minScale, CrosswalkOverlay.maxScale, (v) => '×${v.toStringAsFixed(1)}'),
                      _slider('Depth', 'depth', CrosswalkOverlay.depthOf(selected), CrosswalkOverlay.minDepth, CrosswalkOverlay.maxDepth, (v) => '×${v.toStringAsFixed(1)}'),
                      _slider('Rotate', 'angle', CrosswalkOverlay.angleOf(selected), -CrosswalkOverlay.maxAngle, CrosswalkOverlay.maxAngle, (v) => '${v.round()}°'),
                      _slider('Perspective', 'slant', CrosswalkOverlay.slantOf(selected), 0, CrosswalkOverlay.maxSlant, (v) => '${v.round()}°'),
                    ],
                    _slider('Stripes', 'stripes', CrosswalkOverlay.stripesOf(selected).toDouble(), CrosswalkOverlay.minStripes.toDouble(),
                        CrosswalkOverlay.maxStripes.toDouble(), (v) => '${v.round()}',
                        divisions: CrosswalkOverlay.maxStripes - CrosswalkOverlay.minStripes, whole: true),
                    _slider('Worn paint', 'wear', CrosswalkOverlay.wearOf(selected), 0, 1, (v) => '${(v * 100).round()}%'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('cw-reset'),
                        onPressed: _reset,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset its look'),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: Fx.s12),
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('Realistic look', style: Fx.body(context))),
                Switch(
                  key: const ValueKey('cw-realistic'),
                  value: _realistic,
                  onChanged: (v) {
                    widget.draft.config(key)['crosswalks_realistic'] = v;
                    widget.draft.touch();
                    setState(() {});
                  },
                ),
              ]),
              Text('Soft edges, grain and paint dulled to the light of the scene. Off = flat white bars.', style: Fx.caption(context)),
              const SizedBox(height: Fx.s8),
              Text(
                _items.isEmpty
                    ? 'No overlay crosswalk yet.'
                    : '${_items.length} overlay crosswalk${_items.length == 1 ? '' : 's'}. Each one is a crosswalk zone.',
                key: const ValueKey('cw-summary'),
                style: Fx.caption(context),
              ),
              if (_items.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('cw-clear'),
                    onPressed: _clearAll,
                    icon: const Icon(Icons.layers_clear_outlined, size: 18),
                    label: const Text('Remove all'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Fx.s12),
        ViolationParams(draft: widget.draft, violationKey: key, onChanged: () => setState(() {})),
      ],
    );
  }

  Widget _slider(String title, String field, double value, double min, double max, String Function(double) show,
      {int? divisions, bool whole = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: Fx.body(context))),
        Text(show(value), style: Fx.heading(context)),
      ]),
      Slider(
        key: ValueKey('cw-slider-$field'),
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: show(value),
        onChanged: (v) => _setLook(field, whole ? v.round() : v),
      ),
    ]);
  }
}

/// The crosswalks as they will be painted (bars between the four corners, like the backend), with handles on the selected one.
class _CrosswalkPainter extends CustomPainter {
  _CrosswalkPainter({required this.items, required this.selected, required this.realistic});

  final List<Map<String, dynamic>> items;
  final int? selected;
  final bool realistic;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    for (var n = 0; n < items.length; n++) {
      final c = items[n];
      final quad = CrosswalkOverlay.quad(c);
      final worn = CrosswalkOverlay.wearOf(c);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: (realistic ? 0.9 : 0.85) * (1 - 0.35 * worn))
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      if (realistic) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7);
      for (final bar in CrosswalkOverlay.bars(quad, CrosswalkOverlay.stripesOf(c))) {
        canvas.drawPath(Path()..addPolygon([for (final p in bar) px(p)], true), paint);
      }
      final outline = Path()..addPolygon([for (final p in quad) px(p)], true);
      canvas.drawPath(
        outline,
        Paint()
          ..color = n == selected ? Fx.accent : Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = n == selected ? 2 : 1,
      );
      if (n == selected && CrosswalkOverlay.isFree(c)) {
        for (var k = 0; k < 4; k++) {                          // the four sides stretch, the four corners reshape
          final side = CrosswalkOverlay.sideHandle(c, k, size);
          canvas.drawRect(Rect.fromCenter(center: side, width: 11, height: 11), Paint()..color = Fx.accent);
          canvas.drawRect(Rect.fromCenter(center: side, width: 11, height: 11), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }
        for (var k = 0; k < 4; k++) {
          final at = CrosswalkOverlay.cornerHandle(c, k, size);
          canvas.drawCircle(at, 8, Paint()..color = Colors.white);
          canvas.drawCircle(at, 8, Paint()..color = Fx.accent..style = PaintingStyle.stroke..strokeWidth = 2);
        }
      } else if (n == selected) {
        final knob = CrosswalkOverlay.rotateKnob(c, size);
        final handle = CrosswalkOverlay.resizeHandle(c, size);
        final centre = px(CrosswalkOverlay.centerOf(c));
        final far = (px(quad[0]) + px(quad[1])) / 2;
        canvas.drawLine(far, knob, Paint()..color = Fx.accent..strokeWidth = 2);
        for (final (at, icon) in [(knob, true), (handle, false)]) {
          canvas.drawCircle(at, 7, Paint()..color = Colors.white);
          canvas.drawCircle(at, 7, Paint()..color = Fx.accent..style = PaintingStyle.stroke..strokeWidth = 2);
          if (icon) canvas.drawCircle(at, 2.5, Paint()..color = Fx.accent);
        }
        canvas.drawCircle(centre, 3, Paint()..color = Fx.accent);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CrosswalkPainter old) => true;
}
