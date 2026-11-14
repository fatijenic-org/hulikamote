import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_media.dart';
import '../../data/harvest_labeling.dart';
import '../../domain/forensic_models.dart';
import '../../domain/review_controller.dart';
import 'decision_panel.dart';
import 'evidence_viewer.dart';
import 'fx.dart';
import 'harvest_categories_view.dart';
import 'holding_view.dart';
import 'live_preview_panel.dart';
import 'merge_dialog.dart';
import 'plate_reads_panel.dart';
import 'queue_panel.dart';
import 'video_panel.dart';

/// Review workspace for one finished analysis: queue | evidence | decision.
///
/// Wide windows show three panes. Medium windows keep the queue and the evidence and open
/// the decision details in a side drawer (the verdict stays under the photo). Narrow windows
/// tuck the queue into a drawer too. Nothing has a fixed size, so nothing overflows.
class ResultsWorkspace extends StatefulWidget {
  const ResultsWorkspace({
    super.key,
    required this.controller,
    required this.media,
    required this.title,
    this.subtitle,
    this.videoUrl,
    this.videoBuilder = defaultVideoPanel,
    this.previewBuilder = defaultPreviewPanel,
    required this.onBack,
    required this.onNewAnalysis,
    this.onSendToLive,
    this.harvest,
  });

  final ReviewController controller;
  final ForensicMedia media;
  final String title;
  final String? subtitle;
  final String? videoUrl;
  final VideoPanelBuilder videoBuilder;
  final PreviewPanelBuilder previewBuilder; // the Video tab of an analysis that is still running
  final VoidCallback onBack;
  final VoidCallback onNewAnalysis;
  final Future<void> Function()? onSendToLive;

  /// Gives this analysis its own Harvest tab (the pictures that can teach the system). Null = no such tab.
  final HarvestLabeling? harvest;

  @override
  State<ResultsWorkspace> createState() => _ResultsWorkspaceState();
}

class _ResultsWorkspaceState extends State<ResultsWorkspace> {
  static const double _wide = 1240, _narrow = 920;

  final _root = FocusNode(debugLabel: 'forensic-workspace');
  final _plateFocus = FocusNode(debugLabel: 'plate-field');
  final _scaffold = GlobalKey<ScaffoldState>();
  final ValueNotifier<double?> _seek = ValueNotifier<double?>(null);
  final ValueNotifier<int> _playSignal = ValueNotifier<int>(0);
  int _tab = 0; // 0 photos, 1 plate reads, 2 video
  bool _videoOpened = false;
  bool _harvesting = false; // the Harvest tab of this analysis instead of the review
  bool _holdingOpen = false; // Holding (photos set aside from tickets) instead of the review
  bool _showDetails = false; // right column: false = the list of tickets, true = the open ticket's details
  String? _lastUid;
  String? _lastVideo;

  ReviewController get c => widget.controller;

  /// The evidence video: known from the start for a finished run, from the end of the analysis for a running one.
  String? get _videoUrl => c.resultVideo ?? widget.videoUrl;

  @override
  void initState() {
    super.initState();
    _lastUid = c.selectedUid;
    _lastVideo = _videoUrl;
    c.addListener(_onController);
    c.loadHolding(); // photos set aside earlier: the header shows how many wait
  }

  /// Another view (Harvest or Holding) is on screen instead of the review: no ticket shortcuts, no review controls.
  bool get _away => _harvesting || _holdingOpen;

  @override
  void dispose() {
    c.removeListener(_onController);
    _root.dispose();
    _plateFocus.dispose();
    _seek.dispose();
    _playSignal.dispose();
    super.dispose();
  }

  void _onController() {
    if (_videoUrl != _lastVideo) {          // the running analysis finished: its video exists now
      _lastVideo = _videoUrl;
      if (mounted) setState(() {});
    }
    if (c.selectedUid != _lastUid) {
      _lastUid = c.selectedUid;
      // On the video tab, following the selection keeps the video on the ticket's moment.
      final s = c.selected?.span?.start;
      if (_tab == 2 && s != null) _seekVideo(s);
    }
  }

  // ── actions ──
  void _seekVideo(double seconds) {
    _seek.value = null;
    _seek.value = seconds;
  }

