/// 75.5 -> "1:15.5", 3725 -> "1:02:05.0". [tenths] false drops the ".5".
String formatClock(double seconds, {bool tenths = true}) {
  final total = seconds < 0 ? 0.0 : seconds;
  final whole = total.floor();
  final h = whole ~/ 3600, m = (whole % 3600) ~/ 60, s = whole % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  final clock = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return tenths ? '$clock.${((total - whole) * 10).floor()}' : clock;
}

/// What a person types for a time: "75", "1:15", "1:15.5", "0:01:15". Null when it is not a time.
double? parseClock(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.trim().isEmpty)) return null;
  var seconds = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final value = double.tryParse(parts[i].trim());
    if (value == null || value < 0 || value.isNaN || value.isInfinite) return null;
    final isLast = i == parts.length - 1;
    if (!isLast && value != value.truncateToDouble()) return null;      // only the seconds may have a fraction
    seconds = seconds * 60 + value;
  }
  return seconds;
}
