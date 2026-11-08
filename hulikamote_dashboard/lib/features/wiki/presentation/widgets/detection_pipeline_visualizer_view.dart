import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/detection_pipeline_content.dart';
import '../../domain/detection_pipeline_rules.dart';
import 'detection_figure_kit.dart';
import 'detection_judge_painters.dart';
import 'detection_spine_painters.dart';

/// Low-cognitive-load visualizer that follows a video frame through the nine
/// steps of the detection engine and shows how each of the 25 violations is
/// judged. Secondary explanations, technical specs, and the 14-recipe catalog
/// open on demand in clean modal dialogs.
class DetectionPipelineVisualizerView extends StatefulWidget {
  const DetectionPipelineVisualizerView({super.key});

  @override
  State<DetectionPipelineVisualizerView> createState() =>
      _DetectionPipelineVisualizerViewState();
}

class _Pal {
  final bool dark;
  const _Pal(this.dark);
  Color get canvas => dark ? const Color(0xFF0A0D12) : const Color(0xFFF8FAFC);
  Color get surface => dark ? const Color(0xFF0F141C) : Colors.white;
  Color get subtle => dark ? const Color(0xFF151C28) : const Color(0xFFF1F5F9);
  Color get border => dark ? const Color(0xFF1E2634) : const Color(0xFFE2E8F0);
  Color get text => dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get sub => dark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  Color get mute => const Color(0xFF64748B);
}

