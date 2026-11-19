import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/crosswalk_quad.dart';
import '../../domain/models/road_detect.dart';
import 'road_arrow.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

/// The correction step after "Detect road": the frozen picture with the draft shapes on it. Areas (crosswalk, road, sidewalk) and lines
/// (solid line, stop line) are made of points, as many as the shape needs, so a curve is just more points:
///   - tap a shape to select it, drag a point to move it
///   - tap an EDGE of the selected shape to add a point there; right-click a point (or select it and press Remove point) to take it away
///   - Smooth rounds the corners into a curve; Draw… places a new shape point by point
///   - a road area can have a direction (incoming = toward the camera, outgoing = away), shown by its arrow; the arrow has as many
///     points as the road bends: drag its dots, tap the arrow to add a point, right-click a dot to remove it
///   - the picture takes the whole width and the page scrolls; Ctrl + wheel (or the + / - buttons, or a pinch on a touchpad) zooms,
///     and the shapes zoom with the picture; zoomed in, drag the empty picture with the mouse (or the middle button) to move it
/// The finder only gives a first draft; the enforcer who knows the street has the last word.
class RoadZoneEditor extends StatefulWidget {
  const RoadZoneEditor({
    super.key,
    required this.frame,
    required this.size,
    required this.areas,
    required this.onChanged,
    this.onReset,
    this.markings = false,
    this.actions = const [],
  });

  final Uint8List? frame;

  /// The frozen picture's size in pixels: the shapes are in these coordinates.
  final Size size;
  final List<RoadArea> areas;
  final ValueChanged<List<RoadArea>> onChanged;

  /// Back to what the scan found; null = no such button (the road markings page has no scan to go back to).
  final VoidCallback? onReset;

  /// The road markings of the live setup, not the correction after "Detect road": a lane has a type, a road a class, both a direction;
  /// every solid line counts (which rule uses it depends on the violations picked); [actions] come first in the toolbar.
  final bool markings;
  final List<Widget> actions;

  static Color colourOf(RoadArea area) => switch (area.kind) {
    'road' => flowColour(area.flow),
    'lane' => Colors.amberAccent,
    'sidewalk' => Colors.lightGreenAccent,
    'solid_line' => area.style == 'solid_white' ? Colors.white : Colors.yellowAccent,
    'stop_line' => Colors.orangeAccent,
    _ => Colors.cyanAccent,
  };

  /// Chaikin corner cutting: each segment is replaced by two points a quarter and three quarters along it, which rounds the shape into a
  /// curve. A line keeps its two ends.
  static List<Offset> smooth(List<Offset> points, {required bool closed}) {
    final n = points.length;
    if (n < 3 && closed || n < 2) return points;
    final out = <Offset>[];
    if (!closed) out.add(points.first);
    final segments = closed ? n : n - 1;
    for (var i = 0; i < segments; i++) {
      final a = points[i], b = points[(i + 1) % n];
      out
        ..add(a * 0.75 + b * 0.25)
        ..add(a * 0.25 + b * 0.75);
    }
    if (!closed) out.add(points.last);
    return out;
  }

  @override
  State<RoadZoneEditor> createState() => _RoadZoneEditorState();
}

/// A shape being drawn, one tap at a time.
class _Drawing {
  _Drawing(this.kind, {this.flow, this.style = 'solid_white'});

  final String kind;
  final String? flow;
  final String style;
  final List<Offset> points = [];

  bool get isLine => RoadArea.lineKinds.contains(kind);
  int get least => isLine ? 2 : 3;
}

class _RoadZoneEditorState extends State<RoadZoneEditor> {
  static const _grab = 18.0; // how close to a point (screen pixels) a press grabs it
  static const _edge = 12.0; // how close to an edge or a line a tap must be to add a point there / select the line
  static const _maxZoom = 8.0;
  final ScrollController _scroll = ScrollController();
  String? _selected;
  int? _point; // the selected point of the selected shape (the one Remove point takes away)
  int? _drag; // the point being dragged
  int? _apoint; // the selected point of the selected shape's arrow
  bool _dragArrow = false; // the point being dragged is an arrow point
  int _added = 0;
  _Drawing? _drawing;

  // The zoom: the picture and its shapes are drawn at the size of the box, then scaled by _zoom and moved by _pan (where the picture's
  // top-left corner is, in the box's own pixels; never positive, so the picture always covers the box).
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _box = Size.zero;
  bool _middleDrag = false; // moving the picture with the middle mouse button
  double _zoomAtStart = 1; // touchpad pinch
  Offset _panAtStart = Offset.zero;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static Offset _clampPan(Offset pan, double zoom, Size box) =>
      Offset(pan.dx.clamp(box.width - box.width * zoom, 0.0), pan.dy.clamp(box.height - box.height * zoom, 0.0));

