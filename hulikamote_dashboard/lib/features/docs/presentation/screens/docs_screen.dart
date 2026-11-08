import 'dart:io';
import 'package:flutter/material.dart';

import '../../data/docs_loader.dart';
import '../../domain/models/doc_block.dart';
import '../../domain/models/doc_page.dart';
import '../../domain/palette/doc_palette.dart';
import '../widgets/block_renderer.dart';
import '../widgets/cmd_widget.dart';
import '../widgets/inline_text_renderer.dart';

class DocsScreen extends StatefulWidget {
  final Directory? root;
  final int initialTabIndex;

  const DocsScreen({
    super.key,
    this.root,
    this.initialTabIndex = 0,
  });

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  late int _activeTabIndex;
  bool _isLoading = true;
  bool _isSiteMissing = false;
  Map<String, String> _glossary = {};
  DocPage? _currentPage;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex.clamp(0, DocsLoader.tabs.length - 1);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadInitial() {
    if (!DocsLoader.isSiteBuilt(widget.root)) {
      setState(() {
        _isLoading = false;
        _isSiteMissing = true;
      });
      return;
    }

    final glossary = DocsLoader.loadGlossary(widget.root);
    final spec = DocsLoader.tabs[_activeTabIndex];
    final page = DocsLoader.loadPage(spec.fileName, widget.root);

    setState(() {
      _glossary = glossary;
      _currentPage = page;
      _isLoading = false;
      _isSiteMissing = page == null;
      _rebuildSectionKeys();
    });
  }

  void _rebuildSectionKeys() {
    _sectionKeys.clear();
    if (_currentPage != null) {
      for (final toc in _currentPage!.toc) {
        if (toc.id.isNotEmpty) {
          _sectionKeys[toc.id] = GlobalKey();
        }
      }
    }
  }

  void _selectTab(int index) {
    if (_activeTabIndex == index) return;
    final spec = DocsLoader.tabs[index];
    final page = DocsLoader.loadPage(spec.fileName, widget.root);

    setState(() {
      _activeTabIndex = index;
      _currentPage = page;
      _isLoading = false;
      _rebuildSectionKeys();
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _scrollToSection(String id) {
    final key = _sectionKeys[id];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  void _handleLink(String href) {
    if (href.startsWith('#')) {
      _scrollToSection(href.substring(1));
    } else {
      // Check if href links to another doc page
      for (var i = 0; i < DocsLoader.tabs.length; i++) {
        final spec = DocsLoader.tabs[i];
        if (href.contains(spec.fileName.replaceAll('.json', '')) ||
            href.contains(spec.id)) {
          _selectTab(i);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DocPalette.of(context);

    if (_isSiteMissing) {
      return _buildMissingSiteView(palette);
    }

    return Scaffold(
      backgroundColor: palette.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopNav(palette),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: palette.accent,
                    ),
                  )
                : _buildPageContent(palette),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNav(DocPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'HULI-KAMOTE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  fontSize: 14,
                  color: palette.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'technical documentation',
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: DocsLoader.tabs.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final spec = entry.value;
                  final isSelected = idx == _activeTabIndex;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => _selectTab(idx),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? palette.soft : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: isSelected
                              ? Border.all(color: palette.accent.withValues(alpha: 0.5))
                              : Border.all(color: Colors.transparent),
                        ),
                        child: Text(
                          spec.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? palette.accent : palette.ink2,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(DocPalette palette) {
    if (_currentPage == null) {
      return Center(
        child: Text(
          'Failed to load documentation page.',
          style: TextStyle(color: palette.ink2),
        ),
      );
    }

    final page = _currentPage!;
    final blocks = page.blocks;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          itemCount: blocks.length + 2, // Hero header + TOC + blocks
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHero(page, palette);
            }
            if (index == 1) {
              return _buildToc(page, palette);
            }

            final block = blocks[index - 2];
            Widget blockWidget = BlockRenderer(
              block: block,
              palette: palette,
              glossary: _glossary,
              onLinkTap: _handleLink,
              root: widget.root,
            );

            // If heading has an ID that matches a TOC item, assign the key for scroll
            if (block is HeadingBlock && block.id.isNotEmpty && _sectionKeys.containsKey(block.id)) {
              blockWidget = KeyedSubtree(
                key: _sectionKeys[block.id],
                child: blockWidget,
              );
            } else if (block is CardBlock && block.id.isNotEmpty && _sectionKeys.containsKey(block.id)) {
              blockWidget = KeyedSubtree(
                key: _sectionKeys[block.id],
                child: blockWidget,
              );
            }

            return blockWidget;
          },
        ),
      ),
    );
  }

  Widget _buildHero(DocPage page, DocPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (page.number.isNotEmpty && page.number != 'Start')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'PAGE ${page.number}'.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.0,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  color: palette.accent,
                ),
              ),
            ),
          Text(
            page.title,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: palette.ink,
              height: 1.2,
            ),
          ),
          if (page.lede.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: InlineTextRenderer.buildSpans(
                  inlines: page.lede,
                  palette: palette,
                  glossary: _glossary,
                  baseStyle: TextStyle(
                    fontSize: 18.0,
                    color: palette.ink2,
                    height: 1.5,
                  ),
                  onLinkTap: _handleLink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToc(DocPage page, DocPalette palette) {
    if (page.toc.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ON THIS PAGE',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: page.toc.map((t) {
              return InkWell(
                onTap: () => _scrollToSection(t.id),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: t.level == 3 ? '    • ' : '• ',
                          style: TextStyle(
                            color: palette.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: t.title,
                          style: TextStyle(
                            fontSize: t.level == 3 ? 13.0 : 14.0,
                            color: palette.accent,
                            fontWeight: t.level == 2 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingSiteView(DocPalette palette) {
    return Scaffold(
      backgroundColor: palette.page,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.menu_book_outlined, size: 54, color: palette.accent),
              const SizedBox(height: 18),
              Text(
                'Technical Documentation Not Built Yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The documentation website is generated from the Python repository files. Run this command once in your terminal to build all pages and export the JSON data:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: palette.ink2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              CmdWidget(
                text: DocsLoader.buildCommand,
                palette: palette,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh / Check Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
