import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/time_format.dart';
import '../../domain/trim_session.dart';
import '../../domain/trimmer_controller.dart';
import '../widgets/clip_panel.dart';
import '../widgets/jobs_panel.dart';
import '../widgets/trim_player.dart';
import '../widgets/trim_timeline.dart';

Future<String?> pickVideoFile() async => (await FilePicker.pickFile(type: FileType.video))?.path;

Future<String?> pickFolderPath() => FilePicker.getDirectoryPath();

/// Shows a file in its folder.
Future<void> revealInFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,${path.replaceAll('/', '\\')}']);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {
    // the path is also shown and can be copied
  }
}

/// The video trimmer: open one or more videos, mark clips on the timeline (drag the edges to trim, drag on an empty spot
/// to make a new one), pick several, lock the ones that are done, and export them all. Exports run in the background, so
/// the next video can be opened and edited while earlier clips are still being cut.
class TrimmerScreen extends StatefulWidget {
  const TrimmerScreen({
    super.key,
    this.controller,
    this.playerFactory = defaultTrimPlayer,
    this.player,
    this.pickVideo = pickVideoFile,
    this.pickFolder = pickFolderPath,
    this.reveal = revealInFolder,
    this.onBack,
  });

  /// Kept by whoever owns it when the trimmer must remember its videos and exports after leaving the page.
  final TrimmerController? controller;
  final TrimPlayerFactory playerFactory;

  /// A player kept alive by the owner, so leaving the page and coming back does not start a new one.
  final TrimPlayer? player;
  final Future<String?> Function() pickVideo;
  final Future<String?> Function() pickFolder;
  final Future<void> Function(String path) reveal;
  final VoidCallback? onBack;

  @override
  State<TrimmerScreen> createState() => _TrimmerScreenState();
}

class _TrimmerScreenState extends State<TrimmerScreen> {
  late final bool _ownsController = widget.controller == null;
  late final TrimmerController _c = widget.controller ?? TrimmerController();
  late final bool _ownsPlayer = widget.player == null;
  late final TrimPlayer _player = widget.player ?? widget.playerFactory();
  late final ScrubSeeker _scrubber = ScrubSeeker(_player.seek);     // dragging along the ruler asks for many moments: only the newest counts
  final _focus = FocusNode(debugLabel: 'trimmer');

