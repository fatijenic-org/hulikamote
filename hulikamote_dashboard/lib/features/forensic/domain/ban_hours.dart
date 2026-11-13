/// The hours a rule such as the truck ban holds, e.g. `[['06:00', '09:00'], ['16:00', '19:00']]`.
///
/// Shared by the hours editor, the "time of the video" card and the ticket text. The backend (engine/video_clock.py) is the one
/// that judges each frame; this only shows and edits.
class BanHours {
  BanHours._();

  /// What the "Use example hours" button puts in. An EXAMPLE only (the usual rush hours); the real hours of a city are in its ordinance.
  static const example = <List<String>>[
    ['06:00', '09:00'],
    ['16:00', '19:00'],
  ];

  /// Most windows one rule can have in the editor.
  static const maxWindows = 3;

  /// Every half hour of the day, "00:00" to "23:30".
  static final List<String> options = [for (var m = 0; m < 1440; m += 30) _hhmm(m)];

  static String _hhmm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// "06:00" -> 360 (minutes after midnight); null when it is not a time of day.
  static int? minutes(Object? text) {
    final m = RegExp(r'^\s*(\d{1,2})(?::(\d{2}))?\s*$').firstMatch('$text');
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2) ?? '0');
    if (min > 59 || h > 24 || (h == 24 && min > 0)) return null;
    return h * 60 + min;
  }

  /// "16:30" -> "4:30 PM".
  static String label(String hhmm) {
    final total = minutes(hhmm);
    return total == null ? hhmm : _words(total);
  }

  /// A moment as the clock of a wall shows it: "7:42 AM".
  static String clock(DateTime t) => _words(t.hour * 60 + t.minute);

  static String _words(int total) {
    final h = (total ~/ 60) % 24, m = total % 60;
    return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  /// The windows that can be used: pairs of two different times of day. A start after the end runs past midnight.
  static List<(int, int)> parse(List? raw) {
    final out = <(int, int)>[];
    for (final pair in raw ?? const []) {
      if (pair is! List || pair.length < 2) continue;
      final a = minutes(pair[0]), b = minutes(pair[1]);
      if (a != null && b != null && a != b) out.add((a, b));
    }
    return out;
  }

  /// Is the time of day of [t] inside any window (start included, end excluded)?
  static bool contains(List? raw, DateTime t) {
    final minute = t.hour * 60 + t.minute;
    for (final (a, b) in parse(raw)) {
      if (a < b ? (minute >= a && minute < b) : (minute >= a || minute < b)) return true;
    }
    return false;
  }

  /// "6:00 AM–9:00 AM and 4:00 PM–7:00 PM", or '' when there are no usable windows.
  static String describe(List? raw) => [for (final (a, b) in parse(raw)) '${_words(a)}–${_words(b)}'].join(' and ');
}
