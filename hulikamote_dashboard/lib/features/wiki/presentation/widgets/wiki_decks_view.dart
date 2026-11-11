import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/external_apps.dart';

class WikiDecksView extends StatelessWidget {
  final Directory? root;

  const WikiDecksView({super.key, this.root});

  Future<void> _openHtmlFile(BuildContext context, String relativePath) async {
    final baseDir = root ?? ExternalApps.repoRoot();
    if (baseDir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Repository root not found.')),
      );
      return;
    }

    final file = File('${baseDir.path}/$relativePath');
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: $relativePath')),
      );
      return;
    }

    try {
      if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', file.uri.toString()],
            mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [file.path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [file.path], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final decks = [
      (
        title: 'Huli-Kamote Progress Deck (Latest)',
        subtitle: 'Interactive HTML slide deck summarizing project milestones, hardware specs, dataset breakdown, and system architecture.',
        path: 'Progress Report/index.html',
        tag: 'Recommended',
        icon: Icons.slideshow_rounded,
        color: const Color(0xFF3B82F6),
        stats: 'Modern UI • Milestone Timeline • System Overview',
      ),
      (
        title: 'The Journey of Huli-Kamote',
        subtitle: 'Earlier narrative progress deck documenting the origin, research evolution, and early algorithmic attempts.',
        path: 'Progress Report/previous version/index.html',
        tag: 'Archive',
        icon: Icons.history_edu_rounded,
        color: const Color(0xFF3B82F6),
        stats: 'Historical Journey • Early Prototypes',
      ),
      (
        title: 'Engineering Progress & Technical Audit Report',
        subtitle: 'Deep-dive technical audit report assessing architecture readiness, test coverage, and modular coupling.',
        path: 'docs/PROGRESS_AUDIT_REPORT.html',
        tag: 'Audit',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF3B82F6),
        stats: 'System Health • 20 Violations • Test Coverage',
      ),
      (
        title: 'Academic Thesis Revisions & Defense Plan',
        subtitle: 'Systematic breakdown of panelist recommendations, academic revisions, and theoretical backing.',
        path: 'docs/THESIS_REVISIONS.md',
        tag: 'Thesis',
        icon: Icons.school_rounded,
        color: const Color(0xFF3B82F6),
        stats: 'Oral Defense • Panelist Alignment • Academic Rigor',
      ),
      (
        title: 'Engineering Changelog (Since Aug 25)',
        subtitle: 'Comprehensive progress changelog detailing models trained, detector refactoring, and benchmark evaluations.',
        path: 'docs/PROGRESS_SINCE_AUG25.md',
        tag: 'Changelog',
        icon: Icons.update_rounded,
        color: const Color(0xFF3B82F6),
        stats: 'Milestone Tracking • Commits • Performance Deltas',
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.slideshow_rounded, size: 20, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Research Presentation Decks & Audits',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Interactive HTML decks, technical audit reports, and academic defense revision documents.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Deck Cards
          ...decks.map((deck) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 650;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B26) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: deck.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: deck.color.withOpacity(0.2)),
                              ),
                              child: Icon(deck.icon, size: 22, color: deck.color),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDeckDetails(deck, isDark)),
                            const SizedBox(width: 16),
                            FilledButton.icon(
                              onPressed: () => _openHtmlFile(context, deck.path),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                              label: const Text('Launch in Browser'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                textStyle: const TextStyle(fontSize: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: deck.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(deck.icon, size: 18, color: deck.color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    deck.title,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              deck.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _openHtmlFile(context, deck.path),
                                icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                                label: const Text('Launch in Browser'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  textStyle: const TextStyle(fontSize: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeckDetails(dynamic deck, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                deck.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: deck.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                deck.tag,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: deck.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          deck.subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          deck.stats,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: deck.color,
          ),
        ),
      ],
    );
  }
}
