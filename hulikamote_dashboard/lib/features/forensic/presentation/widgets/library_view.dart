import 'package:flutter/material.dart';

import '../../data/forensic_api.dart';
import '../../domain/forensic_models.dart';
import '../../domain/violation_catalog.dart';
import 'fx.dart';

/// "Oct 6, 2026 · 2:02 PM"
String formatRunTime(DateTime t) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${months[t.month - 1]} ${t.day}, ${t.year} · $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today", "Yesterday" or the date, for grouping the library.
String dayLabel(DateTime t, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return formatRunTime(t).split(' · ').first;
}

/// Every finished analysis, newest first, grouped by day. Each card says when it ran, what it
/// looked for and how many tickets it found; open it to review.
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.api,
    required this.onOpen,
    required this.onSendToLive,
    required this.onNew,
    this.refreshToken = 0,
  });

  final ForensicApi api;
  final void Function(RunSummary run) onOpen;
  final Future<void> Function(String taskId) onSendToLive;
  final VoidCallback onNew;

  /// Changing this reloads the list (e.g. after a new analysis finished).
  final int refreshToken;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  List<RunSummary>? _runs;
  String? _error;
  bool _loading = false;
  /// A key with a null value is still loading; an empty map means the run left no settings.
  final Map<String, Map<String, dynamic>?> _configs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LibraryView old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runs = await widget.api.history();
      if (!mounted) return;
      setState(() => _runs = runs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureConfig(String taskId) async {
    if (_configs.containsKey(taskId)) return;
    _configs[taskId] = null; // claim it, so each card asks once
    final cfg = await widget.api.runConfig(taskId);
    if (mounted) setState(() => _configs[taskId] = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final runs = _runs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s24, Fx.s8),
          child: Row(
            children: [
              Text('Library', style: Fx.title(context)),
              const SizedBox(width: Fx.s12),
              if (runs != null)
                Text(
                  '${runs.length} ${runs.length == 1 ? 'analysis' : 'analyses'}',
                  style: Fx.caption(context),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Expanded(child: _content(context, runs)),
      ],
    );
  }

  Widget _content(BuildContext context, List<RunSummary>? runs) {
    if (_error != null && runs == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the library',
        message: _error,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (runs == null) {
      return GridView.count(
        padding: const EdgeInsets.all(Fx.s24),
        crossAxisCount: 3,
        mainAxisSpacing: Fx.s16,
        crossAxisSpacing: Fx.s16,
        childAspectRatio: 2.2,
        children: [
          for (var i = 0; i < 6; i++) const SkeletonBox(radius: Fx.radius),
        ],
      );
    }
    if (runs.isEmpty) {
      return EmptyState(
        icon: Icons.video_library_outlined,
        title: 'No analyses yet',
        message:
            'Analyze a video and its tickets will be kept here for review.',
        action: FilledButton.icon(
          onPressed: widget.onNew,
          icon: const Icon(Icons.add),
          label: const Text('New analysis'),
        ),
      );
    }
    final now = DateTime.now();
    final groups = <String, List<RunSummary>>{};
    for (final r in runs) {
      groups.putIfAbsent(dayLabel(r.createdAt, now), () => []).add(r);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Fx.s24, 0, Fx.s24, Fx.s24),
      children: [
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Fx.s16),
            child: SectionLabel(e.key),
          ),
          Wrap(
            spacing: Fx.s16,
            runSpacing: Fx.s16,
            children: [for (final r in e.value) _card(context, r)],
          ),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, RunSummary r) {
    _ensureConfig(r.taskId);
    final cfg = _configs[r.taskId];
    final violations = ((cfg?['active_violations'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    return SizedBox(
      width: 360,
      child: FxCard(
        onTap: () => widget.onOpen(r),
        padding: const EdgeInsets.all(Fx.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Fx.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.biotech_outlined,
                    color: Fx.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: Fx.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatRunTime(r.createdAt),
                        style: Fx.heading(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(r.shortId, style: Fx.caption(context)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) {
                    if (v == 'live') widget.onSendToLive(r.taskId);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'live',
                      child: Text('Send to Live Monitor'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Fx.s12),
            SizedBox(
              height: 24,
              child: violations.isEmpty
                  ? (cfg == null
                        ? const SkeletonBox(height: 18, width: 160, radius: 9)
                        : const SizedBox.shrink())
                  : Row(
                      children: [
                        Flexible(
                          child: ViolationChip(violations.first, dense: true),
                        ),
                        if (violations.length > 1) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: violations
                                .map((v) => ViolationCatalog.of(v).label)
                                .join(', '),
                            child: StatusPill(
                              label: '+${violations.length - 1}',
                              color: Fx.muted(context),
                              dense: true,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: Fx.s12),
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 16,
                  color: Fx.muted(context),
                ),
                const SizedBox(width: 6),
                Text(
                  '${r.ticketCount} ticket${r.ticketCount == 1 ? '' : 's'}',
                  style: Fx.body(context),
                ),
                const SizedBox(width: Fx.s16),
                if (r.running)
                  StatusPill(
                    key: Key('running-${r.taskId}'),
                    label: 'Analyzing',
                    color: Fx.accent,
                    icon: Icons.autorenew,
                    dense: true,
                  )
                else ...[
                  Icon(
                    r.videoUrl != null
                        ? Icons.smart_display_outlined
                        : Icons.videocam_off_outlined,
                    size: 16,
                    color: Fx.muted(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    r.videoUrl != null ? 'Video ready' : 'No video',
                    style: Fx.caption(context),
                  ),
                ],
                const Spacer(),
                Text(
                  'Review',
                  style: Fx.body(
                    context,
                  ).copyWith(color: Fx.accent, fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Fx.accent),
              ],
            ),
            if (r.stoppedEarly)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.content_cut, size: 14, color: Fx.muted(context)),
                    const SizedBox(width: 6),
                    Text('Stopped early', key: Key('stopped-early-${r.taskId}'), style: Fx.caption(context)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
