import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/external_apps.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/reference_data.dart';
import '../../domain/reference_models.dart';
import '../../domain/tests_index.dart';
import '../widgets/code_panel.dart';
import '../widgets/path_rail.dart';
import '../widgets/recipe_strip.dart';

/// The Code Reference: four parts, each a short ladder of slices from the smallest building block to the whole picture.
/// One slice is on screen at a time: a question, a sentence or two, what it is made of, and the real code.
/// Left/Right arrow keys move along the ladder.
class BlueprintScreen extends StatefulWidget {
  const BlueprintScreen({super.key, this.root});

  /// The repository to read code from. Defaults to the one this app runs from.
  final Directory? root;

  @override
  State<BlueprintScreen> createState() => _BlueprintScreenState();
}

class _BlueprintScreenState extends State<BlueprintScreen> {
  ReferenceCategory _category = ReferenceCategory.violations;
  final Map<ReferenceCategory, int> _remembered = {};
  String _openGroup = '';
  late final Directory? _root = widget.root ?? ExternalApps.repoRoot();
  late final TestsIndex? _tests = _root == null ? null : TestsIndex.load(_root);   // built by tools/tests_index.py
  final FocusNode _focus = FocusNode();

  List<Slice> get _slices => ReferenceData.inCategory(_category);
  int get _index => (_remembered[_category] ?? 0).clamp(0, _slices.length - 1);
  Slice get _slice => _slices[_index];

  @override
  void initState() {
    super.initState();
    _openGroup = _slice.group;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go(ReferenceCategory category, int index) => setState(() {
        _category = category;
        _remembered[category] = index;
        _openGroup = _slice.group;
      });

  void _jump(String id) {
    final target = ReferenceData.byId(id);
    if (target == null) return;
    _go(target.category, ReferenceData.inCategory(target.category).indexOf(target));
  }

  void _step(int by) {
    final next = _index + by;
    if (next >= 0 && next < _slices.length) {
      _go(_category, next);
    } else if (by > 0 && _category.index < ReferenceCategory.values.length - 1) {
      _go(ReferenceCategory.values[_category.index + 1], 0);
    } else if (by < 0 && _category.index > 0) {
      final previous = ReferenceCategory.values[_category.index - 1];
      _go(previous, ReferenceData.inCategory(previous).length - 1);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Fx.page(context),
        body: Column(
          children: [
            _Header(category: _category, onSelect: (c) => _go(c, _remembered[c] ?? 0)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,   // the rail and the slice fill the height
                children: [
                  SizedBox(
                    width: 300,
                    child: PathRail(
                      slices: _slices,
                      current: _index,
                      openGroup: _openGroup,
                      onSelect: (i) => _go(_category, i),
                      onToggleGroup: (g) => setState(() => _openGroup = g),
                    ),
                  ),
                  VerticalDivider(width: 1, color: Fx.border(context)),
                  Expanded(child: _SliceView(slice: _slice, index: _index, count: _slices.length, root: _root, tests: _tests, onJump: _jump, onStep: _step, next: _next(), previous: _previous())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the Next button leads to: the next slice, or the first one of the next part.
  String? _next() {
    if (_index < _slices.length - 1) return _slices[_index + 1].title;
    return _category.index < ReferenceCategory.values.length - 1 ? ReferenceCategory.values[_category.index + 1].title : null;
  }

  String? _previous() {
    if (_index > 0) return _slices[_index - 1].title;
    return _category.index > 0 ? ReferenceCategory.values[_category.index - 1].title : null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.category, required this.onSelect});

  final ReferenceCategory category;
  final void Function(ReferenceCategory) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Fx.s32, Fx.s24, Fx.s32, 0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Fx.border(context)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Code reference', style: Fx.title(context)),
          const SizedBox(height: Fx.s4),
          Text(category.blurb, style: Fx.caption(context)),
          const SizedBox(height: Fx.s16),
          Row(
            children: [
              for (final c in ReferenceCategory.values) _Tab(label: c.title, selected: c == category, onTap: () => onSelect(c)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(right: Fx.s32),
        padding: const EdgeInsets.only(bottom: Fx.s12, top: Fx.s4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? Fx.accent : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: Fx.heading(context).copyWith(
            color: selected ? Theme.of(context).colorScheme.onSurface : Fx.muted(context),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _SliceView extends StatelessWidget {
  const _SliceView({
    required this.slice,
    required this.index,
    required this.count,
    required this.root,
    required this.tests,
    required this.onJump,
    required this.onStep,
    required this.next,
    required this.previous,
  });

  final Slice slice;
  final int index;
  final int count;
  final Directory? root;
  final TestsIndex? tests;
  final void Function(String id) onJump;
  final void Function(int by) onStep;
  final String? next;
  final String? previous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: ValueKey(slice.id), // a new slice starts at the top
      padding: const EdgeInsets.fromLTRB(Fx.s32, 40, Fx.s32, Fx.s32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1} OF $count  ·  ${slice.group.toUpperCase()}', style: Fx.label(context)),
              const SizedBox(height: Fx.s12),
              Text(slice.title, style: Fx.title(context).copyWith(fontSize: 30, height: 1.2)),
              const SizedBox(height: Fx.s16),
              Text(slice.says, style: Fx.body(context).copyWith(fontSize: 16, height: 1.55, color: scheme.onSurface.withValues(alpha: 0.82))),
              if (slice.recipe.isNotEmpty) ...[
                const SizedBox(height: Fx.s24),
                RecipeStrip(slice: slice, onJump: onJump),
              ],
              const SizedBox(height: Fx.s24),
              CodePanel(anchors: slice.code, root: root, tests: tests),
              const SizedBox(height: Fx.s32),
              Row(
                children: [
                  if (previous != null)
                    TextButton.icon(onPressed: () => onStep(-1), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Back')),
                  const SizedBox(width: Fx.s16),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(child: Text('Use the arrow keys', maxLines: 1, overflow: TextOverflow.clip, style: Fx.caption(context))),
                        if (next != null) ...[
                          const SizedBox(width: Fx.s16),
                          Flexible(
                            flex: 3,
                            child: FilledButton.icon(
                              onPressed: () => onStep(1),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: Text('Next: ${_short(next!)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String text) => text.length > 34 ? '${text.substring(0, 32)}…' : text;
}
