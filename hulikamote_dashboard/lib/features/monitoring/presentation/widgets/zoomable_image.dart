import 'package:flutter/material.dart';

import 'package:hulikamote_dashboard/core/theme/light_mode.dart';
import '../../../forensic/presentation/widgets/fx.dart';

/// A picture from the network that can be zoomed: mouse wheel, pinch, the + / - buttons or a double tap; zoomed in, drag to move it.
/// Used for the evidence pictures of the Live Monitor. Give it a new [key] per picture so each starts fitted.
class ZoomableImage extends StatefulWidget {
  const ZoomableImage({super.key, required this.url, this.maxScale = 10, this.onFullScreen});

  final String url;

  /// When given, the bar has a button for the full-screen view.
  final VoidCallback? onFullScreen;
  final double maxScale;

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  final TransformationController _c = TransformationController();
  Size _box = Size.zero;
  Offset _tapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _scale => _c.value.getMaxScaleOnAxis();

  /// Zoom by [factor] around [focus] (the box's own pixels); at 1x the picture is back in place.
  void _zoomBy(double factor, [Offset? focus]) {
    final now = _scale;
    final next = (now * factor).clamp(1.0, widget.maxScale);
    if (next <= 1.001) {
      _c.value = Matrix4.identity();
      return;
    }
    final k = next / now;
    final at = focus ?? Offset(_box.width / 2, _box.height / 2);
    _c.value = (Matrix4.identity()
          ..translate(at.dx, at.dy)
          ..scale(k)
          ..translate(-at.dx, -at.dy)) *
        _c.value;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _box = Size(box.maxWidth, box.maxHeight);
      return Stack(fit: StackFit.expand, children: [
        GestureDetector(
          onDoubleTapDown: (d) => _tapAt = d.localPosition,
          onDoubleTap: () => _scale > 1.05 ? _c.value = Matrix4.identity() : _zoomBy(3, _tapAt),
          child: InteractiveViewer(
            transformationController: _c,
            minScale: 1,
            maxScale: widget.maxScale,
            child: Center(
              child: KeepColors(child: Image.network(widget.url, fit: BoxFit.contain)),
            ),
          ),
        ),
        Positioned(top: 8, right: 8, child: _bar()),
      ]);
    });
  }

  Widget _bar() {
    const tint = Colors.white;
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: const ValueKey('evidence-zoom-out'),
          tooltip: 'Zoom out',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _scale > 1.001 ? () => _zoomBy(1 / 1.5) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 46,
          child: Text('${(_scale * 100).round()}%', key: const ValueKey('evidence-zoom-level'), textAlign: TextAlign.center, style: const TextStyle(color: tint, fontSize: 12)),
        ),
        IconButton(
          key: const ValueKey('evidence-zoom-in'),
          tooltip: 'Zoom in (or mouse wheel, pinch, double tap). Zoomed in, drag the picture to move it.',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _scale < widget.maxScale - 0.01 ? () => _zoomBy(1.5) : null,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          key: const ValueKey('evidence-zoom-fit'),
          tooltip: 'Show the whole picture',
          visualDensity: VisualDensity.compact,
          color: tint,
          onPressed: _scale > 1.001 ? () => _c.value = Matrix4.identity() : null,
          icon: const Icon(Icons.fit_screen),
        ),
        if (widget.onFullScreen != null)
          IconButton(
            key: const ValueKey('evidence-fullscreen'),
            tooltip: 'Full screen (F)',
            visualDensity: VisualDensity.compact,
            color: tint,
            onPressed: widget.onFullScreen,
            icon: const Icon(Icons.open_in_full),
          ),
      ]),
    );
  }
}
