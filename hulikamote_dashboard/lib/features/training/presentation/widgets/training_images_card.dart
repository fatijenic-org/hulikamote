import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../forensic/data/harvest_source.dart';
import '../../../forensic/domain/harvest_models.dart';
import '../../../forensic/domain/violation_catalog.dart';
import '../../../forensic/presentation/widgets/fx.dart';
import '../../../forensic/presentation/widgets/harvest_parts.dart';
import '../../data/dataset_browser.dart';

/// One picture to show: how to load it, what to draw on it, and its short story.
class PictureRef {
  const PictureRef({
    required this.id,
    required this.image,
    required this.title,
    this.detail = '',
    this.dot,
    this.boxes,
    this.loadBoxes,
    this.aspect,
    this.loadText,
  });

  final String id;
  final ImageProvider Function(int? width) image;
  final String title; // short: the file name, or why the picture is there
  final String detail; // one line: where it came from
  final Color? dot; // split or state colour
  final List<HarvestBox>? boxes; // known now (harvested pictures) ...
  final Future<List<HarvestBox>> Function()? loadBoxes; // ... or read from the label file when shown
  final double? aspect;
  final Future<String?> Function()? loadText; // plate text drawn on the picture
}

/// width / height of a picture, once it has been decoded.
Future<double> imageAspect(ImageProvider provider) {
  final done = Completer<double>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.width / info.image.height);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!done.isCompleted) done.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// A picture with its boxes, its colour dot and (for plate crops) its text. Used small in the grid and large in the viewer.
class _Pic extends StatefulWidget {
  const _Pic({super.key, required this.ref, this.decodeWidth, this.stroke = 2});

  final PictureRef ref;
  final int? decodeWidth;
  final double stroke;

  @override
  State<_Pic> createState() => _PicState();
}

class _PicState extends State<_Pic> {
  double? _aspect;
  List<HarvestBox> _boxes = const [];
  String? _text;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Pic old) {
    super.didUpdateWidget(old);
    if (old.ref.id != widget.ref.id) {
      _aspect = null;
      _boxes = const [];
      _text = null;
      _load();
    }
  }

  Future<void> _load() async {
    final ref = widget.ref;
    _aspect = ref.aspect;
    _boxes = ref.boxes ?? const [];
    try {
      if (ref.boxes == null && ref.loadBoxes != null) {
        final b = await ref.loadBoxes!();
        if (!mounted || ref.id != widget.ref.id) return;
        setState(() => _boxes = b);
      }
      if (ref.loadText != null) {
        final t = await ref.loadText!();
        if (!mounted || ref.id != widget.ref.id) return;
        setState(() => _text = t);
      }
      if (_aspect == null && _boxes.isNotEmpty) {
        final a = await imageAspect(ref.image(widget.decodeWidth));
        if (!mounted || ref.id != widget.ref.id) return;
        setState(() => _aspect = a);
      }
    } catch (_) {
      // a picture that cannot be read shows the placeholder of FxImage; nothing else to do
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.ref;
    return Stack(fit: StackFit.expand, children: [
      PictureWithBoxes(
        image: ref.image(widget.decodeWidth),
        aspect: _aspect ?? 4 / 3,
        boxes: _aspect == null ? const [] : _boxes,
        stroke: widget.stroke,
      ),
      if (ref.dot != null)
        Positioned(
          top: 4,
          left: 4,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: ref.dot, shape: BoxShape.circle, border: Border.all(color: Colors.black54)),
          ),
        ),
      if (_text != null && _text!.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(_text!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Fx.plate.copyWith(color: Colors.white, fontSize: 12)),
          ),
        ),
    ]);
  }
}

/// A picture of the grid, enlarged: arrows or keys move through the grid, Esc closes. One caption line.
class _Viewer extends StatefulWidget {
  const _Viewer({required this.refs, required this.start});

