import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';

/// One thing that can be placed on the picture. [least] taps are needed; [auto] taps finish it at once (null = press Finish).
class _Tool {
  const _Tool(this.label, this.kind, this.extra, this.least, [this.auto]);
  final String label;
  final String kind;
  final Map<String, dynamic> extra;
  final int least;
  final int? auto;
}

const _tools = <_Tool>[
  _Tool('Solid white line', 'line', {'style': 'solid_white'}, 2),
  _Tool('Solid yellow line', 'line', {'style': 'solid_yellow'}, 2),
  _Tool('Double yellow line', 'line', {'style': 'double_yellow'}, 2),
  _Tool('Broken white line', 'line', {'style': 'dashed_white'}, 2),
  _Tool('Stop line', 'stop_line', {}, 2, 2),
  _Tool('Bicycle lane (green)', 'lane', {'type': 'bicycle'}, 3),
  _Tool('Bus lane (red)', 'lane', {'type': 'bus'}, 3),
  _Tool('Crosswalk (4 corners)', 'crosswalk', {}, 4, 4),
  _Tool('Stop sign', 'object', {'type': 'stop_sign'}, 1, 1),
  _Tool('No-parking sign', 'object', {'type': 'sign'}, 1, 1),
  _Tool('No-loading plate', 'object', {'type': 'no_loading'}, 1, 1),
  _Tool('No trucks sign', 'object', {'type': 'no_trucks'}, 1, 1),
  _Tool('No tricycles plate', 'object', {'type': 'no_tricycles'}, 1, 1),
  _Tool('Fire hydrant', 'object', {'type': 'hydrant'}, 1, 1),
  _Tool('Traffic light', 'object', {'type': 'traffic_light_red'}, 1, 1),
  _Tool('Sidewalk plate', 'object', {'type': 'sidewalk'}, 1, 1),
];

/// Road and traffic overlays for the whole video: road lines, coloured lanes, a crosswalk and roadside objects placed anywhere
/// on the picture. The backend paints them realistically and outlines what its road finder reads back from the picture, so the
/// operator sees at once which markings the analysis will use. Points are kept in the wizard's 1920x1080 space.
class SceneOverlayDialog extends StatefulWidget {
  const SceneOverlayDialog({super.key, required this.draft, required this.api, this.frame});

  final AnalysisDraft draft;
  final ForensicApi api;

  /// The wizard's own picture of the video: shown at once, and kept if the painted preview cannot be made.
  final ImageProvider? frame;

  @override
  State<SceneOverlayDialog> createState() => _SceneOverlayDialogState();
}

class _SceneOverlayDialogState extends State<SceneOverlayDialog> {
  int _tool = 0;
  final List<Offset> _pending = []; // taps of the item being placed, in 1920x1080 points
  Uint8List? _image;
  double _aspect = 16 / 9;
  Map<String, dynamic> _found = const {};
  bool _busy = false;
  String? _error;

  List<Map<String, dynamic>> get _items => widget.draft.sceneOverlays;

  ImageStream? _frameStream;
  ImageStreamListener? _frameListener;

  @override
  void initState() {
    super.initState();
    _watchFrame();
    _refresh();
  }

  @override
  void dispose() {
    if (_frameListener != null) _frameStream?.removeListener(_frameListener!);
    super.dispose();
  }

  /// Takes the picture's shape from the wizard's frame, so it is not stretched before the preview arrives.
  void _watchFrame() {
    final frame = widget.frame;
    if (frame == null) return;
    _frameStream = frame.resolve(ImageConfiguration.empty);
    _frameListener = ImageStreamListener((info, _) {
      if (!mounted || _image != null || info.image.height == 0) return;
      setState(() => _aspect = info.image.width / info.image.height);
    }, onError: (_, _) {});
    _frameStream!.addListener(_frameListener!);
  }

