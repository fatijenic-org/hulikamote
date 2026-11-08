import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/violation_catalog.dart';
import '../../domain/zone_geometry.dart';
import 'fx.dart';
import 'violation_params.dart';

enum ZoneTool { zone, arrow, light }

/// Draws the zones of one violation on the first frame of the video.
///
/// Points live in 0..1 canvas coordinates, so the drawing survives any window size, and are
/// stored in the 1920x1080 reference space the backend expects. The canvas keeps the frame's
/// own aspect ratio. Tools are explicit modes with a checklist, saved zones can be deleted.
class ZoneEditor extends StatefulWidget {
  const ZoneEditor({
    super.key,
    required this.draft,
    required this.violationKey,
    required this.frame,
    this.api,
  });

  final AnalysisDraft draft;
  final String violationKey;
  final ImageProvider frame;

  /// Lets the editor look for the painted lines of the video (stop line, crosswalk, solid line) and suggest zones.
  final ForensicApi? api;

  @override
  State<ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<ZoneEditor> {
  final List<Offset> _poly = [];
  final List<Offset> _arrow = [];
  final List<Offset> _light = [];
  ZoneTool _tool = ZoneTool.zone;
  String _sign = 'no_entry';
  int? _drag;
  double _aspect = 16 / 9;
  String? _notice;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get key => widget.violationKey;
  ViolationInfo get info => ViolationCatalog.of(key);
  bool get _isSigns => key == 'disregarding_signs';
  Map<String, dynamic> get _cfg => widget.draft.config(key);

  /// The zone also needs an arrow (or stop line).
  bool get needsArrow =>
      ViolationCatalog.arrowViolations.contains(key) ||
      (_isSigns && (ViolationCatalog.signs[_sign]?.arrow ?? false));
  bool get needsLight => key == 'red_light' && _cfg['light_mode'] == 'camera';

  /// The two points are a LINE (stop line, solid line), not an arrow.
  bool get _drawsLine =>
      ViolationCatalog.lineViolations.contains(key) ||
      (_isSigns && _sign == 'stop');

  String get arrowName {
    if (key == 'crossing_solid_line') return 'solid line';
    if (_drawsLine) return 'stop line';
    if (key == 'illegal_turn' || (_isSigns && _sign == 'no_turn')) {
      return 'prohibited-turn arrow';
    }
    if (_isSigns) return 'no-entry direction arrow';
    return 'legal-flow arrow';
  }

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  @override
  void didUpdateWidget(ZoneEditor old) {
    super.didUpdateWidget(old);
    if (old.violationKey != widget.violationKey) _resetDrawing();
    if (old.frame != widget.frame) _resolveAspect();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _resolveAspect() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = widget.frame.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      final a = info.image.width / info.image.height;
      if (mounted && a.isFinite && a > 0.3 && a < 4) {
        setState(() => _aspect = a);
      }
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  /// The rules whose zones can be suggested from the painted lines of the video.
  static const _findable = {'crossing_solid_line', 'red_light', 'pedestrian_lane'};
  bool _finding = false;

  bool get _canFindLines => widget.api != null && widget.draft.videoPath != null && _findable.contains(key);

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
      for (final z in found) {
        widget.draft.zones(key).add(Map<String, dynamic>.from(z as Map));
      }
      widget.draft.touch();
      setState(() {
        _finding = false;
        _notice = found.isEmpty
            ? (result['message'] as String? ?? 'No painted line of this kind was found. Draw it by hand.')
            : 'Added ${found.length} suggested zone${found.length == 1 ? '' : 's'}. Check each one on the picture and delete the wrong ones.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finding = false;
        _notice = 'Could not look for the painted lines: $e';
      });
    }
  }

  void _resetDrawing() {
    _poly.clear();
    _arrow.clear();
    _light.clear();
    _tool = ZoneTool.zone;
    _drag = null;
    _notice = null;
  }

  List<Offset> _pointsOf(ZoneTool t) => switch (t) {
    ZoneTool.zone => _poly,
    ZoneTool.arrow => _arrow,
    ZoneTool.light => _light,
  };

  bool get _complete =>
      _poly.length >= 3 &&
      (!needsArrow || _arrow.length == 2) &&
      (!needsLight || _light.length == 2);

  // ── canvas input ──
  Offset _norm(Offset p, Size s) => Offset(
    (p.dx / s.width).clamp(0.0, 1.0),
    (p.dy / s.height).clamp(0.0, 1.0),
  );

