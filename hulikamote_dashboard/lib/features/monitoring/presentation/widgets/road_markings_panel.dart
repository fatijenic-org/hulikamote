import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/domain/zone_geometry.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/road_detect.dart';
import '../../domain/road_markings.dart';
import 'road_detect_view.dart';
import 'road_zone_editor.dart';

/// The "Road" step of the live setup: the road is marked ONCE, on the setup picture, with the same editor as "Detect road" (many points,
/// zoom): crosswalks, solid lines, stop lines, lanes (with a type and a direction), roads (with a kind and a direction) and sidewalks.
/// Each violation that is picked in the next step then takes only the markings it needs (see [RoadMarkingMap]).
///
/// "Find the road automatically" shows the walkthrough of Detect road (step by step, on a few seconds of the video that start at the
/// setup picture); "Use these" puts what it found in the editor, where it can be corrected.
///
/// Every change is reported to [onChanged] at once, in the 1920x1080 reference space (the step has no save button).
class RoadMarkingsPanel extends StatefulWidget {
  const RoadMarkingsPanel({super.key, required this.cameraApi, required this.markings, required this.onChanged});

  final CameraApi cameraApi;

  /// The markings made before, in the 1920x1080 reference space.
  final List<RoadArea> markings;
  final ValueChanged<List<RoadArea>> onChanged;

  @override
  State<RoadMarkingsPanel> createState() => _RoadMarkingsPanelState();
}

class _RoadMarkingsPanelState extends State<RoadMarkingsPanel> {
  Uint8List? _frame;
  Size? _size;                       // the picture's pixels: the editor works in them
  List<RoadArea> _areas = const [];
  String? _error;
  bool _scanning = false;            // the walkthrough is on screen
  bool _starting = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.cameraApi.referenceFrameBytes();
      if (bytes == null) throw Exception('The setup picture is not there any more. Go back and pick a picture again.');
      final image = await decodeImageFromList(bytes);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      if (!mounted) return;
      final fx = size.width / ZoneGeometry.refWidth, fy = size.height / ZoneGeometry.refHeight;
      setState(() {
        _frame = bytes;
        _size = size;
        _areas = [for (final m in widget.markings) m.scaled(fx, fy)];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Back to the reference space, and on to the setup. A marking the finder found keeps its 'auto-' name; the others get plain numbers.
  void _emit() {
    final size = _size;
    if (size == null) return;
    final fx = ZoneGeometry.refWidth / size.width, fy = ZoneGeometry.refHeight / size.height;
    var n = 0;
    widget.onChanged([for (final a in _areas) a.scaled(fx, fy).withId(a.id.startsWith('auto-') ? a.id : 'm${++n}')]);
  }

  Future<void> _find() async {
    if (_starting || _size == null) return;
    setState(() {
      _starting = true;
      _notice = null;
    });
    try {
      await widget.cameraApi.startRoadScan();
      if (mounted) setState(() => _scanning = true);
    } catch (e) {
      if (mounted) setState(() => _notice = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// The scan's result: what an earlier scan proposed is replaced; what the operator drew stays.
  void _found(List<RoadArea> found, Size scanSize) {
    final size = _size;
    if (size == null) return;
    final fx = size.width / scanSize.width, fy = size.height / scanSize.height;
    var n = 0;
    setState(() {
      _areas = [
        ..._areas.where((a) => !a.id.startsWith('auto-')),
        for (final a in found) a.scaled(fx, fy).withId('auto-${++n}'),
      ];
      _notice = null;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return RoadDetectView(
        key: const ValueKey('road-scan'),
        api: widget.cameraApi,
        scan: true,
        onFound: _found,
        sweepTime: const Duration(milliseconds: 800),
        dwell: const Duration(milliseconds: 250),
        onClose: ({required applied}) {
          if (mounted) setState(() => _scanning = false);
        },
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (marking, key) in RoadMarkingMap.uses)
          StatusPill(label: '$marking → ${ViolationCatalog.of(key).label}', color: Fx.muted(context), dense: true),
      ]),
      const SizedBox(height: Fx.s12),
      if (_notice != null) ...[
        FxBanner(key: const ValueKey('markings-notice'), message: _notice!, color: Fx.warning, icon: Icons.info_outline),
        const SizedBox(height: Fx.s8),
      ],
      Expanded(child: _editor(context)),
      const SizedBox(height: Fx.s8),
      Text('${_areas.length} marking${_areas.length == 1 ? '' : 's'}. You can skip this step: a violation then asks for its own zone.',
          key: const ValueKey('markings-count'), style: Fx.caption(context)),
    ]);
  }

  Widget _editor(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: Fx.body(context), textAlign: TextAlign.center));
    final size = _size;
    if (size == null) return const Center(child: CircularProgressIndicator());
    return RoadZoneEditor(
      frame: _frame,
      size: size,
      areas: _areas,
      markings: true,
      actions: [
        Tooltip(
          message: 'Takes a few seconds of the video from this picture on, and reads the road from how vehicles move: crosswalks, lines, '
              'lanes, the road and its direction. It shows each step.',
          child: FilledButton.tonalIcon(
            key: const ValueKey('markings-find'),
            onPressed: _starting ? null : _find,
            icon: _starting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high, size: 18),
            label: Text(_starting ? 'Starting…' : 'Find the road automatically'),
          ),
        ),
      ],
      onChanged: (areas) {
        setState(() => _areas = areas);
        _emit();
      },
    );
  }
}
