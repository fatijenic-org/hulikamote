/// A notice the system wrote to the motorist when a ticket was confirmed (the same text the e-mail carries).
class Notice {
  const Notice({required this.id, required this.subject, required this.body, required this.createdAt, this.frames = const []});

  final String id;
  final String subject;
  final String body;

  /// The server's ISO time, kept as text: it is also what the app sends back as "newer than this".
  final String createdAt;

  /// File names of the ticket's photos on the laptop.
  final List<String> frames;

  factory Notice.fromJson(Map<String, dynamic> json) => Notice(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        frames: [for (final f in json['frames'] as List? ?? const []) f as String],
      );

  Map<String, dynamic> toJson() => {'id': id, 'subject': subject, 'body': body, 'created_at': createdAt, 'frames': frames};

  DateTime? get time => DateTime.tryParse(createdAt)?.toLocal();

  /// "No Helmet · ABC 1234" instead of "Traffic violation recorded: No Helmet (ABC 1234)".
  String get title {
    final match = RegExp(r'^Traffic violation recorded: (.+?) \((.+)\)$').firstMatch(subject);
    return match == null ? subject : '${match.group(1)} \u00b7 ${match.group(2)}';
  }
}