  void _tap(Offset local, Size size) {
    final pts = _pointsOf(_tool);
    if (ZoneGeometry.hit(pts, local, size) != null) {
      return; // a tap on a handle is not a new point
    }
    setState(() {
      _notice = null;
      if (_tool != ZoneTool.zone && pts.length >= 2) {
        pts.clear(); // a third click restarts the arrow / box
      }
      pts.add(_norm(local, size));
      if (_tool == ZoneTool.zone &&
          _poly.length == 3 &&
          needsArrow &&
          _arrow.isEmpty) {
        _notice = 'Zone ready. Now draw the $arrowName.';
      }
    });
  }

  void _removeAt(Offset local, Size size) {
    final pts = _pointsOf(_tool);
    final i =
        ZoneGeometry.hit(pts, local, size) ??
        (pts.isEmpty ? null : pts.length - 1);
    if (i != null) setState(() => pts.removeAt(i));
  }

  // ── actions ──
  void _undoPoint() {
    final pts = _pointsOf(_tool);
    if (pts.isNotEmpty) setState(pts.removeLast);
  }

  void _clearActive() => setState(() {
    _pointsOf(_tool).clear();
    _notice = null;
  });

  void _save() {
    if (!_complete) return;
    final zone = <String, dynamic>{'polygon': ZoneGeometry.toReference(_poly)};
    if (needsArrow) {
      zone['vector'] = ZoneGeometry.vectorOf(_arrow[0], _arrow[1]);
      zone['ui_vector'] = ZoneGeometry.toReference(_arrow);
    }
    if (needsLight) zone['ui_light_box'] = ZoneGeometry.toReference(_light);
    if (_isSigns) zone['sign'] = _sign;
    widget.draft.zones(key).add(zone);
    widget.draft.touch();
    setState(() {
      _resetDrawing();
      _notice = 'Zone saved.';
    });
  }

