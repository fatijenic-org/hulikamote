import 'package:flutter/material.dart';

import '../../../core/models/account.dart';
import '../../../core/services/friendly_error.dart';
import '../../../core/services/local_cache.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../models/violation.dart';
import '../widgets/ticket_card.dart';
import 'violation_detail_screen.dart';

enum _Filter { all, open, appealed }

/// "Records": the motorist's confirmed tickets, how many can still be appealed, and where each appeal stands.
/// Shows what was saved last time when the system cannot be reached.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api});

  /// Injected by tests; the app talks to the system.
  final PortalApi? api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  PortalApi get _api => widget.api ?? PortalApi();

  Account? _account;
  List<Violation>? _tickets;
  Map<String, String> _appeals = const {};
  DateTime? _savedAt;             // set when what is shown is a saved copy
  String? _error;
  _Filter _filter = _Filter.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final account = await Session.current();
    if (account == null || !mounted) return;
    setState(() => _account = account);
    await _load();
  }

  Future<void> _load() async {
    final account = _account;
    if (account == null) return;
    try {
      final tickets = await _api.tickets(account.userId);
      Map<String, String> appeals = const {};
      try {
        appeals = await _api.appealStatuses(account.userId);        // a missing appeal list must not hide the tickets
      } catch (_) {}
      await LocalCache.save('tickets', account.userId, [for (final t in tickets) t.toJson()]);
      await LocalCache.save('appeals', account.userId, appeals);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _appeals = appeals;
        _savedAt = null;
        _error = null;
      });
    } catch (e) {
      await _fallBackToSaved(account, e);
    }
  }

  /// The system did not answer: keep what is on screen, or show the saved copy, or say what went wrong.
  Future<void> _fallBackToSaved(Account account, Object error) async {
    if (_tickets != null && _savedAt == null) {
      if (mounted) AppToast.show(context, 'Could not refresh. ${friendlyMessage(error)}', error: true);
      return;
    }
    final saved = await LocalCache.load('tickets', account.userId);
    final savedAppeals = await LocalCache.load('appeals', account.userId);
    if (!mounted) return;
    if (saved == null) {
      setState(() => _error = friendlyMessage(error));
      return;
    }
    setState(() {
      _tickets = [for (final t in saved.data as List) Violation.fromCache(Map<String, dynamic>.from(t as Map))];
      _appeals = savedAppeals == null ? const {} : {for (final e in (savedAppeals.data as Map).entries) '${e.key}': '${e.value}'};
      _savedAt = saved.at;
      _error = null;
    });
  }

  Future<void> _retry() async {
    setState(() => _error = null);
    await _load();
  }

  Future<void> _open(Violation v) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ViolationDetailScreen(violation: v, appealStatus: _appeals[v.id], api: widget.api)),
    );
    if (changed == true) await _load();
  }

  List<Violation> get _shown {
    final all = _tickets ?? const <Violation>[];
    return switch (_filter) {
      _Filter.all => all,
      _Filter.open => [for (final t in all) if (!_appeals.containsKey(t.id)) t],
      _Filter.appealed => [for (final t in all) if (_appeals.containsKey(t.id)) t],
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tickets = _tickets;
    final account = _account;
    final openCount = tickets == null ? 0 : tickets.where((t) => !_appeals.containsKey(t.id)).length;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x6, Sp.page, Sp.x2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Semantics(
                      header: true,
                      child: Text(account == null || account.name.isEmpty ? 'Records' : 'Hi, ${account.name.split(' ').first}', style: context.text.headlineMedium),
                    ),
                    const SizedBox(height: Sp.x1),
                    Text(
                      account == null || account.plate.isEmpty ? 'Your confirmed tickets' : 'Your confirmed tickets · plate ${account.plate}',
                      style: context.text.bodyLarge?.copyWith(color: context.muted),
                    ),
                    const SizedBox(height: Sp.x5),
                    Row(children: [
                      Expanded(child: _Stat(value: tickets?.length, label: 'Tickets')),
                      const SizedBox(width: Sp.x3),
                      Expanded(child: _Stat(value: tickets == null ? null : openCount, label: 'Can appeal')),
                      const SizedBox(width: Sp.x3),
                      Expanded(child: _Stat(value: tickets == null ? null : _appeals.length, label: 'Appealed')),
                    ]),
                    if (_savedAt != null) ...[
                      const SizedBox(height: Sp.x4),
                      InfoBanner(
                        tone: Tone.warning,
                        icon: Icons.cloud_off_outlined,
                        message: 'Cannot reach the system. Showing what was saved ${ago(_savedAt!, DateTime.now())}.',
                        actionLabel: 'Retry',
                        onAction: _retry,
                      ),
                    ],
                    if (tickets != null && tickets.isNotEmpty) ...[
                      const SizedBox(height: Sp.x4),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<_Filter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _Filter.all, label: Text('All')),
                          ButtonSegment(value: _Filter.open, label: Text('Can appeal')),
                          ButtonSegment(value: _Filter.appealed, label: Text('Appealed')),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (v) => setState(() => _filter = v.first),
                        ),
                      ),
                    ],
                    const SizedBox(height: Sp.x4),
                  ]),
                ),
              ),
              if (tickets == null && _error == null)
                const SliverPadding(padding: EdgeInsets.symmetric(horizontal: Sp.page), sliver: SliverToBoxAdapter(child: SkeletonList()))
              else if (_error != null)
                SliverFillRemaining(hasScrollBody: false, child: ErrorState(message: _error!, onRetry: _retry))
              else if (_shown.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _empty())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x6),
                  sliver: SliverList.separated(
                    itemCount: _shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Sp.x3),
                    itemBuilder: (context, i) {
                      final v = _shown[i];
                      return TicketCard(violation: v, appealStatus: _appeals[v.id], onTap: () => _open(v));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    if (_tickets!.isEmpty) {
      return const EmptyState(
        icon: Icons.verified_outlined,
        title: 'Nothing on your record',
        message: 'When a ticket is confirmed for your plate, it shows up here and you get a notice.',
      );
    }
    final open = _filter == _Filter.open;
    return EmptyState(
      icon: open ? Icons.task_alt_rounded : Icons.gavel_rounded,
      title: open ? 'Nothing left to appeal' : 'No appeals yet',
      message: open ? 'Every ticket already has an appeal.' : 'Open a ticket and tap “Appeal this ticket” if you think it is wrong.',
      action: AppButton(label: 'Show all tickets', kind: AppButtonKind.secondary, expand: false, onPressed: () => setState(() => _filter = _Filter.all)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${value ?? 'loading'}',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            value == null ? const Skeleton(height: 28, width: 32) : Text('$value', style: context.text.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: context.text.bodyMedium?.copyWith(color: context.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
