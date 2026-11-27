import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../domain/time_format.dart';
import '../../domain/trim_session.dart';
import '../../domain/trimmer_controller.dart';
import '../widgets/bench_stats_panel.dart';
import '../widgets/clip_panel.dart';
import '../widgets/label_palette.dart';
import '../widgets/jobs_panel.dart';
import '../widgets/trim_player.dart';
import '../widgets/trim_timeline.dart';
import '../widgets/video_zoom.dart';

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
    final note = _c.notice;
    if (note != null) {
      _c.clearNotice();
      _toast(note);
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
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      shift ? _redo(s) : _undo(s);                                      // Ctrl+Z undoes, Ctrl+Shift+Z redoes
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyY) {
      _redo(s);
      return KeyEventResult.handled;
    }
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
    } else if (_c.benchmarkMode && key == LogicalKeyboardKey.bracketLeft) {
      s.markIn = now;                                                  // "[": the slice starts here
      s.refresh();
      _toast('Slice starts at ${formatClock(now)}. Press ] where it ends.');
    } else if (_c.benchmarkMode && key == LogicalKeyboardKey.bracketRight) {
      final from = s.markIn;
      if (from == null || now - from < TrimSession.minLength) {
        _toast('Press [ where the slice starts, then ] where it ends.');
      } else {
        s.markIn = null;
        s.addClip(from, now);                                          // the new slice is selected: pick its label next
      }
    } else if (_c.benchmarkMode && key == LogicalKeyboardKey.keyC && !HardwareKeyboard.instance.isControlPressed) {
      _label(s, cleanLabel);
    } else if (_c.benchmarkMode && _digit(key) != null && _digit(key)! <= quickLabelKeys.length) {
      _label(s, quickLabelKeys[_digit(key)! - 1]);
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (s.removeSelected() == 0 && s.selected.isNotEmpty) _toast('Locked clips stay. Unlock to delete.');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _undo(TrimSession s) {
    if (!s.undo()) _toast('Nothing to undo.');
  }

  void _redo(TrimSession s) {
    if (!s.redo()) _toast('Nothing to redo.');
  }

  static int? _digit(LogicalKeyboardKey key) {
    const keys = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    final i = keys.indexOf(key);
    return i < 0 ? null : i + 1;
  }

  void _label(TrimSession s, String key) {
    if (s.selected.isEmpty) {
      _toast('Click a slice on the timeline first, then pick its label.');
    } else if (s.toggleLabel(key) == 0) {
      _toast('Those slices are locked or already exported.');
    }
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
      Text(_c.benchmarkMode ? 'Benchmark labelling' : 'Video trimmer', style: Fx.title(context)),
      const SizedBox(width: Fx.s12),
      SegmentedButton<bool>(
        key: const ValueKey('trimmer-mode'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.content_cut, size: 16), label: Text('Trim')),
          ButtonSegment(value: true, icon: Icon(Icons.label_outline, size: 16), label: Text('Label for benchmark')),
        ],
        selected: {_c.benchmarkMode},
        onSelectionChanged: (v) => _c.setBenchmarkMode(v.first),
      ),
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
                  VideoZoom(key: ValueKey('zoom-${session.path}'), child: _player.view()),
                  ValueListenableBuilder<double>(
                    valueListenable: _player.duration,
                    builder: (context, length, _) => length > 0 || _player.openedPath != session.path
                        ? const SizedBox.shrink()
                        : Center(
                            child: ValueListenableBuilder<String?>(
                              valueListenable: trimPreviewStatus,
                              builder: (context, status, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: Fx.s12),
                                Text(status ?? 'Opening the video…', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                              ]),
                            ),
                          ),
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
                  playing: _player.playing,
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
            _c.benchmarkMode
                ? 'Drag on the timeline (or press [ and ]) to slice · click a slice, then a label (or press 1-9, C) · Space plays · I / O trim the slice · Delete removes it'
                : 'Drag an edge to trim · drag the middle to slide · drag on empty space for a new clip · Space plays · I / O set the start / end · L locks · A adds a clip',
            style: Fx.caption(context),
          ),
        ]),
      ),
      const SizedBox(width: Fx.s16),
      SizedBox(width: 300, child: ListenableBuilder(listenable: session, builder: (context, _) => _sidebar(session))),
    ]);
  }

  /// The right sidebar: the whole column scrolls, and each part is a dropdown section that can be folded away.
  Widget _sidebar(TrimSession session) {
    ClipPanel clipPanel(ClipPart part) => ClipPanel(
          part: part,
          session: session,
          controller: _c,
          position: _player.position,
          onSeek: _seek,
          onPlayClip: _playClip,
          pickFolder: widget.pickFolder,
          onMessage: _toast,
        );
    return ListView(padding: const EdgeInsets.only(right: 4), children: [
      if (_c.benchmarkMode)
        _SideSection(
          key: const ValueKey('section-labels'),
          title: 'Labels',
          subtitle: session.selected.isEmpty ? 'click a slice' : '${session.selected.length} selected',
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) => session.selected.isEmpty
                ? Padding(padding: const EdgeInsets.all(Fx.s12), child: Text('Click a slice on the timeline to label it.', style: Fx.caption(context)))
                : SizedBox(height: 420, child: LabelPanel(session: session, onMessage: _toast)),
          ),
        ),
      _SideSection(
        key: const ValueKey('section-slices'),
        title: 'Slices',
        subtitle: '${session.clips.length}',
        child: clipPanel(ClipPart.list),
      ),
      _SideSection(
        key: const ValueKey('section-export'),
        title: _c.benchmarkMode ? 'Export to benchmark' : 'Export',
        child: clipPanel(ClipPart.footer),
      ),
      if (_c.benchmarkMode)
        _SideSection(
          key: const ValueKey('section-stats'),
          title: 'Benchmark folder',
          subtitle: _c.stats == null ? null : '${_c.stats!.clips} clips',
          child: BenchStatsPanel(controller: _c),
        ),
      _SideSection(
        key: const ValueKey('section-jobs'),
        title: 'Exports',
        subtitle: _c.activeJobCount > 0 ? '${_c.activeJobCount} running' : null,
        child: JobsPanel(controller: _c, reveal: widget.reveal, onMessage: _toast),
      ),
    ]);
  }

  /// One small button that moves the playhead by [seconds] (negative = back). Left / Right arrows move 1 s, with Shift 10 s.
  Widget _jump(int seconds) {
    final back = seconds < 0;
    return Tooltip(
      message: back ? 'Back ${-seconds} seconds' : 'Forward $seconds seconds',
      child: TextButton(
        key: ValueKey('jump-$seconds'),
        style: TextButton.styleFrom(minimumSize: const Size(34, 34), padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
        onPressed: () => _seek(_player.position.value + seconds),
        child: Text(back ? '−${-seconds}' : '+$seconds', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
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
      IconButton(tooltip: 'Undo (Ctrl+Z)', icon: const Icon(Icons.undo), onPressed: session.canUndo ? () => _undo(session) : null),
      IconButton(tooltip: 'Redo (Ctrl+Y)', icon: const Icon(Icons.redo), onPressed: session.canRedo ? () => _redo(session) : null),
      for (final step in const [8, 5, 3]) _jump(-step),
      for (final step in const [3, 5, 8]) _jump(step),
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

/// One dropdown part of the sidebar: a title row that folds the part away, open at first.
class _SideSection extends StatelessWidget {
  const _SideSection({super.key, required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Fx.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: Fx.border(context)), borderRadius: BorderRadius.circular(Fx.radiusSm)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            maintainState: true,
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: Fx.s12),
            childrenPadding: const EdgeInsets.fromLTRB(Fx.s8, 0, Fx.s8, Fx.s8),
            title: Text(title.toUpperCase(), style: Fx.label(context)),
            subtitle: subtitle == null ? null : Text(subtitle!, style: Fx.caption(context)),
            children: [child],
          ),
        ),
      ),
    );
  }
}
