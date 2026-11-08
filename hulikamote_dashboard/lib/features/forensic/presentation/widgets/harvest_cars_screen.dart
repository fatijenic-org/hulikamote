import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/harvest_labeling.dart';
import '../../domain/harvest_labeling_models.dart';
import 'harvest_car_viewer.dart';
import 'harvest_pair_labeler.dart';
import 'harvest_parts.dart';

/// Opens the cars of one analysis over the whole window: a card per ticketed car, by number. Pick one to walk along its photos.
Future<void> openCarsScreen(BuildContext context, {required HarvestLabeling labeling, required String taskId}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CarsScreen(labeling: labeling, taskId: taskId),
    ),
  );
}

const _green = Color(0xFF4CC38A);
const _orange = Color(0xFFFFB454);

/// Every ticketed car of one analysis. The first card, when there is one, holds the quick "same car?" questions
/// (a car that vanished as a look-alike appeared); the others are the cars themselves.
class CarsScreen extends StatefulWidget {
  const CarsScreen({super.key, required this.labeling, required this.taskId});

  final HarvestLabeling labeling;
  final String taskId;

  @override
  State<CarsScreen> createState() => _CarsScreenState();
}

class _CarsScreenState extends State<CarsScreen> {
  final FocusNode _focus = FocusNode(debugLabel: 'cars screen');

  CarList? _list;
  int _questions = 0; // "same car?" questions still open
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.labeling.cars(widget.taskId);
      var questions = 0;
      try {
        questions = (await widget.labeling.pairs(taskId: widget.taskId)).items.length;
      } catch (_) {
        // the questions are an extra: the cars still show
      }
      if (!mounted) return;
      setState(() {
        _list = list;
        _questions = questions;
      });
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(CarSummary car) async {
    final saved = await openCarViewer(context, labeling: widget.labeling, taskId: widget.taskId, car: car);
    if (saved == true && mounted) await _load();
    _focus.requestFocus();
  }

  Future<void> _openQuestions() async {
    await openPairLabeler(context, labeling: widget.labeling, taskId: widget.taskId);
    if (mounted) await _load();
    _focus.requestFocus();
  }

  /// The cars nobody opened are taken as right: one number, one car. Asks first: it files them all at once.
  Future<void> _fill() async {
    final open = _list?.counts.open ?? 0;
    if (open == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('File $open cars as one car each?'),
        content: const Text('The cars you did not open are taken as right: one number, one car.'),
        actions: [
          TextButton(key: const Key('cars-fill-cancel'), onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('cars-fill-ok'), onPressed: () => Navigator.of(dialog).pop(true), child: const Text('File them')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.labeling.fillCars(widget.taskId);
      if (mounted) await _load();
    } on HarvestLabelingException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
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
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(children: [
            _topBar(context),
            Expanded(child: _body(context)),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final counts = _list?.counts;
    final done = counts == null ? 0 : counts.checked + counts.split;
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            key: const Key('cars-close'),
            tooltip: 'Close (Esc)',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Icon(HarvestStyle.categoryIcon(harvestPairsKey), size: 20, color: HarvestStyle.categoryColor(harvestPairsKey)),
          const SizedBox(width: 8),
          const Text('Same car?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (counts != null && counts.open > 0)
            TextButton.icon(
              key: const Key('cars-fill'),
              onPressed: _fill,
              icon: const Icon(Icons.done_all, size: 18),
              label: Text('Rest are fine (${counts.open})'),
            ),
          if (counts != null && counts.total > 0)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text('$done of ${counts.total} checked', key: const Key('cars-progress'), style: const TextStyle(color: Colors.white70)),
            ),
        ]),
        if (counts != null && counts.total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: done / counts.total, minHeight: 3, color: _green, backgroundColor: Colors.white12),
          ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    final list = _list;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.items.isEmpty && _questions == 0) {
      return const Center(
        child: Text('No cars to check', key: Key('cars-empty'), style: TextStyle(color: Colors.white70, fontSize: 20)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          if (_questions > 0) _questionsCard(),
          for (final car in list.items) _carCard(list, car),
        ],
      ),
    );
  }

  Widget _questionsCard() {
    return _card(
      key: const Key('cars-questions'),
      onTap: _openQuestions,
      color: _orange,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.compare_arrows, size: 36, color: _orange),
        const SizedBox(height: 6),
        Text('$_questions', style: const TextStyle(color: _orange, fontSize: 40, fontWeight: FontWeight.bold)),
        const Text('Look-alikes', style: TextStyle(color: Colors.white70)),
      ]),
    );
  }

  Widget _carCard(CarList list, CarSummary car) {
    final color = switch (car.state) {
      CarState.open => Colors.white24,
      CarState.checked => _green,
      CarState.split => _orange,
    };
    return _card(
      key: Key('car-card-${car.uid}'),
      onTap: () => _open(car),
      color: color,
      child: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            Image(image: widget.labeling.carPhoto(list.evidenceDir, car.first, width: 320), fit: BoxFit.cover, gaplessPlayback: true),
            if (car.state != CarState.open)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  key: Key('car-state-${car.uid}'),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(car.state == CarState.checked ? Icons.check : Icons.call_split, size: 16, color: Colors.black87),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(children: [
            Text('Car ${car.track}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${car.photos}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 2),
            const Icon(Icons.photo_library_outlined, size: 12, color: Colors.white54),
          ]),
        ),
      ]),
    );
  }

  Widget _card({required Key key, required VoidCallback onTap, required Color color, required Widget child}) {
    return SizedBox(
      width: 168,
      height: 172,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF14161B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 2),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        ),
      ),
    );
  }
}
