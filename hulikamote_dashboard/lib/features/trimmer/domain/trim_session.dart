import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One piece to cut out of the video. A locked clip cannot be moved, resized, renamed or deleted until it is unlocked.
class TrimClip {
  TrimClip({required this.id, required this.start, required this.end, this.label = '', this.locked = false});

  final int id;
  double start;
  double end;
  String label;
  bool locked;

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

  /// "Clip 3" when the person gave it no name.
  String titleOf(TrimClip c) => c.label.trim().isNotEmpty ? c.label.trim() : 'Clip ${clips.indexOf(c) + 1}';

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
    c.start = t.clamp(0.0, math.max(0.0, c.end - minLength));
    notifyListeners();
    return true;
  }

  bool setEnd(int id, double t) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    c.end = t.clamp(math.min(duration, c.start + minLength), duration);
    notifyListeners();
    return true;
  }

  /// Slide the whole clip so it starts at [newStart], keeping its length.
  bool moveClip(int id, double newStart) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
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
    c.start = start;
    c.end = math.min(end, duration);
    notifyListeners();
    return true;
  }

  bool rename(int id, String label) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
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
    c.locked = locked;
    notifyListeners();
  }

  /// Lock (or unlock) every selected clip.
  void lockSelected(bool locked) {
    for (final c in selectedClips) {
      c.locked = locked;
    }
    notifyListeners();
  }

  bool remove(int id) {
    final c = clipById(id);
    if (c == null || c.locked) return false;
    clips.remove(c);
    selected.remove(id);
    notifyListeners();
    return true;
  }

  /// Deletes the selected clips that are not locked; returns how many went.
  int removeSelected() {
    final gone = selectedClips.where((c) => !c.locked).toList();
    for (final c in gone) {
      clips.remove(c);
      selected.remove(c.id);
    }
    if (gone.isNotEmpty) notifyListeners();
    return gone.length;
  }
}
