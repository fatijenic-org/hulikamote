import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../blueprint/presentation/screens/blueprint_screen.dart';
import '../../../docs/data/docs_loader.dart';
import '../../../docs/domain/palette/doc_palette.dart';
import '../../../docs/presentation/screens/docs_screen.dart';
import '../../../docs/presentation/widgets/qa_view.dart';
import '../../domain/models/archived_resource.dart';
import '../widgets/detection_pipeline_visualizer_view.dart';
import '../widgets/model_dissection_visualizer_view.dart';
import '../widgets/training_pipeline_visualizer_view.dart';
import '../widgets/wiki_clean_canvas.dart';
import '../widgets/wiki_decks_view.dart';
import '../widgets/wiki_header.dart';
import '../widgets/wiki_project_map_view.dart';
import '../widgets/wiki_visualizer_view.dart';

enum _WikiMainTab {
  visualization,
  directory,
}

enum _VisualizationItem {
  trainingPipeline,
  violationPhysics,
  detectionPipeline,
  modelDissection,
}

class WikiScreen extends StatefulWidget {
  final Directory? root;
  final ArchivedResource? initialArchive;

  const WikiScreen({
    super.key,
    this.root,
    this.initialArchive,
  });

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  _WikiMainTab _activeMainTab = _WikiMainTab.visualization;
  _VisualizationItem _activeVisualizationItem = _VisualizationItem.trainingPipeline;
  ArchivedResource? _selectedArchive;
  String _searchQuery = '';
  Map<String, String> _glossary = {};

  @override
  void initState() {
    super.initState();
    _selectedArchive = widget.initialArchive;
    _loadGlossary();
  }

  void _loadGlossary() {
    try {
      if (DocsLoader.isSiteBuilt(widget.root)) {
        _glossary = DocsLoader.loadGlossary(widget.root);
      }
    } catch (_) {
      _glossary = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Header Bar with Archive Dropdown ────────────────────────
            WikiHeader(
              searchQuery: _searchQuery,
              onSearchChanged: (val) => setState(() => _searchQuery = val),
              onClearSearch: () => setState(() => _searchQuery = ''),
              selectedArchive: _selectedArchive,
              onSelectArchive: (res) => setState(() => _selectedArchive = res),
              onRefresh: () {
                setState(() {
                  _loadGlossary();
                });
              },
            ),

            // ── Archive Banner when an archived resource is active ─────────
            if (_selectedArchive != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedArchive!.color.withOpacity(isDark ? 0.10 : 0.06),
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedArchive!.color.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _selectedArchive = null),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, size: 13, color: isDark ? Colors.white : Colors.black87),
                            const SizedBox(width: 4),
                            Text(
                              'Return to Wiki',
                              style: GoogleFonts.lexend(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(_selectedArchive!.icon, size: 15, color: _selectedArchive!.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Viewing Archive: ${_selectedArchive!.title}',
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _selectedArchive!.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Use Archive Dropdown to switch',
                      style: GoogleFonts.lexend(
                        fontSize: 11,
                        color: textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )
            else
              // ── Main Section Tabs (Mobbin Tool-Grade Navigation) ───────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F141F) : Colors.white,
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    _buildMainTab(
                      label: 'Visualization',
                      icon: Icons.science_rounded,
                      isSelected: _activeMainTab == _WikiMainTab.visualization,
                      onTap: () => setState(() => _activeMainTab = _WikiMainTab.visualization),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildMainTab(
                      label: 'Directory & Archive',
                      icon: Icons.inventory_2_outlined,
                      isSelected: _activeMainTab == _WikiMainTab.directory,
                      onTap: () => setState(() => _activeMainTab = _WikiMainTab.directory),
                      isDark: isDark,
                    ),
                    if (_activeMainTab == _WikiMainTab.visualization) ...[
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF161E2E) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSubItemPill(
                                  label: '1. Training Pipeline',
                                  isSelected: _activeVisualizationItem == _VisualizationItem.trainingPipeline,
                                  onTap: () => setState(() => _activeVisualizationItem = _VisualizationItem.trainingPipeline),
                                  isDark: isDark,
                                ),
                                _buildSubItemPill(
                                  label: '2. Violation Physics',
                                  isSelected: _activeVisualizationItem == _VisualizationItem.violationPhysics,
                                  onTap: () => setState(() => _activeVisualizationItem = _VisualizationItem.violationPhysics),
                                  isDark: isDark,
                                ),
                                _buildSubItemPill(
                                  label: '3. Detection Pipeline',
                                  isSelected: _activeVisualizationItem == _VisualizationItem.detectionPipeline,
                                  onTap: () => setState(() => _activeVisualizationItem = _VisualizationItem.detectionPipeline),
                                  isDark: isDark,
                                ),
                                _buildSubItemPill(
                                  label: '4. Model Dissection',
                                  isSelected: _activeVisualizationItem == _VisualizationItem.modelDissection,
                                  onTap: () => setState(() => _activeVisualizationItem = _VisualizationItem.modelDissection),
                                  isDark: isDark,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // ── Main Body ──────────────────────────────────────────────────
            Expanded(
              child: _selectedArchive != null
                  ? _buildArchivedView(context, _selectedArchive!)
                  : _activeMainTab == _WikiMainTab.directory
                      ? WikiCleanCanvas(
                          onSelectArchive: (res) => setState(() => _selectedArchive = res),
                          searchQuery: _searchQuery,
                        )
                      : switch (_activeVisualizationItem) {
                          _VisualizationItem.trainingPipeline => const TrainingPipelineVisualizerView(),
                          _VisualizationItem.violationPhysics => WikiVisualizerView(root: widget.root),
                          _VisualizationItem.detectionPipeline => const DetectionPipelineVisualizerView(),
                          _VisualizationItem.modelDissection => const ModelDissectionVisualizerView(),
                        },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTab({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF1A2336) : const Color(0xFFEFF6FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6).withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.lexend(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubItemPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF263248) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF0F172A))
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildArchivedView(BuildContext context, ArchivedResource res) {
    switch (res) {
      case ArchivedResource.docs:
        return DocsScreen(root: widget.root);
      case ArchivedResource.visualizer:
        return WikiVisualizerView(root: widget.root);
      case ArchivedResource.blueprint:
        return BlueprintScreen(root: widget.root);
      case ArchivedResource.progress:
        return WikiDecksView(root: widget.root);
      case ArchivedResource.qa:
        return QaView(
          root: widget.root,
          palette: DocPalette.of(context),
          glossary: _glossary,
        );
      case ArchivedResource.projectMap:
        return WikiProjectMapView(root: widget.root);
    }
  }
}
