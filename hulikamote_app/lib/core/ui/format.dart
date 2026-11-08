/// Dates and times in plain words (no extra package needed).
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Oct 29, 2026"
String dateOf(DateTime t) => '${_months[t.month - 1]} ${t.day}, ${t.year}';

/// "3:27 PM"
String timeOf(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Oct 29, 2026 · 3:27 PM", or the raw text when it is not a time.
String dateTimeOf(DateTime? t, [String fallback = '']) => t == null ? fallback : '${dateOf(t)} · ${timeOf(t)}';

/// "Today", "Yesterday", or "Wed, Oct 28".
String dayHeader(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final gap = today.difference(day).inDays;
  if (gap == 0) return 'Today';
  if (gap == 1) return 'Yesterday';
  return '${_days[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}${t.year == now.year ? '' : ', ${t.year}'}';
}

/// "just now", "5 min ago", "2 h ago", or the date.
String ago(DateTime t, DateTime now) {
  final gap = now.difference(t);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  return dateOf(t);
}