  TrimSession? _shown;                    // the video that is open in the player
  bool _awaitingLength = false;           // opened, and the position is restored once the player knows its length
  ({double start, double end})? _range;   // playing one clip: stop at its end
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _player.position.addListener(_onPosition);
    _player.duration.addListener(_onLength);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onController());
  }

  @override
  void dispose() {
    _shown?.position = _player.position.value;
    _c.removeListener(_onController);
    _player.position.removeListener(_onPosition);
    _player.duration.removeListener(_onLength);
    if (_ownsPlayer) {
      _player.dispose();
    } else {
      _player.pause();                                     // the owner keeps it; it must not play on behind another page
    }
    _focus.dispose();
    if (_ownsController) _c.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onController() {
    if (!mounted) return;
    final problem = _c.error;
    if (problem != null) {
      _c.clearError();
      _toast(problem);
    }
    if (_c.active != _shown) _show(_c.active);
  }

  /// Puts the video on screen in the player and remembers where the previous one was left.
  Future<void> _show(TrimSession? session) async {
    _shown?.position = _player.position.value;
    _shown = session;
    _range = null;
    _zoom = 1;
    if (session == null) {
      await _player.pause();
    } else if (_player.openedPath == session.path) {
      _awaitingLength = false;                             // it is still open in the kept player: just go back to where it was
      await _player.pause();
      if (session.position > 0) await _player.seek(session.position);
    } else {
      _awaitingLength = true;
      await _player.open(session.path);
    }
    if (mounted) setState(() {});
  }

  void _onLength() {
    final s = _shown;
    if (!_awaitingLength || s == null) return;
    final length = _player.duration.value;
    if (length <= 0) return;
    if (!s.ready) s.setInfo(duration: length);                      // the player knew before the backend did
    if ((length - s.duration).abs() < 1.5) {                        // it is this video's length, not the previous one's
      _awaitingLength = false;
      if (s.position > 0) _player.seek(s.position);
    }
  }

  void _onPosition() {
    final range = _range;
    if (range != null && _player.position.value >= range.end) {
      _range = null;
      _player.pause();
    }
  }

  Future<void> _openVideo() async {
    final path = await widget.pickVideo();
    if (path != null) await _c.open(path);
  }

  void _seek(double seconds) {
    final s = _c.active;
    if (s == null) return;
    final t = seconds.clamp(0.0, s.duration);
    _range = null;
    _scrubber.request(t);
    s.position = t;
  }

  /// A clip of 10 seconds starting wherever the video is right now.
  void _addClipAtPlayhead(TrimSession session) {
    session.position = _player.position.value;
    session.addAtPlayhead();
  }

  void _playClip(TrimClip clip) {
    _range = (start: clip.start, end: clip.end);
    _player.seek(clip.start);
    _player.play();
  }

  void _togglePlay() => _player.playing.value ? _player.pause() : _player.play();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;                                   // typing in a box: keys are for the text
    }
    final s = _c.active;
    if (s == null || !s.ready) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final one = s.selectedClips.length == 1 ? s.selectedClips.first : null;
    final now = _player.position.value;
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seek(now - (shift ? 10 : 1));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seek(now + (shift ? 10 : 1));
    } else if (key == LogicalKeyboardKey.comma) {
      _seek(now - 1 / s.fps);
    } else if (key == LogicalKeyboardKey.period) {
      _seek(now + 1 / s.fps);
    } else if (key == LogicalKeyboardKey.keyA && !HardwareKeyboard.instance.isControlPressed) {
      _addClipAtPlayhead(s);
    } else if (key == LogicalKeyboardKey.keyI && one != null) {
      s.setStart(one.id, now);
    } else if (key == LogicalKeyboardKey.keyO && one != null) {
      s.setEnd(one.id, now);
    } else if (key == LogicalKeyboardKey.keyL && s.selected.isNotEmpty) {
      s.lockSelected(!s.selectedClips.every((c) => c.locked));
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (s.removeSelected() == 0 && s.selected.isNotEmpty) _toast('Locked clips stay. Unlock to delete.');
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
        listenable: _c,
        builder: (context, _) {
          final session = _c.active;
          return Padding(
            padding: const EdgeInsets.all(Fx.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _header(context),
              const SizedBox(height: Fx.s12),
              Expanded(child: session == null ? _empty() : _workspace(context, session)),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      if (widget.onBack != null) IconButton(tooltip: 'Back to the tools', icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      Text('Video trimmer', style: Fx.title(context)),
      const SizedBox(width: Fx.s16),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < _c.sessions.length; i++) _tab(context, i),
          ]),
        ),
      ),
      const SizedBox(width: Fx.s8),
      FilledButton.icon(onPressed: _openVideo, icon: const Icon(Icons.video_file_outlined), label: Text(_c.sessions.isEmpty ? 'Open a video' : 'Open another video')),
    ]);
  }

  Widget _tab(BuildContext context, int i) {
    final s = _c.sessions[i];
    final selected = i == _c.activeIndex;
    final exporting = _c.jobsFor(s).where((j) => j.active).length;
    return Padding(
      padding: const EdgeInsets.only(right: Fx.s8),
      child: InputChip(
        key: ValueKey('tab-${s.path}'),
        selected: selected,
        showCheckmark: false,
        avatar: exporting > 0 ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.movie_outlined, size: 16),
        label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(exporting > 0 ? '${s.name} · $exporting exporting' : s.name, overflow: TextOverflow.ellipsis)),
        onPressed: () => _c.activate(i),
        onDeleted: () => _c.close(i),
        deleteButtonTooltipMessage: 'Close this video (its exports keep going)',
      ),
    );
  }

  Widget _empty() {
    return EmptyState(
      icon: Icons.content_cut,
      title: 'Open a video to trim it',
      message: 'Mark as many clips as you like, lock the finished ones, and export them together. '
          'Exports run in the background, so you can open the next video right away.',
      action: FilledButton.icon(onPressed: _openVideo, icon: const Icon(Icons.video_file_outlined), label: const Text('Open a video')),
    );
  }

  Widget _workspace(BuildContext context, TrimSession session) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Fx.radius),
              child: ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  _player.view(),
                  ValueListenableBuilder<double>(
                    valueListenable: _player.duration,
                    builder: (context, length, _) => length > 0 || _player.openedPath != session.path
                        ? const SizedBox.shrink()
                        : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(),
                            SizedBox(height: Fx.s12),
                            Text('Opening the video…', style: TextStyle(color: Colors.white70)),
                          ])),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: Fx.s8),
          ListenableBuilder(
            listenable: session,
            builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _transport(context, session),
              const SizedBox(height: Fx.s8),
              if (session.ready)
                TrimTimeline(
                  key: ValueKey(session.path),
                  session: session,
                  position: _player.position,
                  onSeek: _seek,
                  onInteract: _focus.requestFocus,
                  zoom: _zoom,
                  onZoom: (z) => setState(() => _zoom = z),
                  filmstripUrl: _c.api.filmstripUrl(session.path),
                )
              else
                SizedBox(
                  height: 112,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: Fx.s12),
                    Text('Reading the video…', style: Fx.caption(context)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: Fx.s4),
          Text(
            'Drag an edge to trim · drag the middle to slide · drag on empty space for a new clip · Space plays · I / O set the start / end · L locks · A adds a clip',
            style: Fx.caption(context),
          ),
        ]),
      ),
      const SizedBox(width: Fx.s16),
      SizedBox(
        width: 400,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipPanel(
              session: session,
              controller: _c,
              position: _player.position,
              onSeek: _seek,
              onPlayClip: _playClip,
              pickFolder: widget.pickFolder,
              onMessage: _toast,
            ),
          ),
          const Divider(height: Fx.s24),
          JobsPanel(controller: _c, reveal: widget.reveal, onMessage: _toast),
        ]),
      ),
    ]);
  }

  Widget _transport(BuildContext context, TrimSession session) {
    return Row(children: [
      ValueListenableBuilder<bool>(
        valueListenable: _player.playing,
        builder: (context, playing, _) => IconButton.filledTonal(
          tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
      ),
      IconButton(tooltip: 'Back 1 second (Left arrow)', icon: const Icon(Icons.replay_5), onPressed: () => _seek(_player.position.value - 1)),
      IconButton(tooltip: 'Forward 1 second (Right arrow)', icon: const Icon(Icons.forward_5), onPressed: () => _seek(_player.position.value + 1)),
      ValueListenableBuilder<double>(
        valueListenable: _player.position,
        builder: (context, position, _) => Text('${formatClock(position)} / ${formatClock(session.duration)}', style: Fx.plate.copyWith(fontSize: 14)),
      ),
      const Spacer(),
      FilledButton.tonalIcon(
        onPressed: session.ready ? () => _addClipAtPlayhead(session) : null,
        icon: const Icon(Icons.add),
        label: const Text('Add clip at the playhead'),
      ),
      const SizedBox(width: Fx.s12),
      IconButton(tooltip: 'Zoom out', icon: const Icon(Icons.zoom_out), onPressed: _zoom <= 1 ? null : () => setState(() => _zoom = math.max(1, _zoom / 1.5))),
      SizedBox(width: 44, child: Text('×${_zoom.toStringAsFixed(_zoom < 10 ? 1 : 0)}', textAlign: TextAlign.center, style: Fx.caption(context))),
      IconButton(tooltip: 'Zoom in (Ctrl + mouse wheel)', icon: const Icon(Icons.zoom_in), onPressed: () => setState(() => _zoom = math.min(80, _zoom * 1.5))),
    ]);
  }
}
