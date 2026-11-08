import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/core/shell/officer_mode.dart';
import 'package:hulikamote_dashboard/core/utils/external_apps.dart';

import '../../features/forensic/presentation/widgets/fx.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  /// How many menu entries there are (the router needs one branch for each).
  @visibleForTesting
  static int get navCount => _AppShellState._items.length;

  /// Where an officer lands: the Overview page (the last branch, shown first in the menu).
  static int get overviewIndex => _AppShellState._items.indexWhere((e) => e.path == '/overview');

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    OfficerMode.enabled.addListener(_officerChanged);
  }

  @override
  void dispose() {
    OfficerMode.enabled.removeListener(_officerChanged);
    super.dispose();
  }

  /// Switching to the officer view while on a developer tab would leave the officer on a page they cannot navigate
  /// back to, so go to the Overview.
  void _officerChanged() {
    if (!mounted) return;
    final current = widget.navigationShell.currentIndex;
    if (OfficerMode.enabled.value && !_items[current].officer) widget.navigationShell.goBranch(AppShell.overviewIndex);
    setState(() {});
  }

  /// The menu, in router order: the router needs one branch per entry, so new entries go at the end and [_NavItem.first]
  /// pulls one to the top of the menu without moving its branch.
  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.videocam_outlined, label: 'Live Monitor', path: '/', officer: true, group: 'Monitor'),
    _NavItem(icon: Icons.video_library_outlined, label: 'Video Analysis', path: '/offline-video', officer: true, group: 'Monitor'),
    _NavItem(icon: Icons.biotech_outlined, label: 'Forensic Analyzer', path: '/forensic-analyzer', officer: true, group: 'Monitor'),
    _NavItem(icon: Icons.fact_check_outlined, label: 'Benchmark', path: '/benchmark'),
    _NavItem(icon: Icons.inbox_outlined, label: 'Inbox', path: '/inbox', officer: true, group: 'Review'),
    _NavItem(icon: Icons.list_alt_outlined, label: 'Violations', path: '/violations', officer: true, group: 'Review'),
    _NavItem(icon: Icons.balance_outlined, label: 'Demerit Points', path: '/demerit', officer: true, group: 'Records'),
    _NavItem(icon: Icons.contact_mail_outlined, label: 'Motorists', path: '/registry', officer: true, group: 'Records'),
    _NavItem(icon: Icons.model_training, label: 'Models', path: '/model'),
    _NavItem(icon: Icons.settings_outlined, label: 'Settings', path: '/settings'),
    _NavItem(icon: Icons.handyman_outlined, label: 'Utilities', path: '/utilities'),
    _NavItem(icon: Icons.auto_stories_outlined, label: 'Wiki', path: '/wiki', separatorBefore: true),
    _NavItem(icon: Icons.account_tree_outlined, label: 'Code Reference', path: '/blueprint'),
    _NavItem(icon: Icons.menu_book_outlined, label: 'Docs', path: '/docs'),
    // Outside tools: one click opens them (deck in the browser, visualizer as its own app)
    _NavItem(icon: Icons.slideshow, label: 'Progress Report', path: '/progress-report',
        separatorBefore: true, opensOnSelect: _OpenKind.progressReport),
    _NavItem(icon: Icons.school_outlined, label: 'Visualizer', path: '/visualizer', opensOnSelect: _OpenKind.visualizer),
    _NavItem(icon: Icons.photo_library_outlined, label: 'Datasets', path: '/datasets'),
    _NavItem(icon: Icons.space_dashboard_outlined, label: 'Overview', path: '/overview', officer: true, first: true),
  ];

  Future<void> _openExternal(_OpenKind kind) async {
    final error = switch (kind) {
      _OpenKind.progressReport => await ExternalApps.openProgressReport(),
      _OpenKind.visualizer => await ExternalApps.launchVisualizer(),
    };
    if (!mounted) return;
    if (error != null) AppToast.show(context, error, isError: true);
  }

  /// The entries to show now, with the Overview first, and (officer view) a heading above each group.
  List<Widget> _menu() {
    final officer = OfficerMode.enabled.value;
    final visible = [
      for (var i = 0; i < _items.length; i++)
        if (!officer || _items[i].officer) (i, _items[i]),
    ];
    final shown = [...visible.where((e) => e.$2.first), ...visible.where((e) => !e.$2.first)];
    final children = <Widget>[];
    String? lastGroup;
    for (final (i, e) in shown) {
      if (officer && _isExpanded && e.group != null && e.group != lastGroup) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s24, Fx.s16, Fx.s24, Fx.s4),
          child: Text(e.group!.toUpperCase(), style: Fx.label(context)),
        ));
      }
      lastGroup = e.group;
      final tile = _MenuTile(
        item: e,
        selected: widget.navigationShell.currentIndex == i,
        expanded: _isExpanded,
        onTap: () {
          final open = e.opensOnSelect;
          if (open != null) _openExternal(open);
          widget.navigationShell.goBranch(i, initialLocation: i == widget.navigationShell.currentIndex);
        },
      );
      // A thin divider sets the outside tools apart from the operational tabs
      children.add(e.separatorBefore && !officer ? Column(children: [const Divider(height: 24), tile]) : tile);
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final officer = OfficerMode.enabled.value;
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            color: scheme.surface,
            width: _isExpanded ? 248 : 80,
            child: Column(
              children: [
                const SizedBox(height: Fx.s24),
                Row(
                  mainAxisAlignment: _isExpanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
                  children: [
                    if (_isExpanded) ...[
                      const SizedBox(width: Fx.s16),
                      ExcludeSemantics(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Fx.accent),
                          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 19),
                        ),
                      ),
                      const SizedBox(width: Fx.s12),
                      Expanded(
                        child: Text('HULI-KAMOTE',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      ),
                    ],
                    IconButton(
                      icon: Icon(_isExpanded ? Icons.menu_open : Icons.menu, color: Fx.muted(context)),
                      tooltip: _isExpanded ? 'Collapse the menu' : 'Expand the menu',
                      onPressed: () => setState(() => _isExpanded = !_isExpanded),
                    ),
                    if (_isExpanded) const SizedBox(width: Fx.s8),
                  ],
                ),
                const SizedBox(height: Fx.s8),
                Expanded(child: ListView(children: _menu())),
                const Divider(height: 1),
                // Officer view switch
                Tooltip(
                  message: 'Officer view: only the pages an LTO officer needs',
                  child: InkWell(
                    onTap: () => OfficerMode.set(!officer),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Fx.s8, horizontal: Fx.s12),
                      child: Row(
                        mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          if (_isExpanded) const SizedBox(width: Fx.s12),
                          Icon(Icons.badge_outlined, color: officer ? Fx.accent : Fx.muted(context)),
                          if (_isExpanded) ...[
                            const SizedBox(width: Fx.s16),
                            Expanded(
                              child: Text('Officer view',
                                  style: TextStyle(color: officer ? Fx.accent : Fx.muted(context), fontWeight: FontWeight.w500)),
                            ),
                            Switch(value: officer, onChanged: OfficerMode.set),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Tooltip(
                  message: 'Sign out',
                  child: InkWell(
                    onTap: () => context.go('/login'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Fx.s16),
                      child: Row(
                        mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          if (_isExpanded) const SizedBox(width: Fx.s24),
                          const Icon(Icons.logout, color: Fx.danger),
                          if (_isExpanded) ...[
                            const SizedBox(width: Fx.s16),
                            const Text('Sign out', style: TextStyle(color: Fx.danger, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Fx.s8),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }
}

/// One menu entry: icon and label, the open page marked by an accent bar, a tooltip with the name when the menu is
/// collapsed to icons, and screen-reader text that says which page is open.
class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.selected, required this.expanded, required this.onTap});

  final _NavItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Fx.accent : Fx.muted(context);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: expanded ? '' : item.label,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: Fx.s12, horizontal: Fx.s24),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: selected ? Fx.accent : Colors.transparent, width: 4)),
              color: selected ? Fx.accent.withValues(alpha: 0.10) : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: color),
                if (expanded) ...[
                  const SizedBox(width: Fx.s16),
                  Expanded(
                    child: Text(item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: selected ? Fx.accent : Theme.of(context).colorScheme.onSurface, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _OpenKind { progressReport, visualizer }

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  final bool separatorBefore;
  final _OpenKind? opensOnSelect;

  /// Shown in the officer view.
  final bool officer;

  /// The heading above it in the officer view.
  final String? group;

  /// Listed above everything else.
  final bool first;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    this.separatorBefore = false,
    this.opensOnSelect,
    this.officer = false,
    this.group,
    this.first = false,
  });
}
