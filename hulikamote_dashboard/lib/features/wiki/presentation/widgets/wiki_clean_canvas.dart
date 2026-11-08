import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/archived_resource.dart';

class WikiCleanCanvas extends StatefulWidget {
  final ValueChanged<ArchivedResource> onSelectArchive;
  final String searchQuery;

  const WikiCleanCanvas({
    super.key,
    required this.onSelectArchive,
    this.searchQuery = '',
  });

  @override
  State<WikiCleanCanvas> createState() => _WikiCleanCanvasState();
}

class _WikiCleanCanvasState extends State<WikiCleanCanvas> {
  String _selectedCategory = 'All';

  static const List<String> _categories = [
    'All',
    'Architecture',
    'Violations & Physics',
    'Research & Notes',
  ];

  List<ArchivedResource> get _filteredResources {
    return ArchivedResource.values.where((res) {
      final matchesSearch = widget.searchQuery.isEmpty ||
          res.title.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
          res.subtitle.toLowerCase().contains(widget.searchQuery.toLowerCase()) ||
          res.badge.toLowerCase().contains(widget.searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      if (_selectedCategory == 'All') return true;
      if (_selectedCategory == 'Architecture') {
        return res == ArchivedResource.docs ||
            res == ArchivedResource.blueprint ||
            res == ArchivedResource.projectMap;
      }
      if (_selectedCategory == 'Violations & Physics') {
        return res == ArchivedResource.visualizer;
      }
      if (_selectedCategory == 'Research & Notes') {
        return res == ArchivedResource.progress || res == ArchivedResource.qa;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgSurface = isDark ? const Color(0xFF111622) : Colors.white;
    final cardBorder = isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Workspace Header ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wiki Workspace Ready for Restructuring',
                                style: GoogleFonts.lexend(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Engineering knowledge base, violation physics, and project architecture.',
                                style: GoogleFonts.lexend(
                                  fontSize: 12.5,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1B2232) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: cardBorder),
                          ),
                          child: Text(
                            '6 Modules Preserved',
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'All previously built technical documentation, violation logic visualizers, system blueprints, presentation slide decks, and defense Q&A have been consolidated in the archive dropdown and cataloged below for direct access.',
                      style: GoogleFonts.lexend(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Category Filters & Section Title ───────────────────────────
              LayoutBuilder(
                builder: (context, sectionConstraints) {
                  final isNarrow = sectionConstraints.maxWidth < 640;
                  final pills = _categories.map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => setState(() => _selectedCategory = cat),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel
                                ? (isDark ? const Color(0xFF263248) : const Color(0xFFE2E8F0))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel
                                  ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8))
                                  : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          child: Text(
                            cat,
                            style: GoogleFonts.lexend(
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                              color: isSel
                                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                  : textMuted,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList();

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Preserved Archive Resources',
                              style: GoogleFonts.lexend(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: pills),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Preserved Archive Resources',
                        style: GoogleFonts.lexend(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: pills,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),

              // ── Preserved Resources Grid (Mobbin-grade cards) ──────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 640;
                  final cardWidth = isWide ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;

                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: _filteredResources.map((res) {
                      return SizedBox(
                        width: cardWidth,
                        child: _ResourceCard(
                          resource: res,
                          onTap: () => widget.onSelectArchive(res),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 36),

              // ── Modular Restructuring Staging Area ──────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D111A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E2638) : const Color(0xFFE2E8F0),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF151C2C) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Icon(Icons.dashboard_customize_outlined, size: 20, color: textMuted),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modular Wiki Workspace',
                            style: GoogleFonts.lexend(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ready for custom documentation layouts, chapter breakdowns, and interactive benchmarks.',
                            style: GoogleFonts.lexend(
                              fontSize: 11.5,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceCard extends StatefulWidget {
  final ArchivedResource resource;
  final VoidCallback onTap;

  const _ResourceCard({
    required this.resource,
    required this.onTap,
  });

  @override
  State<_ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<_ResourceCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final res = widget.resource;

    final bgCard = isDark ? const Color(0xFF121724) : Colors.white;
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? res.color.withOpacity(0.5)
                  : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0)),
              width: _isHovered ? 1.2 : 1.0,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: res.color.withOpacity(isDark ? 0.15 : 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: res.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(res.icon, size: 18, color: res.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      res.title,
                      style: GoogleFonts.lexend(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF182030) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isDark ? const Color(0x26FFFFFF) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      res.badge,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: res.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                res.subtitle,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  height: 1.4,
                  color: textMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Open Module',
                    style: GoogleFonts.lexend(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isHovered ? res.color : textMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: _isHovered ? res.color : textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
