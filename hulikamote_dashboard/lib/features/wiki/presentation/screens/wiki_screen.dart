import 'dart:io';
import 'package:flutter/material.dart';
import '../../../blueprint/presentation/screens/blueprint_screen.dart';
import '../../../docs/data/docs_loader.dart';
import '../../../docs/domain/palette/doc_palette.dart';
import '../../../docs/presentation/screens/docs_screen.dart';
import '../../../docs/presentation/widgets/qa_view.dart';
import '../widgets/detection_pipeline_visualizer_view.dart';
import '../widgets/model_dissection_visualizer_view.dart';
import '../widgets/training_pipeline_visualizer_view.dart';
import '../widgets/wiki_decks_view.dart';
import '../widgets/wiki_project_map_view.dart';
import '../violation_lab/screens/violation_lab_screen.dart';

/// Every page of the wiki. One flat row of tabs, three groups.
enum WikiPage {
  // How the system works
  detection('Detection Pipeline'),
  training('Training Pipeline'),
  models('Model Dissection'),
  violations('Violation Physics'),
  // Reference
  docs('Docs'),
  blueprint('Blueprint'),
  projectMap('Project Map'),
  // Defense
  decks('Decks'),
  qa('Q&A');

  final String label;
  const WikiPage(this.label);

  /// Pages after which a thin divider is drawn.
  bool get endsGroup => this == violations || this == projectMap;
}

class WikiScreen extends StatefulWidget {
  final Directory? root;
  final WikiPage initialPage;

  const WikiScreen({
    super.key,
    this.root,
    this.initialPage = WikiPage.detection,
  });

  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  late WikiPage _page = widget.initialPage;
  Map<String, String> _glossary = {};

  @override
  void initState() {
    super.initState();
    _loadGlossary();
  }

  void _loadGlossary() {
    try {
      _glossary = DocsLoader.isSiteBuilt(widget.root)
          ? DocsLoader.loadGlossary(widget.root)
          : {};
    } catch (_) {
      _glossary = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _WikiTabs(
              selected: _page,
              onSelect: (p) => setState(() => _page = p),
              onReload: () => setState(_loadGlossary),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (_page) {
      WikiPage.detection => const DetectionPipelineVisualizerView(),
      WikiPage.training => const TrainingPipelineVisualizerView(),
      WikiPage.models => const ModelDissectionVisualizerView(),
      WikiPage.violations => const ViolationLabScreen(),
      WikiPage.docs => DocsScreen(root: widget.root),
      WikiPage.blueprint => BlueprintScreen(root: widget.root),
      WikiPage.projectMap => WikiProjectMapView(root: widget.root),
      WikiPage.decks => WikiDecksView(root: widget.root),
      WikiPage.qa => QaView(
          root: widget.root,
          palette: DocPalette.of(context),
          glossary: _glossary,
        ),
    };
  }
}

/// The only navigation in the wiki: every page as a plain text tab, on one line.
class _WikiTabs extends StatelessWidget {
  final WikiPage selected;
  final ValueChanged<WikiPage> onSelect;
  final VoidCallback onReload;

  const _WikiTabs({
    required this.selected,
    required this.onSelect,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final page in WikiPage.values) ...[
                    _Tab(
                      label: page.label,
                      isSelected: page == selected,
                      onTap: () => onSelect(page),
                    ),
                    if (page.endsGroup)
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: scheme.outlineVariant,
                      ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: Icon(Icons.refresh_rounded, size: 18, color: scheme.onSurfaceVariant),
            onPressed: onReload,
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Tab({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
