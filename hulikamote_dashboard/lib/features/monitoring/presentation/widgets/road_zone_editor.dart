import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/models/road_detect.dart';

/// The correction step after "Detect road": the frozen picture with the draft areas on it. Tap an area to select it, drag its corners,
/// change what it is (crosswalk, road or sidewalk), delete it, or add a new one. The finder only gives a first draft; the enforcer who
/// knows the street has the last word.
class RoadZoneEditor extends StatefulWidget {
  const RoadZoneEditor({
    super.key,
    required this.frame,
    required this.size,
    required this.areas,
    required this.onChanged,
    required this.onReset,
  });

  final Uint8List? frame;

  /// The frozen picture's size in pixels: the areas are in these coordinates.
  final Size size;
  final List<RoadArea> areas;
  final ValueChanged<List<RoadArea>> onChanged;

  /// Back to what the scan found.
  final VoidCallback onReset;

  static Color colourOf(String kind) => switch (kind) {
    'road' => Colors.lightBlueAccent,
    'sidewalk' => Colors.lightGreenAccent,
    _ => Colors.cyanAccent,
  };

  @override
  State<RoadZoneEditor> createState() => _RoadZoneEditorState();
}

class _RoadZoneEditorState extends State<RoadZoneEditor> {
  static const _grab = 18.0; // how close to a corner (screen pixels) a press grabs it
  String? _selected;
  int? _corner;
  int _added = 0;

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

  void _select(Offset local, double scale) {
    final p = local / scale;
    final hit = widget.areas.reversed.where((a) => _inside(p, a.polygon)).firstOrNull;
    setState(() => _selected = hit?.id);
  }

  void _grabCorner(Offset local, double scale) {
    final candidates = [?_selectedArea, ...widget.areas];
    for (final area in candidates) {
      for (var i = 0; i < area.polygon.length; i++) {
        if ((area.polygon[i] * scale - local).distance <= _grab) {
          setState(() {
            _selected = area.id;
            _corner = i;
          });
          return;
        }
      }
    }
    _corner = null;
  }

  void _drag(Offset local, double scale) {
    final area = _selectedArea, corner = _corner;
    if (area == null || corner == null) return;
    final moved = [...area.polygon]..[corner] = _toFrame(local, scale);
    _replace(area.copyWith(polygon: moved));
  }

  void _add() {
    final kind = _selectedArea?.kind ?? 'road';
    final w = widget.size.width, h = widget.size.height;
    final id = '$kind-new-${++_added}';
    final box = [Offset(w * .35, h * .35), Offset(w * .65, h * .35), Offset(w * .65, h * .65), Offset(w * .35, h * .65)];
    widget.onChanged([...widget.areas, RoadArea(id: id, kind: kind, polygon: box)]);
    setState(() => _selected = id);
  }

  void _delete() {
    widget.onChanged([for (final a in widget.areas) if (a.id != _selected) a]);
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedArea;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: Fx.s8, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (selected != null)
          SegmentedButton<String>(
            key: const ValueKey('road-kind'),
            showSelectedIcon: false,
            segments: [for (final k in RoadArea.kinds) ButtonSegment(value: k, label: Text(RoadArea.labelOf(k)))],
            selected: {selected.kind},
            onSelectionChanged: (s) => _replace(selected.copyWith(kind: s.first)),
          )
        else
          Text('Tap an area to select it. Drag its corners to fix it.', style: Fx.caption(context)),
        OutlinedButton.icon(key: const ValueKey('road-add'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add area')),
        if (selected != null)
          OutlinedButton.icon(key: const ValueKey('road-delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
        TextButton(key: const ValueKey('road-reset'), onPressed: widget.onReset, child: const Text('Back to the scan')),
      ]),
      const SizedBox(height: Fx.s8),
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: widget.size.width / widget.size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radiusSm),
              child: LayoutBuilder(builder: (context, box) {
                final scale = box.maxWidth / widget.size.width;
                return GestureDetector(
                  key: const ValueKey('road-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _select(d.localPosition, scale),
                  onPanDown: (d) => _grabCorner(d.localPosition, scale),
                  onPanUpdate: (d) => _drag(d.localPosition, scale),
                  onPanEnd: (_) => _corner = null,
                  child: Stack(fit: StackFit.expand, children: [
                    const ColoredBox(color: Colors.black),
                    if (widget.frame != null) Image.memory(widget.frame!, fit: BoxFit.fill, gaplessPlayback: true),
                    CustomPaint(painter: _AreasPainter(widget.areas, _selected, scale)),
                  ]),
                );
              }),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _AreasPainter extends CustomPainter {
  _AreasPainter(this.areas, this.selected, this.scale);

  final List<RoadArea> areas;
  final String? selected;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final area in areas) {
      if (area.polygon.length < 3) continue;
      final isSelected = area.id == selected;
      final colour = RoadZoneEditor.colourOf(area.kind);
      final path = Path()..addPolygon([for (final p in area.polygon) p * scale], true);
      canvas.drawPath(path, Paint()..color = colour.withValues(alpha: isSelected ? 0.34 : 0.2));
      canvas.drawPath(path, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = isSelected ? 3.5 : 2);
      final text = TextPainter(
        text: TextSpan(text: ' ${RoadArea.labelOf(area.kind)} ', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: colour)),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = area.polygon.map((p) => p.dy).reduce((a, b) => a < b ? a : b) * scale;
      final left = area.polygon.map((p) => p.dx).reduce((a, b) => a < b ? a : b) * scale;
      text.paint(canvas, Offset(left + 4, top + 4));
      if (isSelected) {
        for (final p in area.polygon) {
          canvas.drawCircle(p * scale, 8, Paint()..color = Colors.white);
          canvas.drawCircle(p * scale, 8, Paint()..color = colour..style = PaintingStyle.stroke..strokeWidth = 3);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AreasPainter old) => true;
}