  /// Zoom to [zoom], keeping the point of the picture under [focus] (the box's own pixels) where it is.
  void _zoomTo(double zoom, Offset focus) {
    final next = zoom.clamp(1.0, _maxZoom);
    setState(() {
      _pan = _clampPan(focus - (focus - _pan) * (next / _zoom), next, _box);
      _zoom = next;
    });
  }

  void _zoomBy(double factor) => _zoomTo(_zoom * factor, Offset(_box.width / 2, _box.height / 2));

  void _fit() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final held = HardwareKeyboard.instance;
    if (!held.isControlPressed && !held.isMetaPressed) return; // a plain wheel scrolls the page
    final focus = event.localPosition; // read here: the resolver hands the callback the untransformed event
    final turn = event.scrollDelta.dy;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => _zoomTo(_zoom * math.exp(-turn * 0.002), focus));
  }

  RoadArea? get _selectedArea => widget.areas.where((a) => a.id == _selected).firstOrNull;

  void _replace(RoadArea area) => widget.onChanged([for (final a in widget.areas) a.id == area.id ? area : a]);

  Offset _toFrame(Offset local, double scale) => Offset(
    (local.dx / scale).clamp(0.0, widget.size.width - 1),
    (local.dy / scale).clamp(0.0, widget.size.height - 1),
  );

  static bool _inside(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) inside = !inside;
    }
    return inside;
  }

  /// The edge of [a] nearest to [p] (screen pixels): the index of the edge's first point, the distance and the nearest point on it.
  ({int index, double distance, Offset point})? _nearestEdge(RoadArea a, Offset p, double scale) =>
      _nearestOn([for (final q in a.polygon) q * scale], p, open: a.isLine);

  /// The same for any run of points ([open]: no edge from the last point back to the first).
  ({int index, double distance, Offset point})? _nearestOn(List<Offset> pts, Offset p, {required bool open}) {
    if (pts.length < 2) return null;
    final count = open ? pts.length - 1 : pts.length;
    ({int index, double distance, Offset point})? best;
    for (var i = 0; i < count; i++) {
      final from = pts[i], to = pts[(i + 1) % pts.length];
      final ab = to - from;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      final t = len2 == 0 ? 0.0 : (((p - from).dx * ab.dx + (p - from).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final q = from + ab * t;
      final d = (p - q).distance;
      if (best == null || d < best.distance) best = (index: i, distance: d, point: q);
    }
    return best;
  }

  int? _pointNear(RoadArea area, Offset local, double scale) {
    for (var i = 0; i < area.polygon.length; i++) {
      if ((area.polygon[i] * scale - local).distance <= _grab / _zoom) return i;
    }
    return null;
  }

  /// The arrow point of [area] under [local], if it has an arrow.
  int? _arrowNear(RoadArea area, Offset local, double scale) {
    if (area.flow == null || !area.hasDirection) return null;
    for (var i = 0; i < area.arrow.length; i++) {
      if ((area.arrow[i] * scale - local).distance <= _grab / _zoom) return i;
    }
    return null;
  }

  // ── tapping ──
  void _tap(Offset local, double scale) {
    final drawing = _drawing;
    if (drawing != null) {
      _drawPoint(drawing, local, scale);
      return;
    }
    final selected = _selectedArea;
    if (selected != null) {
      final arrowNear = _arrowNear(selected, local, scale);
      if (arrowNear != null) {
        setState(() {
          _apoint = arrowNear;
          _point = null;
        });
        return;
      }
      final near = _pointNear(selected, local, scale);
      if (near != null) {
        setState(() {
          _point = near;
          _apoint = null;
        });
        return;
      }
      if (selected.flow != null && selected.hasDirection && selected.arrow.length >= 2 && selected.arrow.length < RoadArea.maxPoints) {
        final bend = _nearestOn([for (final q in selected.arrow) q * scale], local, open: true);
        if (bend != null && bend.distance <= _edge / _zoom) {
          _replace(selected.copyWith(arrow: [...selected.arrow]..insert(bend.index + 1, _toFrame(bend.point, scale))));
          setState(() {
            _apoint = bend.index + 1;
            _point = null;
          });
          return;
        }
      }
      final edge = _nearestEdge(selected, local, scale);
      if (edge != null && edge.distance <= _edge / _zoom && selected.polygon.length < RoadArea.maxPoints) {
        _replace(selected.copyWith(polygon: [...selected.polygon]..insert(edge.index + 1, _toFrame(edge.point, scale))));
        setState(() {
          _point = edge.index + 1;
          _apoint = null;
        });
        return;
      }
    }
    _select(local, scale);
  }

  void _select(Offset local, double scale) {
    final p = local / scale;
    RoadArea? hit;
    for (final a in widget.areas.reversed) {
      final onIt = a.isLine ? (_nearestEdge(a, local, scale)?.distance ?? double.infinity) <= _edge / _zoom : (a.polygon.length >= 3 && _inside(p, a.polygon));
      if (onIt) {
        hit = a;
        break;
      }
    }
    setState(() {
      _selected = hit?.id;
      _point = null;
      _apoint = null;
    });
  }

  // ── dragging a point ──
  void _grabPoint(Offset local, double scale) {
    if (_drawing != null) return;
    final chosen = _selectedArea;
    final onArrow = chosen == null ? null : _arrowNear(chosen, local, scale);
    if (onArrow != null) {
      setState(() {
        _dragArrow = true;
        _drag = onArrow;
        _apoint = onArrow;
        _point = null;
      });
      return;
    }
    for (final area in [?chosen, ...widget.areas]) {
      final i = _pointNear(area, local, scale);
      if (i != null) {
        setState(() {
          _selected = area.id;
          _dragArrow = false;
          _drag = i;
          _point = i;
          _apoint = null;
        });
        return;
      }
    }
    _endDrag();
  }

  void _endDrag() {
    _drag = null;
    _dragArrow = false;
  }

  void _dragPoint(Offset local, double scale) {
    final area = _selectedArea, i = _drag;
    if (area == null || i == null) return;
    if (_dragArrow) {
      if (i < area.arrow.length) _replace(area.copyWith(arrow: [...area.arrow]..[i] = _toFrame(local, scale)));
      return;
    }
    if (i >= area.polygon.length) return;
    _replace(area.copyWith(polygon: [...area.polygon]..[i] = _toFrame(local, scale)));
  }

  /// A drag that started on a point moves the point; one that started on the empty picture moves the picture (only when zoomed in).
  void _dragOrPan(DragUpdateDetails d, double scale) {
    if (_drag != null) {
      _dragPoint(d.localPosition, scale);
    } else if (_zoom > 1) {
      setState(() => _pan = _clampPan(_pan + d.delta * _zoom, _zoom, _box)); // d.delta is in the picture's own pixels
    }
  }

  // ── removing a point ──
  void _removePoint(RoadArea area, int i) {
    if (area.polygon.length <= area.minPoints || i >= area.polygon.length) return;
    _replace(area.copyWith(polygon: [...area.polygon]..removeAt(i)));
    setState(() => _point = null);
  }

  void _removeArrowPoint(RoadArea area, int i) {
    if (area.arrow.length <= 2 || i >= area.arrow.length) return;
    _replace(area.copyWith(arrow: [...area.arrow]..removeAt(i)));
    setState(() => _apoint = null);
  }

  void _removeNear(Offset local, double scale) {
    final area = _selectedArea;
    if (area == null || _drawing != null) return;
    final a = _arrowNear(area, local, scale);
    if (a != null) {
      _removeArrowPoint(area, a);
      return;
    }
    final i = _pointNear(area, local, scale);
    if (i != null) _removePoint(area, i);
  }

  // ── drawing a new shape ──
  void _startDrawing(String kind, {String? flow, String style = 'solid_white'}) => setState(() {
    _drawing = _Drawing(kind, flow: flow, style: style);
    _selected = null;
    _point = null;
  });

  void _drawPoint(_Drawing d, Offset local, double scale) {
    if (!d.isLine && d.points.length >= 3 && (d.points.first * scale - local).distance <= _grab / _zoom) {
      _finishDrawing(); // tapping the first point again closes an area
      return;
    }
    if (d.points.length >= RoadArea.maxPoints) return;
    setState(() => d.points.add(_toFrame(local, scale)));
  }

  void _finishDrawing() {
    final d = _drawing;
    if (d == null || d.points.length < d.least) return;
    final id = '${d.kind}-new-${++_added}';
    var shape = RoadArea(id: id, kind: d.kind, polygon: List.of(d.points), style: d.style, rule: d.kind == 'solid_line', paint: d.kind == 'crosswalk' && widget.markings);
    if (d.flow != null) shape = shape.copyWith(flow: d.flow, arrow: _autoArrow(shape.polygon, d.flow!));
    widget.onChanged([...widget.areas, shape]);
    setState(() {
      _drawing = null;
      _selected = id;
      _point = null;
    });
  }

  /// An arrow down the middle of a road area: incoming (toward the camera) points down the picture, outgoing points up.
  static List<Offset> _autoArrow(List<Offset> poly, String flow) {
    final xs = poly.map((p) => p.dx), ys = poly.map((p) => p.dy);
    final x = (xs.reduce(math.min) + xs.reduce(math.max)) / 2;
    final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
    final far = Offset(x, top + 0.30 * (bottom - top)), near = Offset(x, top + 0.78 * (bottom - top));
    return flow == 'in' ? [far, near] : [near, far];
  }

  void _setFlow(RoadArea area, String? flow) {
    if (flow == null) {
      _replace(area.copyWith(clearFlow: true));
      return;
    }
    final turned = area.arrow.length >= 2 && area.flow != null;
    final arrow = turned ? (area.flow == flow ? area.arrow : area.arrow.reversed.toList()) : _autoArrow(area.polygon, flow);
    _replace(area.copyWith(flow: flow, arrow: arrow));
  }

  // ── the buttons ──
  /// A starting shape the operator then reshapes (add points, drag them): a box in the middle of the picture.
  void _add() {
    final current = _selectedArea;
    final kind = current != null && !current.isLine ? current.kind : 'road';
    final w = widget.size.width, h = widget.size.height;
    final id = '$kind-new-${++_added}';
    final box = [Offset(w * .35, h * .35), Offset(w * .65, h * .35), Offset(w * .65, h * .65), Offset(w * .35, h * .65)];
    widget.onChanged([...widget.areas, RoadArea(id: id, kind: kind, polygon: box)]);
    setState(() {
      _selected = id;
      _point = null;
    });
  }

  void _delete() {
    widget.onChanged([for (final a in widget.areas) if (a.id != _selected) a]);
    setState(() {
      _selected = null;
      _point = null;
    });
  }

  void _smooth(RoadArea area) {
    final next = RoadZoneEditor.smooth(area.polygon, closed: !area.isLine);
    if (next.length > RoadArea.maxPoints) return;
    _replace(area.copyWith(polygon: next));
    setState(() => _point = null);
  }

  List<Widget> _markingItems() => [
    MenuItemButton(key: const ValueKey('draw-crosswalk'), onPressed: () => _startDrawing('crosswalk'), child: const Text('Crosswalk')),
    MenuItemButton(key: const ValueKey('draw-solid'), onPressed: () => _startDrawing('solid_line'), child: const Text('Solid line')),
    MenuItemButton(key: const ValueKey('draw-stop'), onPressed: () => _startDrawing('stop_line'), child: const Text('Stop line')),
    MenuItemButton(key: const ValueKey('draw-lane'), onPressed: () => _startDrawing('lane'), child: const Text('Lane (bus lane, motorcycle lane …)')),
    MenuItemButton(key: const ValueKey('draw-road'), onPressed: () => _startDrawing('road'), child: const Text('Road')),
    MenuItemButton(key: const ValueKey('draw-sidewalk'), onPressed: () => _startDrawing('sidewalk'), child: const Text('Sidewalk')),
  ];

  /// What belongs to the selected shape in the road markings: its kind, paint, lane type, road class and direction.
  List<Widget> _markingControls(RoadArea selected) {
    RoadArea asKind(String kind) => selected.copyWith(
      kind: kind,
      clearFlow: kind != 'road' && kind != 'lane',
      clearLaneType: kind != 'lane',
      clearRoadClass: kind != 'road',
    );
    return [
      if (!selected.isLine)
        SegmentedButton<String>(
          key: const ValueKey('road-kind'),
          showSelectedIcon: false,
          segments: [for (final k in RoadArea.markingKinds) ButtonSegment(value: k, label: Text(RoadArea.labelOf(k)))],
          selected: {selected.kind},
          onSelectionChanged: (s) => _replace(asKind(s.first)),
        )
      else if (selected.kind == 'solid_line')
        DropdownButton<String>(
          key: const ValueKey('line-style'),
          value: selected.style,
          items: [for (final s in RoadArea.lineStyles) DropdownMenuItem(value: s, child: Text(RoadArea.styleLabel(s)))],
          onChanged: (s) {
            if (s != null) _replace(selected.copyWith(style: s));
          },
        )
      else
        Text('Stop line: the Red light rule uses it.', style: Fx.caption(context)),
      if (selected.kind == 'crosswalk')
        Tooltip(
          message: 'On: the crosswalk is painted as a zebra on the live video (vehicles drive over it), like the other overlays. '
              'Leave it off for a crosswalk that is really on the road.',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(key: const ValueKey('crosswalk-paint'), value: selected.paint, onChanged: (v) => _replace(selected.copyWith(paint: v))),
            Text('Paint on video', style: Fx.caption(context)),
          ]),
        ),
      if (selected.kind == 'crosswalk' && selected.paint) ...[
        Tooltip(
          message: 'On: soft edge, grain and paint dulled to the scene light, like a real crosswalk. Off: flat clean paint.',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(key: const ValueKey('crosswalk-realistic'), value: selected.realistic, onChanged: (v) => _replace(selected.copyWith(realistic: v))),
            Text('Realistic', style: Fx.caption(context)),
          ]),
        ),
        _slider('crosswalk-stripes', 'Bars ${selected.stripes}', selected.stripes.toDouble(), RoadArea.minStripes.toDouble(), RoadArea.maxStripes.toDouble(),
            (v) => _replace(selected.copyWith(stripes: v.round())), divisions: RoadArea.maxStripes - RoadArea.minStripes),
        _slider('crosswalk-wear', 'Worn ${(selected.wear * 100).round()}%', selected.wear, 0, 1, (v) => _replace(selected.copyWith(wear: v))),
      ],
      if (selected.kind == 'lane')
        DropdownButton<String?>(
          key: const ValueKey('lane-type'),
          value: selected.laneType,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Any vehicle may use it')),
            for (final e in RoadArea.laneTypes.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => _replace(v == null ? selected.copyWith(clearLaneType: true) : selected.copyWith(laneType: v)),
        ),
      if (selected.kind == 'road')
        DropdownButton<String?>(
          key: const ValueKey('road-class'),
          value: selected.roadClass,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Kind of road: not said')),
            for (final e in RoadArea.roadClasses.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => _replace(v == null ? selected.copyWith(clearRoadClass: true) : selected.copyWith(roadClass: v)),
        ),
      if (selected.hasDirection)
        const Tooltip(
          message: 'The arrow shows the way traffic goes. Drag its square dots to move them. Tap the arrow to add a bend. Right-click a dot to remove it.',
          child: Icon(Icons.info_outline, size: 18),
        ),
      if (selected.hasDirection)
        SegmentedButton<String>(
          key: const ValueKey('road-flow'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'none', label: Text('No direction')),
            ButtonSegment(value: 'in', label: Text('Incoming')),
            ButtonSegment(value: 'out', label: Text('Outgoing')),
          ],
          selected: {selected.flow ?? 'none'},
          onSelectionChanged: (s) => _setFlow(selected, s.first == 'none' ? null : s.first),
        ),
    ];
  }

  /// A small labelled slider for the toolbar.
  Widget _slider(String key, String label, double value, double min, double max, ValueChanged<double> onChanged, {int? divisions}) {
    return SizedBox(
      width: 210,
      child: Row(children: [
        SizedBox(width: 72, child: Text(label, style: Fx.caption(context))),
        Expanded(child: Slider(key: ValueKey(key), value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged)),
      ]),
    );
  }

  Widget _drawMenu() => MenuAnchor(
    menuChildren: widget.markings ? _markingItems() : [
      MenuItemButton(key: const ValueKey('draw-solid'), onPressed: () => _startDrawing('solid_line'), child: const Text('Solid line')),
      MenuItemButton(key: const ValueKey('draw-stop'), onPressed: () => _startDrawing('stop_line'), child: const Text('Stop line')),
      MenuItemButton(key: const ValueKey('draw-in'), onPressed: () => _startDrawing('road', flow: 'in'), child: const Text('Incoming road (toward the camera)')),
      MenuItemButton(key: const ValueKey('draw-out'), onPressed: () => _startDrawing('road', flow: 'out'), child: const Text('Outgoing road (away from the camera)')),
      MenuItemButton(key: const ValueKey('draw-crosswalk'), onPressed: () => _startDrawing('crosswalk'), child: const Text('Crosswalk')),
      MenuItemButton(key: const ValueKey('draw-sidewalk'), onPressed: () => _startDrawing('sidewalk'), child: const Text('Sidewalk')),
    ],
    builder: (context, controller, _) => OutlinedButton.icon(
      key: const ValueKey('road-draw'),
      onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      icon: const Icon(Icons.draw_outlined),
      label: const Text('Draw…'),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final d = _drawing;
    if (d != null) {
      return Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(
          'Drawing ${RoadArea.labelOf(d.kind).toLowerCase()}${d.flow == null ? '' : ' (${flowLabel(d.flow)!.toLowerCase()})'}: tap the picture to place points '
          '(${d.points.length}). ${d.isLine ? 'At least 2.' : 'At least 3; tap the first point to close it.'}',
          key: const ValueKey('road-drawing'),
          style: Fx.caption(context),
        ),
        FilledButton.icon(
          key: const ValueKey('road-finish'),
          onPressed: d.points.length >= d.least ? _finishDrawing : null,
          icon: const Icon(Icons.check),
          label: const Text('Finish'),
        ),
        TextButton(
          key: const ValueKey('road-draw-undo'),
          onPressed: d.points.isEmpty ? null : () => setState(d.points.removeLast),
          child: const Text('Undo point'),
        ),
        TextButton(key: const ValueKey('road-draw-cancel'), onPressed: () => setState(() => _drawing = null), child: const Text('Cancel')),
      ]);
    }
    final selected = _selectedArea;
    // The buttons that are always there come first, then what belongs to the selected shape (its kind, direction, paint).
    return Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ...widget.actions,
      IconButton.outlined(key: const ValueKey('road-add'), tooltip: 'Add an area (a box to reshape)', onPressed: _add, icon: const Icon(Icons.add_box_outlined)),
      _drawMenu(),
      if (selected != null) ...[
        IconButton.outlined(
          key: const ValueKey('road-remove-point'),
          tooltip: 'Remove the selected point of the shape or of its arrow (or right-click a point)',
          onPressed: (_apoint != null && selected.arrow.length > 2)
              ? () => _removeArrowPoint(selected, _apoint!)
              : ((_point != null && selected.polygon.length > selected.minPoints) ? () => _removePoint(selected, _point!) : null),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton.outlined(
          key: const ValueKey('road-smooth'),
          tooltip: 'Smooth: round the corners into a curve',
          onPressed: selected.polygon.length * 2 <= RoadArea.maxPoints ? () => _smooth(selected) : null,
          icon: const Icon(Icons.gesture),
        ),
        IconButton.outlined(key: const ValueKey('road-delete'), tooltip: 'Delete this shape', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
      ],
      if (widget.onReset != null) TextButton(key: const ValueKey('road-reset'), onPressed: widget.onReset, child: const Text('Back to the scan')),
      if (selected == null)
        Text(
          'Tap a shape to select it. Drag a point to move it. Tap an edge to add a point; right-click a point to remove it.',
          style: Fx.caption(context),
        )
      else if (widget.markings)
        ..._markingControls(selected)
      else if (!selected.isLine)
        SegmentedButton<String>(
          key: const ValueKey('road-kind'),
          showSelectedIcon: false,
          segments: [for (final k in RoadArea.kinds) ButtonSegment(value: k, label: Text(RoadArea.labelOf(k)))],
          selected: {selected.kind},
          onSelectionChanged: (s) => _replace(selected.copyWith(kind: s.first, clearFlow: s.first != 'road')),
        )
      else if (selected.kind == 'solid_line') ...[
        DropdownButton<String>(
          key: const ValueKey('line-style'),
          value: selected.style,
          items: [for (final s in RoadArea.lineStyles) DropdownMenuItem(value: s, child: Text(RoadArea.styleLabel(s)))],
          onChanged: (s) {
            if (s != null) _replace(selected.copyWith(style: s));
          },
        ),
        Tooltip(
          message: 'On: a vehicle that crosses this line is flagged (Crossing a solid line). Off: the line is only shown.',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(key: const ValueKey('line-rule'), value: selected.rule, onChanged: (v) => _replace(selected.copyWith(rule: v))),
            Text('Flag crossings', style: Fx.caption(context)),
          ]),
        ),
      ] else
        Text('Stop line: only shown (a red light needs a light).', style: Fx.caption(context)),
      if (selected != null && selected.kind == 'road' && !widget.markings)
        SegmentedButton<String>(
          key: const ValueKey('road-flow'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'none', label: Text('No direction')),
            ButtonSegment(value: 'in', label: Text('Incoming')),
            ButtonSegment(value: 'out', label: Text('Outgoing')),
          ],
          selected: {selected.flow ?? 'none'},
          onSelectionChanged: (s) => _setFlow(selected, s.first == 'none' ? null : s.first),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // A page that scrolls: the toolbar at its own height, then the picture at the FULL width (as tall as that makes it).
    // Nothing is squeezed into what is left over; scroll down to see all of the picture.
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(right: Fx.s12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _toolbar(context),
          const SizedBox(height: Fx.s8),
          AspectRatio(
            aspectRatio: widget.size.width / widget.size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radiusSm),
              child: LayoutBuilder(builder: (context, box) => _viewport(box)),
            ),
          ),
          const SizedBox(height: Fx.s16),
        ]),
      ),
    );
  }

  /// The picture with its shapes, zoomed and moved as one: the shapes scale in real time with the picture. Taps and drags reach the
  /// canvas already in the picture's own pixels (a Transform maps them back), so editing works the same at any zoom.
  Widget _viewport(BoxConstraints box) {
    _box = Size(box.maxWidth, box.maxHeight);
    final scale = box.maxWidth / widget.size.width;
    final pan = _clampPan(_pan, _zoom, _box);
    final zoomed = Matrix4.identity()
      ..setEntry(0, 0, _zoom)
      ..setEntry(1, 1, _zoom)
      ..setEntry(0, 3, pan.dx)
      ..setEntry(1, 3, pan.dy);
    return Listener(
      onPointerSignal: _onSignal,
      onPointerDown: (e) => _middleDrag = e.kind == PointerDeviceKind.mouse && e.buttons == kMiddleMouseButton,
      onPointerMove: (e) {
        if (_middleDrag) setState(() => _pan = _clampPan(_pan + e.delta, _zoom, _box));
      },
      onPointerUp: (_) => _middleDrag = false,
      onPointerCancel: (_) => _middleDrag = false,
      onPointerPanZoomStart: (_) {
        _zoomAtStart = _zoom;
        _panAtStart = _pan;
      },
      onPointerPanZoomUpdate: (e) {
        if ((e.scale - 1).abs() < 0.01) return; // a two-finger scroll without a pinch: the page scrolls
        final next = (_zoomAtStart * e.scale).clamp(1.0, _maxZoom);
        setState(() {
          _pan = _clampPan(e.localPosition - (e.localPosition - _panAtStart) * (next / _zoomAtStart), next, _box);
          _zoom = next;
        });
      },
      child: Stack(children: [
        Positioned.fill(
          child: MouseRegion(
            cursor: _drawing != null ? SystemMouseCursors.precise : MouseCursor.defer,
            child: Transform(
              transform: zoomed,
              child: RawGestureDetector(
                key: const ValueKey('road-canvas'),
                behavior: HitTestBehavior.opaque,
                gestures: {
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (tap) => tap
                      ..onTapUp = ((d) => _tap(d.localPosition, scale))
                      ..onSecondaryTapUp = ((d) => _removeNear(d.localPosition, scale)),
                  ),
                  _GrabbingPan: GestureRecognizerFactoryWithHandlers<_GrabbingPan>(
                    // A drag that starts on a point is the canvas's, not the page's: it wins at once.
                    () => _GrabbingPan(() => _drag != null),
                    (pan) => pan
                      ..onDown = ((d) => _grabPoint(d.localPosition, scale))
                      ..onUpdate = ((d) => _dragOrPan(d, scale))
                      ..onEnd = ((_) => _endDrag())
                      ..onCancel = _endDrag,
                  ),
                },
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Colors.black),
                  if (widget.frame != null) KeepColors(child: Image.memory(widget.frame!, fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true)),
                  CustomPaint(painter: _ShapesPainter(widget.areas, _selected, _point, _apoint, scale, _zoom, _drawing, widget.markings)),
                ]),
              ),
            ),
          ),
        ),
        Positioned(top: Fx.s8, right: Fx.s8, child: _zoomBar()),
      ]),
    );
  }

  Widget _zoomBar() {
    const tint = Colors.white;
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: const ValueKey('road-zoom-out'),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom > 1 ? () => _zoomBy(1 / 1.4) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 46,
          child: Text('${(_zoom * 100).round()}%', key: const ValueKey('road-zoom-level'), textAlign: TextAlign.center, style: const TextStyle(color: tint, fontSize: 12)),
        ),
        IconButton(
          key: const ValueKey('road-zoom-in'),
          tooltip: 'Zoom in (or Ctrl + wheel). Zoomed in, drag the empty picture with the mouse to move it.',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom < _maxZoom ? () => _zoomBy(1.4) : null,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          key: const ValueKey('road-zoom-fit'),
          tooltip: 'Show the whole picture',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _zoom > 1 ? _fit : null,
          icon: const Icon(Icons.fit_screen),
        ),
      ]),
    );
  }
}

