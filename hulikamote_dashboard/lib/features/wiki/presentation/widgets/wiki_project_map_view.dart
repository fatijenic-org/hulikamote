import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/utils/external_apps.dart';

class WikiProjectMapView extends StatelessWidget {
  final Directory? root;

  const WikiProjectMapView({super.key, this.root});

  Future<void> _openFile(BuildContext context, String relativePath) async {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final maps = [
      (
        title: 'Interactive D3 Architecture Graph',
        subtitle: 'Dynamic node-link diagram mapping imports, caller-callee dependencies, and dataflow across backend and dashboard.',
        path: 'docs/project_map/graph.html',
        tag: 'D3 Graph',
        icon: Icons.hub_rounded,
        color: const Color(0xFF3B82F6),
      ),
      (
        title: 'Project Map & Module Coupling Explorer',
        subtitle: 'Comprehensive breakdown of architectural layers, module coupling metrics, and structural boundaries.',
        path: 'docs/project_map/index.html',
        tag: 'Project Map',
        icon: Icons.account_tree_rounded,
        color: const Color(0xFF3B82F6),
      ),
      (
        title: 'Python & Dart Test Coverage Report',
        subtitle: 'Line-by-line statement and branch coverage visualization for detection engine, specialists, and tests.',
        path: 'docs/project_map/coverage_html/index.html',
        tag: 'Coverage',
        icon: Icons.fact_check_rounded,
        color: const Color(0xFF3B82F6),
      ),
      (
        title: 'Codebase Risk Mitigation Table',
        subtitle: 'Assessment of algorithmic edge cases, hardware thermal risks, false-positive vectors, and fallback strategies.',
        path: 'docs/project_map/RISK_TABLE.md',
        tag: 'Risk Analysis',
        icon: Icons.security_rounded,
        color: const Color(0xFF3B82F6),
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
                child: const Icon(Icons.hub_rounded, size: 20, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Map, Coupling & Risk Matrices',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Interactive D3 network graphs, test coverage reports, and architectural risk tables.',
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

          ...maps.map((m) {
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
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: m.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: m.color.withOpacity(0.2)),
                              ),
                              child: Icon(m.icon, size: 22, color: m.color),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildMapDetails(m, isDark)),
                            const SizedBox(width: 16),
                            FilledButton.icon(
                              onPressed: () => _openFile(context, m.path),
                              icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                              label: const Text('Open Resource'),
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
                                    color: m.color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(m.icon, size: 18, color: m.color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    m.title,
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
                              m.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _openFile(context, m.path),
                                icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                                label: const Text('Open Resource'),
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

  Widget _buildMapDetails(dynamic m, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                m.title,
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
                color: m.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                m.tag,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: m.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          m.subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
