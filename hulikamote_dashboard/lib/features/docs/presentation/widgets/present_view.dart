import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/live_slides.dart';
import '../../domain/palette/doc_palette.dart';
import 'acronym_text.dart';

/// Full-screen, one-slide-at-a-time presentation. Arrow keys, Space, or the buttons move;
/// Esc (or the X) closes. Built for people who want one small idea at a time.
class PresentView extends StatefulWidget {
  final List<LiveSlide> slides;
  final DocPalette palette;
  final VoidCallback onClose;

  const PresentView({
    super.key,
    required this.slides,
    required this.palette,
    required this.onClose,
  });

  @override
  State<PresentView> createState() => _PresentViewState();
}

class _PresentViewState extends State<PresentView> {
  int _index = 0;
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _isFirst => _index == 0;
  bool get _isLast => _index == widget.slides.length - 1;

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.slides.length - 1);
    if (next != _index) setState(() => _index = next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.pageDown) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _index = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final slide = widget.slides[_index];
    final total = widget.slides.length;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        color: p.page,
        child: Column(
          children: [
            // Top: where we are, and a way out.
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 12, 0),
              child: Row(
                children: [
                  Text(
                    slide.section.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close (Esc)',
                    icon: Icon(Icons.close_rounded, color: p.muted),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // The slide. Tap the left or right half to move.
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _go(-1),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Flexible(
                    flex: 6,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _SlideBody(key: ValueKey(_index), slide: slide, palette: p),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _go(1),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom: a thin progress line, the count, and the two buttons.
            LinearProgressIndicator(
              value: (_index + 1) / total,
              minHeight: 3,
              color: p.accent,
              backgroundColor: p.border,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back (←)',
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: p.ink2,
                    onPressed: _isFirst ? null : () => _go(-1),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / $total',
                    style: TextStyle(fontSize: 13, color: p.muted),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _isLast ? 'Close' : 'Next (→)',
                    icon: Icon(_isLast ? Icons.check_rounded : Icons.arrow_forward_rounded),
                    color: p.accent,
                    onPressed: _isLast ? widget.onClose : () => _go(1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideBody extends StatelessWidget {
  final LiveSlide slide;
  final DocPalette palette;

  const _SlideBody({super.key, required this.slide, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: p.soft, shape: BoxShape.circle),
            child: Icon(slide.icon, size: 40, color: p.accent),
          ),
          const SizedBox(height: 28),
          Text.rich(
            TextSpan(
              children: AcronymText.spans(
                slide.title,
                TextStyle(fontSize: 38, fontWeight: FontWeight.w700, height: 1.15, color: p.ink),
                p,
              ),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Text.rich(
            TextSpan(
              children: AcronymText.spans(
                slide.text,
                TextStyle(fontSize: 22, height: 1.5, color: p.ink2),
                p,
              ),
            ),
            textAlign: TextAlign.center,
          ),
          if (slide.code != null) ...[
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.border),
              ),
              child: Text(
                slide.code!,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13.5, color: p.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