class _DetectionPipelineVisualizerViewState
    extends State<DetectionPipelineVisualizerView>
    with SingleTickerProviderStateMixin {
  static const Color _blue = FigColors.blue;
  static const int _stepCount = 9;

  String _recipeId = kRecipes.first.id;
  int _active = 0;
  bool _auto = false;
  bool _singleStepFocus = false;
  double _speed = 1.0;
  double _cutoff = kDefaultCutoff;
  List<bool> _looks = [true, false, true, false, false, true, false, false, false, false];
  int _taken = 6;
  Set<int> _visible = {0, 1};
  Timer? _timer;

  late final AnimationController _loop;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _bodyKey = GlobalKey();
  final List<GlobalKey> _stepKeys = List.generate(_stepCount, (_) => GlobalKey());

  DetectionRecipe get _recipe => recipeById(_recipeId);

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
      ..repeat();
    _scroll.addListener(_updateVisible);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _loop.dispose();
    super.dispose();
  }

  // ── Behaviour ─────────────────────────────────────────────────────────────

  /// Only figures on screen animate; the rest hold one still frame.
  void _updateVisible() {
    if (_singleStepFocus) {
      if (!_visible.contains(_active) || _visible.length != 1) {
        setState(() => _visible = {_active});
      }
      return;
    }
    final body = _bodyKey.currentContext?.findRenderObject();
    if (body is! RenderBox || !body.attached) return;
    final top = body.localToGlobal(Offset.zero).dy;
    final bottom = top + body.size.height;
    final seen = <int>{};
    for (var i = 0; i < _stepKeys.length; i++) {
      final box = _stepKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y < bottom && y + box.size.height > top) seen.add(i);
    }
    if (!setEquals(seen, _visible)) setState(() => _visible = seen);
  }

  void _selectStep(int index) {
    final i = index.clamp(0, _stepCount - 1);
    setState(() => _active = i);
    if (_singleStepFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _stepKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        );
      }
    });
  }

  void _selectRecipe(String id) {
    setState(() {
      _recipeId = id;
      _looks = [true, false, true, false, false, true, false, false, false, false];
      _taken = 6;
    });
    _selectStep(5);
  }

  void _toggleAuto() {
    setState(() => _auto = !_auto);
    _timer?.cancel();
    if (_auto) _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (4200 / _speed).round()), () {
      if (!mounted || !_auto) return;
      _selectStep((_active + 1) % _stepCount);
      _scheduleNext();
    });
  }

  void _cycleSpeed() {
    setState(() {
      _speed = _speed == 1.0 ? 1.5 : (_speed == 1.5 ? 0.6 : 1.0);
    });
    if (_auto) _scheduleNext();
  }

  /// Extracts a short, single-sentence digest so cards stay visually calm.
  String _firstSentence(String text) {
    final dot = text.indexOf('. ');
    if (dot != -1 && dot < 140) return text.substring(0, dot + 1);
    return text;
  }

  // ── On-Demand Dialogs (Zero clutter on main screen) ───────────────────────

  void _showRecipePickerDialog(_Pal p) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select a Violation Recipe (14 Recipes · All 25 Violations)',
                              style: GoogleFonts.lexend(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Steps 1–5, 8 and 9 are shared by every rule. Picking a recipe updates Steps 6 and 7.',
                              style: GoogleFonts.lexend(fontSize: 12, color: p.sub),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: Icon(Icons.close_rounded, size: 18, color: p.sub),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: p.border),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: _pickerGrid(
                        p,
                        _recipe,
                        onPick: (id) {
                          Navigator.of(ctx).pop();
                          _selectRecipe(id);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStepDetailsDialog(_Pal p, PipelineStep st, DetectionRecipe r) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: p.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'STEP ${st.numLabel}',
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            st.title,
                            style: GoogleFonts.lexend(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: p.text,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close_rounded, size: 18, color: p.sub),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      st.source,
                      style: GoogleFonts.firaCode(fontSize: 11, color: _blue),
                    ),
                    if (st.index == 5) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${r.family.title} · Catches: ${r.covers.join(' · ')}',
                        style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      st.plain,
                      style: GoogleFonts.lexend(fontSize: 13, height: 1.6, color: p.text),
                    ),
                    if (st.facts.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'TECHNICAL SPECIFICATIONS & CODE PARAMETERS',
                        style: GoogleFonts.firaCode(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: p.mute,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: p.subtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.border),
                        ),
                        child: _facts(p, st),
                      ),
                    ],
                    if (st.guards != null) _note(p, 'Stays quiet when', st.guards!, FigColors.pass),
                    if (st.limits != null) _note(p, 'Know the limits', st.limits!, FigColors.warn),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = _Pal(Theme.of(context).brightness == Brightness.dark);
    final recipe = _recipe;
    final steps = buildSteps(recipe);
    final displayedSteps =
        _singleStepFocus ? [steps[_active.clamp(0, steps.length - 1)]] : steps;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisible();
    });

    return Container(
      color: p.canvas,
      child: Column(
        children: [
          _header(p, steps),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            decoration: BoxDecoration(
              color: p.canvas,
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: _compactRuleBar(p, recipe),
              ),
            ),
          ),
          Expanded(
            key: _bodyKey,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final step in displayedSteps)
                        Container(
                          key: _stepKeys[step.index],
                          child: _stepSection(
                            p,
                            step,
                            recipe,
                            last: _singleStepFocus || step.index == _stepCount - 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(_Pal p, List<PipelineStep> steps) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Detection Pipeline',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lexend(
                      fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: p.text),
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 14, color: p.border),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'How a video frame becomes a ticket',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _singleStepFocus = !_singleStepFocus),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _singleStepFocus ? _blue.withValues(alpha: 0.14) : p.subtle,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _singleStepFocus ? _blue : p.border),
                  ),
                  child: Text(
                    _singleStepFocus ? 'View: 1-by-1 Focus' : 'View: Scroll All',
                    style: GoogleFonts.lexend(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _singleStepFocus ? p.text : p.sub,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _transport(p),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final st in steps)
                InkWell(
                  onTap: () => _selectStep(st.index),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _active == st.index ? _blue.withValues(alpha: 0.14) : p.subtle,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _active == st.index ? _blue : p.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(st.numLabel, style: GoogleFonts.firaCode(fontSize: 10, color: p.mute)),
                        const SizedBox(width: 5),
                        Text(
                          st.navLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            fontWeight: _active == st.index ? FontWeight.w600 : FontWeight.w400,
                            color: _active == st.index ? p.text : p.sub,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 6,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) => CustomPaint(
                painter: _SignalLinePainter(
                    progress: _loop.value, active: _active, total: _stepCount, dark: p.dark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transport(_Pal p) {
    Widget cell(String text, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Text(text,
                style: GoogleFonts.lexend(fontSize: 11, fontWeight: FontWeight.w500, color: p.text)),
          ),
        );
    final divider = Container(width: 1, height: 18, color: p.border);
    return Container(
      decoration: BoxDecoration(
        color: p.subtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell('Prev', () => _selectStep(_active - 1)),
          divider,
          InkWell(
            onTap: _toggleAuto,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: (_auto ? FigColors.pass : _blue).withValues(alpha: 0.12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_auto ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 13, color: _auto ? FigColors.pass : _blue),
                  const SizedBox(width: 4),
                  Text(_auto ? 'Pause' : 'Auto-play',
                      style: GoogleFonts.lexend(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _auto ? FigColors.pass : _blue)),
                ],
              ),
            ),
          ),
          divider,
          cell('Next', () => _selectStep(_active + 1)),
          divider,
          InkWell(
            onTap: _cycleSpeed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('${_speed}x', style: GoogleFonts.firaCode(fontSize: 10.5, color: p.sub)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Slim Active Rule Banner (Replaces the giant 14-box inline table) ───────

  Widget _compactRuleBar(_Pal p, DetectionRecipe selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _blue.withValues(alpha: 0.45)),
            ),
            child: Text(
              selected.family.title,
              style: GoogleFonts.firaCode(fontSize: 10.5, fontWeight: FontWeight.w600, color: _blue),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        selected.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '(${selected.covers.join(' · ')})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            key: const ValueKey('open-recipe-picker'),
            onTap: () => _showRecipePickerDialog(p),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _blue),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune_rounded, size: 14, color: _blue),
                  const SizedBox(width: 6),
                  Text(
                    'Change Violation Rule (25)',
                    style: GoogleFonts.lexend(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerGrid(_Pal p, DetectionRecipe selected, {required ValueChanged<String> onPick}) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      final cols = [
        for (final f in JudgeFamily.values) _familyColumn(p, f, selected, onPick: onPick),
      ];
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: cols[i]),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cols.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  cols[i],
                ],
              ],
            );
    });
  }

  Widget _familyColumn(
    _Pal p,
    JudgeFamily f,
    DetectionRecipe selected, {
    required ValueChanged<String> onPick,
  }) {
    final count = recipesIn(f).fold<int>(0, (n, r) => n + r.covers.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.title,
            style: GoogleFonts.lexend(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
        const SizedBox(height: 2),
        Text('${f.question} ($count checks)',
            style: GoogleFonts.lexend(fontSize: 11.5, height: 1.4, color: p.sub)),
        const SizedBox(height: 8),
        for (final r in recipesIn(f))
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: InkWell(
              onTap: () => onPick(r.id),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: r.id == selected.id ? _blue.withValues(alpha: 0.12) : p.subtle,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: r.id == selected.id ? _blue : p.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        style: GoogleFonts.lexend(
                            fontSize: 12,
                            fontWeight: r.id == selected.id ? FontWeight.w600 : FontWeight.w500,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Text(r.covers.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(fontSize: 10.5, height: 1.35, color: p.mute)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Visual-First Step Cards ───────────────────────────────────────────────

  Widget _stepSection(_Pal p, PipelineStep st, DetectionRecipe r, {required bool last}) {
    final isActive = st.index == _active;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 32 : 20),
      child: Stack(
        children: [
          if (!last)
            Positioned(left: 11, top: 28, bottom: -20, width: 1, child: ColoredBox(color: p.border)),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? _blue.withValues(alpha: 0.16) : p.surface,
                border: Border.all(color: isActive ? _blue : p.border),
              ),
              child: Text(st.numLabel,
                  style: GoogleFonts.firaCode(fontSize: 9, color: isActive ? p.text : p.mute)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isActive ? _blue.withValues(alpha: 0.65) : p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          st.title,
                          style: GoogleFonts.lexend(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: p.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        key: ValueKey('step-details-${st.index}'),
                        onTap: () => _showStepDetailsDialog(p, st, r),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: p.subtle,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: p.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 13, color: _blue),
                              const SizedBox(width: 5),
                              Text(
                                'Details & Specs',
                                style: GoogleFonts.lexend(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: p.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _firstSentence(st.plain),
                    style: GoogleFonts.lexend(fontSize: 12.5, height: 1.45, color: p.sub),
                  ),
                  const SizedBox(height: 12),
                  _figureBlock(p, st, r),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(_Pal p, String title, String body, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 2))),
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.lexend(fontSize: 12.5, height: 1.5, color: p.sub),
            children: [
              TextSpan(text: '$title.  ', style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
              TextSpan(text: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _facts(_Pal p, PipelineStep st) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < st.facts.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: i == 0 ? Colors.transparent : p.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 118,
                  child: Text(st.facts[i].$1,
                      style: GoogleFonts.lexend(fontSize: 11.5, color: p.mute)),
                ),
                Expanded(
                  child: Text(st.facts[i].$2,
                      style: GoogleFonts.lexend(fontSize: 12, height: 1.45, color: p.text)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Figures ───────────────────────────────────────────────────────────────

  double _aspect(DetectionFigure f) => switch (f) {
        DetectionFigure.holdConfirm || DetectionFigure.marginConfirm => 3.2,
        DetectionFigure.exitConfirm => 3.0,
        _ => 2.5,
      };

  FigurePainter? _painterFor(PipelineStep st, DetectionRecipe r, double t, bool d) =>
      switch (st.figure) {
        DetectionFigure.frames => FramesPainter(t, d),
        DetectionFigure.detector => DetectorPainter(t, d, cutoff: _cutoff),
        DetectionFigure.zoneFilter => ZoneFilterPainter(t, d),
        DetectionFigure.tracker => TrackerPainter(t, d),
        DetectionFigure.ledger => LedgerPainter(t, d),
        DetectionFigure.stopped => StoppedPainter(t, d),
        DetectionFigure.wrongWay => WrongWayPainter(t, d),
        DetectionFigure.wrongTurn => WrongTurnPainter(t, d),
        DetectionFigure.crossLine => CrossLinePainter(t, d),
        DetectionFigure.vehicleType => VehicleTypePainter(t, d),
        DetectionFigure.weaving => WeavingPainter(t, d),
        DetectionFigure.signal => SignalPainter(t, d),
        DetectionFigure.riders => RidersPainter(t, d),
        DetectionFigure.onboard => OnboardPainter(t, d),
        DetectionFigure.helmet => HelmetPainter(t, d),
        DetectionFigure.seatbelt => CabinPainter(t, d, phoneVariant: false),
        DetectionFigure.phone => CabinPainter(t, d, phoneVariant: true),
        DetectionFigure.mirror => MirrorPainter(t, d),
        DetectionFigure.plate => PlatePainter(t, d),
        DetectionFigure.holdConfirm => HoldConfirmPainter(t, d, caption: r.confirmLabel),
        DetectionFigure.marginConfirm => MarginConfirmPainter(t, d, caption: r.confirmLabel),
        DetectionFigure.exitConfirm => ExitConfirmPainter(t, d),
        DetectionFigure.evidence => EvidencePainter(t, d),
        DetectionFigure.ticket => TicketPainter(t, d),
        DetectionFigure.voteConfirm => null,
      };

  Widget _figureBlock(_Pal p, PipelineStep st, DetectionRecipe r) {
    final painterAt = _painterFor(st, r, 0.4, p.dark);
    final live = _visible.contains(st.index);
    final Widget canvas;
    if (painterAt == null) {
      canvas = _voteSimulator(p, r);
    } else {
      canvas = AspectRatio(
        aspectRatio: _aspect(st.figure),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => CustomPaint(
              painter: _painterFor(st, r, live ? _loop.value : 0.4, p.dark),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.border),
          ),
          child: canvas,
        ),
        if (st.figure == DetectionFigure.detector) _cutoffSlider(p),
      ],
    );
  }

  Widget _cutoffSlider(_Pal p) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('General cutoff', style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub)),
          Expanded(
            child: Slider(
              value: _cutoff,
              min: 0.1,
              max: 0.9,
              divisions: 16,
              label: _cutoff.toStringAsFixed(2),
              onChanged: (v) => setState(() => _cutoff = v),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text('${_cutoff.toStringAsFixed(2)}  (code: 0.45)',
                style: GoogleFonts.firaCode(fontSize: 10.5, color: p.sub)),
          ),
        ],
      ),
    );
  }

  Widget _voteSimulator(_Pal p, DetectionRecipe r) {
    final looks = _looks.take(_taken).toList();
    final fires = voteVerdict(looks, minLooks: r.voteMinLooks, share: r.voteShare);
    final bad = looks.where((b) => b).length;
    final need = (r.voteShare * looks.length).ceil();
    final pct = (r.voteShare * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Each look: was it bad?  ${r.confirmLabel}',
            style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < 10; i++)
              GestureDetector(
                onTap: i < _taken
                    ? () => setState(() {
                          _looks = [..._looks]..[i] = !_looks[i];
                        })
                    : null,
                child: Container(
                  key: ValueKey('look-$i'),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i >= _taken
                        ? Colors.transparent
                        : (_looks[i] ? FigColors.warn.withValues(alpha: 0.22) : p.subtle),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: i >= _taken ? p.border : (_looks[i] ? FigColors.warn : p.border)),
                  ),
                  child: Text(
                    i >= _taken ? '' : (_looks[i] ? 'bad' : 'ok'),
                    style: GoogleFonts.firaCode(
                        fontSize: 10.5, color: _looks[i] ? FigColors.warn : p.sub),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Looks taken', style: GoogleFonts.lexend(fontSize: 11.5, color: p.sub)),
            Expanded(
              child: Slider(
                value: _taken.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$_taken',
                onChanged: (v) => setState(() => _taken = v.round()),
              ),
            ),
            Text('$_taken', style: GoogleFonts.firaCode(fontSize: 11, color: p.sub)),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (fires ? FigColors.fail : p.subtle).withValues(alpha: fires ? 0.14 : 1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: fires ? FigColors.fail : p.border),
          ),
          child: Text(
            fires
                ? 'TICKET: $bad bad of ${looks.length} looks, needs at least $need '
                    '($pct%) and at least ${r.voteMinLooks} looks.'
                : (looks.length < r.voteMinLooks
                    ? 'No ticket yet: only ${looks.length} look${looks.length == 1 ? '' : 's'}, '
                        'needs at least ${r.voteMinLooks}.'
                    : 'No ticket: $bad bad of ${looks.length} looks, needs at least $need ($pct%).'),
            key: const ValueKey('vote-verdict'),
            style: GoogleFonts.firaCode(
                fontSize: 11, height: 1.5, color: fires ? FigColors.fail : p.sub),
          ),
        ),
      ],
    );
  }
}

/// The thin line under the step buttons: a pulse runs through the nine steps and
/// the active step is lit.
class _SignalLinePainter extends CustomPainter {
  _SignalLinePainter({
    required this.progress,
    required this.active,
    required this.total,
    required this.dark,
  });

  final double progress;
  final int active;
  final int total;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = dark ? const Color(0xFF1E2634) : const Color(0xFFE2E8F0);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = line..strokeWidth = 1);
    for (var i = 0; i < total; i++) {
      final x = size.width * (i + 0.5) / total;
      canvas.drawCircle(
          Offset(x, y), i == active ? 3 : 2, Paint()..color = i == active ? FigColors.blue : line);
    }
    final px = size.width * progress;
    canvas.drawCircle(Offset(px, y), 2, Paint()..color = FigColors.blue.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _SignalLinePainter old) =>
      old.progress != progress || old.active != active || old.dark != dark;
}
