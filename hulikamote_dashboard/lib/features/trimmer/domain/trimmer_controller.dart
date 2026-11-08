import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/trimmer_api.dart';
import 'trim_session.dart';
import 'trimmer_models.dart';

/// Everything the trimmer remembers: the videos that are open (each with its own clips), which one is on screen, and the
/// exports. Exports run on the laptop on their own, so switching to another video or starting more exports never waits
/// for earlier ones; this just keeps asking how they are doing while any is still going.
class TrimmerController extends ChangeNotifier {
  TrimmerController({TrimmerApi? api, this.pollEvery = const Duration(seconds: 1)}) : api = api ?? TrimmerApi();

  final TrimmerApi api;
  final Duration pollEvery;

  final List<TrimSession> sessions = [];
  int activeIndex = -1;
  List<TrimJob> jobs = const [];

  /// Re-encode for a cut that starts exactly where asked (slower). Off = copy: instant, no quality loss, the start snaps
  /// to the nearest keyframe before it.
  bool exact = false;

  /// Where cuts go. Empty = next to each video.
  String outputDir = '';

  /// The last problem, for the screen to show once.
  String? error;

  Timer? _timer;
  bool _disposed = false;

  TrimSession? get active => activeIndex >= 0 && activeIndex < sessions.length ? sessions[activeIndex] : null;
  int get activeJobCount => jobs.where((j) => j.active).length;

  List<TrimJob> jobsFor(TrimSession s) => [for (final j in jobs) if (j.source == s.path) j];

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void clearError() {
    error = null;
    _changed();
  }

  void setExact(bool value) {
    exact = value;
    _changed();
  }

  void setOutputDir(String dir) {
    outputDir = dir;
    _changed();
  }

  // ── videos ──

  /// Opens a video (or brings it to the front if it is already open). Null, with [error] set, when it cannot be read.
  Future<TrimSession?> open(String path) async {
    final existing = sessions.indexWhere((s) => s.path == path);
    if (existing >= 0) {
      activeIndex = existing;
      _changed();
      return sessions[existing];
    }
    // The video appears (and the player starts opening it) straight away; the backend's answer fills in the rest.
    final session = TrimSession(path: path);
    sessions.add(session);
    activeIndex = sessions.length - 1;
    _changed();
    try {
      final info = await api.probe(path);
      session.setInfo(duration: info.duration, fps: info.fps);
      return session;
    } on TrimmerApiException catch (e) {
      if (session.ready) return session;               // the player already knew its length, so it is playable
      final index = sessions.indexOf(session);
      if (index >= 0) close(index);
      error = e.message;
      _changed();
      return null;
    }
  }

  void activate(int index) {
    if (index < 0 || index >= sessions.length || index == activeIndex) return;
    activeIndex = index;
    _changed();
  }

  /// Closes a video. Its exports keep going.
  void close(int index) {
    if (index < 0 || index >= sessions.length) return;
    sessions.removeAt(index).dispose();
    if (sessions.isEmpty) {
      activeIndex = -1;
    } else if (activeIndex > index || activeIndex >= sessions.length) {
      activeIndex = (activeIndex - 1).clamp(0, sessions.length - 1);
    }
    _changed();
  }

  // ── exports ──

  /// Queues these clips of [session] for cutting and returns at once. The clips stay as they are, so they can be edited
  /// and exported again.
  Future<bool> export(TrimSession session, List<TrimClip> clips) async {
    if (clips.isEmpty) return false;
    final requests = [for (final c in clips) ClipRequest(start: c.start, end: c.end, label: c.label.trim())];   // the name becomes part of the file name
    try {
      final started = await api.startJobs(session.path, requests, exact: exact, outputDir: outputDir);
      jobs = [...started, ...jobs.where((j) => !started.any((s) => s.id == j.id))];
      _changed();
      _startPolling();
      return true;
    } on TrimmerApiException catch (e) {
      error = e.message;
      _changed();
      return false;
    }
  }

  Future<bool> exportSelected() async {
    final s = active;
    return s == null ? false : export(s, s.selectedClips);
  }

  Future<bool> exportAll() async {
    final s = active;
    return s == null ? false : export(s, List.of(s.clips));
  }

  Future<void> cancel(TrimJob job) async {
    try {
      await api.cancel(job.id);
    } on TrimmerApiException catch (e) {
      error = e.message;
    }
    await refreshJobs();
  }

  Future<void> clearFinished() async {
    try {
      await api.clearFinished();
    } on TrimmerApiException catch (e) {
      error = e.message;
    }
    await refreshJobs();
  }

  /// Asks the laptop how every export is doing.
  Future<void> refreshJobs() async {
    try {
      jobs = await api.jobs();
    } on TrimmerApiException catch (e) {
      error = e.message;
    }
    _changed();
  }

  void _startPolling() {
    _timer ??= Timer.periodic(pollEvery, (_) async {
      await refreshJobs();
      if (activeJobCount == 0) _stopPolling();
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    for (final s in sessions) {
      s.dispose();
    }
    super.dispose();
  }
}
