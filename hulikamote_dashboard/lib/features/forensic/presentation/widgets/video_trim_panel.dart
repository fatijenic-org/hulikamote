import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../trimmer/domain/time_format.dart';
import '../../../trimmer/presentation/widgets/range_timeline.dart';
import '../../../trimmer/presentation/widgets/time_field.dart';
import '../../../trimmer/presentation/widgets/trim_player.dart';
import '../../domain/analysis_draft.dart';
import 'fx.dart';

/// The first step once a video is chosen: watch it and pick the part to analyze. The video plays at once (it is opened by
/// its path, not uploaded). Drag the two ends of the range, or drag anywhere on the timeline to scrub through the video;
/// frame buttons and the arrow keys step one frame at a time, so the cut can be placed exactly.
class VideoTrimPanel extends StatefulWidget {
  const VideoTrimPanel({
    super.key,
    required this.draft,
    required this.player,
    required this.preparing,
    required this.onPick,
    this.filmstripUrl,
  });

  final AnalysisDraft draft;
  final TrimPlayer player;

  /// The picture for drawing zones is being looked up (Continue waits for it).
  final bool preparing;
  final VoidCallback onPick;

  /// A strip of frames for behind the timeline (the plain bar is used when it cannot be loaded).
  final String? filmstripUrl;

  @override
  State<VideoTrimPanel> createState() => _VideoTrimPanelState();
}

class _VideoTrimPanelState extends State<VideoTrimPanel> {
  final _focus = FocusNode(debugLabel: 'video-trim');
  late final ScrubSeeker _scrub = ScrubSeeker(widget.player.seek);
  double _zoom = 1;
  double _cursor = 0;                 // where the video was last asked to be (the player reports it a moment later)
  DateTime _askedAt = DateTime.fromMillisecondsSinceEpoch(0);
  ({double start, double end})? _playingPart;

  AnalysisDraft get draft => widget.draft;
  TrimPlayer get player => widget.player;

