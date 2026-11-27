import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../forensic/domain/violation_catalog.dart';

/// The label of a stretch with nothing illegal in it (benchmark labelling).
const cleanLabel = 'clean';

/// Extra seconds of normal traffic to keep before and after a violation, by what the rule needs (see benchmarks/CLIP_CHECKLIST.md):
/// a model check or a quick zone rule needs little; a rule that must watch a vehicle stand, turn or hold a heading needs more;
/// swerving judges a 6 s window, so it needs the most. A label that is not listed gets [defaultPad].
const defaultPad = 3;
const recommendedPads = <String, int>{
  'no_helmet': 3, 'overloading': 3, 'no_plate': 3, 'no_seatbelt': 3, 'distracted_driving': 3, 'missing_side_mirror': 3,
  'passenger_outside': 3, 'restricted_lane': 3, 'truck_ban': 3, 'tricycle_on_highway': 3, 'sidewalk_driving': 3, 'pedestrian_lane': 3,
  'counterflow': 5, 'illegal_parking': 5, 'illegal_loading': 5, 'double_parking': 5, 'blocking_intersection': 5, 'crossing_solid_line': 5,
  'illegal_turn': 5, 'illegal_u_turn': 5, 'red_light': 5, 'signal_light': 5, 'disregarding_signs': 5, 'overtaking_on_right': 5,
  'swerving': 8,
};

/// The rules a motorcycle or tricycle can break: only for these does the "incoming motorcycles and tricycles" demo switch matter.
const twoWheelerRules = {'no_helmet', 'overloading', 'missing_side_mirror', 'tricycle_on_highway'};

/// The recommended extra seconds for one label.
int padOfLabel(String key) => recommendedPads[key] ?? defaultPad;

/// One piece to cut out of the video. A locked clip cannot be moved, resized, renamed or deleted until it is unlocked.
class TrimClip {
  TrimClip({required this.id, required this.start, required this.end, this.label = '', this.locked = false});

  final int id;
  double start;
  double end;
  String label;
  bool locked;

  /// Benchmark labelling: the violations that really happen in this slice (violation keys), or [cleanLabel].
  final Set<String> labels = {};

  /// A clean slice: the violations it is clean for (nothing on it breaks THESE rules). Empty = the common ones.
  final Set<String> cleanFor = {};

  /// How many vehicles break the rule in this slice (each is one event: a ticket catches one event only).
  int count = 1;

  /// The true plate of the vehicle in this slice (typed by the person), for the plate scores. Empty = not readable.
  String plate = '';

  /// Already cut into the benchmark folder: not cut again (it still counts as an event next to other slices).
  bool exported = false;

  double get length => end - start;
}

/// One open video and the clips marked on it. Everything the timeline, the clip list and the export buttons do to the
/// clips goes through here, so the rules (clip stays inside the video, never shorter than [minLength], locked = untouched)
/// live in one place.
class TrimSession extends ChangeNotifier {
  TrimSession({required this.path, this.duration = 0, this.fps = 25});

  static const minLength = 0.5;
  static const defaultLength = 10.0;

  final String path;

  /// Seconds. 0 until the player or the backend has said how long the video is.
  double duration;
  double fps;

  final List<TrimClip> clips = [];
  final Set<int> selected = {};

  /// Where the playhead was when this video was last on screen.
  double position = 0;

  int _nextId = 1;

  String get name => path.split(RegExp(r'[\\/]')).last;

  /// The length is known, so clips can be made.
  bool get ready => duration > 0;

  /// Whoever learns the length first (the player or the backend) tells the session; a later answer only adds what is new.
  void setInfo({double? duration, double? fps}) {
    if (duration != null && duration > 0 && !ready) this.duration = duration;
    if (fps != null && fps > 0) this.fps = fps;
    notifyListeners();
  }

