import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/harvest_labeling.dart';
import '../../domain/harvest_labeling_models.dart';
import 'harvest_parts.dart';

/// Opens the "same car?" questions over the whole window (sidebar included): two pictures, one answer, next.
Future<void> openPairLabeler(BuildContext context, {required HarvestLabeling labeling, String? taskId}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PairLabeler(labeling: labeling, taskId: taskId),
    ),
  );
}

/// Two cars from one analysis. The tracker may have split one car in two (it got a new number), or these may be two
/// cars that merely look alike. Enter = the same car, N = different cars, S = not sure. The answer teaches the car matcher.
class PairLabeler extends StatefulWidget {
  const PairLabeler({super.key, required this.labeling, this.taskId});

  final HarvestLabeling labeling;

  /// Only the questions of this analysis; null = every analysis.
  final String? taskId;

  @override
  State<PairLabeler> createState() => _PairLabelerState();
}

class _PairLabelerState extends State<PairLabeler> {
  final FocusNode _focus = FocusNode(debugLabel: 'pair labeler');

  PairQueue? _queue;
  String? _loadError;
  String? _error; // the last answer that failed
  bool _busy = false;
  int _i = 0;

  List<PairItem> get _items => _queue?.items ?? const [];
  PairItem? get _item => _i >= 0 && _i < _items.length ? _items[_i] : null;
  bool get _finished => _queue != null && _i >= _items.length;

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
    setState(() {
      _loadError = null;
      _queue = null;
    });
    try {
      final q = await widget.labeling.pairs(taskId: widget.taskId);
      if (!mounted) return;
      setState(() {
        _queue = q;
        _i = 0;
        _error = null;
      });
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  Future<void> _answer(PairAnswer answer) async {
    final item = _item;
    if (item == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.labeling.answerPair(item.id, answer);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _i++;
      });
      _focus.requestFocus();
    } on HarvestLabelingException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _answer(PairAnswer.same);
    } else if (key == LogicalKeyboardKey.keyN) {
      _answer(PairAnswer.different);
    } else if (key == LogicalKeyboardKey.keyS) {
      _answer(PairAnswer.notSure);
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
            if (_item != null) _bottomBar(context),
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final total = _items.length;
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            key: const Key('labeler-close'),
            tooltip: 'Close (Esc)',
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Icon(HarvestStyle.categoryIcon(harvestPairsKey), size: 20, color: HarvestStyle.categoryColor(harvestPairsKey)),
          const SizedBox(width: 8),
          const Text('Same car?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_queue != null && total > 0)
            Text(_finished ? '$total of $total' : '${_i + 1} of $total',
                key: const Key('labeler-progress'), style: const TextStyle(color: Colors.white70)),
        ]),
        if (_queue != null && total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (_i.clamp(0, total)) / total,
              minHeight: 3,
              color: const Color(0xFF4CC38A),
              backgroundColor: Colors.white12,
            ),
          ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }
    if (_queue == null) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty || _finished) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 72, color: Color(0xFF4CC38A)),
          const SizedBox(height: 16),
          Text(_items.isEmpty ? 'Nothing to check' : 'All done',
              key: const Key('labeler-done'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          FilledButton(key: const Key('labeler-finish'), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ]),
      );
    }
    final item = _item!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Expanded(
          child: Row(children: [
            Expanded(child: _picture(item, 'a')),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.help_outline, size: 40, color: Colors.white38),
            ),
            Expanded(child: _picture(item, 'b')),
          ]),
        ),
        const SizedBox(height: 10),
        Text(item.together ? 'On screen at the same time' : 'One after the other',
            key: const Key('pair-kind'), style: const TextStyle(color: Colors.white54, fontSize: 14)),
      ]),
    );
  }

  Widget _picture(PairItem item, String side) {
    return Container(
      key: Key('pair-$side'),
      decoration: BoxDecoration(
        color: const Color(0xFF14161B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: widget.labeling.pairImage(item.id, side),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38)),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, key: const Key('labeler-error'), style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 12,
          children: [
            TextButton(
              key: const Key('pair-not-sure'),
              onPressed: _busy ? null : () => _answer(PairAnswer.notSure),
              child: const Text('Not sure  (S)'),
            ),
            OutlinedButton(
              key: const Key('pair-different'),
              onPressed: _busy ? null : () => _answer(PairAnswer.different),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), textStyle: const TextStyle(fontSize: 16)),
              child: const Text('Different cars  (N)'),
            ),
            FilledButton.icon(
              key: const Key('pair-same'),
              onPressed: _busy ? null : () => _answer(PairAnswer.same),
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Same car  (Enter)'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4CC38A),
                foregroundColor: Colors.black87,
                minimumSize: const Size(0, 48),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
