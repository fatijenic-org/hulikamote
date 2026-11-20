/// The ticket an appeal is about (backend: routers/appeals.py, GET /appeals/review).
class AppealTicket {
  const AppealTicket({required this.id, required this.cls, required this.plate, required this.timestamp, this.frames = const [], this.found = true});

  final String id;

  /// The violation key, e.g. `no_helmet`. Empty when the ticket is no longer on this laptop.
  final String cls;
  final String plate;
  final String timestamp;

  /// File names of the ticket's photos under snapshots/evidence (only the ones still on disk).
  final List<String> frames;

  /// False when the ticket was deleted from this laptop after the appeal was filed.
  final bool found;

  DateTime? get time => DateTime.tryParse(timestamp)?.toLocal();

  factory AppealTicket.fromJson(Map<String, dynamic> json) => AppealTicket(
        id: json['id'] as String? ?? '',
        cls: json['cls'] as String? ?? '',
        plate: json['plate'] as String? ?? '',
        timestamp: json['timestamp'] as String? ?? '',
        frames: [for (final f in json['frames'] as List? ?? const []) f as String],
        found: json['found'] as bool? ?? true,
      );
}

/// One appeal a motorist filed from the phone app.
class AppealItem {
  const AppealItem({
    required this.id,
    required this.source,
    required this.status,
    required this.reason,
    required this.caseNo,
    required this.ticket,
    this.note = '',
    this.motorist = '',
    this.createdAt,
    this.decidedAt,
  });

  final String id;

  /// `local` (filed on the same Wi-Fi) or `cloud` (filed through Supabase).
  final String source;

  /// `pending`, `accepted` or `rejected`.
  final String status;
  final String reason;

  /// What the reviewer told the motorist.
  final String note;
  final String caseNo;
  final String motorist;
  final AppealTicket ticket;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get pending => status == 'pending';
  bool get accepted => status == 'accepted';

  factory AppealItem.fromJson(Map<String, dynamic> json) => AppealItem(
        id: json['id'] as String? ?? '',
        source: json['source'] as String? ?? 'local',
        status: json['status'] as String? ?? 'pending',
        reason: json['reason'] as String? ?? '',
        note: json['note'] as String? ?? '',
        caseNo: json['case_no'] as String? ?? '',
        motorist: json['motorist'] as String? ?? '',
        ticket: AppealTicket.fromJson(Map<String, dynamic>.from(json['ticket'] as Map? ?? const {})),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
        decidedAt: DateTime.tryParse(json['decided_at'] as String? ?? '')?.toLocal(),
      );
}

/// Everything the Appeals page shows: the appeals, how many are in each state, and why the cloud part could not be read.
class AppealList {
  const AppealList({required this.items, this.pending = 0, this.accepted = 0, this.rejected = 0, this.cloudError = ''});

  final List<AppealItem> items;
  final int pending;
  final int accepted;
  final int rejected;
  final String cloudError;

  factory AppealList.fromJson(Map<String, dynamic> json) {
    final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? const {});
    return AppealList(
      items: [for (final a in json['appeals'] as List? ?? const []) AppealItem.fromJson(Map<String, dynamic>.from(a as Map))],
      pending: (counts['pending'] as num?)?.toInt() ?? 0,
      accepted: (counts['accepted'] as num?)?.toInt() ?? 0,
      rejected: (counts['rejected'] as num?)?.toInt() ?? 0,
      cloudError: json['cloud_error'] as String? ?? '',
    );
  }
}
