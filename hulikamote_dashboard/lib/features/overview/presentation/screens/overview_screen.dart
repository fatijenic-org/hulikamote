import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/page_parts.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/overview_api.dart';

/// The officer's first page: what needs attention now, and the four steps of the system in the order a ticket
/// travels (analyse, review, points, notice). Every number is a link to the page behind it.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, this.api, this.onOpen});

  /// Injected by tests; the app uses the real backend.
  final OverviewApi? api;

  /// Where a tile or step goes. The app switches page; tests record the path.
  final void Function(BuildContext context, String path)? onOpen;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> with AutomaticKeepAliveClientMixin {
  late final OverviewApi _api = widget.api ?? OverviewApi();
  OverviewData? _data;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _api.load();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _open(String path) => (widget.onOpen ?? (c, p) => c.go(p))(context, path);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _data;
    final allFailed = data != null && data.problems.length >= 4;
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Fx.s24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeader(
                title: 'Overview',
                subtitle: 'What needs your attention, and the four steps from a video to a driver\'s notice.',
                actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _load)],
              ),
              if (allFailed)
                ErrorPanel(
                  title: 'The system is not answering',
                  message: 'Start the backend with tools\\run_demo_backend.bat, then try again.',
                  onRetry: _load,
                )
              else ...[
                if (data != null && data.hasProblems) ...[
                  FxBanner(
                    message: '${data.problems.join(' ')} The other numbers are still right.',
                    color: Fx.warning,
                    icon: Icons.warning_amber_rounded,
                    action: TextButton(onPressed: _load, child: const Text('Try again')),
                  ),
                  const SizedBox(height: Fx.s16),
                ],
                _tiles(data),
                const SizedBox(height: Fx.s24),
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 860;
                  final steps = _Steps(data: data, onOpen: _open);
                  final latest = _Latest(data: data, loading: _loading, onOpen: _open);
                  return wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: steps),
                          const SizedBox(width: Fx.s24),
                          Expanded(flex: 2, child: latest),
                        ])
                      : Column(children: [steps, const SizedBox(height: Fx.s24), latest]);
                }),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tiles(OverviewData? d) {
    final tiles = [
      StatTile(
        label: 'To review',
        value: d?.toReview,
        icon: Icons.inbox_outlined,
        color: Fx.warning,
        hint: 'waiting in the Inbox',
        loading: _loading && d == null,
        onTap: () => _open('/inbox'),
      ),
      StatTile(
        label: 'Confirmed violations',
        value: d?.confirmed,
        icon: Icons.verified_outlined,
        color: Fx.success,
        hint: 'a reviewer approved',
        loading: _loading && d == null,
        onTap: () => _open('/violations'),
      ),
      StatTile(
        label: 'Plates with points',
        value: d?.plates,
        icon: Icons.balance_outlined,
        hint: d?.points == null ? null : '${d!.points} points in total',
        loading: _loading && d == null,
        onTap: () => _open('/demerit'),
      ),
      StatTile(
        label: 'Motorists',
        value: d?.motorists,
        icon: Icons.contact_mail_outlined,
        hint: 'who get a notice',
        loading: _loading && d == null,
        onTap: () => _open('/registry'),
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
      final width = (c.maxWidth - Fx.s16 * (columns - 1)) / columns;
      return Wrap(spacing: Fx.s16, runSpacing: Fx.s16, children: [for (final t in tiles) SizedBox(width: width, child: t)]);
    });
  }
}

class _Step {
  const _Step(this.title, this.text, this.path, this.icon, this.action);

  final String title;
  final String text;
  final String path;
  final IconData icon;
  final String action;
}

/// The path of one ticket, as four numbered cards.
class _Steps extends StatelessWidget {
  const _Steps({required this.data, required this.onOpen});

  final OverviewData? data;
  final void Function(String path) onOpen;

  static const _steps = [
    _Step('Analyse a video', 'Choose a clip. The system finds the violations and reads the plates.', '/offline-video', Icons.video_library_outlined, 'Open Video Analysis'),
    _Step('Review what it found', 'Look at the photos, then confirm or reject each ticket. Only confirmed tickets count.', '/inbox', Icons.fact_check_outlined, 'Open the Inbox'),
    _Step('Check the points', 'Every confirmed ticket adds one demerit point to the plate.', '/demerit', Icons.balance_outlined, 'Open Demerit Points'),
    _Step('Notify the driver', 'The motorist gets the notice on the phone app, and by e-mail if one is set.', '/registry', Icons.contact_mail_outlined, 'Open Motorists'),
  ];

  String? _badge(int i) => switch (i) {
        1 => data?.toReview == null ? null : '${data!.toReview} waiting',
        2 => data?.points == null ? null : '${data!.points} points',
        3 => data?.motorists == null ? null : '${data!.motorists} motorists',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('How it works', trailing: SizedBox(height: 40)),
      for (var i = 0; i < _steps.length; i++) ...[
        FxCard(
          onTap: () => onOpen(_steps[i].path),
          child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: Fx.accent.withValues(alpha: 0.16), child: Text('${i + 1}', style: const TextStyle(color: Fx.accent, fontWeight: FontWeight.w700))),
            const SizedBox(width: Fx.s16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(_steps[i].title, style: Fx.heading(context))),
                  if (_badge(i) != null) ...[const SizedBox(width: Fx.s8), StatusPill(label: _badge(i)!, color: i == 1 ? Fx.warning : Fx.accent, dense: true)],
                ]),
                const SizedBox(height: Fx.s4),
                Text(_steps[i].text, style: Fx.caption(context)),
              ]),
            ),
            const SizedBox(width: Fx.s12),
            Tooltip(message: _steps[i].action, child: Icon(Icons.arrow_forward, color: Fx.muted(context))),
          ]),
        ),
        if (i < _steps.length - 1) const SizedBox(height: Fx.s8),
      ],
    ]);
  }
}

/// The last confirmed violations, newest first.
class _Latest extends StatelessWidget {
  const _Latest({required this.data, required this.loading, required this.onOpen});

  final OverviewData? data;
  final bool loading;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final recent = data?.recent ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionLabel('Latest confirmed', trailing: TextButton(onPressed: () => onOpen('/violations'), child: const Text('See all'))),
      if (loading && data == null)
        const SizedBox(height: 280, child: SkeletonRows(count: 4))
      else if (recent.isEmpty)
        FxCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 240),
            child: EmptyState(
              icon: Icons.playlist_add_check,
              title: 'Nothing confirmed yet',
              message: 'Confirmed tickets show here. Review one in the Inbox to see it appear.',
              action: FilledButton.tonal(onPressed: () => onOpen('/inbox'), child: const Text('Open the Inbox')),
            ),
          ),
        )
      else
        for (final v in recent) ...[
          FxCard(
            padding: const EdgeInsets.symmetric(horizontal: Fx.s16, vertical: Fx.s12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ViolationChip(v.cls, dense: true),
                  const SizedBox(height: Fx.s4),
                  Text(v.userName ?? 'Plate not read', style: Fx.plate.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Text(ago(DateTime.tryParse(v.timestamp)?.toLocal()), style: Fx.caption(context)),
            ]),
          ),
          const SizedBox(height: Fx.s8),
        ],
    ]);
  }
}
