import 'package:flutter/material.dart';

enum WikiTab {
  overview(
    id: 'overview',
    label: 'Overview',
    shortLabel: 'Overview',
    subtitle: 'System wiki portal, knowledge domains, and quick navigation',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
    badge: 'Hub',
    accentColor: Color(0xFF3B82F6), // Blue
  ),
  docs(
    id: 'docs',
    label: 'Technical Docs',
    shortLabel: 'Docs',
    subtitle: 'Generated technical documentation, datasets, models, pipeline & violations',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book_rounded,
    badge: '6 Pages',
    accentColor: Color(0xFF10B981), // Emerald
  ),
  visualizer(
    id: 'visualizer',
    label: 'Logic Visualizer',
    shortLabel: 'Visualizer',
    subtitle: 'Interactive violation algorithms, first-principle physics & mathematical geometry',
    icon: Icons.science_outlined,
    selectedIcon: Icons.science_rounded,
    badge: '13 Models',
    accentColor: Color(0xFF8B5CF6), // Purple
  ),
  blueprint(
    id: 'blueprint',
    label: 'Architecture Blueprint',
    shortLabel: 'Blueprint',
    subtitle: 'Interactive system pipeline stages, code symbol explorer & test execution trace',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree_rounded,
    badge: 'Code',
    accentColor: Color(0xFFF59E0B), // Amber
  ),
  progress(
    id: 'progress',
    label: 'Progress & Decks',
    shortLabel: 'Decks',
    subtitle: 'Interactive milestone presentation deck, journey narrative & engineering audit',
    icon: Icons.slideshow_outlined,
    selectedIcon: Icons.slideshow_rounded,
    badge: 'Decks',
    accentColor: Color(0xFFEC4899), // Pink
  ),
  qa(
    id: 'qa',
    label: 'Defense Q&A',
    shortLabel: 'Q&A',
    subtitle: 'Panelist questions, oral defense preparation & local markdown knowledge base',
    icon: Icons.help_outline_rounded,
    selectedIcon: Icons.help_rounded,
    badge: 'Local',
    accentColor: Color(0xFF06B6D4), // Cyan
  ),
  projectMap(
    id: 'projectMap',
    label: 'Project Map & Risks',
    shortLabel: 'Map & Risks',
    subtitle: 'Interactive D3 architecture graphs, coupling risk matrix & test coverage',
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub_rounded,
    badge: 'Graph',
    accentColor: Color(0xFF6366F1), // Indigo
  );

  final String id;
  final String label;
  final String shortLabel;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
  final String badge;
  final Color accentColor;

  const WikiTab({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
    required this.badge,
    required this.accentColor,
  });
}
