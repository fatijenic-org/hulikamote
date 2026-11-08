import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/harvest_labeling.dart';
import '../../domain/harvest_labeling_models.dart';
import '../../domain/harvest_models.dart';
import 'harvest_parts.dart';

/// Opens the labeler over the whole window (sidebar included): one picture at a time, nothing else.
Future<void> openHarvestLabeler(
  BuildContext context, {
  required HarvestLabeling labeling,
  required LabelModelInfo model,
  String? taskId,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => HarvestLabeler(labeling: labeling, model: model, taskId: taskId),
    ),
  );
}

/// A box while a person is editing it. Coordinates are fractions of the picture (0..1).
class _Box {
  _Box(this.cls, this.cx, this.cy, this.w, this.h);

  factory _Box.from(HarvestBox b) => _Box(b.cls, b.cx, b.cy, b.w, b.h);

  int cls;
  double cx, cy, w, h;

  _Box copy() => _Box(cls, cx, cy, w, h);

  Rect get rect => Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

  void setRect(Rect r) {
    cx = r.center.dx;
    cy = r.center.dy;
    w = r.width;
    h = r.height;
  }

  HarvestBox toHarvest() => HarvestBox(cls: cls, cx: cx, cy: cy, w: w, h: h);
}

enum _Drag { none, draw, move, resize, pan }

/// Full-screen, one picture at a time. The picture shows the model's boxes: Enter keeps them, drag to draw or move one,
/// pull a corner to fix it, Delete removes it, N = nothing here, S = not sure. Every answer is saved at once.
/// Zoom (mouse wheel, + / - , the buttons on top, 0 = fit) to place a small box exactly; hold Space and drag to move the zoomed picture.
class HarvestLabeler extends StatefulWidget {
  const HarvestLabeler({super.key, required this.labeling, required this.model, this.taskId});

  final HarvestLabeling labeling;
  final LabelModelInfo model;

  /// Only the pictures of this analysis; null = every analysis.
  final String? taskId;

  @override
  State<HarvestLabeler> createState() => _HarvestLabelerState();
}

class _HarvestLabelerState extends State<HarvestLabeler> {
  final FocusNode _focus = FocusNode(debugLabel: 'harvest labeler');

  LabelQueue? _queue;
  String? _loadError;
  String? _error; // the last save that failed
  bool _busy = false;

  int _i = 0;
  List<_Box> _boxes = [];
  int _selected = -1;
  int _cls = 0;
  final Map<String, List<_Box>> _edited = {}; // what was on screen for a picture when we left it
  final Set<String> _answered = {};

  // dragging
  _Drag _drag = _Drag.none;
  Offset _anchor = Offset.zero; // the corner that stays still (resize) or where the drag began (draw)
  Offset _grab = Offset.zero; // move: where inside the box it was grabbed
  Size _canvas = Size.zero;

  // zoom: 1 = the whole picture fits. The picture is scaled from its top-left corner, then moved by _pan (screen pixels).
  static const double _maxZoom = 8;
  static const double _zoomStep = 1.25;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  bool _space = false; // Space is held: dragging moves the picture instead of drawing
  Offset _panFrom = Offset.zero; // where a Space-drag began (window pixels)
  Offset _panWas = Offset.zero; // _pan at that moment

