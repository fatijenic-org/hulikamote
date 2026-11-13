import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_api.dart';
import '../../domain/analysis_draft.dart';
import '../../domain/lane_signs.dart';
import '../../domain/loading_signs.dart';
import '../../domain/parking_reasons.dart';
import '../../data/object_previews.dart';
import '../../domain/violation_catalog.dart';
import '../../domain/zone_geometry.dart';
import 'box_object.dart';
import 'fx.dart';
import 'violation_params.dart';

enum ZoneTool { zone, arrow, light, sign }

/// What a drag in the sign tool is doing to the selected sign.
enum _SignGrab { none, move, resize, rotate }

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
  String _laneSign = 'bus_only'; // the overlay sign that a click places (Restricted lane)
  int? _selSign; // the placed sign whose size and angle are being set
  _SignGrab _grab = _SignGrab.none;
  int? _drag;
  double _aspect = 16 / 9;
  String? _notice;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get key => widget.violationKey;
  ViolationInfo get info => ViolationCatalog.of(key);
  bool get _isSigns => key == 'disregarding_signs';

  /// "Restricted lane": the zone is optional and overlay signs can be placed on the roads.
  bool get _isLane => key == 'restricted_lane';

  /// "Illegal loading / unloading" and "Illegal parking": a no-loading / no-parking sign (a box) can be placed anywhere on the picture,
  /// moved and resized; it is a zone.
  bool get _boxSigns => AnalysisDraft.signZoneKeys.contains(key);

  /// The no-parking signs also say WHY parking is banned there (RA 4136 Section 46).
  bool get _isParking => key == LoadingSigns.parkingRuleKey;

  /// "no-loading" or "no-parking": what the sign of this rule bans (and the same as a verb: "loading" / "parking").
  String get _ban => LoadingSigns.banFor(key);
  String get _banned => key == LoadingSigns.parkingRuleKey ? 'parking' : 'loading';

  /// The zone is optional for this rule (nothing drawn = the whole picture), see AnalysisDraft.wholeFrameKeys.
  bool get _zoneOptional => AnalysisDraft.wholeFrameKeys.contains(key);

  /// What the whole picture counts as when no zone is drawn.
  String get _wholePictureIs => switch (key) {
    'restricted_lane' => 'the lane',
    'tricycle_on_highway' || 'truck_ban' => 'a road where the ban applies',
    _ => 'the zone',
  };

  /// What the rule does when nothing is drawn.
  String get _nothingDrawn =>
      key == 'counterflow' ? 'the direction of traffic is learned from the video' : 'the whole picture is $_wholePictureIs';
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
    _previews = ObjectPreviews(widget.api)..addListener(_previewReady);
    _resolveAspect();
  }

  /// The pictures of the overlay objects, drawn by the backend like the evidence photos (see ObjectPreviews).
  late final ObjectPreviews _previews;

  void _previewReady() {
    if (mounted) setState(() {});
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
    _previews.dispose();
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
    _loadDrag = null;
    _notice = null;
  }

  List<Offset> _pointsOf(ZoneTool t) => switch (t) {
    ZoneTool.zone => _poly,
    ZoneTool.arrow => _arrow,
    ZoneTool.light => _light,
    ZoneTool.sign => _signPoints, // a copy: signs are changed through the draft, see _moveSign / _removeSign
  };

  // ── overlay signs (Restricted lane) ──
  List<Map<String, dynamic>> get _signs => widget.draft.signs(key);

  List<Offset> get _signPoints => [
    for (final s in _signs) Offset((s['x'] as num).toDouble() / ZoneGeometry.refWidth, (s['y'] as num).toDouble() / ZoneGeometry.refHeight),
  ];

  double _num(int i, String field, double fallback) => (_signs[i][field] as num?)?.toDouble() ?? fallback;
  double _scaleOf(int i) => SignGeometry.clampScale(_num(i, 'scale', 1.0));
  double _angleOf(int i) => SignGeometry.clampAngle(_num(i, 'angle', 0.0));
  double _tiltOf(int i) => SignGeometry.clampTilt(_num(i, 'tilt', 0.0));

  Offset _centerPx(int i, Size size) {
    final p = _signPoints[i];
    return Offset(p.dx * size.width, p.dy * size.height);
  }

  void _placeSign(Offset local, Size size) {
    final n = _norm(local, size);
    _signs.add({
      'type': _laneSign,
      'x': n.dx * ZoneGeometry.refWidth,
      'y': n.dy * ZoneGeometry.refHeight,
      'scale': 1.0, // size: 1.0 = 8.5% of the picture's width
      'angle': 0.0, // turned in the picture, degrees clockwise
      'tilt': 0.0, // turned away from the camera, degrees
    });
    widget.draft.touch();
    setState(() {
      _notice = null;
      _selSign = _signs.length - 1; // the sign just placed is the one to size and turn
    });
  }

  void _moveSign(int i, Offset n) {
    _signs[i]['x'] = n.dx * ZoneGeometry.refWidth;
    _signs[i]['y'] = n.dy * ZoneGeometry.refHeight;
    setState(() {});
  }

  void _removeSign(int i) {
    _signs.removeAt(i);
    widget.draft.touch();
    setState(() {
      _notice = null;
      final s = _selSign;
      if (s != null) _selSign = s == i ? null : (s > i ? s - 1 : s);
    });
  }

  /// The sign under the pointer (the one placed last wins where they overlap), or null.
  int? _signAt(Offset local, Size size) {
    for (var i = _signs.length - 1; i >= 0; i--) {
      final scale = _scaleOf(i);
      if (SignGeometry.onBoard(_centerPx(i, size), SignGeometry.width(size, scale), SignGeometry.height(size, scale), _angleOf(i), local)) return i;
    }
    return null;
  }

  /// What the pointer is on of the selected sign: its resize corner, its turn knob, or nothing.
  _SignGrab _handleAt(Offset local, Size size) {
    final i = _selSign;
    if (i == null || i >= _signs.length) return _SignGrab.none;
    final c = _centerPx(i, size);
    final w = SignGeometry.width(size, _scaleOf(i)), h = SignGeometry.height(size, _scaleOf(i));
    if ((SignGeometry.rotateKnob(c, w, h, _angleOf(i)) - local).distance <= 16) return _SignGrab.rotate;
    if ((SignGeometry.resizeHandle(c, w, h, _angleOf(i)) - local).distance <= 16) return _SignGrab.resize;
    return _SignGrab.none;
  }

  /// The start of a drag in the sign tool: a handle of the selected sign, or a sign (which becomes the selected one).
  int? _grabSign(Offset local, Size size) {
    final handle = _handleAt(local, size);
    if (handle != _SignGrab.none) {
      _grab = handle;
      return _selSign;
    }
    final i = _signAt(local, size);
    if (i == null) return null;
    _grab = _SignGrab.move;
    setState(() => _selSign = i);
    return i;
  }

  void _dragSign(int i, Offset local, Size size) {
    switch (_grab) {
      case _SignGrab.move:
        _moveSign(i, _norm(local, size));
      case _SignGrab.resize:
        _signs[i]['scale'] = SignGeometry.scaleFor(size, _centerPx(i, size), local);
        setState(() {});
      case _SignGrab.rotate:
        _signs[i]['angle'] = SignGeometry.angleFor(_centerPx(i, size), local);
        setState(() {});
      case _SignGrab.none:
        break;
    }
  }

  /// Sets one number of the selected sign (size, angle, tilt) from a slider.
  void _setLook(String field, double value) {
    final i = _selSign;
    if (i == null || i >= _signs.length) return;
    _signs[i][field] = value;
    widget.draft.touch();
    setState(() {});
  }

  bool get _realistic => (widget.draft.config(key)['signs_realistic'] as bool?) ?? true;

  // ── overlay signs (Illegal loading): a box placed anywhere, moved by its body and resized by its corners ──
  ({int i, bool resize, Offset grab, Offset anchor})? _loadDrag;

  /// Illegal parking: what the next placed sign marks (a hydrant, a corner ...), see parking_reasons.dart.
  String _kind = ParkingReasons.defaultKind;

  void _placeLoadingSign(Offset local, Size size) {
    _signs.add(LoadingSigns.make(_norm(local, size), kind: _isParking ? _kind : null));
    widget.draft.touch();
    setState(() {
      _notice = null;
      _selSign = _signs.length - 1; // the box just placed is the one whose look is set
    });
  }

  void _dragLoadingSign(Offset local, Size size) {
    final grab = _loadDrag;
    if (grab == null) return;
    final to = _norm(local, size);
    if (grab.resize) {
      LoadingSigns.resizeTo(_signs[grab.i], to, grab.anchor);
    } else {
      LoadingSigns.moveBy(_signs[grab.i], to, grab.grab);
    }
    setState(() {});
  }

  /// Which saved zone a sign stands in (0-based), or -1.
  int _zoneOfSign(int i) {
    final at = _signPoints[i];
    final zones = widget.draft.zones(key).cast<Map<String, dynamic>>();
    for (var z = 0; z < zones.length; z++) {
      if (ZoneGeometry.inside(ZoneGeometry.fromReference(zones[z]['polygon'] as List), at)) return z;
    }
    return -1;
  }

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
    if (_tool == ZoneTool.sign) {
      if (_boxSigns) {
        final hit = LoadingSigns.grab(_signs, local, size);
        if (hit == null) {
          _placeLoadingSign(local, size); // a click on a sign is not a new sign
        } else {
          setState(() => _selSign = hit.i); // it selects it
        }
        return;
      }
      if (_handleAt(local, size) != _SignGrab.none) return; // a tap on a handle is not a new sign
      final hit = _signAt(local, size);
      if (hit != null) {
        setState(() => _selSign = hit); // a tap on a sign selects it
      } else {
        _placeSign(local, size);
      }
      return;
    }
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
    if (_tool == ZoneTool.sign) {
      final i = _boxSigns ? LoadingSigns.bodyAt(_signs, local, size) : _signAt(local, size);
      if (i != null) _removeSign(i);
      return;
    }
    final pts = _pointsOf(_tool);
    final i =
        ZoneGeometry.hit(pts, local, size) ??
        (pts.isEmpty ? null : pts.length - 1);
    if (i != null) setState(() => pts.removeAt(i));
  }

  void _endDrag() {
    if (_tool == ZoneTool.sign && (_drag != null || _loadDrag != null)) widget.draft.touch(); // a moved, sized or turned sign is saved
    _drag = null;
    _loadDrag = null;
    _grab = _SignGrab.none;
  }

  // ── actions ──
  void _undoPoint() {
    if (_tool == ZoneTool.sign) {
      if (_signs.isNotEmpty) _removeSign(_signs.length - 1);
      return;
    }
    final pts = _pointsOf(_tool);
    if (pts.isNotEmpty) setState(pts.removeLast);
  }

  void _clearActive() {
    if (_tool == ZoneTool.sign) {
      _signs.clear();
      widget.draft.touch();
      setState(() {
        _notice = null;
        _selSign = null;
      });
      return;
    }
    setState(() {
      _pointsOf(_tool).clear();
      _notice = null;
    });
  }

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
      ZoneTool.sign => Fx.accent,
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
                          key: const ValueKey('zone-canvas'),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down, // grab the point under the finger / cursor, not where the slop ended
                          onTapUp: (d) => _tap(d.localPosition, size),
                          onSecondaryTapUp: (d) =>
                              _removeAt(d.localPosition, size),
                          onPanStart: (d) {
                            if (_boxSigns && _tool == ZoneTool.sign) {
                              _loadDrag = LoadingSigns.grab(_signs, d.localPosition, size); // a corner resizes, the body moves
                              if (_loadDrag != null) setState(() => _selSign = _loadDrag!.i);
                              return;
                            }
                            _drag = _tool == ZoneTool.sign
                                ? _grabSign(d.localPosition, size)
                                : ZoneGeometry.hit(_pointsOf(_tool), d.localPosition, size);
                          },
                          onPanUpdate: (d) {
                            if (_boxSigns && _tool == ZoneTool.sign) {
                              _dragLoadingSign(d.localPosition, size);
                              return;
                            }
                            final i = _drag;
                            if (i == null) return;
                            if (_tool == ZoneTool.sign) {
                              _dragSign(i, d.localPosition, size);
                              return;
                            }
                            setState(
                              () => _pointsOf(_tool)[i] = _norm(
                                d.localPosition,
                                size,
                              ),
                            );
                          },
                          onPanEnd: (_) => _endDrag(),
                          onPanCancel: _endDrag,
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
                                  signs: _isLane
                                      ? [
                                          for (var i = 0; i < _signs.length; i++)
                                            (at: _signPoints[i], type: _signs[i]['type'] as String, scale: _scaleOf(i), angle: _angleOf(i), tilt: _tiltOf(i)),
                                        ]
                                      : const [],
                                  selectedSign: _tool == ZoneTool.sign ? _selSign : null,
                                  boxSigns: _boxSigns ? _boxObjects() : const [],
                                  loadingHandles: _boxSigns && _tool == ZoneTool.sign,
                                ),
                              ),
                              if (_poly.isEmpty && saved.isEmpty && (!(_isLane || _boxSigns) || _signs.isEmpty))
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
                                    child: Text(
                                      _boxSigns
                                          ? 'Place a $_ban sign (card on the right), or click the corners of the area to draw a zone.\nNothing placed = the whole picture is watched.'
                                          : _zoneOptional
                                          ? 'Optional: click the corners of one road area to limit the rule to it.\nNothing drawn = $_nothingDrawn.'
                                          : 'Click the corners of the area to draw the zone',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
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
                _boxSigns ? 'Zone (or place a sign)' : (_zoneOptional ? 'Zone (optional)' : 'Zone'),
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
                key: const ValueKey('zone-save'),
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
        if (_isLane) ...[
          _signsCard(context),
          const SizedBox(height: Fx.s12),
        ],
        if (_boxSigns) ...[
          _loadingSignsCard(context),
          const SizedBox(height: Fx.s12),
        ],
        if (_isParking) ...[
          _parkingConditionsCard(context),
          const SizedBox(height: Fx.s12),
        ],
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
                    Icon(
                      _boxSigns && _signs.isNotEmpty ? Icons.check_circle : (_zoneOptional ? Icons.crop_free : Icons.error_outline),
                      size: 16,
                      color: _zoneOptional || (_boxSigns && _signs.isNotEmpty) ? Fx.success : Fx.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _boxSigns
                            ? (_signs.isNotEmpty
                                  ? 'No zone drawn: the placed signs mark where $_banned is banned.'
                                  : 'No zone and no sign: the whole picture is watched. Place a sign or save a zone to limit the rule.')
                            : _zoneOptional
                            ? 'No zone drawn: $_nothingDrawn. Draw a zone to limit the rule to one area.'
                            : 'Save at least one zone to continue.',
                        key: const ValueKey('lane-no-zone'),
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

  Widget _lookSlider(String sliderKey, String label, double value, double min, double max, String shown, String field) {
    return Row(
      children: [
        SizedBox(width: 74, child: Text(label, style: Fx.caption(context))),
        Expanded(
          child: Slider(key: ValueKey(sliderKey), value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: (v) => _setLook(field, v)),
        ),
        SizedBox(width: 46, child: Text(shown, key: ValueKey('$sliderKey-value'), textAlign: TextAlign.end, style: Fx.caption(context))),
      ],
    );
  }

  /// How the rule will work with what is drawn and placed now, in one sentence.
  String _laneSummary() {
    final zones = widget.draft.zones(key).length;
    if (zones > 0) {
      return 'Only the $zones zone${zones == 1 ? '' : 's'} are checked. A sign inside a zone sets who may use that zone; '
          'a zone without a sign uses the tick boxes below.';
    }
    if (_signs.isEmpty) return 'No zone and no sign: the whole picture is the lane, and only the types ticked below may use it.';
    if (_signs.length == 1) return 'No zone: the whole picture is the lane, and the sign says who may use it.';
    return 'No zone: each vehicle follows the sign nearest to it, so two roads can have different signs.';
  }

  Widget _signsCard(BuildContext context) {
    final placing = _tool == ZoneTool.sign;
    final zoneCount = widget.draft.zones(key).length;
    return FxCard(
      key: const ValueKey('lane-signs'),
      padding: const EdgeInsets.all(Fx.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIGNS ON THE ROAD (TEMPORARY)', style: Fx.label(context)),
          const SizedBox(height: 4),
          Text(
            'A sign says who may use the road it stands on. Place it on the picture. It is only drawn on the photos and the video of '
            'this analysis: nothing is written into your video, and it goes when you start a new analysis.',
            style: Fx.caption(context),
          ),
          const SizedBox(height: Fx.s8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sign in LaneSigns.all)
                ChoiceChip(
                  key: ValueKey('sign-type-${sign.key}'),
                  label: Text(sign.label),
                  selected: _laneSign == sign.key,
                  onSelected: (_) => setState(() => _laneSign = sign.key),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('May use it: ${LaneSigns.allowedText(_laneSign)}', key: const ValueKey('sign-allowed'), style: Fx.caption(context)),
          const SizedBox(height: Fx.s8),
          FilledButton.tonalIcon(
            key: const ValueKey('sign-place'),
            onPressed: () => setState(() => _tool = placing ? ZoneTool.zone : ZoneTool.sign),
            icon: Icon(placing ? Icons.check : Icons.add_location_alt_outlined, size: 18),
            label: Text(placing ? 'Done placing signs' : 'Place this sign on the picture'),
          ),
          if (placing) ...[
            const SizedBox(height: 4),
            Text(
              'Click on the road to place it. Drag a sign to move it. Right-click removes it.',
              key: const ValueKey('sign-help'),
              style: Fx.caption(context),
            ),
          ],
          if (_signs.isNotEmpty) ...[
            const SizedBox(height: Fx.s8),
            for (var i = 0; i < _signs.length; i++)
              InkWell(
                key: ValueKey('sign-row-$i'),
                borderRadius: BorderRadius.circular(Fx.radiusSm),
                onTap: () => setState(() {
                  _selSign = i;
                  _tool = ZoneTool.sign; // so its handles can be dragged on the picture
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: _selSign == i ? Fx.accent.withValues(alpha: 0.12) : null,
                    borderRadius: BorderRadius.circular(Fx.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.signpost_outlined, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${LaneSigns.of(_signs[i]['type'] as String)?.label ?? 'Sign'}  ·  '
                          '${zoneCount == 0 ? 'covers the road around it' : (_zoneOfSign(i) >= 0 ? 'sets Zone ${_zoneOfSign(i) + 1}' : 'outside every zone: not used')}',
                          style: Fx.body(context).copyWith(fontWeight: _selSign == i ? FontWeight.w600 : null),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('sign-delete-$i'),
                        tooltip: 'Remove this sign',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeSign(i),
                      ),
                    ],
                  ),
                ),
              ),
            if (_selSign != null && _selSign! < _signs.length) ...[
              const SizedBox(height: Fx.s8),
              Text('SIZE AND ANGLE OF THE SELECTED SIGN', style: Fx.label(context)),
              _lookSlider('sign-scale', 'Size', _scaleOf(_selSign!), SignGeometry.minScale, SignGeometry.maxScale, '${(_scaleOf(_selSign!) * 100).round()}%', 'scale'),
              _lookSlider('sign-angle', 'Rotate', _angleOf(_selSign!), -SignGeometry.maxAngle, SignGeometry.maxAngle, '${_angleOf(_selSign!).round()}°', 'angle'),
              _lookSlider('sign-tilt', 'Turn away', _tiltOf(_selSign!), -SignGeometry.maxTilt, SignGeometry.maxTilt, '${_tiltOf(_selSign!).round()}°', 'tilt'),
              Text(
                'Or drag the corner of the sign to resize it, and the round knob above it to rotate it.',
                key: const ValueKey('sign-handles-help'),
                style: Fx.caption(context),
              ),
              TextButton(
                key: const ValueKey('sign-reset'),
                onPressed: () {
                  final i = _selSign!;
                  _signs[i]['scale'] = 1.0;
                  _signs[i]['angle'] = 0.0;
                  _signs[i]['tilt'] = 0.0;
                  widget.draft.touch();
                  setState(() {});
                },
                child: const Text('Reset size and angle'),
              ),
            ],
            const SizedBox(height: Fx.s8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Realistic look', style: Fx.body(context).copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        'Soft edges, a little grain, a shadow on the road, and colours that follow the light of the scene, so the sign '
                        'looks filmed. Turn it off for a plain, sharp sign.',
                        style: Fx.caption(context),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('sign-realistic'),
                  value: _realistic,
                  onChanged: (v) {
                    widget.draft.config(key)['signs_realistic'] = v;
                    widget.draft.touch();
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: Fx.s8),
          Text(_laneSummary(), key: const ValueKey('lane-summary'), style: Fx.caption(context).copyWith(color: Fx.accent)),
        ],
      ),
    );
  }

  /// The boxes as the painter draws them: the area, the object in it, and the picture of the object when the backend has made it.
  List<BoxObject> _boxObjects() {
    final realistic = _realistic;
    return [
      for (var i = 0; i < _signs.length; i++)
        () {
          final s = _signs[i];
          final kind = LoadingSigns.objectKind(key, s);
          final rect = LoadingSigns.rectOf(s);
          return BoxObject(
            box: rect,
            kind: kind,
            at: rect.center,
            selected: _tool == ZoneTool.sign && _selSign == i,
            preview: _previews.peek(
              kind,
              scale: LoadingSigns.scaleOf(s),
              angle: LoadingSigns.angleOf(s),
              tilt: LoadingSigns.tiltOf(s),
              stand: LoadingSigns.standOf(s, kind),
              realistic: realistic,
            ),
          );
        }(),
    ];
  }

  /// Size, angle, turn-away, stand and filmed look of the selected box's object (the object is drawn by the backend, so the photos match).
  Widget _boxLook(BuildContext context) {
    final i = _selSign!;
    final sign = _signs[i];
    final kind = LoadingSigns.objectKind(key, sign);
    final scale = LoadingSigns.scaleOf(sign), angle = LoadingSigns.angleOf(sign), tilt = LoadingSigns.tiltOf(sign);
    return Column(
      key: const ValueKey('box-look'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LOOK OF SIGN ${i + 1}', style: Fx.label(context)),
        _lookSlider('box-look-size', 'Size', scale, LoadingSigns.minScale, LoadingSigns.maxScale, '${(scale * 100).round()}%', 'scale'),
        _lookSlider('box-look-angle', 'Rotate', angle, -LoadingSigns.maxAngle, LoadingSigns.maxAngle, '${angle.round()}°', 'angle'),
        _lookSlider('box-look-tilt', 'Turn away', tilt, -LoadingSigns.maxTilt, LoadingSigns.maxTilt, '${tilt.round()}°', 'tilt'),
        if (LoadingSigns.standable(kind)) ...[
          const SizedBox(height: 4),
          SegmentedButton<String>(
            key: const ValueKey('box-look-stand'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'none', label: Text('Ground')),
              ButtonSegment(value: 'post', label: Text('Pole')),
              ButtonSegment(value: 'tripod', label: Text('Tripod')),
            ],
            selected: {LoadingSigns.standOf(sign, kind)},
            onSelectionChanged: (v) {
              sign['stand'] = v.first;
              widget.draft.touch();
              setState(() {});
            },
          ),
        ],
        Row(
          children: [
            Expanded(child: Text('Realistic look', style: Fx.body(context))),
            Switch(
              key: const ValueKey('box-look-realistic'),
              value: _realistic,
              onChanged: (v) {
                widget.draft.config(key)['signs_realistic'] = v;
                widget.draft.touch();
                setState(() {});
              },
            ),
          ],
        ),
        TextButton(
          key: const ValueKey('box-look-reset'),
          onPressed: () {
            LoadingSigns.resetLook(sign);
            widget.draft.touch();
            setState(() {});
          },
          child: const Text('Reset look'),
        ),
      ],
    );
  }

  /// How the rule will work with what is drawn and placed now, in one sentence.
  String _loadingSummary() {
    final zones = widget.draft.zones(key).length;
    final signs = _signs.length;
    if (zones == 0 && signs == 0) {
      return 'Nothing marked: the whole picture is watched. Place a sign, or draw a zone, to limit the rule.';
    }
    final parts = [
      if (signs > 0) '$signs sign${signs == 1 ? '' : 's'}',
      if (zones > 0) '$zones zone${zones == 1 ? '' : 's'}',
    ];
    final who = key == LoadingSigns.parkingRuleKey ? 'A vehicle' : 'A bus, jeepney, tricycle or truck';
    return '${_cap(_banned)} is banned in the ${parts.join(' and ')}. $who that stands still there too long is flagged.';
  }

  Widget _loadingSignsCard(BuildContext context) {
    final placing = _tool == ZoneTool.sign;
    return FxCard(
      key: const ValueKey('loading-signs'),
      padding: const EdgeInsets.all(Fx.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_ban.toUpperCase()} SIGNS (TEMPORARY)', style: Fx.label(context)),
          const SizedBox(height: 4),
          Text(
            'A sign marks a $_ban area. Place it anywhere on the picture, then move it and resize it: its box is the area. '
            'It is only drawn on the photos and the video of this analysis: nothing is written into your video, and it goes when you '
            'start a new analysis.',
            style: Fx.caption(context),
          ),
          if (_isParking) ...[
            const SizedBox(height: Fx.s8),
            Text('What marks the area?', style: Fx.label(context)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in ParkingReasons.all)
                  ChoiceChip(
                    key: ValueKey('parking-kind-${r.key}'),
                    label: Text(r.short),
                    selected: _kind == r.key,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _kind = r.key),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(ParkingReasons.of(_kind).hint, key: const ValueKey('parking-kind-hint'), style: Fx.caption(context)),
          ],
          const SizedBox(height: Fx.s8),
          FilledButton.tonalIcon(
            key: const ValueKey('sign-place'),
            onPressed: () => setState(() => _tool = placing ? ZoneTool.zone : ZoneTool.sign),
            icon: Icon(placing ? Icons.check : Icons.add_location_alt_outlined, size: 18),
            label: Text(placing ? 'Done placing signs' : (_isParking && _kind != ParkingReasons.defaultKind ? 'Place: ${ParkingReasons.of(_kind).short}' : 'Place a $_ban sign')),
          ),
          if (placing) ...[
            const SizedBox(height: 4),
            Text(
              'Click the picture to place a sign. Drag it to move it. Drag a corner to resize it. Right-click removes it.',
              key: const ValueKey('sign-help'),
              style: Fx.caption(context),
            ),
          ],
          if (_signs.isNotEmpty) ...[
            const SizedBox(height: Fx.s8),
            for (var i = 0; i < _signs.length; i++)
              InkWell(
                key: ValueKey('loading-sign-select-$i'),
                borderRadius: BorderRadius.circular(Fx.radiusSm),
                onTap: () => setState(() {
                  _selSign = i;
                  _tool = ZoneTool.sign; // so its handles can be dragged on the picture
                }),
                child: Row(
                key: ValueKey('loading-sign-row-$i'),
                children: [
                  Icon(key == LoadingSigns.parkingRuleKey ? Icons.local_parking : Icons.no_transfer, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isParking
                          ? 'Sign ${i + 1}  ·  ${ParkingReasons.of(_signs[i]['kind'] as String?).label}  ·  ${LoadingSigns.sizeText(_signs[i])}'
                          : 'Sign ${i + 1}  ·  ${LoadingSigns.sizeText(_signs[i])}',
                      key: ValueKey('loading-sign-text-$i'),
                      style: Fx.body(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isParking)
                    PopupMenuButton<String>(
                      key: ValueKey('parking-sign-kind-$i'),
                      tooltip: 'Change what this sign marks',
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      padding: EdgeInsets.zero,
                      onSelected: (v) {
                        _signs[i]['kind'] = v;
                        widget.draft.touch();
                        setState(() {});
                      },
                      itemBuilder: (_) => [
                        for (final r in ParkingReasons.all) PopupMenuItem<String>(value: r.key, child: Text(r.label)),
                      ],
                    ),
                  IconButton(
                    key: ValueKey('loading-sign-delete-$i'),
                    tooltip: 'Remove this sign',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeSign(i),
                  ),
                ],
              ),
              ),
          ],
          if (_selSign != null && _selSign! < _signs.length) ...[
            const SizedBox(height: Fx.s8),
            _boxLook(context),
          ],
          const SizedBox(height: Fx.s8),
          Text(_loadingSummary(), key: const ValueKey('loading-summary'), style: Fx.caption(context).copyWith(color: Fx.accent)),
        ],
      ),
    );
  }

  /// "What counts as illegal parking": the eight places of RA 4136 Section 46 and where each one is handled in this analysis.
  /// A place that is marked on the picture has a Place button; a place that another rule judges shows whether that rule is on.
  Widget _parkingConditionsCard(BuildContext context) {
    final rows = <Widget>[];
    for (final item in const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
      final reason = ParkingReasons.all.where((r) => r.item == item).firstOrNull;
      final other = ParkingReasons.others.where((o) => o.item == item).firstOrNull;
      final String text, note;
      final Widget action;
      if (reason != null) {
        final placed = _signs.where((s) => ParkingReasons.of(s['kind'] as String?).key == reason.key).length;
        text = reason.text;
        note = placed == 0 ? 'Marked with a box on the picture' : '$placed placed on the picture';
        action = TextButton(
          key: ValueKey('parking-item-$item-action'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => setState(() {
            _kind = reason.key;
            _tool = ZoneTool.sign;
          }),
          child: const Text('Place'),
        );
      } else {
        final rule = other!.ruleKey;
        final on = widget.draft.isSelected(rule);
        text = other.text;
        note = 'Judged by the rule "${ViolationCatalog.of(rule).label}": ${on ? 'on' : 'off'}';
        action = on
            ? const Icon(Icons.check_circle, size: 18, color: Fx.success)
            : TextButton(
                key: ValueKey('parking-item-$item-action'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => widget.draft.toggle(rule, on: true),
                child: const Text('Add rule'),
              );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            key: ValueKey('parking-item-$item'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 26, child: Text('($item)', style: Fx.caption(context))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: Fx.body(context)),
                    Text(note, key: ValueKey('parking-item-$item-note'), style: Fx.caption(context)),
                  ],
                ),
              ),
              action,
            ],
          ),
        ),
      );
    }
    return FxCard(
      key: const ValueKey('parking-conditions'),
      padding: const EdgeInsets.all(Fx.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHAT COUNTS AS ILLEGAL PARKING', style: Fx.label(context)),
          const SizedBox(height: 4),
          Text(
            '${ParkingReasons.source}: no driver may park a vehicle, or leave it standing, in these places. Each one is marked on the picture or '
            'judged by its own rule.',
            style: Fx.caption(context),
          ),
          const SizedBox(height: Fx.s8),
          ...rows,
          const SizedBox(height: 4),
          Text(ParkingReasons.fireCodeNote, key: const ValueKey('parking-source-note'), style: Fx.caption(context)),
        ],
      ),
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
    this.signs = const [],
    this.selectedSign,
    this.boxSigns = const [],
    this.loadingHandles = false,
  });

  final List<({Offset at, String type, double scale, double angle, double tilt})> signs;
  final int? selectedSign;

  /// The boxes of Illegal parking / Illegal loading: the banned area (0..1), what stands in it (a hydrant, a plate on a pole ...) and where.
  /// The corner handles show while boxes are being placed.
  final List<BoxObject> boxSigns;
  final bool loadingHandles;
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

  /// An overlay sign: a blue board with its two lines of text, placed, sized, turned and turned away like it will be drawn on the
  /// photos and the video (same size rule and same perspective as the backend). The selected one also shows its handles.
  void _sign(Canvas canvas, ({Offset at, String type, double scale, double angle, double tilt}) sign, bool selected, Size size) {
    final spec = LaneSigns.of(sign.type);
    if (spec == null) return;
    final c = _px(sign.at, size);
    final w = SignGeometry.width(size, sign.scale), h = SignGeometry.height(size, sign.scale);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    final m = Matrix4.identity()..rotateZ(sign.angle * math.pi / 180);
    m.multiply(Matrix4.identity()..setEntry(3, 2, 1 / (3 * w)));
    m.rotateY(-sign.tilt * math.pi / 180); // a positive turn puts the right edge farther, as in the backend
    canvas.transform(m.storage);
    final board = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(w / 22));
    canvas.drawRRect(board.shift(Offset(w * 0.045, w * 0.07)), Paint()..color = Colors.black38);
    canvas.drawRRect(board, Paint()..color = const Color(0xFF0A4696));
    canvas.drawRRect(
      board.deflate(w / 28),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w / 40),
    );
    final lines = [spec.line1, spec.line2];
    final probe = TextPainter(
      text: TextSpan(text: lines.reduce((a, b) => a.length >= b.length ? a : b), style: TextStyle(fontSize: h * 0.3, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final fontSize = h * 0.3 * math.min(1.0, (w * 0.8) / math.max(probe.width, 1));
    for (var i = 0; i < 2; i++) {
      final tp = TextPainter(
        text: TextSpan(text: lines[i], style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, (i == 0 ? -h * 0.22 : h * 0.18) - tp.height / 2));
    }
    canvas.restore();

    if (selected) {
      final knob = SignGeometry.rotateKnob(c, w, h, sign.angle);
      final corner = SignGeometry.resizeHandle(c, w, h, sign.angle);
      final top = c + (knob - c) * ((h / 2) / (h / 2 + 26)); // where the stem leaves the top edge of the sign
      final turned = [
        for (final p in const [Offset(-0.5, -0.5), Offset(0.5, -0.5), Offset(0.5, 0.5), Offset(-0.5, 0.5)])
          c + _turn(Offset(p.dx * w, p.dy * h), sign.angle),
      ];
      canvas.drawPath(
        Path()..addPolygon(turned, true),
        Paint()
          ..color = Fx.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.drawLine(top, knob, Paint()..color = Fx.accent..strokeWidth = 1.5);
      for (final p in [knob, corner]) {
        canvas.drawCircle(p, 8, Paint()..color = Colors.black87);
        canvas.drawCircle(p, 6.5, Paint()..color = Colors.white);
        canvas.drawCircle(p, 4, Paint()..color = Fx.accent);
      }
    }
  }

  static Offset _turn(Offset p, double degrees) {
    final a = degrees * math.pi / 180;
    return Offset(p.dx * math.cos(a) - p.dy * math.sin(a), p.dx * math.sin(a) + p.dy * math.cos(a));
  }

  static const _loadingRed = Color(0xFFD72828); // the same red as the backend's sign (engine/loading_signs.py)

  /// A box of Illegal parking / Illegal loading: the banned area as a faint tinted patch with a dashed edge, and the object that stands in it
  /// (a picture made by the backend, so it is the one the evidence photos show). While the picture is on its way, a dot marks the spot.
  void _boxObject(Canvas canvas, BoxObject s, Size size) {
    final box = Rect.fromLTRB(s.box.left * size.width, s.box.top * size.height, s.box.right * size.width, s.box.bottom * size.height);
    final tint = LoadingSigns.tintOf(s.kind);
    canvas.drawRect(box, Paint()..color = tint.withValues(alpha: 0.14));
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final corners = [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft, box.topLeft];
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[i + 1];
      final length = (b - a).distance;
      for (var d = 0.0; d < length; d += 16) {
        canvas.drawLine(a + (b - a) * (d / length), a + (b - a) * (math.min(d + 8, length) / length), dash);
      }
    }
    final at = Offset(s.at.dx * size.width, s.at.dy * size.height);
    final p = s.preview;
    if (p != null) {
      final k = size.width / ZoneGeometry.refWidth; // the picture was made for a frame 1920 wide
      canvas.drawImageRect(
        p.image,
        Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble()),
        Rect.fromLTWH(at.dx + p.dx * k, at.dy + p.dy * k, p.image.width * k, p.image.height * k),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawCircle(at, 6, Paint()..color = tint);
    }
    if (s.selected) {
      canvas.drawRect(
        box,
        Paint()
          ..color = Colors.cyanAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (loadingHandles) {
      for (final corner in [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft]) {
        final handle = Rect.fromCenter(center: corner, width: 12, height: 12);
        canvas.drawRect(handle.inflate(1.5), Paint()..color = _loadingRed);
        canvas.drawRect(handle, Paint()..color = Colors.white);
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

    for (var i = 0; i < signs.length; i++) {
      _sign(canvas, signs[i], selectedSign == i, size);
    }
    for (final sign in boxSigns) {
      _boxObject(canvas, sign, size);
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
