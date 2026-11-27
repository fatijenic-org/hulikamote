import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/slice_store.dart';
import '../data/trimmer_api.dart';
import 'trim_session.dart';
import 'trimmer_models.dart';

/// Everything the trimmer remembers: the videos that are open (each with its own clips), which one is on screen, and the
/// exports. Exports run on the laptop on their own, so switching to another video or starting more exports never waits
/// for earlier ones; this just keeps asking how they are doing while any is still going.
class TrimmerController extends ChangeNotifier {
  TrimmerController({TrimmerApi? api, SliceStore? store, this.pollEvery = const Duration(seconds: 1)})
      : api = api ?? TrimmerApi(),
        store = store ?? SliceStore();

  final TrimmerApi api;

  /// Keeps the marked slices of every video in a file, so a restart or a crash loses nothing.
  final SliceStore store;
  final Map<String, Timer> _saveTimers = {};
  final Duration pollEvery;

  final List<TrimSession> sessions = [];
  int activeIndex = -1;
  List<TrimJob> jobs = const [];

  /// Re-encode for a cut that starts exactly where asked (slower). Off = copy: instant, no quality loss, the start snaps
  /// to the nearest keyframe before it.
  bool exact = false;

  /// Where cuts go. Empty = next to each video.
  String outputDir = '';

  /// Benchmark labelling is on: slices get violation labels and export into the benchmark folder.
  bool benchmarkMode = false;

  /// The saved setups on offer, and the one picked: its zones and overlays are used to score the clips (null = none: zone rules have no zone).
  List<SavedSetup> setups = const [];
  String? setupId;

  /// Demo: motorcycles and tricycles coming toward the camera are judged too (a front view shows no plate). Only for two-wheeler rules.
  bool incomingTwoWheelers = false;

  void setIncomingTwoWheelers(bool value) {
    incomingTwoWheelers = value;
    _changed();
  }

  /// Demo: the most riders a motorcycle may carry before it counts as overloaded (2 is the normal limit; 1 = every two-up bike).
  int overloadingLimit = 2;

  void setOverloadingLimit(int value) {
    overloadingLimit = value.clamp(1, 9);
    _changed();
  }

  /// What the benchmark folder holds per violation (null until read). Read when benchmark mode opens and after every export.
  BenchStats? stats;
  bool statsLoading = false;
  String? statsError;

  Future<void> loadStats() async {
    if (statsLoading) return;
    statsLoading = true;
    _changed();
    try {
      stats = await api.benchStats();
      statsError = null;
    } on TrimmerApiException catch (e) {
      statsError = e.message;
    }
    statsLoading = false;
    _changed();
  }

  /// Simulated wrong-way traffic: the exported counterflow clips are scored with the legal direction flipped.
  bool reverseCounterflow = false;

  void setReverseCounterflow(bool value) {
    reverseCounterflow = value;
    _changed();
  }

  Future<void> loadSetups() async {
    try {
      setups = await api.setups();
      if (setupId != null && !setups.any((s) => s.id == setupId)) setupId = null;
    } on TrimmerApiException {
      setups = const [];
    }
    _changed();
  }

  void setSetup(String? id) {
    setupId = id;
    _changed();
  }

  /// Seconds of normal traffic kept before and after each violation slice: 3, 5 or 8, or 0 = automatic (each slice gets the
  /// recommended seconds of its labels).
  int benchPad = 0;

  void setBenchPad(int seconds) {
    benchPad = seconds;
    _changed();
  }

  /// Score the new clips by itself as soon as every cut is done (the person only trims and labels).
  bool autoScore = true;

  /// A message for the screen to show once (scoring started, or could not start).
  String? notice;

  void clearNotice() {
    notice = null;
  }

  void setAutoScore(bool value) {
    autoScore = value;
    _changed();
  }

  final List<({Set<String> jobIds, List<String> clipIds})> _toScore = [];

  /// Each benchmark export: its cuts and its slices. If a cut is cancelled or fails, the slices are free again.
  final List<({Set<String> jobIds, TrimSession session, List<TrimClip> clips})> _batches = [];

  /// What the last benchmark export said (clips queued, folder, zones still to draw), for the screen to show once.
  String? benchNote;

  void setBenchmarkMode(bool value) {
    benchmarkMode = value;
    _changed();
    if (value) {
      loadSetups();
      loadStats();
    }
  }

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
    unawaited(_restoreSaved(session));
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

