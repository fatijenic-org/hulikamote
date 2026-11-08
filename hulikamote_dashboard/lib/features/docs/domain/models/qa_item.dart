class QaItem {
  final String id;
  final String q;
  final String a;
  final List<String> tags;
  final String created;
  final String updated;

  const QaItem({
    required this.id,
    required this.q,
    required this.a,
    required this.tags,
    required this.created,
    required this.updated,
  });

  bool get isAnswered => a.trim().isNotEmpty;

  QaItem copyWith({
    String? q,
    String? a,
    List<String>? tags,
    String? updated,
  }) {
    return QaItem(
      id: id,
      q: q ?? this.q,
      a: a ?? this.a,
      tags: tags ?? this.tags,
      created: created,
      updated: updated ?? this.updated,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'q': q,
    'a': a,
    'tags': tags,
    'created': created,
    'updated': updated,
  };

  factory QaItem.fromJson(Map<String, dynamic> json) => QaItem(
    id: json['id'] as String? ?? '',
    q: json['q'] as String? ?? '',
    a: json['a'] as String? ?? '',
    tags: ((json['tags'] as List<dynamic>?) ?? []).map((t) => t.toString()).toList(),
    created: json['created'] as String? ?? '',
    updated: json['updated'] as String? ?? '',
  );
}