/// A pan that takes the drag at once when [claims] says the press landed on something to drag (a point). Without it the page's own
/// scrolling can win a vertical drag made by touch and the point would not move. A mouse never scrolls the page by dragging, so it is
/// not affected either way. (It must not claim every press: a press that wins at once can never become a tap.)
class _GrabbingPan extends PanGestureRecognizer {
  _GrabbingPan(this.claims);

  final bool Function() claims;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event); // runs onDown, which decides what was grabbed
    if (claims()) resolve(GestureDisposition.accepted);
  }
}

class _ShapesPainter extends CustomPainter {
  _ShapesPainter(this.areas, this.selected, this.point, this.apoint, this.scale, this.zoom, this.drawing, this.markings);

  final List<RoadArea> areas;
  final String? selected;
  final int? point;
  final int? apoint; // the selected point of the selected shape's arrow
  final double scale;
  final double zoom; // the picture is drawn zoomed: handles, lines and labels are made smaller by it, so they keep their size on screen
  final _Drawing? drawing;
  final bool markings; // the road markings of the live setup (lane type, road class, no rule / hint wording)

  double get _k => 1 / zoom;

  void _text(Canvas canvas, String text, Color colour, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: ' $text ', style: TextStyle(color: Colors.black, fontSize: 12 * _k, fontWeight: FontWeight.bold, backgroundColor: colour)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  static Offset _topLeft(List<Offset> pts) =>
      Offset(pts.map((p) => p.dx).reduce(math.min), pts.map((p) => p.dy).reduce(math.min));

  void _handles(Canvas canvas, List<Offset> pts, Color colour, {required bool closed, int? chosenAt, bool square = false}) {
    final k = _k;
    final segments = closed ? pts.length : pts.length - 1;
    for (var i = 0; i < segments; i++) {                                    // a small dot in the middle of each edge: tap there to add a point
      final mid = (pts[i] + pts[(i + 1) % pts.length]) / 2;
      canvas.drawCircle(mid, 4 * k, Paint()..color = colour.withValues(alpha: 0.7));
    }
    for (final (i, p) in pts.indexed) {
      final chosen = i == (square ? chosenAt : point);
      final r = (chosen ? 10 : 8) * k;
      if (square) {                                                          // arrow points are squares, the shape's points are dots
        final box = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
        canvas.drawRect(box, Paint()..color = chosen ? colour : Colors.white);
        canvas.drawRect(box, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 3 * k);
        continue;
      }
      canvas.drawCircle(p, r, Paint()..color = chosen ? colour : Colors.white);
      canvas.drawCircle(p, r, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 3 * k);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = _k;
    for (final area in areas) {
      if (area.polygon.length < (area.isLine ? 2 : 3)) continue;
      final isSelected = area.id == selected;
      final colour = RoadZoneEditor.colourOf(area);
      final pts = [for (final p in area.polygon) p * scale];
      if (area.isLine) {
        final path = Path()..addPolygon(pts, false);
        if (area.style == 'double_yellow') {
          canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = (isSelected ? 8 : 6) * k);
          canvas.drawPath(path, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2 * k);
        } else {
          canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = (isSelected ? 6 : 4) * k);
        }
        final what = area.kind == 'stop_line' ? 'Stop line' : (markings ? 'Solid line' : 'Solid line · ${area.rule ? 'rule' : 'hint'}');
        _text(canvas, what, colour, _topLeft(pts) + Offset(2, -18) * k);
      } else {
        final path = Path()..addPolygon(pts, true);
        final zebra = markings && area.kind == 'crosswalk' && area.paint ? zebraQuad(pts) : null;
        if (zebra != null) {                                                  // painted: the zebra as the video will show it
          for (final bar in zebraBars(zebra, stripes: area.stripes)) {
            canvas.drawPath(Path()..addPolygon(bar, true), Paint()..color = Colors.white.withValues(alpha: (0.95 - 0.4 * area.wear).clamp(0.4, 0.95)));
          }
          canvas.drawPath(path, Paint()..color = colour.withValues(alpha: isSelected ? 0.9 : 0.5)..style = PaintingStyle.stroke..strokeWidth = (isSelected ? 2.5 : 1.5) * k);
        } else {
          canvas.drawPath(path, Paint()..color = colour.withValues(alpha: isSelected ? 0.34 : 0.2));
          canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = (isSelected ? 3.5 : 2) * k);
        }
        final flow = flowLabel(area.flow);
        final name = switch (area.kind) {
          'road' => ['Road', if (markings && area.roadClass != null) RoadArea.roadClasses[area.roadClass] ?? area.roadClass!, ?flow].join(' · '),
          'lane' => ['Lane', if (area.laneType != null) RoadArea.laneTypes[area.laneType] ?? area.laneType!, ?flow].join(' · '),
          _ => RoadArea.labelOf(area.kind),
        };
        _text(canvas, name, colour, _topLeft(pts) + Offset(4, 4) * k);
        if (area.hasDirection && area.flow != null && area.arrow.length >= 2) {
          paintRoadPath(canvas, [for (final p in area.arrow) p * scale], colour, width: (isSelected ? 6 : 4) * k, head: 22 * k);
          if (isSelected) _handles(canvas, [for (final p in area.arrow) p * scale], colour, closed: false, chosenAt: apoint, square: true);
        }
      }
      if (isSelected) _handles(canvas, pts, colour, closed: !area.isLine);
    }
    final d = drawing;
    if (d != null && d.points.isNotEmpty) {
      final colour = switch (d.kind) {
        'solid_line' => d.style == 'solid_white' ? Colors.white : Colors.yellowAccent,
        'stop_line' => Colors.orangeAccent,
        'road' => flowColour(d.flow),
        'lane' => Colors.amberAccent,
        'sidewalk' => Colors.lightGreenAccent,
        _ => Colors.cyanAccent,
      };
      final pts = [for (final p in d.points) p * scale];
      if (!d.isLine && pts.length >= 3) canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = colour.withValues(alpha: 0.18));
      canvas.drawPath(Path()..addPolygon(pts, false), Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 3 * k);
      for (final (i, p) in pts.indexed) {
        canvas.drawCircle(p, (i == 0 ? 10 : 7) * k, Paint()..color = i == 0 ? colour : Colors.white);
        canvas.drawCircle(p, (i == 0 ? 10 : 7) * k, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 3 * k);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShapesPainter old) => true;
}