  final List<PictureRef> refs;
  final int start;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _i = widget.start;
  final FocusNode _focus = FocusNode(debugLabel: 'picture viewer');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _i = (_i + step).clamp(0, widget.refs.length - 1));
    _focus.requestFocus(); // a button that just turned off (the first / last picture) must not take the keys with it
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.refs[_i];
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _go(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _go(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 720),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: _Pic(key: ValueKey('big-${ref.id}'), ref: ref, decodeWidth: 1400, stroke: 3)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                      child: Text('${_i + 1} / ${widget.refs.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const Key('viewer-close'),
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      key: const Key('viewer-prev'),
                      onPressed: _i > 0 ? () => _go(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filledTonal(
                      key: const Key('viewer-next'),
                      onPressed: _i < widget.refs.length - 1 ? () => _go(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                if (ref.dot != null) ...[
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: ref.dot, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(ref.title, key: const Key('viewer-title'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (ref.detail.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(child: Text(ref.detail, key: const Key('viewer-detail'), overflow: TextOverflow.ellipsis, style: Fx.caption(context))),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The Training Studio's pictures of one model, shown two ways side by side: the ORIGINAL dataset and what the
/// HARVEST collected. Pick one, filter it by a colour chip, look at the pictures (boxes drawn), click one to enlarge.
class TrainingImagesCard extends StatefulWidget {
  const TrainingImagesCard({super.key, required this.modelKey, this.harvest, this.datasets, this.onOpenHarvest});

  /// The Studio's model key: `plate_specialist`, `helmet_specialist`, `cabin_specialist`, `plate_ocr`, `reid`...
  final String modelKey;

  /// Injected by tests; the app reads the Training Lab on disk.
  final HarvestSource? harvest;
  final DatasetBrowser? datasets;
  final VoidCallback? onOpenHarvest;

  @override
  State<TrainingImagesCard> createState() => _TrainingImagesCardState();
}

class _TrainingImagesCardState extends State<TrainingImagesCard> {
  late final HarvestSource _harvest = widget.harvest ?? LocalHarvestSource();
  late final DatasetBrowser _datasets =
      widget.datasets ?? LocalDatasetBrowser(lab: _harvest is LocalHarvestSource ? _harvest : null);

  static const _page = 40;
  static const _thumbW = 132.0, _thumbH = 99.0;

  DatasetListing? _listing;
  HarvestCategory? _cat;
  String? _error;
  bool _loading = true;
  bool _updating = false;

  int _tab = 0; // 0 original, 1 harvested
  String? _split;
  String? _source;
  HarvestState? _state;
  int _shown = _page;
  int _seed = 0;
  List<(String, String)> _order = const []; // original pictures after the filters, in a shuffled order
  List<(String, String)> _spread = const []; // four pictures spread over the whole original dataset (the tile)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _datasets.list(widget.modelKey, refresh: refresh);
      final gallery = await _harvest.load();
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _cat = gallery?.byKey(widget.modelKey);
        if (listing == null && (_cat?.pictures ?? 0) > 0) _tab = 1;
        _spread = listing == null ? const [] : _spreadOf(listing);
        _reorder();
      });
    } on HarvestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update() async {
    setState(() => _updating = true);
    final problem = await _harvest.rebuild();
    if (!mounted) return;
    setState(() => _updating = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
    await _load(refresh: true);
  }

  /// Up to four pictures evenly spread over the dataset, so a tile shows variety and not just the first source.
  static List<(String, String)> _spreadOf(DatasetListing l) {
    final total = l.total;
    if (total == 0) return const [];
    final n = min(4, total);
    final out = <(String, String)>[];
    for (var i = 0; i < n; i++) {
      var index = (i * total) ~/ n;
      for (final e in l.bySplit.entries) {
        if (index < e.value.length) {
          out.add((e.key, e.value[index]));
          break;
        }
        index -= e.value.length;
      }
    }
    return out;
  }

  void _reorder() {
    final l = _listing;
    if (l == null) {
      _order = const [];
      return;
    }
    final all = <(String, String)>[
      for (final e in l.bySplit.entries)
        if (_split == null || e.key == _split)
          for (final n in e.value)
            if (_source == null || DatasetListing.sourceOf(n) == _source) (e.key, n),
    ];
    all.shuffle(Random(_seed * 7919 + 13));
    _order = all;
  }

  Color _splitColor(String split) => switch (split) {
        'train' => Fx.accent,
        'val' => Fx.warning,
        'test' => const Color(0xFFB388FF),
        _ => const Color(0xFF9AA5B1),
      };

  // ── pictures ──
  PictureRef _originalRef(String split, String name) => PictureRef(
        id: '$split/$name',
        image: (w) => _datasets.image(widget.modelKey, split, name, width: w),
        title: name.split('/').last,
        detail: '${DatasetListing.sourceOf(name)} · $split',
        dot: _splitColor(split),
        loadBoxes: () => _datasets.boxes(widget.modelKey, split, name),
        loadText: () => _datasets.text(widget.modelKey, split, name),
      );

  List<PictureRef> _harvestRefs() {
    final cat = _cat;
    if (cat == null) return const [];
    if (cat.isDetector) {
      final names = {for (final s in cat.sources) s.key: s.label};
      return [
        for (final item in cat.items)
          if (_state == null || item.state == _state)
            PictureRef(
              id: item.id,
              image: (w) => _harvest.inboxImage(item.image, width: w),
              title: item.why.isNotEmpty ? item.why : item.reason,
              detail: [
                names[item.source] ?? item.source,
                if (item.violation != null && item.violation!.isNotEmpty) ViolationCatalog.of(item.violation!).label,
                if (item.task != null && item.task!.isNotEmpty) 'analysis ${_short(item.task!)}',
                if (item.ticket != null && item.ticket!.isNotEmpty) 'ticket ${_short(item.ticket!)}',
                item.state.title,
              ].where((s) => s.isNotEmpty).join(' · '),
              dot: HarvestStyle.state(item.state),
              boxes: item.boxes,
              aspect: item.aspect,
            ),
      ];
    }
    return [
      for (final s in cat.samples)
        PictureRef(
          id: s.path,
          image: (w) => _harvest.labImage(s.path, width: w),
          title: s.label,
          detail: 'Typed correction · ${agoText(s.when, DateTime.now())}',
          loadText: () async => s.label,
        ),
      for (final g in cat.groups)
        for (final p in g.photos)
          PictureRef(id: p, image: (w) => _harvest.labImage(p, width: w), title: 'Car ${g.id}', detail: '${g.n} photos of this car'),
    ];
  }

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

  /// Up to four pictures to show on a tile (spread over the whole dataset).
  List<PictureRef> _mosaic(int which) {
    if (which == 0) return [for (final p in _spread) _originalRef(p.$1, p.$2)];
    return _harvestRefs().take(4).toList();
  }

  void _open(List<PictureRef> refs, int index) {
    showDialog<void>(context: context, builder: (_) => _Viewer(refs: refs, start: index));
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(),
          const SizedBox(height: 12),
          if (_loading && _listing == null && _cat == null)
            const LinearProgressIndicator()
          else if (_error != null)
            Row(children: [
              Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ])
          else ...[
            Row(children: [
              Expanded(child: _tile(0)),
              const SizedBox(width: 12),
              Expanded(child: _tile(1)),
            ]),
            const SizedBox(height: 12),
            ..._body(),
          ],
        ]),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      const Icon(Icons.collections_outlined, size: 20),
      const SizedBox(width: 8),
      const Text('Training pictures', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const Spacer(),
      if (_tab == 0 && _order.length > 1)
        IconButton(
          key: const Key('shuffle'),
          tooltip: 'Show other pictures',
          icon: const Icon(Icons.shuffle, size: 20),
          onPressed: () => setState(() {
            _seed++;
            _shown = _page;
            _reorder();
          }),
        ),
      if (_updating)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else
        IconButton(
          key: const Key('pictures-update'),
          tooltip: 'Update (re-reads the folders and rebuilds the harvest snapshot)',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _loading ? null : _update,
        ),
      if (widget.onOpenHarvest != null)
        TextButton.icon(
          key: const Key('open-harvest'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Harvest tab'),
          onPressed: widget.onOpenHarvest,
        ),
    ]);
  }

  Widget _tile(int which) {
    final original = which == 0;
    final total = original ? (_listing?.total ?? 0) : (_cat?.pictures ?? 0);
    final selected = _tab == which;
    final pics = _mosaic(which);
    final enabled = total > 0;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? Fx.accent.withValues(alpha: 0.10) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Fx.radius),
          side: BorderSide(color: selected ? Fx.accent : Fx.border(context), width: selected ? 2 : 1),
        ),
        child: InkWell(
          key: Key(original ? 'tile-original' : 'tile-harvested'),
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Fx.radius)),
          onTap: enabled
              ? () => setState(() {
                    _tab = which;
                    _shown = _page;
                  })
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              SizedBox(
                width: 136,
                height: 92,
                child: pics.isEmpty
                    ? Center(child: Icon(original ? Icons.photo_library_outlined : Icons.inbox_outlined, size: 32, color: Fx.muted(context)))
                    : GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        childAspectRatio: 1.5,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final p in pics)
                            ClipRRect(borderRadius: BorderRadius.circular(3), child: Image(image: p.image(120), fit: BoxFit.cover)),
                        ],
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(grouped(total), key: Key(original ? 'count-original' : 'count-harvested'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  Text(original ? 'ORIGINAL' : 'HARVESTED', style: Fx.label(context)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _chip({required String label, Color? color, required bool selected, required VoidCallback onTap, Key? key}) {
    return FilterChip(
      key: key,
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: color == null ? null : Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }

  List<Widget> _body() {
    final original = _tab == 0;
    final List<PictureRef> refs;
    final List<Widget> chips;
    int total;
    if (original) {
      final l = _listing;
      if (l == null) return [Text('No original pictures found for this model.', style: Fx.caption(context))];
      chips = [
        if (l.bySplit.length > 1)
          for (final e in l.bySplit.entries)
            _chip(
              key: Key('split-${e.key}'),
              label: '${e.key}  ${grouped(e.value.length)}',
              color: _splitColor(e.key),
              selected: _split == e.key,
              onTap: () => setState(() {
                _split = _split == e.key ? null : e.key;
                _shown = _page;
                _reorder();
              }),
            ),
        for (final s in l.sources.take(12))
          _chip(
            key: Key('source-${s.key}'),
            label: '${s.key}  ${grouped(s.value)}',
            selected: _source == s.key,
            onTap: () => setState(() {
              _source = _source == s.key ? null : s.key;
              _shown = _page;
              _reorder();
            }),
          ),
      ];
      total = _order.length;
      refs = [for (final e in _order.take(_shown)) _originalRef(e.$1, e.$2)];
    } else {
      final cat = _cat;
      if (cat == null) return [Text('The harvest does not feed this model.', style: Fx.caption(context))];
      chips = [
        if (cat.isDetector)
          for (final s in HarvestState.values)
            if (cat.counts.of(s) > 0)
              _chip(
                key: Key('state-${s.name}'),
                label: '${HarvestStyle.stateShort(s)}  ${grouped(cat.counts.of(s))}',
                color: HarvestStyle.state(s),
                selected: _state == s,
                onTap: () => setState(() {
                  _state = _state == s ? null : s;
                  _shown = _page;
                }),
              ),
      ];
      final all = _harvestRefs();
      total = all.length;
      refs = all.take(_shown).toList();
    }
    return [
      if (chips.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: chips),
      const SizedBox(height: 12),
      if (refs.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('Nothing here with this filter.', style: Fx.caption(context))))
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < refs.length; i++)
            Tooltip(
              message: '${refs[i].title}\n${refs[i].detail}',
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                key: Key('pic-$i'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => _open(refs, i),
                child: SizedBox(
                  width: _thumbW,
                  height: _thumbH,
                  child: ClipRRect(borderRadius: BorderRadius.circular(6), child: _Pic(key: ValueKey('${original ? 'o' : 'h'}-${refs[i].id}'), ref: refs[i], decodeWidth: 260)),
                ),
              ),
            ),
        ]),
      if (total > refs.length)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            OutlinedButton.icon(
              key: const Key('show-more'),
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text('Show more  (${refs.length} of ${grouped(total)})'),
              onPressed: () => setState(() => _shown += _page),
            ),
          ]),
        ),
    ];
  }
}
