import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/theme/light_mode.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/object_previews.dart';
import '../../../forensic/domain/crosswalk_overlay.dart';
import '../../../forensic/domain/lane_signs.dart';
import '../../../forensic/domain/loading_signs.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/domain/zone_geometry.dart';
import '../../../forensic/presentation/widgets/box_object.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/crosswalk_quad.dart';
import '../../domain/live_setup_draft.dart';
import '../../domain/models/road_detect.dart';
import 'overlay_sign_paint.dart';
import 'road_arrow.dart';
import 'road_zone_editor.dart';

/// One thing that can be shown on the picture: a row of the checklist.
class _Layer {
  const _Layer(this.id, this.group, this.label, this.count, this.colour);

  final String id;
  final String group;
  final String label;
  final int count;
  final Color colour;
}

/// "Show layers": the setup picture with everything that was set up on it, and a checklist of what to show: the road markings (by kind,
/// and their direction arrows), the zones of each picked violation, and the overlay signs (lane signs, parking / loading signs, painted
/// crosswalks, painted lines). It only shows: nothing is changed here. The signs are the Forensic pictures: the backend draws the hydrant,
/// the signs on their poles and the road paint ([api]), and the lane boards are drawn as in the zone editor.
class SetupLayersDialog extends StatefulWidget {
  const SetupLayersDialog({super.key, required this.draft, required this.frame, this.api});

  final LiveSetupDraft draft;
  final ImageProvider frame;
  final ForensicApi? api;

  @override
  State<SetupLayersDialog> createState() => _SetupLayersDialogState();
}

class _SetupLayersDialogState extends State<SetupLayersDialog> {
  final Set<String> _hidden = {};
  late final List<_Layer> _layers = _collect();
  late final ObjectPreviews _previews = ObjectPreviews(widget.api)..addListener(_pictureArrived);

  void _pictureArrived() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _previews.dispose();
    super.dispose();
  }

  static const _markingNames = {
    'crosswalk': 'Crosswalks',
    'solid_line': 'Solid lines',
    'stop_line': 'Stop lines',
    'lane': 'Lanes',
    'road': 'Roads',
    'sidewalk': 'Sidewalks',
  };

  static List<List<double>> _points(Object? raw) => [
    for (final p in (raw as List? ?? const []))
      if (p is List && p.length >= 2) [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
  ];

  static bool _painted(Object? zone) => zone is Map && zone['paint'] != null && zone['paint'] != false;

  List<_Layer> _collect() {
    final d = widget.draft;
    final out = <_Layer>[];
    for (final kind in _markingNames.keys) {
      final of = d.markings.where((m) => m.kind == kind).toList();
      if (of.isNotEmpty) out.add(_Layer('m:$kind', 'Road markings', _markingNames[kind]!, of.length, RoadZoneEditor.colourOf(of.first)));
    }
    final arrows = d.markings.where((m) => m.hasDirection && m.flow != null && m.arrow.length >= 2).length;
    if (arrows > 0) out.add(_Layer('m:arrows', 'Road markings', 'Direction arrows', arrows, Colors.lightBlueAccent));
    for (final key in d.selection) {
      final info = ViolationCatalog.of(key);
      final zones = d.zones(key).length;
      if (zones > 0) out.add(_Layer('z:$key', 'Violation zones', info.label, zones, info.color));
    }
    for (final key in d.selection) {
      final info = ViolationCatalog.of(key);
      final signs = d.signCount(key);
      if (signs > 0) out.add(_Layer('s:$key', 'Overlay signs', '${info.label}: signs', signs, info.color));
      final zebras = d.crosswalkCount(key) + (key == 'pedestrian_lane' ? d.zones(key).where(_painted).length : 0);
      if (zebras > 0) out.add(_Layer('c:$key', 'Overlay signs', 'Painted crosswalks', zebras, Colors.white));
      final painted = key == 'crossing_solid_line' ? d.zones(key).where((z) => z is Map && z['look'] is Map).length : 0;
      if (painted > 0) out.add(_Layer('l:$key', 'Overlay signs', 'Painted lines', painted, Colors.yellowAccent));
    }
    return out;
  }

  bool _on(String id) => !_hidden.contains(id);

  void _toggle(String id, bool on) => setState(() => on ? _hidden.remove(id) : _hidden.add(id));

  void _all(bool on) => setState(() {
    _hidden.clear();
    if (!on) _hidden.addAll(_layers.map((l) => l.id));
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final picture = _picture();
    final list = _checklist(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Fx.s16),
      child: Padding(
        padding: const EdgeInsets.all(Fx.s16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Show layers', style: Fx.title(context))),
            IconButton(key: const ValueKey('layers-close'), tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: Fx.s8),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Center(child: picture)),
                    const SizedBox(width: Fx.s16),
                    SizedBox(width: 280, child: list),
                  ])
                : Column(children: [
                    Expanded(child: Center(child: picture)),
                    const SizedBox(height: Fx.s8),
                    SizedBox(height: 220, child: list),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _picture() {
    return AspectRatio(
      aspectRatio: ZoneGeometry.refWidth / ZoneGeometry.refHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Fx.radiusSm),
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          KeepColors(child: Image(image: widget.frame, fit: BoxFit.fill, gaplessPlayback: true)),
          CustomPaint(key: const ValueKey('layers-canvas'), painter: _LayersPainter(widget.draft, _layers.where((l) => _on(l.id)).map((l) => l.id).toSet(), _previews)),
        ]),
      ),
    );
  }

  Widget _checklist(BuildContext context) {
    if (_layers.isEmpty) {
      return Text('Nothing is set up on this picture yet: no road markings, zones or signs.', style: Fx.body(context));
    }
    final groups = <String>[];
    for (final l in _layers) {
      if (!groups.contains(l.group)) groups.add(l.group);
    }
    return ListView(children: [
      Row(children: [
        TextButton(key: const ValueKey('layers-all'), onPressed: () => _all(true), child: const Text('Show all')),
        TextButton(key: const ValueKey('layers-none'), onPressed: () => _all(false), child: const Text('Hide all')),
      ]),
      for (final g in groups) ...[
        Padding(padding: const EdgeInsets.only(top: Fx.s8, bottom: 2), child: Text(g.toUpperCase(), style: Fx.label(context))),
        for (final l in _layers.where((l) => l.group == g))
          CheckboxListTile(
            key: ValueKey('layer-${l.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _on(l.id),
            onChanged: (v) => _toggle(l.id, v ?? true),
            title: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: l.colour, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${l.count}', style: Fx.caption(context)),
            ]),
          ),
      ],
    ]);
  }
}

