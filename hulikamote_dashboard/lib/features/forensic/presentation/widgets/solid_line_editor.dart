import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_api.dart';
import '../../data/object_previews.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/line_paint.dart';
import '../../domain/violation_catalog.dart';
import '../../domain/zone_geometry.dart';
import 'fx.dart';
import 'violation_params.dart';

/// Draws the solid lines of "Crossing a solid line" on the first frame of the video.
///
/// Nothing here is required: when no line is drawn, the painted solid lines are found in the video when the analysis starts
/// (the switch below, on by default). Drawing is for choosing the lines yourself, or for a curve the finder cannot follow.
///
/// A line is two or more points, so it can follow a curve or a corner. Every saved line is one entry of the draft's zones,
/// `{'line': [[x, y], ...]}` in the 1920x1080 reference space, so a road can have as many lines as it has. A line is bent
/// by dragging a point, or by dragging the middle of a piece (that adds a point); a right-click removes a point.
class SolidLineEditor extends StatefulWidget {
  const SolidLineEditor({
    super.key,
    required this.draft,
    required this.violationKey,
    required this.frame,
    this.api,
  });

  final AnalysisDraft draft;
  final String violationKey;
  final ImageProvider frame;

  /// Lets the editor preview what the automatic search finds (and edit it).
  final ForensicApi? api;

  @override
  State<SolidLineEditor> createState() => _SolidLineEditorState();
}

/// A point being dragged: which list it lives in and, for a saved line, the zone to write the result back to.
class _Drag {
  _Drag(this.points, this.index, [this.zone]);
  final List<Offset> points;
  final int index;
  final Map<String, dynamic>? zone;
}

class _SolidLineEditorState extends State<SolidLineEditor> {
  final List<Offset> _line = []; // the line being drawn, 0..1 canvas coordinates
  _Drag? _drag;
  double _aspect = 16 / 9;
  String? _notice;
  bool _finding = false;
  int? _selLine; // the saved line whose paint is being set
  late final ObjectPreviews _previews;
  final Map<int, ObjectPreview> _lastPaint = {}; // the last picture of each line's paint, kept while a new one is on its way
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get key => widget.violationKey;
  ViolationInfo get info => ViolationCatalog.of(key);
  Map<String, dynamic> get _cfg => widget.draft.config(key);
  bool get _auto => widget.draft.findsLinesItself(key);

  List<Map<String, dynamic>> get _saved => widget.draft.zones(key).cast<Map<String, dynamic>>();

  /// A saved line's points, in 0..1. (Older drawings stored the two points as `ui_vector`.)
  List<Offset> _pointsOf(Map<String, dynamic> zone) =>
      ZoneGeometry.fromReference((zone['line'] ?? zone['ui_vector'] ?? const []) as List);

  void _write(Map<String, dynamic> zone, List<Offset> points) {
    zone['line'] = ZoneGeometry.toReference(points);
    zone.remove('ui_vector');
  }

  @override
  void initState() {
    super.initState();
    _previews = ObjectPreviews(widget.api)..addListener(_previewReady);
    _resolveAspect();
  }

