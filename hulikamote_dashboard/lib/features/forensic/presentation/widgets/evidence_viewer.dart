import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';
import 'ticket_picker.dart';

/// The open ticket's evidence: one large photo (zoom / pan), a scrubber, and a filmstrip.
///
/// A ticket can have over a hundred photos, so the viewer shows one at a time and lets the
/// reviewer move through them with the buttons, the scrubber, the filmstrip or the arrow keys.
/// "Select photos" ticks photos, to separate them into a new ticket (a different car) or remove them from this one.
class EvidenceViewer extends StatefulWidget {
  const EvidenceViewer({
    super.key,
    required this.controller,
    required this.media,
    this.onJumpToVideo,
    this.onFullscreen,
    this.onMessage,
    this.onClose,
    this.playSignal,
    this.immersive = false,
  });

  final ReviewController controller;
  final ForensicMedia media;

  /// Shows this moment in the result video (tab / seek); null hides the button.
  final void Function(double seconds)? onJumpToVideo;

  /// Opens the fullscreen viewer; null hides the button (already fullscreen).
  final VoidCallback? onFullscreen;
  final void Function(String message)? onMessage;

  /// Fullscreen only: closes the viewer (shown as the last toolbar button).
  final VoidCallback? onClose;

  /// Each change toggles the photo slideshow (the workspace's P key).
  final ValueListenable<int>? playSignal;

  /// Fullscreen: black stage, no card chrome.
  final bool immersive;

  @override
  State<EvidenceViewer> createState() => _EvidenceViewerState();
}

class _EvidenceViewerState extends State<EvidenceViewer> {
  final _zoom = TransformationController();
  final _strip = ScrollController();
  final Set<String> _marked = {};
  int? _anchor; // where a Shift-click range starts
  Timer? _play;
  bool _selecting = false;
  String? _uid;
  int _lastFrame = -1;

  ReviewController get c => widget.controller;
  static const double _thumbW = 124;

