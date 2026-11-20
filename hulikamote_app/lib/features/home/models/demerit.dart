import 'violation.dart';

/// This motorist's demerit counter: one point for each confirmed ticket. A ticket whose appeal a reviewer accepted is cancelled and
/// does not count. It is the same rule the laptop uses (backend: demerit_points.py), worked out here from the tickets and appeals
/// the phone already has, so it also shows when the phone is offline. It carries no legal weight.
class Demerit {
  const Demerit({required this.points, required this.byClass, required this.byPlate, required this.cancelled});

  /// Tickets that count.
  final int points;

  /// Violation class (like `no_helmet`) -> points, the most first.
  final Map<String, int> byClass;

  /// Plate -> points, the most first. Only filled when the account has tickets on more than one plate.
  final Map<String, int> byPlate;

  /// Tickets that do not count because their appeal was accepted.
  final int cancelled;

  /// `appeals` maps a ticket id to pending / accepted / rejected.
  factory Demerit.of(List<Violation> tickets, Map<String, String> appeals) {
    final classes = <String, int>{};
    final plates = <String, int>{};
    final shown = <String, String>{};          // plate key -> how to show it
    var cancelled = 0;
    for (final t in tickets) {
      if (appeals[t.id] == 'accepted') {
        cancelled++;
        continue;
      }
      classes[t.cls] = (classes[t.cls] ?? 0) + 1;
      final key = t.plate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (key.isNotEmpty) {
        plates[key] = (plates[key] ?? 0) + 1;
        shown.putIfAbsent(key, () => t.plate.toUpperCase());
      }
    }
    return Demerit(
      points: classes.values.fold(0, (a, b) => a + b),
      byClass: _mostFirst(classes),
      byPlate: plates.length > 1 ? _mostFirst({for (final e in plates.entries) shown[e.key]!: e.value}) : const {},
      cancelled: cancelled,
    );
  }

  static Map<String, int> _mostFirst(Map<String, int> counts) {
    final entries = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    return {for (final e in entries) e.key: e.value};
  }
}