  void _showMoment(double seconds) {
    _seekVideo(seconds);
    setState(() {
      _tab = 2;
      _videoOpened = true;
    });
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      if (i == 2) {
        _videoOpened = true;
        final s = c.selected?.span?.start;
        if (s != null && _seek.value == null) _seek.value = s;
      }
    });
  }

  void _toast(String message) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _decide(ReviewStatus s) async {
    final t = c.selected;
    if (t == null || c.busy) return;
    // Pressing the active verdict again clears it.
    final target = c.statusOf(t) == s ? ReviewStatus.pending : s;
    final ok = await c.decide(t.uid, target);
    if (!mounted || !ok) return;
    final who = 'vehicle #${t.trackId}';
    _toast(switch (target) {
      ReviewStatus.confirmed => 'Confirmed $who.',
      ReviewStatus.rejected => 'Marked $who as a false alarm.',
      ReviewStatus.pending => 'Cleared the decision on $who.',
    });
    _root.requestFocus();
  }

  Future<void> _decideBatch(ReviewStatus s) async {
    final n = c.checked.length;
    if (n == 0) return;
    final confirming = s == ReviewStatus.confirmed;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          confirming ? Icons.fact_check_outlined : Icons.report_off_outlined,
          color: confirming ? Fx.warning : Fx.danger,
        ),
        title: Text(
          confirming
              ? 'Confirm $n tickets?'
              : 'Mark $n tickets as false alarms?',
        ),
        content: Text(
          confirming
              ? 'Each ticket is recorded as a confirmed violation. Notifying owners is not set up yet. '
                    'You can still change any of them later.'
              : 'They move out of the to-review list. You can still change any of them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: confirming ? Fx.success : Fx.danger,
              foregroundColor: Colors.black87,
            ),
            child: Text(confirming ? 'Confirm $n' : 'Mark $n'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await c.decideChecked(s);
    if (done && mounted) {
      _toast(
        confirming
            ? 'Confirmed $n tickets.'
            : 'Marked $n tickets as false alarms.',
      );
    }
  }

  Future<void> _merge() async {
    final t = c.selected;
    if (t == null) return;
    await showMergeDialog(
      context,
      controller: c,
      media: widget.media,
      ticket: t,
    );
    if (mounted) _root.requestFocus();
  }

  Future<void> _fullscreen() async {
    if (c.selected == null) return;
    await showEvidenceFullscreen(context, controller: c, media: widget.media);
    if (mounted) _root.requestFocus();
  }

  void _showShortcuts() {
    showDialog<void>(
      context: context,
      builder: (_) => const _ShortcutsDialog(),
    );
  }

  // ── keyboard ──
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _away) return KeyEventResult.ignored; // no ticket shortcuts on the Harvest or Holding view
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final typing =
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (typing) {
        FocusManager.instance.primaryFocus?.unfocus();
        _root.requestFocus();
        return KeyEventResult.handled;
      }
      if (c.checked.isNotEmpty) {
        c.clearChecked();
        return KeyEventResult.handled;
      }
      if (_showDetails) {
        setState(() => _showDetails = false); // back to the list of tickets
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (typing) {
      return KeyEventResult.ignored; // never steal keys from a text field
    }
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final isDown = event is KeyDownEvent;
    if (key == LogicalKeyboardKey.arrowRight) {
      c.stepFrame(hw.isShiftPressed ? 10 : 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      c.stepFrame(hw.isShiftPressed ? -10 : -1);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        (isDown && key == LogicalKeyboardKey.keyJ)) {
      c.selectRelative(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        (isDown && key == LogicalKeyboardKey.keyK)) {
      c.selectRelative(-1);
    } else if (isDown && key == LogicalKeyboardKey.home) {
      c.setFrame(0);
    } else if (isDown && key == LogicalKeyboardKey.end) {
      c.setFrame(1 << 20);
    } else if (isDown && key == LogicalKeyboardKey.keyC) {
      _decide(ReviewStatus.confirmed);
    } else if (isDown && key == LogicalKeyboardKey.keyX) {
      _decide(ReviewStatus.rejected);
    } else if (isDown && key == LogicalKeyboardKey.keyE) {
      _plateFocus.requestFocus();
    } else if (isDown && key == LogicalKeyboardKey.keyM) {
      _merge();
    } else if (isDown && key == LogicalKeyboardKey.keyF) {
      _fullscreen();
    } else if (isDown && key == LogicalKeyboardKey.keyP) {
      _playSignal.value++;
    } else if (isDown && key == LogicalKeyboardKey.digit1) {
      _setTab(0);
    } else if (isDown && key == LogicalKeyboardKey.digit2) {
      _setTab(1);
    } else if (isDown && key == LogicalKeyboardKey.digit3) {
      _setTab(2);
    } else if (isDown && event.character == '?') {
      _showShortcuts();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _root,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final mode = w >= _wide
              ? _Mode.wide
              : (w >= _narrow ? _Mode.medium : _Mode.narrow);
          final queuePanel = QueuePanel(
            controller: c,
            media: widget.media,
            onBatchDecision: _decideBatch,
            onPicked: mode == _Mode.narrow
                ? () => _scaffold.currentState?.closeDrawer()
                : () => setState(() => _showDetails = true), // the list gives way to that ticket's details
          );
          final queue = _surface(queuePanel); // narrow windows: the list lives in a drawer
          final decision = DecisionPanel(
            controller: c,
            media: widget.media,
            onDecide: _decide,
            onMerge: _merge,
            plateFocus: _plateFocus,
            onPlateSaved: () => _root.requestFocus(),
          );
          return Scaffold(
            key: _scaffold,
            backgroundColor: Colors.transparent,
            drawer: mode == _Mode.narrow
                ? Drawer(width: 360, child: queue)
                : null,
            endDrawer: mode == _Mode.narrow
                ? Drawer(width: 400, child: decision)
                : null,
            body: Column(
              children: [
                _header(context, mode),
                Divider(height: 1, color: Fx.border(context)),
                ListenableBuilder(
                  listenable: c,
                  builder: (context, _) {
                    if (c.runGone) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s8, Fx.s16, 0),
                        child: FxBanner(
                          key: const Key('run-gone'),
                          message: 'This analysis was cancelled. Its tickets were removed.',
                          action: TextButton(onPressed: widget.onBack, child: const Text('Back to the library')),
                        ),
                      );
                    }
                    if (!c.analyzing) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(Fx.s16, Fx.s8, Fx.s16, 0),
                      child: FxBanner(
                        key: const Key('still-analyzing'),
                        color: Fx.accent,
                        icon: Icons.autorenew,
                        message: 'Still analyzing the video (${c.runProgress.toStringAsFixed(0)}%). '
                            'New tickets appear here as cars leave the scene, and a ticket can still change '
                            '(the same car merged in, a plate read).',
                      ),
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => c.error == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Fx.s16,
                            Fx.s8,
                            Fx.s16,
                            0,
                          ),
                          child: FxBanner(
                            message: c.error!,
                            action: TextButton(
                              onPressed: c.clearError,
                              child: const Text('Dismiss'),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: _holdingOpen
                      ? HoldingView(
                          controller: c,
                          media: widget.media,
                          onShowTicket: () => setState(() => _holdingOpen = false),
                          onMessage: _toast,
                        )
                      : _harvesting && widget.harvest != null
                      ? HarvestCategoriesView(labeling: widget.harvest!, taskId: c.taskId)
                      : switch (mode) {
                    _Mode.wide => Row(
                      children: [
                        Expanded(child: _center(context, mode)),
                        VerticalDivider(width: 1, color: Fx.border(context)),
                        SizedBox(width: 400, child: _sidePane(context, queuePanel, decision)),
                      ],
                    ),
                    _Mode.medium => Row(
                      children: [
                        Expanded(child: _center(context, mode)),
                        VerticalDivider(width: 1, color: Fx.border(context)),
                        SizedBox(width: 380, child: _sidePane(context, queuePanel, decision)),
                      ],
                    ),
                    _Mode.narrow => _center(context, mode),
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The right column: the list of tickets, or (after picking one) that ticket's details with a way back to the list.
  /// The video and photos take all the rest of the width.
  Widget _sidePane(BuildContext context, Widget list, Widget details) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final showing = _showDetails && c.selected != null;
        return _surface(
          Stack(
            fit: StackFit.expand,
            children: [
              // The list stays alive behind the details: its place, search and filters are still there on the way back.
              Offstage(offstage: showing, child: list),
              if (showing)
                Column(
                  children: [
                    _detailsBar(context),
                    Divider(height: 1, color: Fx.border(context)),
                    Expanded(child: details),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  /// Above a ticket's details: back to the list, and a way to the neighbouring tickets.
  Widget _detailsBar(BuildContext context) {
    final list = c.visible;
    final i = list.indexWhere((t) => t.uid == c.selectedUid);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s8, vertical: Fx.s4),
      child: Row(
        children: [
          // The back button gives way first when the column is tight: the previous / next buttons must always fit.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('back-to-list'),
                onPressed: () => setState(() => _showDetails = false),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text('All tickets (${c.total})', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          if (i >= 0) Text('${i + 1} of ${list.length}', style: Fx.caption(context)),
          IconButton(
            key: const Key('previous-ticket'),
            tooltip: 'Previous ticket (K)',
            icon: const Icon(Icons.chevron_left),
            onPressed: i > 0 ? () => c.selectRelative(-1) : null,
          ),
          IconButton(
            key: const Key('next-ticket'),
            tooltip: 'Next ticket (J)',
            icon: const Icon(Icons.chevron_right),
            onPressed: i >= 0 && i < list.length - 1 ? () => c.selectRelative(1) : null,
          ),
        ],
      ),
    );
  }

  /// The way into Holding: photos set aside from tickets, with how many wait. An icon only in a narrow window.
  Widget _holdingButton(BuildContext context, _Mode mode) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final n = c.holdingCount;
        void toggle() => setState(() {
          _holdingOpen = !_holdingOpen;
          if (_holdingOpen) _harvesting = false;
        });
        final icon = Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: Icon(_holdingOpen ? Icons.arrow_back : Icons.inventory_2_outlined, size: 18),
        );
        final tip = _holdingOpen
            ? 'Back to the review'
            : (n == 0 ? 'Holding: photos you set aside from tickets (none yet)' : 'Holding: $n set${n == 1 ? '' : 's'} of photos waiting for a decision');
        if (mode == _Mode.narrow) {
          return IconButton(key: const Key('open-holding'), tooltip: tip, icon: icon, onPressed: toggle);
        }
        return Tooltip(
          message: tip,
          child: _holdingOpen
              ? FilledButton.icon(key: const Key('open-holding'), onPressed: toggle, icon: icon, label: const Text('Back to review'))
              : OutlinedButton.icon(key: const Key('open-holding'), onPressed: toggle, icon: icon, label: const Text('Holding')),
        );
      },
    );
  }

  /// Panels paint on a Material so list tiles and ink splashes inside them stay visible.
  Widget _surface(Widget child) =>
      Material(color: Fx.panel(context), child: child);

  Widget _header(BuildContext context, _Mode mode) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final total = c.total;
        final done = c.reviewedCount;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Fx.s16,
            vertical: Fx.s12,
          ),
          child: Row(
            children: [
              if (mode == _Mode.narrow)
                IconButton(
                  tooltip: 'Open the ticket queue',
                  icon: const Icon(Icons.view_list_outlined),
                  onPressed: () => _scaffold.currentState?.openDrawer(),
                ),
              IconButton(
                tooltip: 'Back to the library',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: Fx.s8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Fx.heading(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: Fx.caption(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Spacer(),
              _holdingButton(context, mode),
              const SizedBox(width: Fx.s12),
              if (widget.harvest != null) ...[
                SegmentedButton<bool>(
                  key: const Key('review-harvest-toggle'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.fact_check_outlined, size: 18), label: Text('Review')),
                    ButtonSegment(value: true, icon: Icon(Icons.inventory_2_outlined, size: 18), label: Text('Harvest')),
                  ],
                  selected: {_harvesting},
                  onSelectionChanged: (s) => setState(() {
                    _harvesting = s.first;
                    if (_harvesting) _holdingOpen = false;
                  }),
                ),
                const SizedBox(width: Fx.s16),
              ],
              if (mode != _Mode.narrow && !_away)
                SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$done of $total reviewed',
                            style: Fx.caption(context),
                          ),
                          const Spacer(),
                          Icon(Icons.check_circle, size: 13, color: Fx.success),
                          const SizedBox(width: 2),
                          Text(
                            '${c.confirmedCount}',
                            style: Fx.caption(context),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.cancel, size: 13, color: Fx.danger),
                          const SizedBox(width: 2),
                          Text(
                            '${c.rejectedCount}',
                            style: Fx.caption(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          minHeight: 6,
                          color: Fx.success,
                          backgroundColor: Fx.raised(context),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: Fx.s12),
              if (mode == _Mode.narrow && !_away)
                IconButton(
                  tooltip: 'Ticket details',
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () => _scaffold.currentState?.openEndDrawer(),
                ),
              if (!_away)
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) async {
                  switch (v) {
                    case 'advance':
                      setState(() => c.autoAdvance = !c.autoAdvance);
                    case 'keys':
                      _showShortcuts();
                    case 'live':
                      await widget.onSendToLive?.call();
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'advance',
                    checked: c.autoAdvance,
                    child: const Text('Open the next ticket after a decision'),
                  ),
                  const PopupMenuItem(
                    value: 'keys',
                    child: Text('Keyboard shortcuts  (?)'),
                  ),
                  if (widget.onSendToLive != null)
                    const PopupMenuItem(
                      value: 'live',
                      child: Text('Send to Live Monitor'),
                    ),
                ],
              ),
              const SizedBox(width: Fx.s4),
              FilledButton.tonalIcon(
                onPressed: widget.onNewAnalysis,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New analysis'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _center(BuildContext context, _Mode mode) {
    return Padding(
      padding: const EdgeInsets.all(Fx.s16),
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final t = c.selected;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          'Photos${t == null ? '' : ' ${t.frameCount}'}',
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.pin_outlined, size: 18),
                        label: Text(
                          'Plate reads${t == null || t.crops.isEmpty ? '' : ' ${t.crops.length}'}',
                        ),
                      ),
                      const ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.smart_display_outlined, size: 18),
                        label: Text('Video'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => _setTab(s.first),
                  ),
                ],
              ),
              const SizedBox(height: Fx.s12),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    EvidenceViewer(
                      controller: c,
                      media: widget.media,
                      playSignal: _playSignal,
                      onJumpToVideo: _videoUrl == null
                          ? null
                          : _showMoment,
                      onFullscreen: _fullscreen,
                      onMessage: _toast,
                    ),
                    // Built only while open, so its crop images are not fetched for every ticket you pass.
                    _tab == 1
                        ? PlateReadsPanel(controller: c, media: widget.media)
                        : const SizedBox.shrink(),
                    _videoOpened && _videoUrl != null
                        ? widget.videoBuilder(
                            context,
                            widget.media.absolute(_videoUrl!),
                            _seek,
                            c,
                          )
                        : _videoOpened && _videoUrl == null && c.analyzing
                            ? widget.previewBuilder(context, c.taskId, widget.media)
                            : EmptyState(
                                icon: Icons.videocam_off_outlined,
                                title: _videoUrl == null
                                    ? (c.analyzing ? 'The video is not ready yet' : 'No result video')
                                    : 'Video',
                                message: _videoUrl == null
                                    ? (c.analyzing
                                        ? 'The full replay appears when the analysis has read the whole video.'
                                        : 'This analysis has no result video on disk.')
                                    : 'Opens the first time you visit this tab.',
                              ),
                  ],
                ),
              ),
              // The verdict buttons live in the details; while the right column shows the list, they stay under the evidence.
              if ((mode == _Mode.narrow || !_showDetails) && t != null) ...[
                const SizedBox(height: Fx.s12),
                _verdictStrip(context, t, mode),
              ],
            ],
          );
        },
      ),
    );
  }

  /// The verdict stays one click away under the evidence while the ticket's details are not on screen.
  Widget _verdictStrip(BuildContext context, ForensicTicket t, _Mode mode) {
    final status = c.statusOf(t);
    return FxCard(
      padding: const EdgeInsets.symmetric(horizontal: Fx.s12, vertical: Fx.s8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                t.plateRead
                    ? Text(t.plateText, style: Fx.plate.copyWith(fontSize: 16))
                    : Text(
                        'Plate unread',
                        style: Fx.body(
                          context,
                        ).copyWith(color: Fx.muted(context)),
                      ),
                Text(
                  'Vehicle #${t.trackId} · ${Fx.statusLabel(status)}',
                  style: Fx.caption(context),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 300,
            child: VerdictBar(
              status: status,
              busy: c.busy,
              onDecide: _decide,
              showHint: false,
            ),
          ),
          const SizedBox(width: Fx.s8),
          OutlinedButton(
            key: const Key('open-details'),
            onPressed: () => mode == _Mode.narrow
                ? _scaffold.currentState?.openEndDrawer()
                : setState(() => _showDetails = true),
            child: const Text('Details'),
          ),
        ],
      ),
    );
  }
}

enum _Mode { wide, medium, narrow }

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    const rows = <(List<String>, String)>[
      (['↑', '↓'], 'Previous / next ticket   (also K, J)'),
      (['←', '→'], 'Previous / next photo   (Shift = 10 at a time)'),
      (['Home', 'End'], 'First / last photo'),
      (['C'], 'Confirm the violation'),
      (['X'], 'Mark as a false alarm'),
      (['E'], 'Edit the plate'),
      (['M'], 'Merge with another ticket'),
      (['P'], 'Play / pause the photos'),
      (['F'], 'Fullscreen photo'),
      (['1', '2', '3'], 'Photos / Plate reads / Video'),
      (['Esc'], 'Leave a text field, clear the selection'),
    ];
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, text) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Wrap(
                        spacing: 4,
                        children: [for (final k in keys) KeyCap(k)],
                      ),
                    ),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
