import 'dart:async';

import 'package:flutter/foundation.dart';

import 'forensic_gateway.dart';
import 'forensic_models.dart';
import 'holding_models.dart';
import 'plate_tools_models.dart';

enum QueueFilter { all, toReview, flagged, confirmed, rejected }

enum QueueSort { flaggedFirst, timeInVideo, mostFrames, trackId }

/// State and rules of the review workspace: which ticket is open, which frame, how the
/// queue is filtered / sorted, and what the reviewer decided. No widgets in here, so the
/// whole workflow is unit-testable.
class ReviewController extends ChangeNotifier {
  ReviewController({
    required this.gateway,
    required this.taskId,
    required List<ForensicTicket> tickets,
    Map<String, ReviewStatus>? statuses,
    this.autoAdvance = true,
  }) : _tickets = List.of(tickets) {
    if (statuses != null) _status.addAll(statuses);
    _selectedUid = _firstToLookAt()?.uid;
    _frame = selected?.heroIndex ?? 0;
  }

  final ReviewGateway gateway;
  final String taskId;

  /// After a decision, jump to the next ticket still waiting for review.
  bool autoAdvance;

  List<ForensicTicket> _tickets;
  final Map<String, ReviewStatus> _status = {};
  String? _selectedUid;
  int _frame = 0;
  QueueFilter _filter = QueueFilter.all;
  QueueSort _sort = QueueSort.flaggedFirst;
  String _query = '';
  final Set<String> _violationFilter = {};
  final Set<String> _checked = {};
  final Map<String, String> _plateFeedback = {}; // ticket uid -> what was sent
  final Map<String, String> _cropChoice =
      {}; // ticket uid -> plate crop file picked for feedback
  Map<String, ReviewStatus>? _undo;
  bool _busy = false;
  String? _error;

  // A run that is still going (see followRun).
  bool _analyzing = false;
  double _runProgress = 0;
  String _runMessage = '';
  String? _resultVideo;
  bool _runGone = false;
  int _liveFailures = 0;
  bool _liveBusy = false;
  int _listVersion = 0; // bumped whenever an edit swaps in a new ticket list
  Timer? _liveTimer;

  // ── read ──
  List<ForensicTicket> get all => List.unmodifiable(_tickets);
  QueueFilter get filter => _filter;
  QueueSort get sort => _sort;
  String get query => _query;
  Set<String> get violationFilter => Set.unmodifiable(_violationFilter);
  Set<String> get checked => Set.unmodifiable(_checked);
  bool get busy => _busy;
  String? get error => _error;
  bool get canUndo => _undo != null;
  int get frameIndex => _frame;
  ForensicTicket? get selected => _byUid(_selectedUid);
  String? get selectedUid => _selectedUid;

  EvidenceFrame? get currentFrame {
    final t = selected;
    if (t == null || t.frames.isEmpty) return null;
    return t.frames[_frame.clamp(0, t.frames.length - 1)];
  }

  ReviewStatus statusOf(ForensicTicket t) =>
      _status[t.uid] ?? ReviewStatus.pending;

  /// Plate feedback already sent for a ticket ("KMO522K" or "not a plate"), if any.
  String? plateFeedbackFor(String uid) => _plateFeedback[uid];

  int get total => _tickets.length;
  int get reviewedCount =>
      _tickets.where((t) => statusOf(t) != ReviewStatus.pending).length;
  int get confirmedCount =>
      _tickets.where((t) => statusOf(t) == ReviewStatus.confirmed).length;
  int get rejectedCount =>
      _tickets.where((t) => statusOf(t) == ReviewStatus.rejected).length;

  int countFor(QueueFilter f) => switch (f) {
    QueueFilter.all => total,
    QueueFilter.toReview => total - reviewedCount,
    QueueFilter.flagged => _tickets.where((t) => t.isFlagged).length,
    QueueFilter.confirmed => confirmedCount,
    QueueFilter.rejected => rejectedCount,
  };

  /// How many tickets carry each violation (for the filter menu).
  Map<String, int> get violationCounts {
    final out = <String, int>{};
    for (final t in _tickets) {
      for (final v in t.violations) {
        out[v] = (out[v] ?? 0) + 1;
      }
    }
    return out;
  }

