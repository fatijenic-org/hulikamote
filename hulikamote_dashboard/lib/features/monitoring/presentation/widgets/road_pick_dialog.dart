import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../forensic/domain/zone_geometry.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/road_detect.dart';
import '../../domain/models/road_preset.dart';

/// What [RoadPickDialog] hands back when a saved road is chosen: which one, and its markings (1920x1080 reference space).
class RoadPick {
  const RoadPick({required this.id, required this.name, required this.markings});

  final String id;
  final String name;
  final List<RoadArea> markings;
}

/// Pick a saved road from a drop-down, with a preview of it painted on the setup picture. The roads saved for the video in use come first
/// (marked ★) and the dialog opens by itself on the Road step when there is one. "Use this road" puts it in the editor, where it can still be
/// corrected.
class RoadPickDialog extends StatefulWidget {
  const RoadPickDialog({super.key, required this.api, required this.presets, required this.frame, required this.size, this.suggested = false});

  final CameraApi api;
  final List<RoadPreset> presets;

  /// The setup picture (the preview is painted on it) and its pixel size.
  final Uint8List? frame;
  final Size? size;

  /// True when it opened by itself because a road was saved for this video.
  final bool suggested;

  @override
  State<RoadPickDialog> createState() => _RoadPickDialogState();
}

class _RoadPickDialogState extends State<RoadPickDialog> {
  late String _selected = widget.presets.first.id;
  final Map<String, List<RoadArea>> _marks = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final id = _selected;
    if (_marks.containsKey(id)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final marks = await widget.api.roadPresetMarkings(id);
      if (mounted) _marks[id] = marks;
    } catch (e) {
      if (mounted) _error = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  RoadPreset get _current => widget.presets.firstWhere((p) => p.id == _selected);

  @override
  Widget build(BuildContext context) {
    final marks = _marks[_selected];
    final size = widget.size;
    final aspect = (size != null && size.height > 0) ? size.width / size.height : 16 / 9;
    final current = _current;
    return AlertDialog(
      title: Text(widget.suggested ? 'A saved road was found for this video' : 'Use a saved road'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButton<String>(
            key: const ValueKey('road-pick-dropdown'),
            isExpanded: true,
            value: _selected,
            items: [
              for (final p in widget.presets)
                DropdownMenuItem(value: p.id, child: Text('${p.match ? '★ ' : ''}${p.name}  ·  ${p.count} marking${p.count == 1 ? '' : 's'}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selected = v);
              _loadPreview();
            },
          ),
          const SizedBox(height: Fx.s8),
          Text(
            current.match
                ? 'Saved for this video.'
                : (current.videoName.isEmpty ? 'Not tied to a video.' : 'Saved for another video: ${current.videoName}.'),
            style: Fx.caption(context),
          ),
          const SizedBox(height: Fx.s8),
          AspectRatio(
            aspectRatio: aspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radiusSm),
              child: Stack(fit: StackFit.expand, children: [
                if (widget.frame != null) Image.memory(widget.frame!, fit: BoxFit.fill, gaplessPlayback: true) else const ColoredBox(color: Colors.black),
                if (marks != null) CustomPaint(painter: _PreviewPainter(marks)),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ]),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Fx.s8), child: Text(_error!, style: Fx.caption(context))),
          const SizedBox(height: Fx.s4),
          Text('Preview on this video\'s picture. After "Use this road" you can still change every marking.', style: Fx.caption(context)),
        ]),
      ),
      actions: [
        TextButton(key: const ValueKey('road-pick-skip'), onPressed: () => Navigator.of(context).pop(), child: Text(widget.suggested ? 'Not now' : 'Close')),
        FilledButton(
          key: const ValueKey('road-pick-use'),
          onPressed: (marks == null) ? null : () => Navigator.of(context).pop(RoadPick(id: current.id, name: current.name, markings: marks)),
          child: const Text('Use this road'),
        ),
      ],
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.marks);

  final List<RoadArea> marks;

  static Color _color(String kind) => switch (kind) {
    'crosswalk' => Colors.white,
    'road' => const Color(0xFF4FA3FF),
    'lane' => const Color(0xFF49D17D),
    'sidewalk' => const Color(0xFFFFB347),
    'solid_line' => const Color(0xFFFFE066),
    'stop_line' => const Color(0xFFFF5C5C),
    _ => Colors.white,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final fx = size.width / ZoneGeometry.refWidth, fy = size.height / ZoneGeometry.refHeight;
    for (final a in marks) {
      if (a.polygon.length < 2) continue;
      final color = _color(a.kind);
      final path = Path()..moveTo(a.polygon.first.dx * fx, a.polygon.first.dy * fy);
      for (final p in a.polygon.skip(1)) {
        path.lineTo(p.dx * fx, p.dy * fy);
      }
      if (!a.isLine) {
        path.close();
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.28));
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = a.isLine ? 3 : 2);
      if (a.arrow.length >= 2) {
        final arrow = Path()..moveTo(a.arrow.first.dx * fx, a.arrow.first.dy * fy);
        for (final p in a.arrow.skip(1)) {
          arrow.lineTo(p.dx * fx, p.dy * fy);
        }
        canvas.drawPath(arrow, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
        final end = a.arrow.last, prev = a.arrow[a.arrow.length - 2];
        final dir = Offset((end.dx - prev.dx) * fx, (end.dy - prev.dy) * fy);
        if (dir.distance > 0) {
          final u = dir / dir.distance, tip = Offset(end.dx * fx, end.dy * fy), n = Offset(-u.dy, u.dx);
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(tip.dx - u.dx * 10 + n.dx * 5, tip.dy - u.dy * 10 + n.dy * 5)
              ..lineTo(tip.dx - u.dx * 10 - n.dx * 5, tip.dy - u.dy * 10 - n.dy * 5)
              ..close(),
            Paint()..color = Colors.white,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.marks != marks;
}