  Future<void> _refresh() async {
    final path = widget.draft.videoPath;
    if (path == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.scenePreview(path, widget.draft.trimStart, _items);
      if (!mounted) return;
      final w = (r['width'] as num?)?.toDouble() ?? 16, h = (r['height'] as num?)?.toDouble() ?? 9;
      setState(() {
        _image = base64Decode('${r['image']}');
        _aspect = h > 0 ? w / h : 16 / 9;
        _found = Map<String, dynamic>.from((r['found'] as Map?) ?? const {});
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(Offset local, Size size) {
    final tool = _tools[_tool];
    setState(() => _pending.add(Offset(local.dx / size.width * 1920, local.dy / size.height * 1080)));
    if (tool.auto != null && _pending.length >= tool.auto!) _finish();
  }

  void _finish() {
    final tool = _tools[_tool];
    if (_pending.length < tool.least) return;
    final pts = [for (final p in _pending) [double.parse(p.dx.toStringAsFixed(1)), double.parse(p.dy.toStringAsFixed(1))]];
    final item = <String, dynamic>{'kind': tool.kind, ...tool.extra};
    switch (tool.kind) {
      case 'object':
        item['at'] = pts.first;
        item['scale'] = 1.0;
      case 'lane' || 'crosswalk':
        item['polygon'] = pts;
      default:
        item['points'] = pts;
    }
    _items.add(item);
    _pending.clear();
    widget.draft.touch();
    _refresh();
  }

  void _remove(int i) {
    _items.removeAt(i);
    widget.draft.touch();
    _refresh();
  }

  String _labelOf(Map<String, dynamic> item) {
    for (final t in _tools) {
      if (t.kind == item['kind'] && t.extra.entries.every((e) => item[e.key] == e.value)) return t.label;
    }
    return '${item['kind']}';
  }

  String get _foundText {
    if (_found.isEmpty) return 'Nothing read yet.';
    int n(String k) => (_found[k] as num?)?.toInt() ?? 0;
    return 'Read from the picture: ${n('solid_lines')} solid line(s), ${n('dashed_lines')} broken line(s), '
        '${n('crosswalks')} crosswalk(s), ${n('bicycle_lanes')} bicycle lane(s), ${n('bus_lanes')} bus lane(s), '
        '${n('stop_lines')} stop line(s).';
  }

  @override
  Widget build(BuildContext context) {
    final tool = _tools[_tool];
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1280,
        height: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _aspect,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final size = Size(box.maxWidth, box.maxHeight);
                        return GestureDetector(
                          key: const ValueKey('scene-overlay-picture'),
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _tap(d.localPosition, size),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_image != null)
                                Image.memory(_image!, fit: BoxFit.fill, gaplessPlayback: true)
                              else if (widget.frame != null)
                                Image(image: widget.frame!, fit: BoxFit.fill, gaplessPlayback: true)
                              else
                                const ColoredBox(color: Colors.black26),
                              CustomPaint(painter: _PendingPainter(_pending)),
                              if (_error != null)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Material(
                                    color: theme.colorScheme.errorContainer,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(child: Text('Preview failed: $_error', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
                                          TextButton(key: const ValueKey('scene-retry'), onPressed: _busy ? null : _refresh, child: const Text('Retry')),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (_busy) const Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Road overlays', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Pick one, then click on the picture. The thin outlines show what the system reads back.', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var i = 0; i < _tools.length; i++)
                              ChoiceChip(
                                key: ValueKey('scene-tool-$i'),
                                label: Text(_tools[i].label),
                                selected: _tool == i,
                                onSelected: (_) => setState(() {
                                  _tool = i;
                                  _pending.clear();
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tool.auto != null
                          ? 'Click ${tool.auto} point(s): ${_pending.length} of ${tool.auto}.'
                          : 'Click ${tool.least} or more points, then press Finish: ${_pending.length} placed.',
                      style: theme.textTheme.bodySmall,
                    ),
                    Row(
                      children: [
                        FilledButton(
                          key: const ValueKey('scene-finish'),
                          onPressed: tool.auto == null && _pending.length >= tool.least ? _finish : null,
                          child: const Text('Finish'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: _pending.isEmpty ? null : () => setState(_pending.removeLast), child: const Text('Undo point')),
                      ],
                    ),
                    const Divider(),
                    Text(_error ?? _foundText, style: theme.textTheme.bodySmall?.copyWith(color: _error != null ? theme.colorScheme.error : null)),
                    const Divider(),
                    Expanded(
                      flex: 4,
                      child: ListView(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${i + 1}. ${_labelOf(_items[i])}'),
                              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: 'Remove', onPressed: () => _remove(i)),
                            ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The taps of the item being placed: dots joined by a line.
class _PendingPainter extends CustomPainter {
  _PendingPainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final shown = [for (final p in points) Offset(p.dx / 1920 * size.width, p.dy / 1080 * size.height)];
    final line = Paint()
      ..color = const Color(0xFFFFEB3B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < shown.length; i++) {
      canvas.drawLine(shown[i - 1], shown[i], line);
    }
    final dot = Paint()..color = const Color(0xFFFF5722);
    for (final p in shown) {
      canvas.drawCircle(p, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _PendingPainter old) => true;
}