  @override
  void initState() {
    super.initState();
    player.position.addListener(_onPosition);
    player.duration.addListener(_onLength);
    // The player may already know the length (it was opened before this page showed). Telling the draft while the page is
    // still being built would be a rebuild during build, so it waits for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onLength();
    });
  }

  @override
  void dispose() {
    player.position.removeListener(_onPosition);
    player.duration.removeListener(_onLength);
    player.pause();
    _focus.dispose();
    super.dispose();
  }

  void _onLength() {
    final length = player.duration.value;
    if (length > 0) draft.learnDuration(length);          // the player knows before the backend does
  }

  void _onPosition() {
    final p = player.position.value;
    if (DateTime.now().difference(_askedAt).inMilliseconds > 400) _cursor = p;
    final part = _playingPart;
    if (part != null && player.playing.value && p >= part.end) {
      _playingPart = null;
      player.pause();
    }
  }

  double get _fps => draft.fps > 0 ? draft.fps : 30;
  double get _length => draft.duration;

  /// Show this moment of the video.
  void _seek(double seconds) {
    if (_length <= 0) return;
    _cursor = seconds.clamp(0.0, _length);
    _askedAt = DateTime.now();
    _playingPart = null;
    _scrub.request(_cursor);
  }

  void _step(double seconds) => _seek(_cursor + seconds);

  void _togglePlay() {
    _playingPart = null;
    player.playing.value ? player.pause() : player.play();
  }

  void _playPart() {
    if (_length <= 0) return;
    _playingPart = (start: draft.trimStart, end: draft.effectiveEnd);
    _scrub.request(draft.trimStart);
    player.play();
  }

  /// Start or end moved to the playhead.
  void _startHere() => _setStart(_cursor);
  void _endHere() => _setEnd(_cursor);

  bool _setStart(double t) {
    if (t >= draft.effectiveEnd - 1 / _fps + 1e-9) return false;
    draft.setTrim(start: t);
    return true;
  }

  bool _setEnd(double t) {
    if (t <= draft.trimStart + 1 / _fps - 1e-9 || t > _length + 1e-6) return false;
    draft.setTrim(end: t);
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;                                   // typing in a box: keys are for the text
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final jump = ctrl ? 10.0 : (shift ? 1.0 : 0.0);                    // arrows: a frame; Shift: a second; Ctrl: ten seconds
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _step(jump > 0 ? -jump : -1 / _fps);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _step(jump > 0 ? jump : 1 / _fps);
    } else if (key == LogicalKeyboardKey.comma) {
      _step(-1 / _fps);
    } else if (key == LogicalKeyboardKey.period) {
      _step(1 / _fps);
    } else if (key == LogicalKeyboardKey.keyI) {
      _startHere();
    } else if (key == LogicalKeyboardKey.keyO) {
      _endHere();
    } else if (key == LogicalKeyboardKey.home) {
      _seek(draft.trimStart);
    } else if (key == LogicalKeyboardKey.end) {
      _seek(draft.effectiveEnd);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: draft,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _video(context),
          const SizedBox(height: Fx.s8),
          _transport(context),
          const SizedBox(height: Fx.s8),
          if (_length > 0)
            RangeTimeline(
              duration: _length,
              start: draft.trimStart,
              end: draft.effectiveEnd,
              position: player.position,
              onSeek: (t) {
                if (player.playing.value) player.pause();
                _seek(t);
              },
              onRange: ({double? start, double? end}) => draft.setTrim(start: start, end: end),
              onInteract: _focus.requestFocus,
              filmstripUrl: widget.filmstripUrl,
              zoom: _zoom,
              onZoom: (z) => setState(() => _zoom = z),
            )
          else
            SizedBox(
              height: 100,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: Fx.s12),
                Text('Reading the video…', style: Fx.caption(context)),
              ]),
            ),
          const SizedBox(height: Fx.s12),
          _rangeControls(context),
          const SizedBox(height: Fx.s12),
          _info(context),
          const SizedBox(height: Fx.s8),
          Text(
            'Drag an end of the range, or drag anywhere on the timeline to scrub · arrows step one frame (Shift: 1 s, Ctrl: 10 s) · '
            'I / O set the start / end here · Space plays · Ctrl + wheel zooms',
            style: Fx.caption(context),
          ),
        ]),
      ),
    );
  }

  Widget _video(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Fx.radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(fit: StackFit.expand, children: [
            player.view(),
            ValueListenableBuilder<double>(
              valueListenable: player.duration,
              builder: (context, length, _) => length > 0
                  ? const SizedBox.shrink()
                  : const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: Fx.s12),
                        Text('Opening the video…', style: TextStyle(color: Colors.white70)),
                      ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _transport(BuildContext context) {
    final ready = _length > 0;
    return Row(children: [
      IconButton(tooltip: 'Back 1 second (Shift + Left)', icon: const Icon(Icons.replay), onPressed: ready ? () => _step(-1) : null),
      IconButton(tooltip: 'Back one frame (Left arrow)', icon: const Icon(Icons.skip_previous), onPressed: ready ? () => _step(-1 / _fps) : null),
      ValueListenableBuilder<bool>(
        valueListenable: player.playing,
        builder: (context, playing, _) => IconButton.filledTonal(
          tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: ready ? _togglePlay : null,
        ),
      ),
      IconButton(tooltip: 'Forward one frame (Right arrow)', icon: const Icon(Icons.skip_next), onPressed: ready ? () => _step(1 / _fps) : null),
      IconButton(tooltip: 'Forward 1 second (Shift + Right)', icon: const Icon(Icons.forward_5), onPressed: ready ? () => _step(1) : null),
      const SizedBox(width: Fx.s8),
      ValueListenableBuilder<double>(
        valueListenable: player.position,
        builder: (context, position, _) => Text(
          '${formatClock(position)} / ${formatClock(_length)}  ·  frame ${(position * _fps).round()}',
          style: Fx.plate.copyWith(fontSize: 13),
        ),
      ),
      const Spacer(),
      IconButton(tooltip: 'Zoom out', icon: const Icon(Icons.zoom_out), onPressed: _zoom <= 1 ? null : () => setState(() => _zoom = math.max(1, _zoom / 1.5))),
      SizedBox(width: 44, child: Text('×${_zoom.toStringAsFixed(_zoom < 10 ? 1 : 0)}', textAlign: TextAlign.center, style: Fx.caption(context))),
      IconButton(tooltip: 'Zoom in (Ctrl + mouse wheel)', icon: const Icon(Icons.zoom_in), onPressed: ready ? () => setState(() => _zoom = math.min(200, _zoom * 1.5)) : null),
    ]);
  }

  Widget _rangeControls(BuildContext context) {
    final ready = _length > 0;
    final kept = draft.keptSeconds;
    return Wrap(spacing: Fx.s12, runSpacing: Fx.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 190,
        child: TimeField(
          label: 'Start',
          value: draft.trimStart,
          enabled: ready,
          onSubmit: (t) {
            final ok = _setStart(t);
            if (ok) _seek(t);
            return ok;
          },
          onSetToPlayhead: _startHere,
        ),
      ),
      SizedBox(
        width: 190,
        child: TimeField(
          label: 'End',
          value: draft.effectiveEnd,
          enabled: ready,
          onSubmit: (t) {
            final ok = _setEnd(t);
            if (ok) _seek(t);
            return ok;
          },
          onSetToPlayhead: _endHere,
        ),
      ),
      OutlinedButton.icon(onPressed: ready ? _playPart : null, icon: const Icon(Icons.play_circle_outline, size: 18), label: const Text('Play this part')),
      TextButton(onPressed: draft.trimmed ? draft.resetTrim : null, child: const Text('Use the whole video')),
      if (ready)
        Text(
          draft.trimmed ? 'Analyzing ${formatClock(kept, tenths: false)} of ${formatClock(_length, tenths: false)}' : 'The whole video will be analyzed',
          style: Fx.body(context).copyWith(fontWeight: FontWeight.w600),
        ),
    ]);
  }

  Widget _info(BuildContext context) {
    return FxCard(
      child: Row(children: [
        Icon(widget.preparing ? Icons.hourglass_bottom : Icons.check_circle, color: widget.preparing ? Fx.warning : Fx.success),
        const SizedBox(width: Fx.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(draft.videoName ?? 'Video', style: Fx.heading(context), overflow: TextOverflow.ellipsis),
            Text(
              widget.preparing
                  ? 'Getting the picture for drawing zones…'
                  : [
                      '${draft.fps.toStringAsFixed(0)} fps',
                      if (draft.frameCount > 0) '${draft.frameCount} frames',
                      if (draft.duration > 0) '${draft.duration.toStringAsFixed(0)} s',
                    ].join('  ·  '),
              style: Fx.caption(context),
            ),
          ]),
        ),
        OutlinedButton(onPressed: widget.onPick, child: const Text('Choose another')),
      ]),
    );
  }
}