  void _deleteZone(int i) {
    widget.draft.zones(key).removeAt(i);
    widget.draft.touch();
    setState(() => _notice = null);
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
          // Side by side: the canvas takes the largest 16:9-ish box that fits, the panel scrolls on its own.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(alignment: Alignment.topCenter, child: canvas),
              ),
              const SizedBox(width: Fx.s16),
              SizedBox(width: 340, child: SingleChildScrollView(child: panel)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            canvas,
            const SizedBox(height: Fx.s16),
            panel,
          ],
        );
      },
    );
  }

  Widget _canvasCard(BuildContext context) {
    final saved = widget.draft.zones(key).cast<Map<String, dynamic>>();
    final color = switch (_tool) {
      ZoneTool.zone => Fx.danger,
      ZoneTool.arrow => Fx.accent,
      ZoneTool.light => Fx.warning,
    };
    return Focus(
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.backspace ||
                e.logicalKey == LogicalKeyboardKey.delete)) {
          _undoPoint();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, outer) {
          // Largest box of the frame's aspect ratio that fits the space we were given.
          var w = outer.maxWidth;
          if (outer.hasBoundedHeight && w / _aspect > outer.maxHeight) {
            w = outer.maxHeight * _aspect;
          }
          return SizedBox(
            width: w,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radius),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2),
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
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _tap(d.localPosition, size),
                          onSecondaryTapUp: (d) =>
                              _removeAt(d.localPosition, size),
                          onPanStart: (d) => _drag = ZoneGeometry.hit(
                            _pointsOf(_tool),
                            d.localPosition,
                            size,
                          ),
                          onPanUpdate: (d) {
                            final i = _drag;
                            if (i == null) return;
                            setState(
                              () => _pointsOf(_tool)[i] = _norm(
                                d.localPosition,
                                size,
                              ),
                            );
                          },
                          onPanEnd: (_) => _drag = null,
                          onPanCancel: () => _drag = null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image(
                                image: widget.frame,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: _ZonePainter(
                                  saved: saved,
                                  poly: List.of(_poly),
                                  arrow: List.of(_arrow),
                                  light: List.of(_light),
                                  tool: _tool,
                                  stopLine: _drawsLine,
                                ),
                              ),
                              if (_poly.isEmpty && saved.isEmpty)
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(
                                        Fx.radiusSm,
                                      ),
                                    ),
                                    child: const Text(
                                      'Click the corners of the area to draw the zone',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
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

  Widget _panel(BuildContext context) {
    final saved = widget.draft.zones(key);
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
              if (_isSigns) ...[
                const SizedBox(height: Fx.s12),
                Text('SIGN FOR THIS ZONE', style: Fx.label(context)),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _sign,
                  items: [
                    for (final e in ViolationCatalog.signs.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value.label),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _sign = v!;
                    _arrow.clear();
                    if (_tool == ZoneTool.arrow && !needsArrow) {
                      _tool = ZoneTool.zone;
                    }
                  }),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Fx.s12),
        if (_canFindLines) ...[
          FxCard(
            padding: const EdgeInsets.all(Fx.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FIND IT FROM THE PAINT', style: Fx.label(context)),
                const SizedBox(height: 4),
                Text(
                  'Looks for the painted stop line, crosswalk and solid line in the video (no AI model) and adds them as '
                  'zones. Needs a fixed camera and some traffic passing, and can take a minute on a long 4K clip. It can be '
                  'wrong on faded paint, rain or night footage: always check the result.',
                  style: Fx.caption(context),
                ),
                const SizedBox(height: Fx.s8),
                OutlinedButton.icon(
                  onPressed: _finding ? null : _findLines,
                  icon: _finding
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high, size: 18),
                  label: Text(_finding ? 'Looking at the video...' : 'Find lines from the video'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Fx.s12),
        ],
        FxCard(
          padding: const EdgeInsets.all(Fx.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DRAW THE NEXT ZONE', style: Fx.label(context)),
              const SizedBox(height: Fx.s8),
              _step(
                context,
                ZoneTool.zone,
                '1',
                'Zone',
                _poly.length >= 3,
                '${_poly.length} point${_poly.length == 1 ? '' : 's'}, at least 3',
              ),
              if (needsArrow)
                _step(
                  context,
                  ZoneTool.arrow,
                  '2',
                  _cap(arrowName),
                  _arrow.length == 2,
                  'click start, then end',
                ),
              if (needsLight)
                _step(
                  context,
                  ZoneTool.light,
                  '3',
                  'Traffic light box',
                  _light.length == 2,
                  'click two opposite corners',
                ),
              const SizedBox(height: Fx.s8),
              Wrap(
                spacing: Fx.s8,
                runSpacing: Fx.s8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pointsOf(_tool).isEmpty ? null : _undoPoint,
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Undo point'),
                  ),
                  TextButton(
                    onPressed: _pointsOf(_tool).isEmpty ? null : _clearActive,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: Fx.s8),
              FilledButton.icon(
                onPressed: _complete ? _save : null,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Save this zone'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: Fx.s8),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Fx.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _notice!,
                        style: Fx.caption(context).copyWith(color: Fx.accent),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Fx.s8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Drag a point to move it', style: Fx.caption(context)),
                  const KeyCap('Right-click'),
                  Text('removes', style: Fx.caption(context)),
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
              Text('SAVED ZONES (${saved.length})', style: Fx.label(context)),
              const SizedBox(height: Fx.s8),
              if (saved.isEmpty)
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Fx.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Save at least one zone to continue.',
                        style: Fx.caption(context),
                      ),
                    ),
                  ],
                )
              else
                for (var i = 0; i < saved.length; i++)
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Fx.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Zone ${i + 1}  ·  ${((saved[i] as Map)['polygon'] as List).length} points'
                          '${(saved[i] as Map).containsKey('vector') ? '  ·  $arrowName' : ''}'
                          '${(saved[i] as Map)['sign'] != null ? '  ·  ${ViolationCatalog.signs[(saved[i] as Map)['sign']]?.label ?? ''}' : ''}',
                          style: Fx.body(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete zone ${i + 1}',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _deleteZone(i),
                      ),
                    ],
                  ),
            ],
          ),
        ),
        const SizedBox(height: Fx.s16),
        ViolationParams(
          draft: widget.draft,
          violationKey: key,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _step(
    BuildContext context,
    ZoneTool tool,
    String n,
    String label,
    bool done,
    String hint,
  ) {
    final active = _tool == tool;
    final color = tool == ZoneTool.zone
        ? Fx.danger
        : (tool == ZoneTool.arrow ? Fx.accent : Fx.warning);
    return InkWell(
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      onTap: () => setState(() => _tool = tool),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(Fx.s8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : null,
          border: Border.all(color: active ? color : Fx.border(context)),
          borderRadius: BorderRadius.circular(Fx.radiusSm),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: done
                  ? Fx.success
                  : color.withValues(alpha: 0.25),
              child: done
                  ? const Icon(Icons.check, size: 14, color: Colors.black87)
                  : Text(
                      n,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(width: Fx.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Fx.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(hint, style: Fx.caption(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZonePainter extends CustomPainter {
  _ZonePainter({
    required this.saved,
    required this.poly,
    required this.arrow,
    required this.light,
    required this.tool,
    required this.stopLine,
  });

  final List<Map<String, dynamic>> saved;
  final List<Offset> poly;
  final List<Offset> arrow;
  final List<Offset> light;
  final ZoneTool tool;
  final bool stopLine;

  Offset _px(Offset n, Size s) => Offset(n.dx * s.width, n.dy * s.height);

  Path _path(List<Offset> pts, Size s, {bool close = true}) {
    final p = Path()..moveTo(_px(pts.first, s).dx, _px(pts.first, s).dy);
    for (final q in pts.skip(1)) {
      p.lineTo(_px(q, s).dx, _px(q, s).dy);
    }
    if (close) p.close();
    return p;
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _arrowShape(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color, {
    bool line = false,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = line ? 5 : 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    if (line) return;
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    const head = 16.0;
    final tip = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(
        b.dx - head * math.cos(ang - math.pi / 6),
        b.dy - head * math.sin(ang - math.pi / 6),
      )
      ..lineTo(
        b.dx - head * math.cos(ang + math.pi / 6),
        b.dy - head * math.sin(ang + math.pi / 6),
      )
      ..close();
    canvas.drawPath(tip, Paint()..color = color);
  }

  void _handles(
    Canvas canvas,
    List<Offset> pts,
    Size s,
    Color color, {
    bool numbered = false,
  }) {
    for (var i = 0; i < pts.length; i++) {
      final c = _px(pts[i], s);
      canvas.drawCircle(c, 7, Paint()..color = Colors.black87);
      canvas.drawCircle(c, 6, Paint()..color = color);
      if (numbered) {
        _label(canvas, '${i + 1}', c + const Offset(0, -14), Colors.white);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Saved zones: calm green, with their own arrows / light boxes and a number.
    for (var i = 0; i < saved.length; i++) {
      final z = saved[i];
      final pts = ZoneGeometry.fromReference(z['polygon'] as List);
      if (pts.length < 3) continue;
      final path = _path(pts, size);
      canvas.drawPath(
        path,
        Paint()..color = Fx.success.withValues(alpha: 0.16),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Fx.success
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final c =
          pts.fold<Offset>(Offset.zero, (a, b) => a + b) /
          pts.length.toDouble();
      _label(canvas, 'Zone ${i + 1}', _px(c, size), Colors.white);
      if (z['ui_vector'] is List && (z['ui_vector'] as List).length == 2) {
        final v = ZoneGeometry.fromReference(z['ui_vector'] as List);
        _arrowShape(
          canvas,
          _px(v[0], size),
          _px(v[1], size),
          Fx.accent,
          line: stopLine,
        );
      }
      if (z['ui_light_box'] is List &&
          (z['ui_light_box'] as List).length == 2) {
        final b = ZoneGeometry.fromReference(z['ui_light_box'] as List);
        canvas.drawRect(
          Rect.fromPoints(_px(b[0], size), _px(b[1], size)),
          Paint()
            ..color = Fx.warning
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    // The zone being drawn.
    final edit = tool == ZoneTool.zone;
    if (poly.length >= 3) {
      final path = _path(poly, size);
      canvas.drawPath(
        path,
        Paint()..color = Fx.danger.withValues(alpha: edit ? 0.22 : 0.10),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Fx.danger
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    } else if (poly.length == 2) {
      canvas.drawLine(
        _px(poly[0], size),
        _px(poly[1], size),
        Paint()
          ..color = Fx.danger
          ..strokeWidth = 2.5,
      );
    }
    _handles(canvas, poly, size, Fx.danger, numbered: edit);

    if (arrow.length == 2) {
      _arrowShape(
        canvas,
        _px(arrow[0], size),
        _px(arrow[1], size),
        Fx.accent,
        line: stopLine,
      );
    }
    _handles(canvas, arrow, size, Fx.accent);

    if (light.length == 2) {
      canvas.drawRect(
        Rect.fromPoints(_px(light[0], size), _px(light[1], size)),
        Paint()
          ..color = Fx.warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    _handles(canvas, light, size, Fx.warning);
  }

  @override
  bool shouldRepaint(_ZonePainter old) => true;
}