  @override
  void initState() {
    super.initState();
    _uid = c.selectedUid;
    c.addListener(_onController);
    widget.playSignal?.addListener(_togglePlay);
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    widget.playSignal?.removeListener(_togglePlay);
    _play?.cancel();
    _zoom.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _onController() {
    if (c.selectedUid != _uid) {
      // A different ticket: start fresh.
      _uid = c.selectedUid;
      _zoom.value = Matrix4.identity();
      _marked.clear();
      _anchor = null;
      _selecting = false;
      _stopPlay();
      _lastFrame = -1;
    }
    if (c.frameIndex != _lastFrame) {
      _lastFrame = c.frameIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollStripTo(c.frameIndex);
        _warmNeighbours();
      });
    }
  }

  void _scrollStripTo(int i) {
    if (!_strip.hasClients) return;
    final view = _strip.position.viewportDimension;
    final target = (i * _thumbW - view / 2 + _thumbW / 2).clamp(0.0, _strip.position.maxScrollExtent);
    _strip.animateTo(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
  }

  /// Decodes the neighbouring photos ahead of time so stepping feels instant.
  void _warmNeighbours() {
    final t = c.selected;
    if (t == null || !mounted) return;
    for (final d in const [1, -1, 2]) {
      final i = c.frameIndex + d;
      if (i >= 0 && i < t.frames.length) {
        precacheImage(widget.media.evidence(t.frames[i].file), context, onError: (_, _) {});
      }
    }
  }

  void _togglePlay() {
    if (_play != null) return _stopPlay();
    final t = c.selected;
    if (t == null || t.frameCount < 2) return;
    if (c.frameIndex >= t.frameCount - 1) c.setFrame(0);
    setState(() {
      _play = Timer.periodic(const Duration(milliseconds: 220), (_) {
        if (c.frameIndex >= (c.selected?.frameCount ?? 1) - 1) return _stopPlay();
        c.stepFrame(1);
      });
    });
  }

  void _stopPlay() {
    _play?.cancel();
    if (_play != null && mounted) setState(() => _play = null);
    _play = null;
  }

  void _toggleZoom(Offset focal) {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      const s = 3.0;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-focal.dx * (s - 1), -focal.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, s, 1);
    }
  }

  /// Click on a photo of the strip. Plain: look at it. Ctrl: add or take away from the selection. Shift: select the
  /// photos from the last clicked one to this one. The photo on screen counts as selected when a selection starts.
  void _tapThumb(ForensicTicket t, int k, int current) {
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final file = t.frames[k].file;
    if (ctrl || shift) {
      setState(() {
        _selecting = true;
        if (_marked.isEmpty) {
          _marked.add(t.frames[current].file);
          _anchor = current;
        }
        if (shift) {
          final from = (_anchor ?? current).clamp(0, t.frameCount - 1);
          if (!ctrl) _marked.clear();
          for (var i = math.min(from, k); i <= math.max(from, k); i++) {
            _marked.add(t.frames[i].file);
          }
        } else {
          _marked.contains(file) ? _marked.remove(file) : _marked.add(file);
          _anchor = k;
        }
      });
    } else if (_selecting) {
      setState(() {
        _marked.contains(file) ? _marked.remove(file) : _marked.add(file);
        _anchor = k;
      });
    }
    c.setFrame(k);
  }

  /// Right-click on a photo: the actions for the selected photos (the clicked one when it was not selected).
  Future<void> _thumbMenu(ForensicTicket t, int k, Offset at) async {
    if (!t.hasUid || t.frameCount < 2) return;
    final file = t.frames[k].file;
    if (!_marked.contains(file)) {
      setState(() {
        _selecting = true;
        _marked
          ..clear()
          ..add(file);
        _anchor = k;
      });
    }
    final n = _marked.length;
    final all = n >= t.frameCount;
    final photos = '$n photo${n == 1 ? '' : 's'}';
    final size = MediaQuery.sizeOf(context);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        PopupMenuItem(
          value: 'aside',
          enabled: !all,
          child: ListTile(dense: true, leading: const Icon(Icons.inventory_2_outlined, size: 18), title: Text('Set $photos aside for later')),
        ),
        PopupMenuItem(
          value: 'new',
          enabled: !all,
          child: ListTile(dense: true, leading: const Icon(Icons.call_split, size: 18), title: Text('New ticket from $photos')),
        ),
        PopupMenuItem(
          value: 'move',
          child: ListTile(dense: true, leading: const Icon(Icons.merge_type, size: 18), title: Text('Move $photos to another ticket…')),
        ),
        PopupMenuItem(
          value: 'remove',
          enabled: !all,
          child: ListTile(dense: true, leading: const Icon(Icons.delete_outline, size: 18), title: Text('Remove $photos from this ticket')),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'clear',
          child: ListTile(dense: true, leading: Icon(Icons.close, size: 18), title: Text('Clear selection')),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'aside':
        await _setAside(t);
      case 'new':
        await _separate(t);
      case 'move':
        await _moveToTicket(t);
      case 'remove':
        await _remove(t);
      case 'clear':
        setState(() {
          _marked.clear();
          _selecting = false;
        });
    }
  }

  Future<void> _moveToTicket(ForensicTicket t) async {
    final files = [for (final f in t.frames) if (_marked.contains(f.file)) f.file];
    if (files.isEmpty) return;
    final n = files.length;
    final whole = n >= t.frameCount;
    final other = await showTicketPickerDialog(
      context,
      controller: c,
      media: widget.media,
      exclude: t,
      title: whole ? 'Merge this ticket into which ticket?' : 'Move $n photo${n == 1 ? '' : 's'} to which ticket?',
      subtitle: whole ? 'Every photo moves, so this ticket is merged into the one you pick.' : 'This ticket keeps the other photos.',
    );
    if (other == null || !mounted) return;
    final ok = await c.moveFramesTo(t, other, files);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _marked.clear();
        _selecting = false;
      });
      widget.onMessage?.call(whole
          ? 'Merged the ticket into #${other.trackId}.'
          : 'Moved $n photo${n == 1 ? '' : 's'} into ticket #${other.trackId}.');
    }
  }

  /// The ticked photos show another car: they leave this ticket and wait in Holding, to be decided there.
  Future<void> _setAside(ForensicTicket t) async {
    final files = [for (final f in t.frames) if (_marked.contains(f.file)) f.file];
    if (files.isEmpty || files.length >= t.frameCount) return;
    final ok = await c.setAside(t, files);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _marked.clear();
        _selecting = false;
      });
      widget.onMessage?.call('Set ${files.length} photo${files.length == 1 ? '' : 's'} aside. They wait in Holding.');
    }
  }

  Future<void> _separate(ForensicTicket t) async {
    final files = [for (final f in t.frames) if (_marked.contains(f.file)) f.file];
    if (files.isEmpty || files.length >= t.frameCount) return;
    final ok = await c.separateFrames(t, files);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _marked.clear();
        _selecting = false;
      });
      widget.onMessage?.call('Moved ${files.length} photo${files.length == 1 ? '' : 's'} into a new ticket.');
    }
  }

  Future<void> _remove(ForensicTicket t) async {
    final files = [for (final f in t.frames) if (_marked.contains(f.file)) f.file];
    if (files.isEmpty || files.length >= t.frameCount) return;
    final n = files.length;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $n photo${n == 1 ? '' : 's'} from this ticket?'),
        content: const Text('They will not be sent to the motorist, and the plate is read again from the photos that stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await c.removeFrames(t, files);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _marked.clear();
        _selecting = false;
      });
      widget.onMessage?.call('Removed $n photo${n == 1 ? '' : 's'} from this ticket.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.selected;
        if (t == null) {
          return const EmptyState(
            icon: Icons.touch_app_outlined,
            title: 'Pick a ticket',
            message: 'Choose a ticket from the queue to see its evidence.',
          );
        }
        if (t.frames.isEmpty) {
          return const EmptyState(
            icon: Icons.no_photography_outlined,
            title: 'No photos for this ticket',
            message: 'The vehicle may have left the frame before a photo could be taken.',
          );
        }
        final i = c.frameIndex.clamp(0, t.frames.length - 1);
        final f = t.frames[i];
        final canSeparate = _marked.isNotEmpty && _marked.length < t.frameCount && t.hasUid && !c.busy;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _toolbar(context, t, f, i),
          const SizedBox(height: Fx.s8),
          Expanded(child: _stage(context, t, f, i)),
          _scrubber(context, t, i),
          _filmstrip(context, t, i),
          if (!_selecting && t.frameCount > 1 && t.hasUid)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Ctrl+click or Shift+click to select photos · right-click for actions', style: Fx.caption(context)),
            ),
          if (_selecting) _selectionBar(context, t, canSeparate),
        ]);
      },
    );
  }

  Widget _toolbar(BuildContext context, ForensicTicket t, EvidenceFrame f, int i) {
    final n = t.frameCount;
    final canSelect = t.frameCount > 1 && t.hasUid;

    Widget btn(IconData icon, String tip, VoidCallback? onTap, {bool on = false}) => IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          color: on ? Fx.accent : null,
          onPressed: onTap,
        );

    void toggleSelect() => setState(() {
          _selecting = !_selecting;
          if (!_selecting) _marked.clear();
        });
    final jump = (widget.onJumpToVideo != null && f.t != null) ? () => widget.onJumpToVideo!(f.t!) : null;

    return LayoutBuilder(builder: (context, box) {
      // Wide: every action is a button. Narrow: the main three, the rest in a menu.
      final compact = box.maxWidth < 860;
      final label = Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('Photo ${i + 1} of $n', style: Fx.heading(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: Fx.s8),
        Text(f.timeLabel, style: Fx.caption(context)),
        if (i == t.heroIndex && n > 1 && !compact) ...[
          const SizedBox(width: Fx.s8),
          const Tooltip(
            message: 'The photo where the vehicle is shown largest',
            child: StatusPill(label: 'Best view', color: Fx.accent, icon: Icons.star_rounded, dense: true),
          ),
        ],
      ]);
      final main = [
        btn(Icons.chevron_left, 'Previous photo (←)', i > 0 ? () => c.stepFrame(-1) : null),
        btn(_play == null ? Icons.play_arrow : Icons.pause, _play == null ? 'Play photos (P)' : 'Pause (P)',
            n > 1 ? _togglePlay : null,
            on: _play != null),
        btn(Icons.chevron_right, 'Next photo (→)', i < n - 1 ? () => c.stepFrame(1) : null),
      ];
      return Row(children: [
        Flexible(child: label),
        const Spacer(),
        if (!compact) btn(Icons.first_page, 'First photo (Home)', i > 0 ? () => c.setFrame(0) : null),
        ...main,
        if (!compact) ...[
          btn(Icons.last_page, 'Last photo (End)', i < n - 1 ? () => c.setFrame(n - 1) : null),
          const SizedBox(width: Fx.s8),
          btn(Icons.zoom_out_map, 'Reset zoom', () => _zoom.value = Matrix4.identity()),
          if (widget.onFullscreen != null) btn(Icons.fullscreen, 'Fullscreen (F)', widget.onFullscreen),
          if (jump != null) btn(Icons.smart_display_outlined, 'Show this moment in the video', jump),
          btn(Icons.checklist, 'Select photos (separate a different car, or remove from this ticket)', canSelect ? toggleSelect : null,
              on: _selecting),
        ] else
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (v) {
              switch (v) {
                case 'first':
                  c.setFrame(0);
                case 'last':
                  c.setFrame(n - 1);
                case 'zoom':
                  _zoom.value = Matrix4.identity();
                case 'full':
                  widget.onFullscreen?.call();
                case 'jump':
                  jump?.call();
                case 'select':
                  toggleSelect();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'first', child: Text('First photo')),
              const PopupMenuItem(value: 'last', child: Text('Last photo')),
              const PopupMenuItem(value: 'zoom', child: Text('Reset zoom')),
              if (widget.onFullscreen != null) const PopupMenuItem(value: 'full', child: Text('Fullscreen')),
              if (jump != null) const PopupMenuItem(value: 'jump', child: Text('Show this moment in the video')),
              if (canSelect)
                PopupMenuItem(value: 'select', child: Text(_selecting ? 'Stop selecting photos' : 'Select photos (separate or remove)')),
            ],
          ),
        if (widget.onClose != null) ...[
          const SizedBox(width: Fx.s8),
          IconButton.filledTonal(icon: const Icon(Icons.close), tooltip: 'Close (Esc)', onPressed: widget.onClose),
        ],
      ]);
    });
  }

  Widget _stage(BuildContext context, ForensicTicket t, EvidenceFrame f, int i) {
    final marked = _marked.contains(f.file);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.immersive ? 0 : Fx.radius),
      child: Container(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          GestureDetector(
            onDoubleTapDown: (d) => _toolbarFocal = d.localPosition,
            onDoubleTap: () => _toggleZoom(_toolbarFocal),
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 6,
              child: FxImage(image: widget.media.evidence(f.file), fit: BoxFit.contain, errorLabel: 'This photo is no longer on disk'),
            ),
          ),
          Positioned(
            left: Fx.s12,
            top: Fx.s12,
            child: Wrap(spacing: 6, children: [
              if (t.vehicleClass != null)
                StatusPill(label: t.vehicleClass!.toUpperCase(), color: Colors.white, icon: Icons.directions_car_filled_outlined, dense: true),
              if (marked) const StatusPill(label: 'Ticked', color: Fx.warning, icon: Icons.check_box, dense: true),
            ]),
          ),
          if (f.plate != null)
            Positioned(
              left: Fx.s12,
              bottom: Fx.s12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(Fx.radiusSm)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pin_outlined, size: 14, color: Fx.warning),
                  const SizedBox(width: 6),
                  Text(f.plate!, style: Fx.plate.copyWith(color: Fx.warning, fontSize: 14)),
                  const SizedBox(width: 6),
                  const Text('read in this photo', style: TextStyle(fontSize: 11, color: Colors.white60)),
                ]),
              ),
            ),
          if (f.details.isNotEmpty) Positioned(right: Fx.s12, bottom: Fx.s12, child: _closeups(context, f)),
          if (i > 0) _edgeButton(Alignment.centerLeft, Icons.chevron_left, () => c.stepFrame(-1)),
          if (i < t.frameCount - 1) _edgeButton(Alignment.centerRight, Icons.chevron_right, () => c.stepFrame(1)),
        ]),
      ),
    );
  }

  Offset _toolbarFocal = Offset.zero;

  /// What the specialist models looked at around this photo (helmet crop, cabin crop ...), one small picture each.
  Widget _closeups(BuildContext context, EvidenceFrame f) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(Fx.radiusSm)),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in f.details)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Tooltip(
              message: '${d.title}: ${d.label}. Click to enlarge.',
              child: InkWell(
                onTap: () => _openCloseup(context, d),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 84, height: 84, child: FxImage(image: widget.media.thumb(d.file, width: 168), radius: 4, fit: BoxFit.cover, errorLabel: '')),
                  const SizedBox(height: 3),
                  Text(d.title, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  void _openCloseup(BuildContext context, FrameDetail d) => showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(Fx.s16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d.title}: ${d.label}', style: Fx.heading(dialog)),
          const SizedBox(height: Fx.s8),
          Text('The picture the model was given, with what it found. Heads are blurred like in every evidence photo.', style: Fx.caption(dialog)),
          const SizedBox(height: Fx.s12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
              child: FxImage(image: widget.media.evidence(d.file), fit: BoxFit.contain, errorLabel: 'This close-up is no longer on disk'),
            ),
          ),
          const SizedBox(height: Fx.s12),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Close'))),
        ]),
      ),
    ),
  );

  Widget _edgeButton(Alignment a, IconData icon, VoidCallback onTap) => Align(
        alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(Fx.s8),
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onTap),
          ),
        ),
      );

  Widget _scrubber(BuildContext context, ForensicTicket t, int i) {
    final n = t.frameCount;
    if (n < 2) return const SizedBox(height: Fx.s8);
    final span = t.span;
    return Row(children: [
      Text(span == null ? '1' : formatVideoTime(span.start), style: Fx.caption(context)),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
          child: Slider(
            value: i.toDouble(),
            min: 0,
            max: (n - 1).toDouble(),
            divisions: n - 1,
            onChanged: (v) => c.setFrame(v.round()),
          ),
        ),
      ),
      Text(span == null ? '$n' : formatVideoTime(span.end), style: Fx.caption(context)),
    ]);
  }

  Widget _filmstrip(BuildContext context, ForensicTicket t, int i) {
    return SizedBox(
      height: 84,
      child: ListView.builder(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        itemExtent: _thumbW,
        itemCount: t.frameCount,
        itemBuilder: (context, k) {
          final f = t.frames[k];
          final selected = k == i;
          final marked = _marked.contains(f.file);
          return Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 4, top: 4),
            child: InkWell(
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(6),
              onTap: () => _tapThumb(t, k, i),
              onSecondaryTapDown: (d) => _thumbMenu(t, k, d.globalPosition),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: marked ? Fx.warning : (selected ? Fx.accent : Colors.transparent),
                    width: selected || marked ? 2 : 1,
                  ),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  FxImage(image: widget.media.thumb(f.file, width: 224), radius: 4, errorLabel: ''),
                  Positioned(
                    left: 4,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                      child: Text('${k + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
                  if (f.plate != null)
                    const Positioned(right: 4, bottom: 3, child: Icon(Icons.pin, size: 12, color: Fx.warning)),
                  if (_selecting)
                    Positioned(
                      left: 2,
                      top: 2,
                      child: Icon(marked ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18, color: marked ? Fx.warning : Colors.white70),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectionBar(BuildContext context, ForensicTicket t, bool canSeparate) {
    final all = _marked.length >= t.frameCount;
    return Container(
      margin: const EdgeInsets.only(top: Fx.s8),
      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s8),
      decoration: BoxDecoration(
        color: Fx.warning.withValues(alpha: 0.12),
        border: Border.all(color: Fx.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(Fx.radiusSm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.checklist, size: 18, color: Fx.warning),
          const SizedBox(width: Fx.s8),
          Expanded(
            child: Text(
              _marked.isEmpty
                  ? 'Tick photos (Ctrl or Shift + click). Then set them aside for later, send them to a new ticket, move them to another ticket, or remove them.'
                  : all
                      ? 'Every photo is ticked: you can move them all to another ticket (a merge).'
                      : '${_marked.length} photo${_marked.length == 1 ? '' : 's'} ticked.',
              style: Fx.body(context),
            ),
          ),
          TextButton(
            onPressed: _marked.isEmpty ? null : () => setState(_marked.clear),
            child: const Text('Clear'),
          ),
        ]),
        const SizedBox(height: Fx.s8),
        Wrap(spacing: Fx.s8, runSpacing: Fx.s8, alignment: WrapAlignment.end, children: [
          OutlinedButton.icon(
            onPressed: canSeparate || (all && _marked.isNotEmpty && t.hasUid && !c.busy) ? () => _moveToTicket(t) : null,
            icon: const Icon(Icons.merge_type, size: 16),
            label: const Text('Move to another ticket'),
          ),
          OutlinedButton.icon(
            onPressed: canSeparate ? () => _remove(t) : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Remove from this ticket'),
          ),
          OutlinedButton.icon(
            onPressed: canSeparate ? () => _separate(t) : null,
            icon: const Icon(Icons.call_split, size: 16),
            label: const Text('Separate into a new ticket'),
          ),
          Tooltip(
            message: 'These photos show another car (the tracker jumped). They wait in Holding until you decide.',
            child: FilledButton.icon(
              key: const Key('set-aside'),
              onPressed: canSeparate ? () => _setAside(t) : null,
              icon: const Icon(Icons.inventory_2_outlined, size: 16),
              label: const Text('Set aside for later'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Fullscreen version of the evidence viewer. Arrow keys step, Esc closes.
Future<void> showEvidenceFullscreen(
  BuildContext context, {
  required ReviewController controller,
  required ForensicMedia media,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(ctx).pop(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => controller.stepFrame(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => controller.stepFrame(1),
          const SingleActivator(LogicalKeyboardKey.home): () => controller.setFrame(0),
          const SingleActivator(LogicalKeyboardKey.end): () => controller.setFrame(1 << 20),
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(Fx.s16),
            child: EvidenceViewer(
              controller: controller,
              media: media,
              immersive: true,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    ),
  );
}
