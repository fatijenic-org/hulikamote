import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../forensic/data/forensic_api.dart';
import '../../../forensic/data/object_previews.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/domain/zone_geometry.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';
import '../../domain/models/road_detect.dart';
import '../../domain/models/road_preset.dart';
import '../../domain/road_markings.dart';
import 'road_detect_view.dart';
import 'road_zone_editor.dart';
import 'road_pick_dialog.dart';
import 'saved_roads_dialog.dart';

/// The "Road" step of the live setup: the road is marked ONCE, on the setup picture, with the same editor as "Detect road" (many points,
/// zoom): crosswalks, solid lines, stop lines, lanes (with a type and a direction), roads (with a kind and a direction) and sidewalks.
/// Each violation that is picked in the next step then takes only the markings it needs (see [RoadMarkingMap]).
///
/// "Find the road automatically" shows the walkthrough of Detect road (step by step, on a few seconds of the video that start at the
/// setup picture); "Use these" puts what it found in the editor, where it can be corrected.
///
/// Every change is reported to [onChanged] at once, in the 1920x1080 reference space (the step has no save button).
class RoadMarkingsPanel extends StatefulWidget {
  const RoadMarkingsPanel({super.key, required this.cameraApi, required this.markings, required this.onChanged, this.api, this.videoHash, this.videoName});

  /// The fingerprint and name of the video in use: roads saved for it are offered at once, and a road saved now is tied to it.
  final String? videoHash;
  final String? videoName;

  final CameraApi cameraApi;

  /// Draws the road paint (a painted solid line) as the evidence photos will show it. Without it a painted line is a coloured stroke.
  final ForensicApi? api;

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
  String? _presetId;                 // the saved road the setup follows (used or saved last), if any
  String? _presetName;

  late final ObjectPreviews _previews = ObjectPreviews(widget.api);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previews.dispose();
    super.dispose();
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
      if (_areas.isEmpty) _suggest();                          // nothing marked yet: a road saved for this video is offered
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Back to the reference space, and on to the setup. A marking the finder found keeps its 'auto-' name; the others get plain numbers.
  void _emit() => widget.onChanged(_refAreas());

  List<RoadArea> _refAreas() {
    final size = _size;
    if (size == null) return const [];
    final fx = ZoneGeometry.refWidth / size.width, fy = ZoneGeometry.refHeight / size.height;
    var n = 0;
    return [for (final a in _areas) a.scaled(fx, fy).withId(a.id.startsWith('auto-') ? a.id : 'm${++n}')];
  }

  /// A road saved for THIS video (same fingerprint) opens a pop-up with the saved roads in a drop-down and a preview. Once per video.
  Future<void> _suggest() async {
    final hash = widget.videoHash;
    if (hash == null) return;
    try {
      final all = await widget.cameraApi.roadPresets(hash: hash);
      if (!mounted || !all.any((p) => p.match)) return;
      await _pick(all, suggested: true);
    } catch (_) {
      // no suggestion then: the road is marked by hand, or "Saved roads" is used
    }
  }

  /// The pop-up: the saved roads in a drop-down (this video's first), the chosen one previewed on the setup picture.
  Future<void> _pick(List<RoadPreset>? known, {bool suggested = false}) async {
    List<RoadPreset> all;
    try {
      all = known ?? await widget.cameraApi.roadPresets(hash: widget.videoHash);
    } catch (e) {
      if (mounted) setState(() => _notice = '$e'.replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    if (all.isEmpty) {
      setState(() => _notice = 'No saved roads yet. Mark the road, then use "Saved roads" to keep it.');
      return;
    }
    final picked = await showDialog<RoadPick>(
      context: context,
      builder: (_) => RoadPickDialog(api: widget.cameraApi, presets: all, frame: _frame, size: _size, suggested: suggested),
    );
    final size = _size;
    if (picked == null || !mounted || size == null) return;
    final fx = size.width / ZoneGeometry.refWidth, fy = size.height / ZoneGeometry.refHeight;
    setState(() {
      _presetId = picked.id;
      _presetName = picked.name;
      _areas = [for (final m in picked.markings) m.scaled(fx, fy)];
    });
    _emit();
  }

  /// "Saved roads": save the road, use a saved one, duplicate, rename, delete.
  Future<void> _openSaved() async {
    final result = await showDialog<SavedRoadsResult>(
      context: context,
      builder: (_) => SavedRoadsDialog(
        api: widget.cameraApi,
        current: _refAreas(),
        loadedId: _presetId,
        loadedName: _presetName,
        videoHash: widget.videoHash,
        videoName: widget.videoName,
      ),
    );
    if (result == null || !mounted) return;
    final size = _size;
    setState(() {
      _presetId = result.loadedId;
      _presetName = result.loadedName;
      if (result.markings != null && size != null) {
        final fx = size.width / ZoneGeometry.refWidth, fy = size.height / ZoneGeometry.refHeight;
        _areas = [for (final m in result.markings!) m.scaled(fx, fy)];
      }
    });
    if (result.markings != null) _emit();
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
      if (_notice != null) ...[
        FxBanner(key: const ValueKey('markings-notice'), message: _notice!, color: Fx.warning, icon: Icons.info_outline),
        const SizedBox(height: Fx.s8),
      ],
      Expanded(child: _editor(context)),
      const SizedBox(height: Fx.s8),
      Text(
        '${_areas.length} marking${_areas.length == 1 ? '' : 's'}${_presetName == null ? '' : ' · saved road: $_presetName'}',
        key: const ValueKey('markings-count'),
        style: Fx.caption(context),
      ),
    ]);
  }

  /// What the markings are for (the hover note): which marking feeds which violation.
  static String get _uses => 'Mark the road once, on this picture. Each violation you pick next takes only what it needs:\n'
      '${[for (final (marking, key) in RoadMarkingMap.uses) '$marking → ${ViolationCatalog.of(key).label}'].join('\n')}\n'
      'You can skip this step: a violation then asks for its own zone.';

  Widget _editor(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!, style: Fx.body(context), textAlign: TextAlign.center));
    final size = _size;
    if (size == null) return const Center(child: CircularProgressIndicator());
    return RoadZoneEditor(
      previews: _previews,
      frame: _frame,
      size: size,
      areas: _areas,
      markings: true,
      actions: [
        Tooltip(
          message: _uses,
          child: const Icon(Icons.info_outline, size: 18),
        ),
        OutlinedButton.icon(
          key: const ValueKey('pick-road-button'),
          onPressed: () => _pick(null),
          icon: const Icon(Icons.preview_outlined, size: 18),
          label: const Text('Pick a saved road'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('saved-roads-button'),
          onPressed: _openSaved,
          icon: const Icon(Icons.bookmarks_outlined, size: 18),
          label: const Text('Saved roads'),
        ),
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
