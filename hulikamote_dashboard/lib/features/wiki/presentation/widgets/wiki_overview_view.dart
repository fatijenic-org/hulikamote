import 'package:flutter/material.dart';
import '../../domain/models/wiki_tab.dart';

class WikiOverviewView extends StatelessWidget {
  final ValueChanged<WikiTab> onSelectTab;
  final String searchQuery;

  const WikiOverviewView({
    super.key,
    required this.onSelectTab,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero Banner ──────────────────────────────────────────────────
          _buildHeroBanner(context),
          const SizedBox(height: 20),

          // ── Metrics Strip ────────────────────────────────────────────────
          _buildMetricsStrip(context),
          const SizedBox(height: 24),

          // ── Section Title ────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Knowledge Domains',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '6 Modules',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Select a domain below to inspect technical specifications, interactive visualizers, and codebases.',
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 14),

          // ── Domain Cards Grid ────────────────────────────────────────────
          _buildDomainCardsGrid(context),
          const SizedBox(height: 28),

          // ── Reading Tracks / Quick Paths ─────────────────────────────────
          _buildReadingTracks(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E2638), const Color(0xFF141926)]
                  : [const Color(0xFFF8FAFC), const Color(0xFFEFF6FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildHeroText(context, theme, isDark)),
                    const SizedBox(width: 20),
                    _buildHeroButtons(context),
                  ],
                ),
              ] else ...[
                _buildHeroText(context, theme, isDark),
                const SizedBox(height: 16),
                _buildHeroButtons(context, isColumn: false),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroText(BuildContext context, ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 12, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
              Text(
                'UNIFIED SYSTEM KNOWLEDGE ENGINE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome to the Huli-Kamote Wiki',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This portal centralizes the complete engineering documentation, 20 traffic violation algorithms, interactive 2D physics visualizers, codebase blueprints, presentation slide decks, and defense preparation answers into a unified native dashboard experience.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: isDark ? Colors.grey[300] : const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroButtons(BuildContext context, {bool isColumn = true}) {
    final buttons = [
      FilledButton.icon(
        onPressed: () => onSelectTab(WikiTab.docs),
        icon: const Icon(Icons.menu_book_rounded, size: 15),
        label: const Text('Read Documentation'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(width: 8, height: 8),
      OutlinedButton.icon(
        onPressed: () => onSelectTab(WikiTab.visualizer),
        icon: const Icon(Icons.science_rounded, size: 15),
        label: const Text('Open Visualizer'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ];

    return isColumn
        ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: buttons)
        : Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _buildMetricsStrip(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final metrics = [
      (
        label: 'Knowledge Domains',
        value: '7 Modules',
        icon: Icons.hub_outlined,
        color: const Color(0xFF3B82F6),
      ),
      (
        label: 'Violation Algorithms',
        value: '20 Rules',
        icon: Icons.gavel_rounded,
        color: const Color(0xFFEF4444),
      ),
      (
        label: 'Physics Visualizers',
        value: '13 Models',
        icon: Icons.motion_photos_on_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      (
        label: 'Trained Model Cards',
        value: '5 Vision Nets',
        icon: Icons.model_training,
        color: const Color(0xFF10B981),
      ),
      (
        label: 'System Execution',
        value: '100% Offline',
        icon: Icons.shield_rounded,
        color: const Color(0xFFF59E0B),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: metrics.map((m) {
          return Container(
            width: 175,
            margin: EdgeInsets.only(right: m == metrics.last ? 0 : 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF171C28) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: m.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(m.icon, size: 15, color: m.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDomainCardsGrid(BuildContext context) {
    final domains = [
      _DomainCardData(
        tab: WikiTab.docs,
        title: 'Technical Documentation',
        subtitle: 'Complete 6-chapter technical site: Start, Datasets trust grades, Vision models, 9-step training pipeline, and 20 violation specs.',
        icon: Icons.menu_book_rounded,
        badge: 'Core Reference',
        color: const Color(0xFF10B981),
        tags: ['Datasets', 'Models', 'Pipeline', 'Violations', 'Glossary'],
      ),
      _DomainCardData(
        tab: WikiTab.visualizer,
        title: 'Violation Logic & Physics Visualizer',
        subtitle: '5-step educational breakdown: Raw code & LaTeX math, brute force comparison, PNPoly raycasting, IoU constraints, and 2D traffic simulation.',
        icon: Icons.science_rounded,
        badge: '13 Physics Models',
        color: const Color(0xFF8B5CF6),
        tags: ['Counterflow', 'Illegal Turn', 'No Helmet', 'Swerving', 'Red Light'],
      ),
      _DomainCardData(
        tab: WikiTab.blueprint,
        title: 'System Architecture Blueprint',
        subtitle: 'Interactive ladder of slices from smallest building blocks to complete pipeline, with live Python symbol and test inspection.',
        icon: Icons.account_tree_rounded,
        badge: 'Live Code Trace',
        color: const Color(0xFFF59E0B),
        tags: ['Pipeline', 'Violations', 'Tracking', 'Test Tracer'],
      ),
      _DomainCardData(
        tab: WikiTab.progress,
        title: 'Research Decks & Progress Audits',
        subtitle: 'Interactive progress presentation deck, milestone narrative, engineering audit report, and academic thesis revisions.',
        icon: Icons.slideshow_rounded,
        badge: '3 Decks',
        color: const Color(0xFFEC4899),
        tags: ['Progress Deck', 'Journey Narrative', 'Technical Audit', 'Revisions'],
      ),
      _DomainCardData(
        tab: WikiTab.qa,
        title: 'Thesis Defense Q&A Knowledge Base',
        subtitle: 'Curated panelist questions, examiner defense strategies, and instant local markdown note editor with offline persistence.',
        icon: Icons.help_rounded,
        badge: 'Offline Local',
        color: const Color(0xFF06B6D4),
        tags: ['Defense Prep', 'Examiner FAQs', 'Markdown Notes', 'Search'],
      ),
      _DomainCardData(
        tab: WikiTab.projectMap,
        title: 'Project Map & Risk Table',
        subtitle: 'Interactive D3 architecture graphs, codebase dependency maps, module coupling analysis, and test coverage matrices.',
        icon: Icons.hub_rounded,
        badge: 'D3 Graphs',
        color: const Color(0xFF6366F1),
        tags: ['Dependency Graph', 'Risk Matrix', 'Coverage', 'Coupling'],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 960 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        final cardWidth = (constraints.maxWidth - (crossAxisCount - 1) * 14) / crossAxisCount;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: domains.map((data) {
            return SizedBox(
              width: cardWidth,
              child: _buildDomainCard(context, data),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDomainCard(BuildContext context, _DomainCardData data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171C28) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: data.color.withOpacity(0.2)),
                ),
                child: Icon(data.icon, size: 18, color: data.color),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: data.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  data.badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: data.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subtitle,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: data.tags.take(4).map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#$tag',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onSelectTab(data.tab),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 9),
                side: BorderSide(
                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Explore Section',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingTracks(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tracks = [
      (
        title: 'For Thesis Evaluators & Panelists',
        desc: 'Review the research methodology, dataset card trust metrics, and defense Q&A.',
        cta: 'Open Defense Q&A',
        tab: WikiTab.qa,
        icon: Icons.school_rounded,
        color: const Color(0xFF06B6D4),
      ),
      (
        title: 'For AI Engineers & Developers',
        desc: 'Inspect the 9-step training pipeline, ONNX exports, and Python architecture blueprint.',
        cta: 'Open Blueprint',
        tab: WikiTab.blueprint,
        icon: Icons.code_rounded,
        color: const Color(0xFFF59E0B),
      ),
      (
        title: 'For Traffic Enforcement Officers',
        desc: 'Examine the 20 violation definitions, zone geometry, and 5-phase visualizer physics.',
        cta: 'Open Visualizer',
        tab: WikiTab.visualizer,
        icon: Icons.local_police_rounded,
        color: const Color(0xFF8B5CF6),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141926) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Recommended Reading Tracks',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: tracks.map((t) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: t == tracks.last ? 0 : 12),
                            child: _buildTrackItem(context, t),
                          ),
                        );
                      }).toList(),
                    )
                  : Column(
                      children: tracks.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildTrackItem(context, t),
                      )).toList(),
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrackItem(BuildContext context, ({String title, String desc, String cta, WikiTab tab, IconData icon, Color color}) t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2232) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(t.icon, size: 14, color: t.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t.title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.desc,
            style: TextStyle(
              fontSize: 10.5,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => onSelectTab(t.tab),
            child: Row(
              children: [
                Text(
                  t.cta,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: t.color,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 11, color: t.color),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DomainCardData {
  final WikiTab tab;
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final Color color;
  final List<String> tags;

  const _DomainCardData({
    required this.tab,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.color,
    required this.tags,
  });
}