  /// The queue as shown: filtered by status / violation / search, then sorted.
  List<ForensicTicket> get visible {
    final q = _query.trim().toLowerCase();
    final list = _tickets.where((t) {
      final s = statusOf(t);
      final passes = switch (_filter) {
        QueueFilter.all => true,
        QueueFilter.toReview => s == ReviewStatus.pending,
        QueueFilter.flagged => t.isFlagged,
        QueueFilter.confirmed => s == ReviewStatus.confirmed,
        QueueFilter.rejected => s == ReviewStatus.rejected,
      };
      if (!passes) return false;
      if (_violationFilter.isNotEmpty &&
          !t.violations.any(_violationFilter.contains)) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${t.plateText} ${t.plateRaw ?? ''} ${t.trackId} ${t.shortId} ${t.vehicleClass ?? ''} '
                    '${t.violations.join(' ')}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    list.sort(_compare);
    return list;
  }

  int _compare(ForensicTicket a, ForensicTicket b) {
    int byTrack() => a.trackId.compareTo(b.trackId);
    switch (_sort) {
      case QueueSort.trackId:
        return byTrack();
      case QueueSort.mostFrames:
        final c = b.frameCount.compareTo(a.frameCount);
        return c != 0 ? c : byTrack();
      case QueueSort.timeInVideo:
        final sa = a.span?.start, sb = b.span?.start;
        if (sa == null && sb == null) return byTrack();
        if (sa == null) return 1;
        if (sb == null) return -1;
        final c = sa.compareTo(sb);
        return c != 0 ? c : byTrack();
      case QueueSort.flaggedFirst:
        final fa = a.isFlagged ? 0 : 1, fb = b.isFlagged ? 0 : 1;
        if (fa != fb) return fa.compareTo(fb);
        final pa = statusOf(a) == ReviewStatus.pending ? 0 : 1,
            pb = statusOf(b) == ReviewStatus.pending ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        return byTrack();
    }
  }

  ForensicTicket? _byUid(String? uid) {
    if (uid == null) return null;
    for (final t in _tickets) {
      if (t.uid == uid) return t;
    }
    return null;
  }

  ForensicTicket? _firstToLookAt() {
    final v = visible;
    if (v.isEmpty) return null;
    return v.firstWhere(
      (t) => statusOf(t) == ReviewStatus.pending,
      orElse: () => v.first,
    );
  }

  // ── navigation ──
  void select(String uid) {
    if (_byUid(uid) == null || uid == _selectedUid) return;
    _selectedUid = uid;
    _frame = selected!.heroIndex;
    notifyListeners();
  }

  /// Moves through the visible queue by [delta] (clamped at both ends).
  void selectRelative(int delta) {
    final v = visible;
    if (v.isEmpty) return;
    final i = v.indexWhere((t) => t.uid == _selectedUid);
    final next = (i < 0 ? 0 : i + delta).clamp(0, v.length - 1);
    select(v[next].uid);
  }

  void setFrame(int index) {
    final n = selected?.frameCount ?? 0;
    if (n == 0) return;
    final i = index.clamp(0, n - 1);
    if (i == _frame) return;
    _frame = i;
    notifyListeners();
  }

  void stepFrame(int delta) => setFrame(_frame + delta);

  // ── queue filters ──
  void setFilter(QueueFilter f) {
    _filter = f;
    _afterQueueChange();
  }

  void setSort(QueueSort s) {
    _sort = s;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    _afterQueueChange();
  }

  void toggleViolationFilter(String key) {
    _violationFilter.contains(key)
        ? _violationFilter.remove(key)
        : _violationFilter.add(key);
    _afterQueueChange();
  }

  void clearFilters() {
    _filter = QueueFilter.all;
    _query = '';
    _violationFilter.clear();
    _afterQueueChange();
  }

  bool get hasActiveFilters =>
      _filter != QueueFilter.all ||
      _query.isNotEmpty ||
      _violationFilter.isNotEmpty;

  /// A filter may hide the open ticket: it stays open (the reviewer keeps their place)
  /// until another is picked. Only when it no longer exists does the first visible one open.
  void _afterQueueChange() {
    if (_byUid(_selectedUid) == null) {
      final v = visible;
      if (v.isNotEmpty) {
        _selectedUid = v.first.uid;
        _frame = selected!.heroIndex;
      }
    }
    notifyListeners();
  }

  // ── batch selection ──
  void toggleChecked(String uid) {
    _checked.contains(uid) ? _checked.remove(uid) : _checked.add(uid);
    notifyListeners();
  }

  void checkAllVisible() {
    _checked
      ..clear()
      ..addAll(visible.map((t) => t.uid));
    notifyListeners();
  }

  void clearChecked() {
    if (_checked.isEmpty) return;
    _checked.clear();
    notifyListeners();
  }

  // ── decisions ──
  /// Sets the review status of one ticket. Optimistic; rolled back if the backend refuses.
  Future<bool> decide(String uid, ReviewStatus status) =>
      _decide([uid], status, advance: autoAdvance);

  /// Same, for every ticket ticked in the queue.
  Future<bool> decideChecked(ReviewStatus status) async {
    final ok = await _decide(_checked.toList(), status, advance: false);
    if (ok) _checked.clear();
    notifyListeners();
    return ok;
  }

  Future<bool> _decide(
    List<String> uids,
    ReviewStatus status, {
    required bool advance,
  }) async {
    final tickets = [
      for (final u in uids)
        if (_byUid(u) != null) _byUid(u)!,
    ];
    if (tickets.isEmpty || _busy) return false;
    final before = {for (final t in tickets) t.uid: statusOf(t)};
    for (final t in tickets) {
      _status[t.uid] = status;
    }
    _busy = true;
    _error = null;
    final wasSelected = _selectedUid;
    notifyListeners();
    try {
      await Future.wait([
        for (final t in tickets) gateway.setStatus(t.dbIds, status),
      ]);
      _undo = before;
      if (advance &&
          tickets.length == 1 &&
          tickets.first.uid == wasSelected &&
          status != ReviewStatus.pending) {
        _advanceFrom(wasSelected);
      }
      return true;
    } catch (e) {
      before.forEach((uid, s) => _status[uid] = s);
      _error = 'Could not save the decision: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Opens the next ticket that still needs review (or the next one, if everything is done).
  void _advanceFrom(String? uid) {
    final v = visible;
    if (v.isEmpty) return;
    final i = v.indexWhere((t) => t.uid == uid);
    final after = i < 0 ? v : [...v.skip(i + 1), ...v.take(i)];
    final next = after.firstWhere(
      (t) => statusOf(t) == ReviewStatus.pending,
      orElse: () => v[(i + 1).clamp(0, v.length - 1)],
    );
    if (next.uid != _selectedUid) {
      _selectedUid = next.uid;
      _frame = next.heroIndex;
    }
  }

  /// Puts back the statuses from before the last decision.
  Future<bool> undo() async {
    final prev = _undo;
    if (prev == null || _busy) return false;
    _busy = true;
    notifyListeners();
    try {
      await Future.wait([
        for (final e in prev.entries)
          if (_byUid(e.key) != null)
            gateway.setStatus(_byUid(e.key)!.dbIds, e.value),
      ]);
      prev.forEach((uid, s) => _status[uid] = s);
      _undo = null;
      return true;
    } catch (e) {
      _error = 'Could not undo: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── plate feedback (training data) ──
  /// The plate crop feedback refers to: the reviewer's pick, else the winning crop.
  PlateCrop? chosenCrop(ForensicTicket t) {
    final f = _cropChoice[t.uid];
    if (f != null) {
      for (final c in t.crops) {
        if (c.file == f) return c;
      }
    }
    return t.bestCrop;
  }

  void chooseCrop(String uid, String file) {
    _cropChoice[uid] = file;
    notifyListeners();
  }

  /// Sends [crop] with the true [label] (empty = "this is not a plate") to the OCR dataset.
  Future<bool> sendPlateFeedback(
    ForensicTicket ticket,
    PlateCrop crop,
    String label,
  ) => sendPlateFeedbackImage(ticket, crop.enhanced ?? crop.file, label);

  /// The same, for a picture named directly (the crop of a plate the reviewer drew).
  Future<bool> sendPlateFeedbackImage(
    ForensicTicket ticket,
    String imageName,
    String label,
  ) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await gateway.sendPlateFeedback(
        imageName: imageName,
        label: label.trim(),
      );
      _plateFeedback[ticket.uid] = label.trim().isEmpty
          ? 'not a plate'
          : label.trim().toUpperCase();
      return true;
    } catch (e) {
      _error = 'Could not send the plate feedback: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── plate and photo tools ──
  /// "Read again" looks at every photo of a small ticket, and at an even spread of a big one.
  static const rereadPhotos = 12;

  /// The photos "Read again" looks at: all when there are few, otherwise an even spread that includes the best view.
  List<String> rereadSample(ForensicTicket t) {
    final n = t.frameCount;
    if (n <= rereadPhotos) return [for (final f in t.frames) f.file];
    final picks = [for (var i = 0; i < rereadPhotos; i++) (i * (n - 1) / (rereadPhotos - 1)).round()];
    final hero = t.heroIndex;
    if (!picks.contains(hero)) {
      var nearest = 0;
      for (var k = 1; k < picks.length; k++) {
        if ((picks[k] - hero).abs() < (picks[nearest] - hero).abs()) nearest = k;
      }
      picks[nearest] = hero; // the best view is always read
    }
    final sorted = picks.toSet().toList()..sort();
    return [for (final i in sorted) t.frames[i].file];
  }

  /// Looks for the plate again and votes again. Returns what it found (null if it failed: the workspace shows why).
  /// Decisions, selection and the open photo stay where they are.
  Future<RereadResult?> rereadPlate(ForensicTicket ticket) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await gateway.rereadPlate(taskId, ticket.uid, rereadSample(ticket));
      final photo = _frame;
      final wasOpen = _selectedUid == ticket.uid;
      replaceTickets(result.tickets, preferUid: ticket.uid);
      final now = selected;
      if (wasOpen && now != null && photo < now.frameCount) _frame = photo;
      return result;
    } catch (e) {
      _error = 'Could not read the plate again: $e';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Reads a box drawn on a photo. Changes nothing on the ticket; errors reach the caller.
  Future<PlateBoxRead> readPlateBox(String image, List<double> box) => gateway.readPlateBox(taskId, image, box);

  /// Moves the photos in [files] out of [ticket] into a new ticket of their own. The ticket keeps the rest.
  Future<bool> separateFrames(ForensicTicket ticket, List<String> files) =>
      ticketAction('split', {'ticket_uid': ticket.uid, 'frames': files}, thenSelect: ticket.uid);

  /// Moves the photos in [files] of [from] into the ticket [to]; [from] keeps the rest. When they are all of its
  /// photos it is a plain merge: [from] disappears and [to] is opened.
  Future<bool> moveFramesTo(ForensicTicket from, ForensicTicket to, List<String> files) => files.length >= from.frameCount
      ? ticketAction('merge', {'keep_uid': to.uid, 'merge_uid': from.uid}, thenSelect: to.uid)
      : ticketAction('move-frames', {'keep_uid': to.uid, 'from_uid': from.uid, 'frames': files}, thenSelect: from.uid);

  /// Takes the photos in [files] out of the ticket (they are not sent to the motorist). One photo must stay.
  Future<bool> removeFrames(ForensicTicket ticket, List<String> files) =>
      ticketAction('remove-frames', {'ticket_uid': ticket.uid, 'frames': files}, thenSelect: ticket.uid);

  // ── ticket edits (merge / separate / not a duplicate) ──
  /// Runs a backend ticket action and swaps in the updated list, keeping the reviewer's place.
  Future<bool> ticketAction(
    String action,
    Map<String, dynamic> body, {
    String? thenSelect,
  }) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await gateway.ticketAction(taskId, action, {
        'task_id': taskId,
        ...body,
      });
      replaceTickets(updated, preferUid: thenSelect);
      return true;
    } catch (e) {
      _error = 'Action failed: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── plate edit ──
  /// Saves [plate] as the ticket's plate (empty = no readable plate); [revert] restores the
  /// system's read. Decisions, selection and the open photo stay where they are.
  Future<bool> setPlate(
    ForensicTicket ticket,
    String plate, {
    bool revert = false,
  }) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await gateway.setPlate(
        taskId,
        ticket.uid,
        plate.trim(),
        revert: revert,
      );
      final photo = _frame;
      final wasOpen = _selectedUid == ticket.uid;
      replaceTickets(updated, preferUid: ticket.uid);
      final now = selected;
      if (wasOpen && now != null && photo < now.frameCount) _frame = photo;
      return true;
    } catch (e) {
      _error = 'Could not save the plate: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Replaces the ticket list (after merge / split) and keeps selection and statuses where possible.
  void replaceTickets(List<ForensicTicket> updated, {String? preferUid}) {
    final previous = _selectedUid;
    _tickets = List.of(updated);
    _listVersion++;
    final alive = _tickets.map((t) => t.uid).toSet();
    _status.removeWhere((uid, _) => !alive.contains(uid));
    _checked.removeWhere((uid) => !alive.contains(uid));
    _undo = null;
    final target = (preferUid != null && alive.contains(preferUid))
        ? preferUid
        : (previous != null && alive.contains(previous)
              ? previous
              : _firstToLookAt()?.uid);
    _selectedUid = target;
    _frame = selected?.heroIndex ?? 0;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ── Holding: photos set aside from a ticket ──
  List<HoldingBatch> _holding = [];

  /// Photos that were set aside and wait for a decision.
  List<HoldingBatch> get holding => List.unmodifiable(_holding);
  int get holdingCount => _holding.length;

  /// Reads what is waiting in Holding. Quiet on failure: an older backend has no Holding, and the review still works.
  Future<void> loadHolding() async {
    try {
      _holding = await gateway.loadHolding(taskId);
      notifyListeners();
    } catch (_) {
      // nothing to show
    }
  }

  /// Takes the photos in [files] out of [ticket] and parks them in Holding. The ticket keeps the rest.
  Future<bool> setAside(ForensicTicket ticket, List<String> files) => _holdingCall(
    () => gateway.setAside(taskId, ticket.uid, files),
    failure: 'Could not set the photos aside',
    open: (_) => ticket.uid,
  );

  /// One batch in Holding: make-ticket | add-to-ticket (needs [into]) | put-back | throw-away.
  /// Afterwards the ticket that was made, the one that received the photos, or the one they came from is open.
  Future<bool> holdingAction(String action, HoldingBatch batch, {ForensicTicket? into}) => _holdingCall(
    () => gateway.holdingAction(taskId, action, {'batch_id': batch.id, if (into != null) 'keep_uid': into.uid}),
    failure: 'That Holding action failed',
    open: (r) => switch (action) {
      'make-ticket' => r.ticketUid,
      'put-back' => batch.fromUid,
      _ => into?.uid,
    },
  );

  Future<bool> _holdingCall(
    Future<HoldingResult> Function() call, {
    required String failure,
    required String? Function(HoldingResult) open,
  }) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final r = await call();
      _holding = r.holding;
      replaceTickets(r.tickets, preferUid: open(r));
      return true;
    } catch (e) {
      _error = '$failure: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── an analysis that is still running ──
  /// True while the analysis behind these tickets is still reading the video: tickets keep arriving.
  bool get analyzing => _analyzing;

  /// How far the running analysis is (0..100), and what it says it is doing.
  double get runProgress => _runProgress;
  String get runMessage => _runMessage;

  /// The evidence video of the run, known once it is done.
  String? get resultVideo => _resultVideo;

  /// The run was cancelled while it was open here: its tickets are gone.
  bool get runGone => _runGone;

  /// Follows the running analysis: every [every] the ticket list is refreshed (new cars, plates read, tickets merged),
  /// until the run ends. The reviewer keeps the open ticket, photo, filters and decisions.
  void followRun({Duration every = const Duration(seconds: 3)}) {
    if (_analyzing) return;
    _analyzing = true;
    _liveFailures = 0;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(every, (_) => refreshLive());
    notifyListeners();
    refreshLive();
  }

  /// One look at the running analysis (the timer calls this; tests call it directly).
  Future<void> refreshLive() async {
    if (!_analyzing || _liveBusy) return;
    _liveBusy = true;
    final version = _listVersion;
    try {
      final s = await gateway.followStatus(taskId);
      _liveFailures = 0;
      _runProgress = s.progress;
      _runMessage = s.message;
      if (s.isCancelled) {
        _runGone = true;
        _tickets = [];
        _selectedUid = null;
        _stopFollowing();
      } else {
        // An edit that ran meanwhile brought its own, newer list: this look is older than that.
        if (!_busy && version == _listVersion) _applyLive(s.tickets);
        if (s.isDone || s.isFailed) {
          _resultVideo = s.resultVideo;
          _stopFollowing();
        }
      }
      notifyListeners();
    } catch (_) {
      // A few failed looks are fine; when the analyzer is gone for good, what was released stays on screen.
      if (++_liveFailures >= 10) {
        _stopFollowing();
        notifyListeners();
      }
    } finally {
      _liveBusy = false;
    }
  }

  void _stopFollowing() {
    _analyzing = false;
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  static String _signature(ForensicTicket t) =>
      '${t.uid}|${t.frameCount}|${t.plateText}|${t.flags.length}|${t.violations.join(',')}|${t.dbIds.length}';

  /// Swaps in the newest ticket list, keeping the open ticket and photo, the decisions and the ticks.
  void _applyLive(List<ForensicTicket> updated) {
    final same = updated.length == _tickets.length &&
        [for (var i = 0; i < updated.length; i++) _signature(updated[i]) == _signature(_tickets[i])].every((b) => b);
    if (same) return;
    _tickets = List.of(updated);
    final alive = _tickets.map((t) => t.uid).toSet();
    _status.removeWhere((uid, _) => !alive.contains(uid));
    _checked.removeWhere((uid) => !alive.contains(uid));
    if (_byUid(_selectedUid) == null) {
      _selectedUid = _firstToLookAt()?.uid;
      _frame = selected?.heroIndex ?? 0;
    } else {
      final n = selected!.frameCount;
      if (_frame >= n) _frame = n > 0 ? n - 1 : 0;
    }
  }

  bool _disposed = false;

  /// A late answer (Holding, a followed run) must not touch a controller the screen already let go of.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _liveTimer?.cancel();
    super.dispose();
  }
}
