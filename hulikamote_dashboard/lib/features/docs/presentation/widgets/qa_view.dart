import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/qa_storage.dart';
import '../../domain/models/qa_item.dart';
import '../../domain/palette/doc_palette.dart';
import '../../domain/utils/qa_markdown.dart';
import 'block_renderer.dart';
import 'chips_widget.dart';

class QaView extends StatefulWidget {
  final Directory? root;
  final DocPalette palette;
  final Map<String, String> glossary;

  const QaView({
    super.key,
    this.root,
    required this.palette,
    required this.glossary,
  });

  @override
  State<QaView> createState() => _QaViewState();
}

class _QaViewState extends State<QaView> {
  List<QaItem> _items = [];
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, answered, unanswered
  String? _selectedTag;
  String? _editingId; // null, 'new', or item.id

  final TextEditingController _qController = TextEditingController();
  final TextEditingController _aController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _isPreview = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qController.dispose();
    _aController.dispose();
    _tagsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    final loaded = QaStorage.loadItems(widget.root);
    setState(() {
      _items = loaded;
      final answeredCount = _items.where((i) => i.isAnswered).length;
      _statusMessage = 'Preserved locally (${_items.length} questions, $answeredCount answered)';
    });
  }

  void _startAdd() {
    setState(() {
      _editingId = 'new';
      _qController.clear();
      _aController.clear();
      _tagsController.clear();
      _isPreview = false;
    });
  }

  void _startEdit(QaItem item) {
    setState(() {
      _editingId = item.id;
      _qController.text = item.q;
      _aController.text = item.a;
      _tagsController.text = item.tags.join(', ');
      _isPreview = false;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
    });
  }

  void _saveItem() {
    final q = _qController.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a question title.')),
      );
      return;
    }

    final a = _aController.text.trim();
    final tags = _tagsController.text
        .split(RegExp(r'[,;\n]'))
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();

    final nowIso = DateTime.now().toUtc().toIso8601String();

    setState(() {
      if (_editingId == 'new') {
        final newId = 'q-${DateTime.now().millisecondsSinceEpoch}';
        final newItem = QaItem(
          id: newId,
          q: q,
          a: a,
          tags: tags,
          created: nowIso,
          updated: nowIso,
        );
        _items.insert(0, newItem);
      } else {
        final idx = _items.indexWhere((i) => i.id == _editingId);
        if (idx != -1) {
          _items[idx] = _items[idx].copyWith(
            q: q,
            a: a,
            tags: tags,
            updated: nowIso,
          );
        }
      }
      _editingId = null;
    });

    final success = QaStorage.saveItems(_items, widget.root);
    final answeredCount = _items.where((i) => i.isAnswered).length;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Saved locally to tools/doc_site/data/qa.json'
              : 'Failed to write to local qa.json',
        ),
        backgroundColor: success ? Colors.green.shade800 : Colors.red.shade800,
        duration: const Duration(seconds: 2),
      ),
    );

    setState(() {
      _statusMessage = success
          ? 'Saved locally at ${TimeOfDay.now().format(context)} (${_items.length} questions, $answeredCount answered)'
          : 'Could not write to disk';
    });
  }

  void _deleteItem(QaItem item) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Question?'),
        content: Text('Are you sure you want to delete:\n\n"${item.q}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          _items.removeWhere((i) => i.id == item.id);
          if (_editingId == item.id) _editingId = null;
        });
        QaStorage.saveItems(_items, widget.root);
        final answeredCount = _items.where((i) => i.isAnswered).length;
        setState(() {
          _statusMessage = 'Question deleted (${_items.length} questions, $answeredCount answered)';
        });
      }
    });
  }

  void _exportJson() {
    final jsonStr = QaStorage.exportJsonString(_items);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Q&A JSON copied to clipboard (ready to backup or share).'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showImportDialog() {
    final importController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Q&A JSON'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the Q&A JSON content below. Questions with matching IDs will be updated; new IDs will be added.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: importController,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{\n  "version": 1,\n  "items": [...]\n}',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final result = QaStorage.importJson(importController.text, _items);
              if (result == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid Q&A JSON format.')),
                );
                return;
              }
              setState(() {
                _items = result.merged;
              });
              QaStorage.saveItems(_items, widget.root);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported ${result.added} new and updated ${result.replaced} existing questions.'),
                ),
              );
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  List<QaItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    return _items.where((x) {
      if (_statusFilter == 'answered' && !x.isAnswered) return false;
      if (_statusFilter == 'unanswered' && x.isAnswered) return false;
      if (_selectedTag != null && !x.tags.contains(_selectedTag)) return false;
      if (query.isNotEmpty) {
        final matches = '${x.q} ${x.a} ${x.tags.join(' ')}'.toLowerCase();
        if (!matches.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  String _formatStamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hh:$mm';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final allTags = _items.expand((i) => i.tags).toSet().toList()..sort();
    final filtered = _filteredItems;
    final answeredTotal = _items.where((i) => i.isAnswered).length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status bar
        if (_statusMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: palette.soft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.ink,
                    ),
                  ),
                ),
                Text(
                  '100% offline & local',
                  style: TextStyle(fontSize: 11.5, color: palette.muted),
                ),
              ],
            ),
          ),

        // Action Toolbar
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _editingId == null ? _startAdd : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Question'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            SizedBox(
              width: 260,
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search questions, tags...',
                  hintStyle: TextStyle(fontSize: 13, color: palette.muted),
                  prefixIcon: Icon(Icons.search, size: 18, color: palette.muted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: palette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _statusFilter,
                  icon: Icon(Icons.arrow_drop_down, color: palette.muted),
                  style: TextStyle(fontSize: 13, color: palette.ink),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text('All (${_items.length})')),
                    DropdownMenuItem(value: 'answered', child: Text('Answered ($answeredTotal)')),
                    DropdownMenuItem(value: 'unanswered', child: Text('Unanswered (${_items.length - answeredTotal})')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _statusFilter = val);
                  },
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _exportJson,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export JSON'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showImportDialog,
              icon: const Icon(Icons.upload_outlined, size: 16),
              label: const Text('Import JSON'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Tag bar
        if (allTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'Tags: ',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.muted),
                  ),
                  const SizedBox(width: 4),
                  ...allTags.map((t) {
                    final isSel = _selectedTag == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => setState(() => _selectedTag = isSel ? null : t),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSel ? palette.accent.withValues(alpha: 0.15) : palette.soft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel ? palette.accent : palette.border,
                            ),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              color: isSel ? palette.accent : palette.ink2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

        // Editor when adding a new question
        if (_editingId == 'new')
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildEditorCard(isNew: true),
          ),

        // Questions list
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            alignment: Alignment.center,
            child: Text(
              _items.isEmpty
                  ? 'No questions yet. Click "+ Add Question" to create your first Q&A.'
                  : 'No questions match the active search or filter.',
              style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: palette.muted),
            ),
          )
        else
          ...filtered.map((item) {
            if (_editingId == item.id) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildEditorCard(isNew: false),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildQuestionCard(item),
            );
          }),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: content,
              ),
            ),
          );
        }
        return content;
      },
    );
  }

  Widget _buildEditorCard({required bool isNew}) {
    final palette = widget.palette;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isNew ? Icons.add_circle_outline : Icons.edit_note, color: palette.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                isNew ? 'New Question' : 'Edit Question',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: palette.ink),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Question', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.ink2)),
          const SizedBox(height: 6),
          TextField(
            controller: _qController,
            maxLines: 2,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: palette.ink),
            decoration: InputDecoration(
              hintText: 'The question a panelist may ask...',
              hintStyle: TextStyle(color: palette.muted),
              filled: true,
              fillColor: palette.page,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Answer (Markdown supported)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.ink2)),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Write', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: true, label: Text('Preview', style: TextStyle(fontSize: 12))),
                ],
                selected: {_isPreview},
                onSelectionChanged: (val) => setState(() => _isPreview = val.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!_isPreview)
            TextField(
              controller: _aController,
              maxLines: 8,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: palette.ink),
              decoration: InputDecoration(
                hintText: 'Your answer. Markdown works: **bold**, *italic*, `code`, - bullet lists, > quotes...',
                hintStyle: TextStyle(color: palette.muted),
                filled: true,
                fillColor: palette.page,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              constraints: const BoxConstraints(minHeight: 180),
              decoration: BoxDecoration(
                color: palette.page,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border),
              ),
              child: _aController.text.trim().isEmpty
                  ? Text('Nothing to preview yet.', style: TextStyle(fontStyle: FontStyle.italic, color: palette.muted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: QaMarkdown.parse(_aController.text)
                          .map((b) => BlockRenderer(block: b, palette: palette, glossary: widget.glossary))
                          .toList(),
                    ),
            ),
          const SizedBox(height: 14),
          Text('Tags', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: palette.ink2)),
          const SizedBox(height: 6),
          TextField(
            controller: _tagsController,
            style: TextStyle(fontSize: 13.5, color: palette.ink),
            decoration: InputDecoration(
              hintText: 'tags, separated by commas (e.g. models, data, plates, evaluation)',
              hintStyle: TextStyle(color: palette.muted),
              filled: true,
              fillColor: palette.page,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _saveItem,
                icon: const Icon(Icons.check, size: 16),
                label: Text(isNew ? 'Add Question' : 'Save Changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _cancelEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(QaItem item) {
    final palette = widget.palette;
    final answered = item.isAnswered;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.q,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ChipPill(
                text: answered ? 'Answered' : 'Unanswered',
                kind: answered ? 'ok' : 'warn',
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (answered)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: QaMarkdown.parse(item.a)
                    .map((b) => BlockRenderer(block: b, palette: palette, glossary: widget.glossary))
                    .toList(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No answer yet. Click Edit to write one.',
                style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: palette.muted),
              ),
            ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              if (item.tags.isNotEmpty)
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.tags.map((t) {
                      return InkWell(
                        onTap: () => setState(() => _selectedTag = _selectedTag == t ? null : t),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.soft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(fontSize: 11, color: palette.muted),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              else
                const Spacer(),
              Text(
                'edited ${_formatStamp(item.updated)}',
                style: TextStyle(fontSize: 11.5, color: palette.muted),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit question',
                onPressed: () => _startEdit(item),
                color: palette.ink2,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                tooltip: 'Delete question',
                onPressed: () => _deleteItem(item),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