  List<LabelItem> get _items => _queue?.items ?? const [];
  LabelItem? get _item => _i >= 0 && _i < _items.length ? _items[_i] : null;
  List<String> get _classes => _queue?.classes ?? widget.model.classes;
  bool get _finished => _queue != null && _i >= _items.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _queue = null;
    });
    try {
      final q = await widget.labeling.queue(widget.model.key, taskId: widget.taskId);
      if (!mounted) return;
      setState(() {
        _queue = q;
        _i = 0;
        _enter();
      });
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  /// Puts the boxes of the current picture on screen: what the person left there, or the model's guess.
  void _enter() {
    final item = _item;
    _selected = -1;
    _drag = _Drag.none;
    _error = null;
    _resetZoom(); // every new picture starts fitted
    if (item == null) {
      _boxes = [];
      return;
    }
    final edited = _edited[item.id];
    _boxes = edited != null ? [for (final b in edited) b.copy()] : [for (final b in item.boxes) _Box.from(b)];
  }

  void _leave() {
    final item = _item;
    if (item != null) _edited[item.id] = [for (final b in _boxes) b.copy()];
  }

  void _go(int step) {
    if (_queue == null) return;
    _leave();
    setState(() {
      _i = (_i + step).clamp(0, _items.length);
      _enter();
    });
    _focus.requestFocus();
  }

  // ── answers ──
  Future<void> _answer(Future<void> Function(LabelItem item) save) async {
    final item = _item;
    if (item == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await save(item);
      if (!mounted) return;
      _answered.add(item.id);
      _busy = false;
      _go(1);
    } on HarvestLabelingException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  void _looksRight() {
    if (_boxes.isEmpty) return;
    _answer((item) => widget.labeling.save(item.id, [for (final b in _boxes) b.toHarvest()]));
  }

  void _nothingHere() => _answer((item) async {
        _boxes = [];
        await widget.labeling.save(item.id, const []);
      });

  void _notSure() => _answer((item) => widget.labeling.skip(item.id));

  void _deleteSelected() {
    if (_selected < 0 || _selected >= _boxes.length) return;
    setState(() {
      _boxes.removeAt(_selected);
      _selected = -1;
    });
  }

  void _pickClass(int cls) {
    setState(() {
      _cls = cls;
      if (_selected >= 0 && _selected < _boxes.length) _boxes[_selected].cls = cls;
    });
  }

  // ── keyboard ──
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      final down = event is! KeyUpEvent;
      if (_space != down) setState(() => _space = down);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _looksRight();
    } else if (key == LogicalKeyboardKey.keyN) {
      _nothingHere();
    } else if (key == LogicalKeyboardKey.keyS) {
      _notSure();
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _deleteSelected();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyB) {
      _go(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(_zoomStep);
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / _zoomStep);
    } else if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      setState(_resetZoom);
    } else if (_digits.contains(key)) {
      final n = _digits.indexOf(key);
      if (n < _classes.length) _pickClass(n);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  // ── zoom ──
  void _resetZoom() {
    _zoom = 1;
    _pan = Offset.zero;
  }

  /// Zooms by [factor] and keeps the spot [at] (pixels inside the picture area; default the middle) under the pointer.
  void _zoomBy(double factor, [Offset? at]) {
    if (_canvas.isEmpty) return;
    final focus = at ?? Offset(_canvas.width / 2, _canvas.height / 2);
    final next = (_zoom * factor).clamp(1.0, _maxZoom);
    if (next == _zoom) return;
    setState(() {
      _pan = focus - (focus - _pan) * (next / _zoom);
      _zoom = next;
      _clampPan();
    });
  }

  /// The picture may not slide off its area: its edges stay at or beyond the edges of the area.
  void _clampPan() {
    if (_zoom <= 1) {
      _pan = Offset.zero;
      return;
    }
    _pan = Offset(
      _pan.dx.clamp(_canvas.width * (1 - _zoom), 0.0),
      _pan.dy.clamp(_canvas.height * (1 - _zoom), 0.0),
    );
  }

  /// Mouse wheel = zoom at the pointer (one notch, about 100 units, is a bit more than a step).
  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && !_busy) _zoomBy(math.pow(1.0015, -e.scrollDelta.dy).toDouble(), e.localPosition);
  }

  /// Dragging with the middle or right mouse button moves a zoomed picture too.
  void _onPointerMove(PointerMoveEvent e) {
    if (_zoom > 1 && (e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0) {
      setState(() {
        _pan += e.delta;
        _clampPan();
      });
    }
  }

  // ── drawing and fixing boxes ──
  Offset _norm(Offset local) => Offset(local.dx / _canvas.width, local.dy / _canvas.height);

  Offset _clamp(Offset p) => Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));

  void _panStart(DragStartDetails d) {
    if (_busy || _canvas.isEmpty) return;
    _focus.requestFocus();
    // Space held: move the zoomed picture, draw nothing
    if (_space) {
      _drag = _Drag.pan;
      _panFrom = d.globalPosition;
      _panWas = _pan;
      return;
    }
    final p = _norm(d.localPosition);
    // 1. a corner of the picked box: pull it (the grab size stays the same on screen when zoomed)
    if (_selected >= 0 && _selected < _boxes.length) {
      final r = _boxes[_selected].rect;
      final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      for (var k = 0; k < 4; k++) {
        final px = Offset(corners[k].dx * _canvas.width, corners[k].dy * _canvas.height);
        if ((px - d.localPosition).distance < 18 / _zoom) {
          _drag = _Drag.resize;
          _anchor = corners[(k + 2) % 4];
          return;
        }
      }
    }
    // 2. inside a box: pick it and move it
    for (var k = _boxes.length - 1; k >= 0; k--) {
      if (_boxes[k].rect.contains(p)) {
        setState(() => _selected = k);
        _drag = _Drag.move;
        _grab = p - _boxes[k].rect.center;
        return;
      }
    }
    // 3. empty picture: draw a new box
    _drag = _Drag.draw;
    _anchor = _clamp(p);
    setState(() {
      _boxes.add(_Box(_cls, _anchor.dx, _anchor.dy, 0, 0));
      _selected = _boxes.length - 1;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_drag == _Drag.pan) {
      setState(() {
        _pan = _panWas + (d.globalPosition - _panFrom);
        _clampPan();
      });
      return;
    }
    if (_drag == _Drag.none || _selected < 0 || _selected >= _boxes.length) return;
    final p = _clamp(_norm(d.localPosition));
    final b = _boxes[_selected];
    setState(() {
      switch (_drag) {
        case _Drag.draw:
        case _Drag.resize:
          b.setRect(Rect.fromPoints(_anchor, p));
        case _Drag.move:
          final half = Offset(b.w / 2, b.h / 2);
          final c = _norm(d.localPosition) - _grab;
          b.cx = c.dx.clamp(half.dx, 1 - half.dx);
          b.cy = c.dy.clamp(half.dy, 1 - half.dy);
        case _Drag.none:
        case _Drag.pan: // handled above
          break;
      }
    });
  }

  void _panEnd(DragEndDetails d) {
    if (_drag == _Drag.draw && _selected >= 0 && _selected < _boxes.length) {
      final b = _boxes[_selected];
      // a drag shorter than ~1% of the picture is a slip of the hand (when zoomed in, the limit shrinks with the zoom)
      if (b.w < 0.012 / _zoom || b.h < 0.012 / _zoom) {
        setState(() {
          _boxes.removeAt(_selected);
          _selected = -1;
        });
      }
    }
    _drag = _Drag.none;
  }

  void _tapUp(TapUpDetails d) {
    if (_canvas.isEmpty) return;
    final p = _norm(d.localPosition);
    var hit = -1;
    for (var k = _boxes.length - 1; k >= 0; k--) {
      if (_boxes[k].rect.contains(p)) {
        hit = k;
        break;
      }
    }
    setState(() {
      _selected = hit;
      if (hit >= 0) _cls = _boxes[hit].cls;
    });
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            _topBar(context),
            Expanded(child: _body(context)),
            if (_item != null) _bottomBar(context),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final total = _items.length;
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            key: const Key('labeler-close'),
            tooltip: 'Close (Esc)',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Icon(HarvestStyle.categoryIcon(widget.model.key), size: 20, color: HarvestStyle.categoryColor(widget.model.key)),
          const SizedBox(width: 8),
          Text(widget.model.tileName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_item != null) ...[
            IconButton(
              key: const Key('zoom-out'),
              tooltip: 'Zoom out (-)',
              color: Colors.white70,
              icon: const Icon(Icons.zoom_out),
              onPressed: _zoom > 1 ? () => _zoomBy(1 / _zoomStep) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(_zoom > 1 ? '${_zoom.toStringAsFixed(1)}×' : 'Fit',
                  key: const Key('zoom-level'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
            IconButton(
              key: const Key('zoom-in'),
              tooltip: 'Zoom in (+, or the mouse wheel)',
              color: Colors.white70,
              icon: const Icon(Icons.zoom_in),
              onPressed: _zoom < _maxZoom ? () => _zoomBy(_zoomStep) : null,
            ),
            IconButton(
              key: const Key('zoom-fit'),
              tooltip: 'Fit the whole picture (0)',
              color: Colors.white70,
              icon: const Icon(Icons.fit_screen),
              onPressed: _zoom > 1 ? () => setState(_resetZoom) : null,
            ),
            const SizedBox(width: 16),
          ],
          if (_queue != null && total > 0)
            Text(_finished ? '$total of $total' : '${_i + 1} of $total',
                key: const Key('labeler-progress'), style: const TextStyle(color: Colors.white70)),
        ]),
        if (_queue != null && total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _answered.length / total,
              minHeight: 3,
              color: const Color(0xFF4CC38A),
              backgroundColor: Colors.white12,
            ),
          ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    if (_queue == null) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty || _finished) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 72, color: Color(0xFF4CC38A)),
          const SizedBox(height: 16),
          Text(_items.isEmpty ? 'Nothing to check' : 'All done',
              key: const Key('labeler-done'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          FilledButton(key: const Key('labeler-finish'), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ]),
      );
    }
    final item = _item!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, box) {
        final fitted = applyBoxFit(BoxFit.contain, Size(item.aspect, 1), box.biggest).destination;
        final dest = Alignment.center.inscribe(fitted, Offset.zero & box.biggest);
        _canvas = dest.size;
        _clampPan();
        return Stack(children: [
          Positioned.fromRect(
            rect: dest,
            // The wheel and the middle / right button work on the picture area itself; the canvas inside is scaled and moved,
            // and Flutter hands its gestures local (unzoomed) positions, so the box maths needs no change.
            child: Listener(
              onPointerSignal: _onSignal,
              onPointerMove: _onPointerMove,
              child: MouseRegion(
                cursor: _space ? (_drag == _Drag.pan ? SystemMouseCursors.grabbing : SystemMouseCursors.grab) : MouseCursor.defer,
                child: Stack(fit: StackFit.expand, children: [
                  ClipRect(
                    child: Transform(
                      transform: Matrix4.translationValues(_pan.dx, _pan.dy, 0)..scaleByDouble(_zoom, _zoom, 1, 1),
                      child: GestureDetector(
                        key: const Key('labeler-canvas'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down, // a box starts exactly where the finger / mouse went down
                        onPanStart: _panStart,
                        onPanUpdate: _panUpdate,
                        onPanEnd: _panEnd,
                        onTapUp: _tapUp,
                        child: Stack(fit: StackFit.expand, children: [
                          Image(image: widget.labeling.image(widget.model.key, item.id), fit: BoxFit.fill, gaplessPlayback: true),
                          CustomPaint(painter: _BoxesPainter(boxes: _boxes, selected: _selected, classes: _classes, zoom: _zoom)),
                        ]),
                      ),
                    ),
                  ),
                  if (_zoom > 1)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Container(
                          key: const Key('zoom-hint'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                          child: Text('${_zoom.toStringAsFixed(1)}×   hold Space + drag to move   0 = fit',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final item = _item!;
    final multi = _classes.length > 1;
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, key: const Key('labeler-error'), style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 16,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const Key('labeler-back'),
                tooltip: 'Previous picture (←)',
                color: Colors.white70,
                onPressed: _i > 0 ? () => _go(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(widget.model.ask, style: const TextStyle(color: Colors.white, fontSize: 16)),
              if (item.reason.isNotEmpty)
                Tooltip(
                  message: item.reason,
                  child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.help_outline, size: 18, color: Colors.white38)),
                ),
              if (item.suggested && item.boxes.isNotEmpty && !_answered.contains(item.id))
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text('the system drew these', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
            ]),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
              if (multi)
                for (var k = 0; k < _classes.length; k++)
                  ChoiceChip(
                    key: Key('class-$k'),
                    selected: _cls == k,
                    onSelected: (_) => _pickClass(k),
                    avatar: Container(width: 10, height: 10, decoration: BoxDecoration(color: HarvestStyle.boxColor(k), shape: BoxShape.circle)),
                    label: Text('${k + 1}  ${friendlyClass(_classes[k])}', style: const TextStyle(fontSize: 13)),
                    visualDensity: VisualDensity.compact,
                  ),
              if (multi) const SizedBox(width: 4),
              TextButton(
                key: const Key('not-sure'),
                onPressed: _busy ? null : _notSure,
                child: const Text('Not sure  (S)'),
              ),
              OutlinedButton(
                key: const Key('nothing-here'),
                onPressed: _busy ? null : _nothingHere,
                child: const Text('Nothing here  (N)'),
              ),
              FilledButton.icon(
                key: const Key('looks-right'),
                onPressed: (_busy || _boxes.isEmpty) ? null : _looksRight,
                icon: const Icon(Icons.check, size: 20),
                label: const Text('Looks right  (Enter)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC38A),
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(0, 48),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ],
        ),
      ]),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter({required this.boxes, required this.selected, required this.classes, this.zoom = 1});

  final List<_Box> boxes;
  final int selected;
  final List<String> classes;

  /// The painting is scaled by the zoom, so lines, handles and the name chip are divided by it to keep their on-screen size.
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final s = 1 / zoom;
    for (var k = 0; k < boxes.length; k++) {
      final b = boxes[k];
      final color = HarvestStyle.boxColor(b.cls);
      final r = Rect.fromLTRB(b.rect.left * size.width, b.rect.top * size.height, b.rect.right * size.width, b.rect.bottom * size.height);
      final isSelected = k == selected;
      if (isSelected) {
        canvas.drawRect(r.inflate(2 * s), Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s);
      }
      canvas.drawRect(r, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (isSelected ? 4 : 3) * s);
      // the class name, on the top-left corner
      if (b.cls >= 0 && b.cls < classes.length && classes.length > 1) {
        final tp = TextPainter(
          text: TextSpan(text: friendlyClass(classes[b.cls]), style: TextStyle(color: Colors.white, fontSize: 12 * s, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        final chip = Rect.fromLTWH(r.left, (r.top - tp.height - 4 * s).clamp(0.0, size.height), tp.width + 8 * s, tp.height + 4 * s);
        canvas.drawRect(chip, Paint()..color = color);
        tp.paint(canvas, chip.topLeft + Offset(4 * s, 2 * s));
      }
      if (isSelected) {
        for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
          canvas.drawRect(Rect.fromCenter(center: c, width: 12 * s, height: 12 * s), Paint()..color = Colors.white);
          canvas.drawRect(Rect.fromCenter(center: c, width: 12 * s, height: 12 * s), Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * s);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => true; // the boxes are edited in place
}