  TrimClip? clipById(int id) {
    for (final c in clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// "Clip 3" when the person gave it no name; a labelled slice shows its labels.
  String titleOf(TrimClip c) {
    if (c.label.trim().isNotEmpty) return c.label.trim();
    if (c.labels.isNotEmpty) return labelText(c);
    return 'Clip ${clips.indexOf(c) + 1}';
  }

  /// "No helmet + Counterflow", or "Clean".
  String labelText(TrimClip c) => [for (final k in c.labels) k == cleanLabel ? 'Clean' : ViolationCatalog.of(k).label].join(' + ');

  // ── saving ──

  /// The slices as plain data (for the file that keeps them across restarts).
  List<Map<String, dynamic>> toJson() => [
        for (final c in clips)
          {
            'start': c.start,
            'end': c.end,
            'label': c.label,
            'labels': c.labels.toList(),
            'clean_for': c.cleanFor.toList(),
            'plate': c.plate,
            'count': c.count,
            'locked': c.locked,
            'exported': c.exported,
          },
      ];

  /// Puts saved slices back (no undo step: this is not an edit). Slices that do not fit are skipped.
  void restore(List<Map<String, dynamic>> saved) {
    for (final s in saved) {
      final start = (s['start'] as num?)?.toDouble(), end = (s['end'] as num?)?.toDouble();
      if (start == null || end == null || end - start < 0.1) continue;
      final c = TrimClip(
        id: _nextId++,
        start: start,
        end: end,
        label: '${s['label'] ?? ''}',
        locked: s['locked'] == true,
      );
      c.labels.addAll([for (final k in (s['labels'] as List? ?? const [])) '$k']);
      c.cleanFor.addAll([for (final k in (s['clean_for'] as List? ?? const [])) '$k']);
      c.plate = '${s['plate'] ?? ''}';
      c.count = ((s['count'] as num?)?.toInt() ?? 1).clamp(1, 50);
      c.exported = s['exported'] == true;
      clips.add(c);
    }
    notifyListeners();
  }

  // ── undo / redo ──

  /// Every change to the clips (make, move, trim, rename, label, lock, delete) first saves how the clips were. A drag makes many small
  /// changes: those within [_mergeWithin] of each other, on the same clip, count as ONE step.
  static const _maxHistory = 200;
  static const _mergeWithin = Duration(milliseconds: 800);
  final List<List<_ClipState>> _undo = [];
  final List<List<_ClipState>> _redo = [];
  String? _lastKind;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<_ClipState> _snapshot() => [for (final c in clips) _ClipState(c)];

  /// Call BEFORE changing the clips. [kind] says what is changing, so a drag is one step.
  void _record(String kind) {
    final now = DateTime.now();
    final merge = kind == _lastKind && now.difference(_lastAt) < _mergeWithin;
    _lastKind = kind;
    _lastAt = now;
    if (merge) return;
    _undo.add(_snapshot());
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(List<_ClipState> state) {
    final exported = {for (final c in clips) if (c.exported) c.id};     // a clip that was cut stays cut, whatever is undone
    clips
      ..clear()
      ..addAll([for (final s in state) s.toClip(exported.contains(s.id))]);
    selected.removeWhere((id) => clipById(id) == null);
    _lastKind = null;
    notifyListeners();
  }

  /// Takes back the last change. False when there is nothing to take back.
  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    return true;
  }

  /// Tells the screens something changed that the session itself did not do (the controller marks slices exported).
  void refresh() => notifyListeners();

  // ── benchmark labels ──

  /// Where "[" was pressed: "]" then makes a slice from there to the playhead.
  double? markIn;

  /// How many vehicles are in the slice (1 to 50).
  bool setCount(int id, int n) {
    final c = clipById(id);
    if (c == null || c.locked || c.exported) return false;
    final v = n.clamp(1, 50);
    if (v == c.count) return true;
    _record('count$id');
    c.count = v;
    notifyListeners();
    return true;
  }

  /// Types the true plate of the vehicle of a slice (capitals, no spaces at the ends).
  bool setPlate(int id, String text) {
    final c = clipById(id);
    if (c == null || c.locked || c.exported) return false;
    final clean = text.trim().toUpperCase();
    if (clean == c.plate) return true;
    _record('plate$id');
    c.plate = clean;
    notifyListeners();
    return true;
  }

  /// Picks [key] as the label of every selected slice (picking it again takes it off). ONE violation per slice: the new label replaces the
  /// old one, so a clip never holds two violations. Returns how many slices changed.
  int toggleLabel(String key) {
    final targets = selectedClips.where((c) => !c.locked && !c.exported).toList();
    if (targets.isEmpty) return 0;
    final allHave = targets.every((c) => c.labels.length == 1 && c.labels.contains(key));
    _record('label');
    for (final c in targets) {
      c.labels.clear();
      if (!allHave) c.labels.add(key);
      if (key != cleanLabel || allHave) c.cleanFor.clear();       // "clean for ..." only belongs to a clean slice
    }
    notifyListeners();
    return targets.length;
  }

  /// A clean slice is clean for these violations only (switches [key] on or off for every selected clean slice).
  int toggleCleanFor(String key) {
    final targets = selectedClips.where((c) => !c.locked && !c.exported && c.labels.contains(cleanLabel)).toList();
    if (targets.isEmpty) return 0;
    final allHave = targets.every((c) => c.cleanFor.contains(key));
    _record('cleanfor');
    for (final c in targets) {
      allHave ? c.cleanFor.remove(key) : c.cleanFor.add(key);
    }
    notifyListeners();
    return targets.length;
  }

  /// The slices still to export carry a label that passes [test] (a setting that only matters for it can show).
  bool pendingHas(bool Function(String key) test) => toExport.any((c) => c.labels.any(test));

  /// The recommended extra seconds for a slice: the longest of its labels (a slice with several violations needs the most demanding one).
  /// Zero for a clean slice: nothing is added around it.
  int recommendedPad(TrimClip c) {
    final pads = [for (final k in c.labels) if (k != cleanLabel) padOfLabel(k)];
    return pads.isEmpty ? 0 : pads.reduce((a, b) => a > b ? a : b);
  }

  List<TrimClip> get labelled => [for (final c in clips) if (c.labels.isNotEmpty) c];
  List<TrimClip> get toExport => [for (final c in clips) if (c.labels.isNotEmpty && !c.exported) c];

  List<TrimClip> get selectedClips => [for (final c in clips) if (selected.contains(c.id)) c];
  bool get hasLocked => clips.any((c) => c.locked);

  // ── making clips ──

  /// A new clip between two times (either order). It stays inside the video and is at least [minLength] long.
  TrimClip addClip(double a, double b) {
    var start = math.max(0.0, math.min(a, b)), end = math.min(duration, math.max(a, b));
    if (end - start < minLength) {
      end = math.min(duration, start + minLength);
      start = math.max(0.0, end - minLength);
    }
    _record('add');
    final clip = TrimClip(id: _nextId++, start: start, end: end);
    clips.add(clip);
    selected
      ..clear()
      ..add(clip.id);
    notifyListeners();
    return clip;
  }

  /// A clip of [length] seconds starting at the playhead (shifted back if it would run past the end).
  TrimClip addAtPlayhead({double length = defaultLength}) {
    final end = math.min(duration, position + length);
    return addClip(math.max(0.0, end - length), end);
  }

  // ── editing ──

  /// Each returns false when nothing changed (locked, unknown clip, or the value does not fit).
  bool setStart(int id, double t) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    _record('edit$id');
    c.start = t.clamp(0.0, math.max(0.0, c.end - minLength));
    notifyListeners();
    return true;
  }

  bool setEnd(int id, double t) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    _record('edit$id');
    c.end = t.clamp(math.min(duration, c.start + minLength), duration);
    notifyListeners();
    return true;
  }