  /// Brings back the slices saved for this video, then keeps saving every change (a moment after the last one).
  Future<void> _restoreSaved(TrimSession session) async {
    final saved = await store.load(session.path);
    if (_disposed) return;
    if (saved.isNotEmpty && session.clips.isEmpty) {
      session.restore(saved);
      notice = 'Brought back ${saved.length} saved slice${saved.length == 1 ? '' : 's'} of ${session.name}.';
      _changed();
    }
    session.addListener(() {
      _saveTimers[session.path]?.cancel();
      _saveTimers[session.path] = Timer(const Duration(milliseconds: 400), () => store.save(session.path, session.toJson()));
    });
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

  /// Cuts every labelled, not yet exported slice of [session] into the benchmark folder (in the background, so another video
  /// can be labelled at once). The slices are locked and marked exported when the backend accepted them.
  Future<bool> exportBenchmark(TrimSession session) async {
    final pending = session.toExport;
    if (pending.isEmpty) {
      error = 'Nothing to export: give at least one slice a label.';
      _changed();
      return false;
    }
    final slices = [
      for (final c in session.labelled)
        {
          'start': c.start,
          'end': c.end,
          'labels': c.labels.toList(),
          'clean_for': c.cleanFor.toList(),
          'export': !c.exported,
          'pad': benchPad == 0 ? session.recommendedPad(c) : benchPad,
          'plate': c.plate,
          'count': c.count,
        },
    ];
    try {
      // a setting that only matters for one violation is sent only when a slice of this export has that violation
      final started = await api.startBenchmark(
        session.path,
        slices,
        setupId: setupId,
        reverseCounterflow: reverseCounterflow && pending.any((c) => c.labels.contains('counterflow')),
        incomingTwoWheelers: incomingTwoWheelers && pending.any((c) => c.labels.any(twoWheelerRules.contains)),
        overloadingMaxRiders: overloadingLimit != 2 && pending.any((c) => c.labels.contains('overloading')) ? overloadingLimit : null,
      );
      jobs = [...started.jobs, ...jobs.where((j) => !started.jobs.any((s) => s.id == j.id))];
      if (autoScore && started.clipIds.isNotEmpty) _toScore.add((jobIds: {for (final j in started.jobs) j.id}, clipIds: started.clipIds));
      for (final c in pending) {
        c.exported = true;
        c.locked = true;
      }
      _batches.add((jobIds: {for (final j in started.jobs) j.id}, session: session, clips: List.of(pending)));
      session.refresh();
      final n = started.jobs.length;
      benchNote = 'Cutting $n clip${n == 1 ? '' : 's'} into ${started.folder}. You can open the next video now.'
          '${started.needsZone.isEmpty ? '' : ' Zone rules (${started.needsZone.join(', ')}) still need their zone drawn before they are scored.'}'
          '${started.skipped.isEmpty ? '' : ' ${started.skipped.join(' ')}'}';
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
      _freeStoppedBatches();
      await _scoreFinished();
    } on TrimmerApiException catch (e) {
      error = e.message;
    }
    _changed();
  }

  /// A cut that was cancelled or failed must not leave its slices locked as "exported": they are free again, so the person can export
  /// again. A batch whose cuts all finished well is forgotten.
  void _freeStoppedBatches() {
    for (final batch in List.of(_batches)) {
      final mine = jobs.where((j) => batch.jobIds.contains(j.id)).toList();
      if (mine.length < batch.jobIds.length) continue;                                      // the list was cleared or not complete yet
      if (mine.any((j) => j.status == JobStatus.cancelled || j.status == JobStatus.failed)) {
        for (final c in batch.clips) {
          c.exported = false;
          c.locked = false;
        }
        batch.session.refresh();
        _batches.remove(batch);
        notice = 'An export was stopped, so its slices are free again. Press Export to benchmark to cut them again.';
      } else if (mine.every((j) => j.status == JobStatus.done)) {
        _batches.remove(batch);
        unawaited(loadStats());                                                              // the folder has new clips: the counts change
      }
    }
  }

  /// When every cut of an export is finished, asks for the benchmark on its clips. If a cut failed its clip is not in the registry,
  /// so nothing is scored and the person is told.
  Future<void> _scoreFinished() async {
    for (final pending in List.of(_toScore)) {
      final mine = jobs.where((j) => pending.jobIds.contains(j.id)).toList();
      if (mine.length < pending.jobIds.length || mine.any((j) => j.active)) continue;      // still cutting
      _toScore.remove(pending);
      if (mine.any((j) => j.status != JobStatus.done)) {
        notice = 'Some cuts failed, so the benchmark was not started. Check the exports list, then run the benchmark in the Benchmark tab.';
        continue;
      }
      try {
        await api.startScoring(pending.clipIds);
        notice = 'Cutting done. The benchmark is scoring ${pending.clipIds.length} clip${pending.clipIds.length == 1 ? '' : 's'} now: open the Benchmark tab to follow it.';
      } on TrimmerApiException catch (e) {
        notice = 'Cutting done, but the benchmark did not start: ${e.message} Run it in the Benchmark tab.';
      }
    }
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
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    for (final s in sessions) {
      store.save(s.path, s.toJson());              // the last state is kept even if a save was still waiting
    }
    _stopPolling();
    for (final s in sessions) {
      s.dispose();
    }
    super.dispose();
  }
}