class _LayersPainter extends CustomPainter {
  _LayersPainter(this.draft, this.on, this.previews);

  final LiveSetupDraft draft;
  final Set<String> on;
  final ObjectPreviews previews;

  void _text(Canvas canvas, String text, Offset at, Color bg, {Color fg = Colors.black, double size = 12}) {
    final p = TextPainter(
      text: TextSpan(text: ' $text ', style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.bold, backgroundColor: bg)),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  void _zebra(Canvas canvas, List<Offset> shape, {int stripes = 8}) {
    final quad = zebraQuad(shape);
    if (quad == null) return;
    for (final bar in zebraBars(quad, stripes: stripes.clamp(3, 16))) {
      canvas.drawPath(Path()..addPolygon(bar, true), Paint()..color = Colors.white.withValues(alpha: 0.92));
    }
    canvas.drawPath(Path()..addPolygon(shape, true), Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / ZoneGeometry.refWidth, sy = size.height / ZoneGeometry.refHeight;
    Offset at(double x, double y) => Offset(x * sx, y * sy);
    List<Offset> poly(Object? raw) => [for (final p in _SetupLayersDialogState._points(raw)) at(p[0], p[1])];

    // 1 road markings (areas under lines under arrows)
    final order = ['sidewalk', 'road', 'lane', 'crosswalk', 'solid_line', 'stop_line'];
    for (final kind in order) {
      if (!on.contains('m:$kind')) continue;
      for (final m in draft.markings.where((m) => m.kind == kind)) {
        final pts = [for (final p in m.polygon) at(p.dx, p.dy)];
        final colour = RoadZoneEditor.colourOf(m);
        if (m.isLine) {
          if (pts.length >= 2) canvas.drawPath(Path()..addPolygon(pts, false), Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 4);
        } else if (pts.length >= 3) {
          final path = Path()..addPolygon(pts, true);
          canvas.drawPath(path, Paint()..color = colour.withValues(alpha: 0.2));
          canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 2);
          final name = switch (kind) {
            'lane' => ['Lane', if (m.laneType != null) RoadArea.laneTypes[m.laneType] ?? m.laneType!].join(' · '),
            'road' => ['Road', if (m.roadClass != null) RoadArea.roadClasses[m.roadClass] ?? m.roadClass!].join(' · '),
            _ => RoadArea.labelOf(kind),
          };
          _text(canvas, name, Offset(pts.map((p) => p.dx).reduce(math.min), pts.map((p) => p.dy).reduce(math.min)) + const Offset(4, 4), colour, size: 11);
        }
      }
    }
    if (on.contains('m:arrows')) {
      for (final m in draft.markings.where((m) => m.hasDirection && m.flow != null && m.arrow.length >= 2)) {
        paintRoadPath(canvas, [for (final p in m.arrow) at(p.dx, p.dy)], flowColour(m.flow), width: 5, head: 22);
      }
    }

    // 2 the zones of the picked violations
    for (final key in draft.selection) {
      if (!on.contains('z:$key')) continue;
      final colour = ViolationCatalog.of(key).color;
      for (final z in draft.zones(key)) {
        if (z is! Map) continue;
        final area = poly(z['polygon']);
        if (area.length >= 3) {
          final path = Path()..addPolygon(area, true);
          canvas.drawPath(path, Paint()..color = colour.withValues(alpha: 0.16));
          canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 2.5);
        }
        final line = poly(z['line']);
        if (line.length >= 2) canvas.drawPath(Path()..addPolygon(line, false), Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 4);
        final lead = area.length >= 3 ? area.first : (line.isNotEmpty ? line.first : null);
        if (lead != null) _text(canvas, ViolationCatalog.of(key).label, lead + const Offset(2, -18), colour, size: 11);
      }
    }

    // 3 overlay signs and painted crosswalks
    for (final key in draft.selection) {
      if (on.contains('s:$key')) {
        final realistic = (draft.config(key)['signs_realistic'] as bool?) ?? true;
        for (final sign in draft.signs(key)) {
          final x = (sign['x'] as num?)?.toDouble(), y = (sign['y'] as num?)?.toDouble();
          if (x == null || y == null) continue;
          double look(String k, double fallback) => (sign[k] as num?)?.toDouble() ?? fallback;
          if (sign['type'] is String) {                                                 // a lane sign: the board, on its stand
            final spec = LaneSigns.of(sign['type'] as String);
            if (spec == null) continue;
            paintLaneBoard(
              canvas, size,
              at: at(x, y),
              spec: spec,
              scale: SignGeometry.clampScale(look('scale', 1)),
              angle: SignGeometry.clampAngle(look('angle', 0)),
              tilt: SignGeometry.clampTilt(look('tilt', 0)),
              stand: (sign['stand'] as String?) ?? 'none',
            );
          } else if (sign['w'] is num && sign['h'] is num) {                            // a box sign: the banned area and its object
            final kind = LoadingSigns.objectKind(key, sign);
            paintBoxPicture(
              canvas, size,
              BoxObject(
                box: LoadingSigns.rectOf(sign),
                polygon: LoadingSigns.areaOf(sign),
                editing: false,
                kind: kind,
                at: LoadingSigns.anchorOf(sign),
                selected: false,
                preview: previews.peek(
                  kind,
                  scale: LoadingSigns.scaleOf(sign),
                  angle: LoadingSigns.angleOf(sign),
                  tilt: LoadingSigns.tiltOf(sign),
                  stand: LoadingSigns.standOf(sign, kind),
                  realistic: realistic,
                ),
              ),
            );
          }
        }
      }
      if (on.contains('l:$key')) {
        final realistic = (draft.config(key)['lines_realistic'] as bool?) ?? true;
        for (final z in draft.zones(key)) {
          if (z is! Map || z['look'] is! Map) continue;
          final points = _SetupLayersDialogState._points(z['line'] ?? z['ui_vector']);
          if (points.length < 2) continue;
          final picture = previews.peekLine(points, Map<String, dynamic>.from(z['look'] as Map), realistic);
          if (picture != null) paintLinePicture(canvas, size, picture);
        }
      }
      if (on.contains('c:$key')) {
        for (final c in draft.crosswalks(key)) {
          final cx = (c['x'] as num?)?.toDouble() ?? 0, cy = (c['y'] as num?)?.toDouble() ?? 0;
          final quad = [for (final p in CrosswalkOverlay.corners(c)) at(cx + p.dx, cy + p.dy)];
          _zebra(canvas, quad);
        }
        if (key == 'pedestrian_lane') {
          for (final z in draft.zones(key).where(_SetupLayersDialogState._painted)) {
            final paint = (z as Map)['paint'];
            _zebra(canvas, poly(z['polygon']), stripes: paint is Map ? (paint['stripes'] as num?)?.toInt() ?? 8 : 8);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LayersPainter old) => true;
}
