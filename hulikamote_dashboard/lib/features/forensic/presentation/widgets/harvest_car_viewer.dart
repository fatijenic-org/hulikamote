import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/harvest_labeling.dart';
import '../../domain/harvest_labeling_models.dart';

/// Opens one car over the whole window: the big photo on top, every photo of that car in a flat strip below. Walk along
/// the strip and mark the photos that show a different car than the first one. Returns true when it was saved.
Future<bool?> openCarViewer(
  BuildContext context, {
  required HarvestLabeling labeling,
  required String taskId,
  required CarSummary car,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CarViewer(labeling: labeling, taskId: taskId, car: car),
    ),
  );
}

const _marked = Color(0xFFFF5252);
const _green = Color(0xFF4CC38A);

/// One ticketed car. The first photo is the original. [D] marks the photo on screen as a different car and moves on;
/// Enter saves: the photos you did not mark are one car, the marked ones another. Esc leaves without saving.
class CarViewer extends StatefulWidget {
  const CarViewer({super.key, required this.labeling, required this.taskId, required this.car});

  final HarvestLabeling labeling;
  final String taskId;
  final CarSummary car;

  @override
  State<CarViewer> createState() => _CarViewerState();
}

class _CarViewerState extends State<CarViewer> {
  static const _thumb = 64.0;
  static const _gap = 6.0;

  final FocusNode _focus = FocusNode(debugLabel: 'car viewer');
  final ScrollController _strip = ScrollController();

  CarDetail? _detail;
  String? _loadError;
  String? _error; // the save that failed
  bool _busy = false;
  int _i = 0;
  final Set<String> _different = {};

  List<String> get _photos => _detail?.photos ?? const [];
  String? get _current => _i >= 0 && _i < _photos.length ? _photos[_i] : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    _strip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _detail = null;
    });
    try {
      final d = await widget.labeling.car(widget.taskId, widget.car.uid);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _i = 0;
        _different
          ..clear()
          ..addAll(d.marked);
      });
    } on HarvestLabelingException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  void _go(int step) {
    if (_detail == null) return;
    setState(() => _i = (_i + step).clamp(0, _photos.length - 1));
    _follow();
  }

  void _pick(int i) {
    setState(() => _i = i);
    _focus.requestFocus();
  }

  /// Keeps the photo on screen in the middle of the strip.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_strip.hasClients) return;
      final target = _i * (_thumb + _gap) - _strip.position.viewportDimension / 2 + _thumb / 2;
      _strip.animateTo(target.clamp(0.0, _strip.position.maxScrollExtent), duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    });
  }

  /// This photo shows a different car than the original; then on to the next one.
  void _toggleDifferent() {
    final photo = _current;
    if (photo == null || _i == 0 || _busy) return; // the first photo IS the original
    setState(() {
      if (!_different.remove(photo)) _different.add(photo);
    });
    if (_i < _photos.length - 1) _go(1);
  }

  Future<void> _done() async {
    final d = _detail;
    if (d == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.labeling.checkCar(widget.taskId, widget.car.uid, [for (final p in d.photos) if (_different.contains(p)) p]);
      if (mounted) Navigator.of(context).pop(true);
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
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
    } else if (key == LogicalKeyboardKey.keyD) {
      _toggleDifferent();
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _done();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
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
            if (_detail != null) ...[_stripBar(context), _controls(context)],
          ]),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
      child: Row(children: [
        IconButton(
          key: const Key('car-close'),
          tooltip: 'Back without saving (Esc)',
          color: Colors.white,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        Text('Car ${widget.car.track}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (_different.isNotEmpty)
          Container(
            key: const Key('car-marked-count'),
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: _marked.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: Text('${_different.length} different', style: const TextStyle(color: _marked, fontSize: 13)),
          ),
        if (_detail != null)
          Text('${_i + 1} of ${_photos.length}', key: const Key('car-progress'), style: const TextStyle(color: Colors.white70)),
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
    final d = _detail;
    final photo = _current;
    if (d == null || photo == null) return const Center(child: CircularProgressIndicator());
    final isDifferent = _different.contains(photo);
    return Stack(children: [
      Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            key: const Key('car-big'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDifferent ? _marked : Colors.transparent, width: 4),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image(
              image: widget.labeling.carPhoto(d.evidenceDir, photo),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38)),
            ),
          ),
        ),
      ),
      if (_i > 0)
        Positioned(
          left: 24,
          top: 24,
          child: Container(
            key: const Key('car-original'),
            width: 112,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 104,
                width: 112,
                child: Image(image: widget.labeling.carPhoto(d.evidenceDir, d.photos.first, width: 240), fit: BoxFit.cover),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: Text('Original', style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      Positioned(
        top: 24,
        left: 0,
        right: 0,
        child: Center(
          child: _i == 0
              ? _badge('car-original-badge', 'This is the original', _green)
              : (isDifferent ? _badge('car-marked-badge', 'Different car', _marked) : const SizedBox.shrink()),
        ),
      ),
    ]);
  }

  Widget _badge(String key, String text, Color color) {
    return Container(
      key: Key(key),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
    );
  }

  Widget _stripBar(BuildContext context) {
    final d = _detail!;
    return Container(
      color: const Color(0xFF14161B),
      height: 92,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.separated(
        key: const Key('car-strip'),
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: d.photos.length,
        separatorBuilder: (context, i) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final photo = d.photos[i];
          final selected = i == _i;
          final different = _different.contains(photo);
          return GestureDetector(
            key: Key('car-thumb-$i'),
            onTap: () => _pick(i),
            child: Container(
              width: _thumb,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: different ? _marked : (selected ? Colors.white : (i == 0 ? _green : Colors.white24)), width: selected || different ? 3 : 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                Image(image: widget.labeling.carPhoto(d.evidenceDir, photo, width: 160), fit: BoxFit.cover, gaplessPlayback: true),
                if (different) Container(color: _marked.withValues(alpha: 0.25)),
                Positioned(
                  left: 3,
                  bottom: 2,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3)])),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final photo = _current;
    final isDifferent = photo != null && _different.contains(photo);
    final original = _i == 0;
    return Container(
      color: const Color(0xFF14161B),
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, key: const Key('car-error'), style: const TextStyle(color: Color(0xFFFF8A80))),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            IconButton(
              key: const Key('car-prev'),
              tooltip: 'Previous (←)',
              color: Colors.white70,
              onPressed: _i > 0 ? () => _go(-1) : null,
              icon: const Icon(Icons.chevron_left, size: 32),
            ),
            OutlinedButton.icon(
              key: const Key('car-different'),
              onPressed: (original || _busy) ? null : _toggleDifferent,
              icon: Icon(isDifferent ? Icons.undo : Icons.block, size: 20),
              label: Text(original ? 'Original' : (isDifferent ? 'Not different  (D)' : 'Different car  (D)')),
              style: OutlinedButton.styleFrom(
                foregroundColor: _marked,
                side: BorderSide(color: original ? Colors.white24 : _marked),
                minimumSize: const Size(0, 48),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              key: const Key('car-next'),
              tooltip: 'Next (→)',
              color: Colors.white70,
              onPressed: _i < _photos.length - 1 ? () => _go(1) : null,
              icon: const Icon(Icons.chevron_right, size: 32),
            ),
            const SizedBox(width: 24),
            FilledButton.icon(
              key: const Key('car-done'),
              onPressed: _busy ? null : _done,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Done  (Enter)'),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
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