  /// Slide the whole clip so it starts at [newStart], keeping its length.
  bool moveClip(int id, double newStart) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    _record('edit$id');
    final length = c.length;
    c.start = newStart.clamp(0.0, math.max(0.0, duration - length));
    c.end = c.start + length;
    notifyListeners();
    return true;
  }

  /// Typed-in times. False (and nothing changes) when the clip is locked or the range does not fit the video.
  bool setRange(int id, double start, double end) {
    final c = clipById(id);
    if (c == null || c.locked || start < 0 || end > duration + 0.001 || end - start < minLength) return false;
    _record('edit$id');
    c.start = start;
    c.end = math.min(end, duration);
    notifyListeners();
    return true;
  }

  bool rename(int id, String label) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    _record('rename$id');
    c.label = label.trim();
    notifyListeners();
    return true;
  }

  // ── selecting, locking, deleting ──

  /// [additive] adds to / removes from the selection (Ctrl or Shift click); otherwise this clip alone is selected.
  void select(int id, {bool additive = false}) {
    if (clipById(id) == null) return;
    if (additive) {
      if (!selected.add(id)) selected.remove(id);
    } else {
      selected
        ..clear()
        ..add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    selected
      ..clear()
      ..addAll(clips.map((c) => c.id));
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  void setLocked(int id, bool locked) {
    final c = clipById(id);
    if (c == null || c.locked == locked) return;
    _record('lock');
    c.locked = locked;
    if (!locked) c.exported = false;       // unlocking an exported slice makes it free to export again (its old clip may stay in the folder)
    notifyListeners();
  }

  /// Lock (or unlock) every selected clip.
  void lockSelected(bool locked) {
    if (selectedClips.isNotEmpty) _record('lock');
    for (final c in selectedClips) {
      c.locked = locked;
      if (!locked) c.exported = false;
    }
    notifyListeners();
  }

  bool remove(int id) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    _record('delete');
    clips.remove(c);
    selected.remove(id);
    notifyListeners();
    return true;
  }

  /// Deletes the selected clips that are not locked; returns how many went.
  int removeSelected() {
    final gone = selectedClips.where((c) => !c.locked).toList();
    if (gone.isNotEmpty) _record('delete');
    for (final c in gone) {
      clips.remove(c);
      selected.remove(c.id);
    }
    if (gone.isNotEmpty) notifyListeners();
    return gone.length;
  }
}

/// How one clip was at a moment (for undo and redo). Whether it was cut into the benchmark folder is not part of it.
class _ClipState {
  _ClipState(TrimClip c)
      : id = c.id,
        start = c.start,
        end = c.end,
        label = c.label,
        locked = c.locked,
        plate = c.plate,
        count = c.count,
        labels = Set.of(c.labels),
        cleanFor = Set.of(c.cleanFor);

  final int id;
  final double start;
  final double end;
  final String label;
  final bool locked;
  final String plate;
  final int count;
  final Set<String> labels;
  final Set<String> cleanFor;

  TrimClip toClip(bool exported) {
    final c = TrimClip(id: id, start: start, end: end, label: label, locked: locked || exported);
    c.labels.addAll(labels);
    c.cleanFor.addAll(cleanFor);
    c.plate = plate;
    c.count = count;
    c.exported = exported;
    return c;
  }
}
