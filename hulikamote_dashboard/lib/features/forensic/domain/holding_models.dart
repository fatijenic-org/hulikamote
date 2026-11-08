import 'forensic_models.dart';

/// Photos set aside from a ticket (the tracker followed another car for a while), waiting in Holding until the operator
/// decides: a new ticket, another ticket, back where they came from, or away.
class HoldingBatch {
  final String id;

  /// The ticket the photos were taken from, and its vehicle number.
  final String fromUid;
  final int fromTrack;
  final DateTime? createdAt;

  /// Shaped like a ticket (its photos, its plate crops, the plate read from them, the violations of the ticket they
  /// came from), so the same widgets can show it. Its uid is the batch id.
  final ForensicTicket ticket;

  const HoldingBatch({
    required this.id,
    required this.fromUid,
    required this.fromTrack,
    required this.createdAt,
    required this.ticket,
  });

  factory HoldingBatch.fromJson(Map<String, dynamic> j) {
    final id = '${j['batch_id']}';
    return HoldingBatch(
      id: id,
      fromUid: '${j['from_uid'] ?? ''}',
      fromTrack: trackNumberOf(j['from_track']),
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      ticket: ForensicTicket.fromJson({...j, 'ticket_uid': id}),
    );
  }

  static List<HoldingBatch> parseList(Iterable<dynamic> list) => [
    for (final b in list)
      if (b is Map) HoldingBatch.fromJson(Map<String, dynamic>.from(b)),
  ];

  int get frameCount => ticket.frameCount;
}

/// What the backend answers to a Holding action: every ticket as it is now, what still waits in Holding, and (for a new
/// ticket) the ticket that was made.
class HoldingResult {
  final List<ForensicTicket> tickets;
  final List<HoldingBatch> holding;
  final String? ticketUid;

  const HoldingResult({required this.tickets, required this.holding, this.ticketUid});

  factory HoldingResult.fromJson(Map<String, dynamic> j) => HoldingResult(
    tickets: ForensicTicket.parseList((j['tickets'] as List?) ?? const []),
    holding: HoldingBatch.parseList((j['holding'] as List?) ?? const []),
    ticketUid: j['ticket_uid'] as String?,
  );
}