  void _previewReady() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SolidLineEditor old) {
    super.didUpdateWidget(old);
    if (old.frame != widget.frame) _resolveAspect();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _previews.dispose();
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

  bool _onAHandle(Offset local, Size size) {
    if (ZoneGeometry.hit(_line, local, size) != null) return true;
    return _saved.any((z) => ZoneGeometry.hit(_pointsOf(z), local, size) != null);
  }

  void _tap(Offset local, Size size) {
    if (_onAHandle(local, size)) return; // a tap on a handle is not a new point
    setState(() {
      _notice = null;
      _line.add(_norm(local, size));
    });
  }

  /// A point to drag: a handle of the line being drawn or of a saved line; else the middle of a piece of one (that adds a
  /// point there, which is how a line is bent).
  _Drag? _grab(Offset local, Size size) {
    final own = ZoneGeometry.hit(_line, local, size);
    if (own != null) return _Drag(_line, own);
    for (var n = _saved.length - 1; n >= 0; n--) {
      final points = _pointsOf(_saved[n]);
      final i = ZoneGeometry.hit(points, local, size);
      if (i != null) return _Drag(points, i, _saved[n]);
    }
    final piece = ZoneGeometry.nearSegment(_line, local, size);
    if (piece != null) {
      _line.insert(piece.segment + 1, piece.point);
      return _Drag(_line, piece.segment + 1);
    }
    for (var n = _saved.length - 1; n >= 0; n--) {
      final points = _pointsOf(_saved[n]);
      final bend = ZoneGeometry.nearSegment(points, local, size);
      if (bend != null) {
        points.insert(bend.segment + 1, bend.point);
        _write(_saved[n], points);
        return _Drag(points, bend.segment + 1, _saved[n]);
      }
    }
    return null;
  }

  void _removeAt(Offset local, Size size) {
    final own = ZoneGeometry.hit(_line, local, size);
    if (own != null) {
      setState(() => _line.removeAt(own));
      return;
    }
    for (final zone in _saved) {
      final points = _pointsOf(zone);
      final i = ZoneGeometry.hit(points, local, size);
      if (i == null) continue;
      if (points.length <= 2) {
        setState(() => _notice = 'A line needs at least 2 points. Use the bin to delete the whole line.');
        return;
      }
      points.removeAt(i);
      _write(zone, points);
      widget.draft.touch();
      setState(() => _notice = null);
      return;
    }
    if (_line.isNotEmpty) setState(_line.removeLast);
  }

  // ── actions ──
  void _undoPoint() {
    if (_line.isNotEmpty) setState(_line.removeLast);
  }

  void _clearLine() => setState(() {
    _line.clear();
    _notice = null;
  });

  void _saveLine() {
    if (_line.length < 2) return;
    widget.draft.zones(key).add({'line': ZoneGeometry.toReference(_line)});
    widget.draft.touch();
    setState(() {
      _line.clear();
      _notice = 'Line saved. Draw another one, or continue.';
    });
  }

  void _deleteLine(int i) {
    widget.draft.zones(key).removeAt(i);
    widget.draft.touch();
    setState(() {
      _notice = null;
      _lastPaint.clear();
      final s = _selLine;
      if (s != null) _selLine = s == i ? null : (s > i ? s - 1 : s);
    });
  }

  /// The paint of each saved line (null for a line that is not painted), as the backend draws it. While the line is being dragged the last
  /// picture stays where it was.
  List<ObjectPreview?> _paints() {
    final realistic = (_cfg['lines_realistic'] as bool?) ?? true;
    final out = <ObjectPreview?>[];
    for (var i = 0; i < _saved.length; i++) {
      final zone = _saved[i];
      final look = zone['look'];
      if (look is! Map) {
        out.add(null);
        continue;
      }
      final raw = (zone['line'] ?? zone['ui_vector'] ?? const []) as List;
      final points = [for (final p in raw) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]];
      final fresh = _drag == null && points.length >= 2 ? _previews.peekLine(points, Map<String, dynamic>.from(look), realistic) : null;
      if (fresh != null) _lastPaint[i] = fresh;
      out.add(fresh ?? _lastPaint[i]);
    }
    return out;
  }

  /// Style, width, wear, perspective, turn and filmed look of the selected painted line.
  Widget _paintLook(BuildContext context) {
    final i = _selLine!;
    final zone = _saved[i];
    final look = zone['look'] as Map<String, dynamic>;
    void set(String k, Object v) {
      look[k] = v;
      widget.draft.touch();
      setState(() {});
    }

    void turn(double degrees) {
      _write(zone, LinePaint.rotated(_pointsOf(zone), degrees));
      widget.draft.touch();
      setState(() {});
    }

    Widget slider(String k, String label, double value, double min, double max, String shown, String field) => Row(
      children: [
        SizedBox(width: 74, child: Text(label, style: Fx.caption(context))),
        Expanded(child: Slider(key: ValueKey(k), value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: (v) => set(field, v))),
        SizedBox(width: 46, child: Text(shown, key: ValueKey('$k-value'), textAlign: TextAlign.end, style: Fx.caption(context))),
      ],
    );
    final width = LinePaint.widthOf(look), wear = LinePaint.wearOf(look), taper = LinePaint.taperOf(look);
    return Column(
      key: const ValueKey('solid-paint-look'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Fx.s8),
        Text('PAINT OF LINE ${i + 1}', style: Fx.label(context)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in LinePaint.styles)
              ChoiceChip(
                key: ValueKey('solid-style-${s.$1}'),
                label: Text(s.$2),
                selected: LinePaint.styleOf(look) == s.$1,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => set('style', s.$1),
              ),
          ],
        ),
        slider('solid-width', 'Width', width, LinePaint.minWidth, LinePaint.maxWidth, '${(width * 100).round()}%', 'width'),
        slider('solid-wear', 'Worn', wear, 0, 1, '${(wear * 100).round()}%', 'wear'),
        slider('solid-taper', 'Perspective', taper, 0, 1, '${(taper * 100).round()}%', 'taper'),
        Row(
          children: [
            SizedBox(width: 74, child: Text('Turn line', style: Fx.caption(context))),
            IconButton(key: const ValueKey('solid-rotate-left'), tooltip: 'Turn 5 degrees counter-clockwise', icon: const Icon(Icons.rotate_left, size: 20), onPressed: () => turn(-5)),
            IconButton(key: const ValueKey('solid-rotate-right'), tooltip: 'Turn 5 degrees clockwise', icon: const Icon(Icons.rotate_right, size: 20), onPressed: () => turn(5)),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text('Realistic look', style: Fx.body(context))),
            Switch(
              key: const ValueKey('solid-realistic'),
              value: (_cfg['lines_realistic'] as bool?) ?? true,
              onChanged: (v) {
                _cfg['lines_realistic'] = v;
                widget.draft.touch();
                setState(() {});
              },
            ),
          ],
        ),
        Text(
          'The paint is only a picture of the line. The rule uses the line itself, and vehicles drive over the paint.',
          style: Fx.caption(context),
        ),
      ],
    );
  }

  void _setAuto(bool on) {
    _cfg['auto_lines'] = on;
    widget.draft.touch();
    setState(() {});
  }

  bool get _canFind => widget.api != null && widget.draft.videoPath != null;

  /// Runs the same search the analysis would run and adds what it finds as ordinary lines, to check and fix by hand.
  Future<void> _findLines() async {
    final api = widget.api;
    final path = widget.draft.videoPath;
    if (api == null || path == null) return;
    setState(() {
      _finding = true;
      _notice = null;
    });
    try {
      final result = await api.roadMarkings(path);
      final found = ((result['zones'] as Map?)?[key] as List?) ?? const [];
      if (!mounted) return;
      var added = 0;
      for (final z in found) {
        final line = (z as Map)['ui_vector'] ?? z['line'];
        if (line is List && line.length >= 2) {
          widget.draft.zones(key).add({'line': line});
          added++;
        }
      }
      widget.draft.touch();
      setState(() {
        _finding = false;
        _notice = added == 0
            ? (result['message'] as String? ?? 'No painted solid line was found. Draw it by hand.')
            : 'Added $added line${added == 1 ? '' : 's'} found from the paint. Check each one on the picture; drag a point to fix it, or delete it.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finding = false;
        _notice = 'Could not look for the painted lines: $e';
      });
    }
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth >= 780 && box.hasBoundedHeight;
        final canvas = _canvasCard(context);
        final panel = _panel(context);
        if (side) {
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
    final saved = [for (final z in _saved) _pointsOf(z)];
    final paints = _paints();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.backspace || e.logicalKey == LogicalKeyboardKey.delete) {
          _undoPoint();
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.enter && _line.length >= 2) {
          _saveLine();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, outer) {
          var w = outer.maxWidth;
          if (outer.hasBoundedHeight && w / _aspect > outer.maxHeight) w = outer.maxHeight * _aspect;
          return SizedBox(
            width: w,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radius),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Fx.accent, width: 2),
                  borderRadius: BorderRadius.circular(Fx.radius),
                ),
                child: AspectRatio(
                  aspectRatio: _aspect,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = box.biggest;
                      return MouseRegion(
                        cursor: SystemMouseCursors.precise,
                        child: GestureDetector(
                          key: const ValueKey('solid-canvas'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down, // grab the point under the finger / cursor, not where the slop ended
                          onTapUp: (d) => _tap(d.localPosition, size),
                          onSecondaryTapUp: (d) => _removeAt(d.localPosition, size),
                          onPanStart: (d) => setState(() => _drag = _grab(d.localPosition, size)),
                          onPanUpdate: (d) {
                            final drag = _drag;
                            if (drag == null) return;
                            setState(() {
                              drag.points[drag.index] = _norm(d.localPosition, size);
                              if (drag.zone != null) _write(drag.zone!, drag.points);
                            });
                          },
                          onPanEnd: (_) => _endDrag(),
                          onPanCancel: _endDrag,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image(image: widget.frame, fit: BoxFit.fill, gaplessPlayback: true),
                              CustomPaint(painter: _LinesPainter(saved: saved, current: List.of(_line), paints: paints)),
                              if (_line.isEmpty && saved.isEmpty)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.all(12),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(Fx.radiusSm)),
                                    child: Text(
                                      _auto
                                          ? 'Nothing to draw: the solid lines are found for you. Click along a line only to choose it yourself.'
                                          : 'Click along the solid line. Add a point at every bend.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
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
      ),
    );
  }

  void _endDrag() {
    final drag = _drag;
    _drag = null;
    if (drag?.zone != null) widget.draft.touch();
  }

  Widget _panel(BuildContext context) {
    final saved = _saved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(info.icon, size: 18, color: info.color),
                  const SizedBox(width: Fx.s8),
                  Expanded(child: Text(info.label, style: Fx.heading(context))),
                ],
              ),
              const SizedBox(height: 4),
              Text(info.zoneHint, style: Fx.caption(context)),
            ],
          ),
        ),
        const SizedBox(height: Fx.s12),
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Find the solid lines automatically', style: Fx.body(context).copyWith(fontWeight: FontWeight.w600))),
                  Switch(key: const ValueKey('solid-auto'), value: _auto, onChanged: _setAuto),
                ],
              ),
              Text(
                'Skip the drawing. When no line is drawn, the painted solid lines are found in the video when the analysis starts '
                '(a fixed camera and some traffic are needed). It finds straight lines only: draw a curve yourself. '
                'A line you draw is used instead.',
                style: Fx.caption(context),
              ),
              if (_canFind) ...[
                const SizedBox(height: Fx.s8),
                OutlinedButton.icon(
                  key: const ValueKey('solid-find'),
                  onPressed: _finding ? null : _findLines,
                  icon: _finding
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high, size: 18),
                  label: Text(_finding ? 'Looking at the video...' : 'Show what it finds (can take a minute)'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Fx.s12),
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DRAW A LINE (OPTIONAL)', style: Fx.label(context)),
              const SizedBox(height: Fx.s8),
              Text(
                _line.isEmpty
                    ? 'Click along the solid line. Add a point at every bend. At least 2 points.'
                    : '${_line.length} point${_line.length == 1 ? '' : 's'}${_line.length < 2 ? ', at least 2' : ': keep clicking along the line, or save it'}',
                key: const ValueKey('solid-count'),
                style: Fx.body(context),
              ),
              const SizedBox(height: Fx.s8),
              Wrap(
                spacing: Fx.s8,
                runSpacing: Fx.s8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('solid-undo'),
                    onPressed: _line.isEmpty ? null : _undoPoint,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Undo point'),
                  ),
                  TextButton(key: const ValueKey('solid-clear'), onPressed: _line.isEmpty ? null : _clearLine, child: const Text('Clear')),
                ],
              ),
              const SizedBox(height: Fx.s8),
              FilledButton.icon(
                key: const ValueKey('solid-save'),
                onPressed: _line.length >= 2 ? _saveLine : null,
                icon: const Icon(Icons.add_road, size: 18),
                label: const Text('Save this line'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
              if (_notice != null) ...[
                const SizedBox(height: Fx.s8),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Fx.accent),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_notice!, key: const ValueKey('solid-notice'), style: Fx.caption(context).copyWith(color: Fx.accent))),
                  ],
                ),
              ],
              const SizedBox(height: Fx.s8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Drag a point to move it. Drag the middle of a line to bend it.', style: Fx.caption(context)),
                  const KeyCap('Right-click'),
                  Text('removes a point', style: Fx.caption(context)),
                  const KeyCap('Backspace'),
                  Text('undoes', style: Fx.caption(context)),
                ],
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
              Text('SAVED LINES (${saved.length})', style: Fx.label(context)),
              const SizedBox(height: Fx.s8),
              if (saved.isEmpty)
                Row(
                  children: [
                    Icon(_auto ? Icons.auto_fix_high : Icons.error_outline, size: 16, color: _auto ? Fx.success : Fx.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _auto
                            ? 'No line drawn: the painted solid lines are found in the video when the analysis starts.'
                            : 'No line drawn and the automatic search is off: draw a line, or turn it on, to continue.',
                        key: const ValueKey('solid-empty'),
                        style: Fx.caption(context),
                      ),
                    ),
                  ],
                )
              else
                for (var i = 0; i < saved.length; i++)
                  InkWell(
                    key: ValueKey('solid-select-$i'),
                    borderRadius: BorderRadius.circular(Fx.radiusSm),
                    onTap: () => setState(() => _selLine = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selLine == i ? Fx.accent.withValues(alpha: 0.12) : null,
                        borderRadius: BorderRadius.circular(Fx.radiusSm),
                      ),
                      child: Row(
                        key: ValueKey('solid-saved-$i'),
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: Fx.success),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Line ${i + 1}  ·  ${_pointsOf(saved[i]).length} points', style: Fx.body(context), overflow: TextOverflow.ellipsis)),
                          Tooltip(
                            message: 'Paint this line on the picture (for testing)',
                            child: Switch(
                              key: ValueKey('solid-paint-$i'),
                              value: saved[i]['look'] is Map,
                              onChanged: (on) => setState(() {
                                if (on) {
                                  saved[i]['look'] = LinePaint.newLook();
                                  _selLine = i;
                                } else {
                                  saved[i].remove('look');
                                  _lastPaint.remove(i);
                                }
                                widget.draft.touch();
                              }),
                            ),
                          ),
                          IconButton(
                            key: ValueKey('solid-delete-$i'),
                            tooltip: 'Delete line ${i + 1}',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteLine(i),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (_selLine != null && _selLine! < saved.length && saved[_selLine!]['look'] is Map) _paintLook(context),
            ],
          ),
        ),
        const SizedBox(height: Fx.s16),
        ViolationParams(draft: widget.draft, violationKey: key, onChanged: () => setState(() {})),
      ],
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({required this.saved, required this.current, this.paints = const []});

  final List<List<Offset>> saved;
  final List<Offset> current;

  /// The paint of each saved line as the backend drew it (null: not painted, or still on its way).
  final List<ObjectPreview?> paints;

  Offset _px(Offset n, Size s) => Offset(n.dx * s.width, n.dy * s.height);

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, shadows: const [Shadow(blurRadius: 3)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _draw(Canvas canvas, List<Offset> points, Size size, Color color, {String? label, bool numbered = false}) {
    if (points.isEmpty) return;
    final px = [for (final p in points) _px(p, size)];
    if (px.length >= 2) {
      final path = Path()..moveTo(px.first.dx, px.first.dy);
      for (final p in px.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i + 1 < px.length; i++) {
        // the middle of each piece: drag it to bend the line there
        final mid = Offset.lerp(px[i], px[i + 1], 0.5)!;
        canvas.drawCircle(mid, 4, Paint()..color = Colors.white.withValues(alpha: 0.75));
        canvas.drawCircle(mid, 4, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }
    for (var i = 0; i < px.length; i++) {
      canvas.drawCircle(px[i], 7, Paint()..color = Colors.black87);
      canvas.drawCircle(px[i], 6, Paint()..color = color);
      if (numbered) _label(canvas, '${i + 1}', px[i] + const Offset(0, -14), Colors.white);
    }
    if (label != null) _label(canvas, label, px.first + const Offset(0, 16), Colors.white);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / ZoneGeometry.refWidth; // the paint was made for a frame 1920 wide
    for (final p in paints) {
      if (p == null) continue;
      canvas.drawImageRect(
        p.image,
        Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble()),
        Rect.fromLTWH(p.dx * k, p.dy * k, p.image.width * k, p.image.height * k),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    for (var i = 0; i < saved.length; i++) {
      _draw(canvas, saved[i], size, Fx.success, label: 'Line ${i + 1}');
    }
    _draw(canvas, current, size, Fx.accent, numbered: true);
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}
