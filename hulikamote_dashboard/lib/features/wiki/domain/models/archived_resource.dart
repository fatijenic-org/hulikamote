import 'package:flutter/material.dart';

enum ArchivedResource {
  docs(
    id: 'docs',
    title: 'Technical Documentation',
    subtitle: '6-chapter site: Datasets, Models, Training Pipeline, Violations',
    icon: Icons.menu_book_rounded,
    badge: '6 Pages',
    color: Color(0xFF10B981),
  ),
  visualizer(
    id: 'visualizer',
    title: 'Violation Logic & Physics Visualizer',
    subtitle: '13 violation algorithms, first-principle math & 5 educational phases',
    icon: Icons.science_rounded,
    badge: '13 Models',
    color: Color(0xFF8B5CF6),
  ),
  blueprint(
    id: 'blueprint',
    title: 'System Architecture Blueprint',
    subtitle: 'Pipeline slices, real Python symbol inspector & live test tracer',
    icon: Icons.account_tree_rounded,
    badge: 'Code Trace',
    color: Color(0xFFF59E0B),
  ),
  progress(
    id: 'progress',
    title: 'Progress Decks & Technical Audits',
    subtitle: 'Interactive HTML slide deck, journey narrative & technical audit',
    icon: Icons.slideshow_rounded,
    badge: '3 Decks',
    color: Color(0xFFEC4899),
  ),
  qa(
    id: 'qa',
    title: 'Defense Q&A Knowledge Base',
    subtitle: 'Oral defense question bank, local offline markdown editor',
    icon: Icons.help_rounded,
    badge: 'Local Q&A',
    color: Color(0xFF06B6D4),
  ),
  projectMap(
    id: 'projectMap',
    title: 'Project Map & Risk Matrices',
    subtitle: 'Interactive D3 architecture graphs, coupling matrix & test coverage',
    icon: Icons.hub_rounded,
    badge: 'D3 Graphs',
    color: Color(0xFF6366F1),
  );

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final Color color;

  const ArchivedResource({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.color,
  });
}
