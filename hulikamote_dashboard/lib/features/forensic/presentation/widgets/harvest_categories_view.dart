import 'package:flutter/material.dart';

import '../../data/harvest_labeling.dart';
import '../../domain/harvest_labeling_models.dart';
import 'fx.dart';
import 'harvest_cars_screen.dart';
import 'harvest_labeler.dart';
import 'harvest_pair_labeler.dart';
import 'harvest_parts.dart';

/// The Harvest tab: only the kinds of pictures that can teach the system something, each as one big tile with the number
/// of pictures waiting. For one analysis ([taskId]) or for all of them (null). A tile opens the full-screen labeler.
class HarvestCategoriesView extends StatefulWidget {
  const HarvestCategoriesView({super.key, required this.labeling, this.taskId, this.active = true});

  final HarvestLabeling labeling;
  final String? taskId;

  /// False while the tab is hidden: nothing is asked of the helper until it is shown.
  final bool active;

  @override
  State<HarvestCategoriesView> createState() => _HarvestCategoriesViewState();
}

class _HarvestCategoriesViewState extends State<HarvestCategoriesView> {
  LabelSession? _session;
  String? _error;
  bool _busy = false; // reading, or getting pictures from the analysis
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(HarvestCategoriesView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !_asked) _start();
    if (widget.taskId != old.taskId) {
      _session = null;
      _asked = false;
      if (widget.active) _start();
    }
  }

  /// Reads what there is; an analysis that was never collected is collected now, once, without asking.
  Future<void> _start() async {
    _asked = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var s = await widget.labeling.session(widget.taskId);
      if (!mounted) return;
      setState(() => _session = s);
      if (!s.collected && !s.protected) {
        s = await widget.labeling.collect(widget.taskId);
        if (!mounted) return;
        setState(() => _session = s);
      }
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// After the labeler: the numbers changed.
  Future<void> _refresh() async {
    try {
      final s = await widget.labeling.session(widget.taskId);
      if (mounted) setState(() => _session = s);
    } catch (_) {
      // the old numbers stay; the next open tells the reason
    }
  }

  Future<void> _open(LabelModelInfo model) async {
    await openHarvestLabeler(context, labeling: widget.labeling, model: model, taskId: widget.taskId);
    if (mounted) await _refresh();
  }

  /// One analysis with cars to check opens the cars; otherwise (every analysis, or only questions) the quick questions.
  Future<void> _openSameCar(LabelSession s) async {
    final task = widget.taskId;
    if (task != null && s.cars.total > 0) {
      await openCarsScreen(context, labeling: widget.labeling, taskId: task);
    } else {
      await openPairLabeler(context, labeling: widget.labeling, taskId: widget.taskId);
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Fx.page(context),
      child: Stack(children: [
        Center(child: _content(context)),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            key: const Key('harvest-refresh'),
            tooltip: 'Look again',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => _start(),
          ),
        ),
      ]),
    );
  }

  Widget _content(BuildContext context) {
    if (_error != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: Fx.s12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(_error!, textAlign: TextAlign.center, style: Fx.body(context)),
        ),
        const SizedBox(height: Fx.s16),
        FilledButton(key: const Key('harvest-retry'), onPressed: _start, child: const Text('Try again')),
      ]);
    }
    final s = _session;
    if (s == null || (_busy && !s.collected)) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: Fx.s16),
        Text(s == null ? 'One moment' : 'Getting the pictures', style: Fx.caption(context)),
      ]);
    }
    if (s.protected) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.shield_outlined, size: 48),
        const SizedBox(height: Fx.s12),
        Text('This clip is protected for the benchmark.', style: Fx.body(context)),
      ]);
    }
    final categories = s.categories;
    // Without the clip's video only the tickets' own pictures exist: say so once, in a few words.
    final hint = widget.taskId != null && s.hasVideo == false
        ? Padding(
            padding: const EdgeInsets.only(top: Fx.s24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.videocam_off_outlined, size: 16, color: Fx.muted(context)),
              const SizedBox(width: Fx.s8),
              Text('Keep the video when analyzing to get more pictures',
                  key: const Key('harvest-video-hint'), style: Fx.caption(context)),
            ]),
          )
        : const SizedBox.shrink();
    if (categories.isEmpty && s.pairs.total == 0 && s.cars.total == 0) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_outlined, size: 56, color: Fx.muted(context)),
        const SizedBox(height: Fx.s12),
        Text('Nothing to harvest here', key: const Key('harvest-empty'), style: Fx.heading(context)),
        hint,
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(
        spacing: Fx.s24,
        runSpacing: Fx.s24,
        alignment: WrapAlignment.center,
        children: [
          for (final m in categories) _tile(context, m),
          if (s.pairs.total + s.cars.total > 0) _sameCarTile(context, s),
        ],
      ),
      hint,
    ]);
  }

  /// "Same car?": one tile like the others, with the number still to check (cars not looked at + quick questions).
  Widget _sameCarTile(BuildContext context, LabelSession s) {
    final waiting = s.cars.open + s.pairs.open;
    final color = HarvestStyle.categoryColor(harvestPairsKey);
    return Opacity(
      opacity: waiting > 0 ? 1 : 0.55,
      child: SizedBox(
        width: 240,
        height: 230,
        child: FxCard(
          key: const Key('category-$harvestPairsKey'),
          onTap: waiting > 0 ? () => _openSameCar(s) : null,
          padding: const EdgeInsets.all(Fx.s16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(HarvestStyle.categoryIcon(harvestPairsKey), size: 40, color: color),
            const SizedBox(height: Fx.s12),
            waiting > 0
                ? Text('$waiting', key: const Key('count-$harvestPairsKey'), style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: color))
                : Icon(Icons.check_circle, key: const Key('count-$harvestPairsKey'), size: 56, color: Fx.success),
            const SizedBox(height: Fx.s8),
            Text('Same car?', style: Fx.title(context)),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, LabelModelInfo m) {
    final waiting = m.toCheck;
    final color = HarvestStyle.categoryColor(m.key);
    return Opacity(
      opacity: waiting > 0 ? 1 : 0.55,
      child: SizedBox(
        width: 240,
        height: 230,
        child: FxCard(
          key: Key('category-${m.key}'),
          onTap: waiting > 0 ? () => _open(m) : null,
          padding: const EdgeInsets.all(Fx.s16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(HarvestStyle.categoryIcon(m.key), size: 40, color: color),
            const SizedBox(height: Fx.s12),
            waiting > 0
                ? Text('$waiting', key: Key('count-${m.key}'), style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: color))
                : Icon(Icons.check_circle, key: Key('count-${m.key}'), size: 56, color: Fx.success),
            const SizedBox(height: Fx.s8),
            Text(m.tileName, style: Fx.title(context)),
          ]),
        ),
      ),
    );
  }
}
