/// The few numbers every screen shares, so spacing and corners look the same everywhere.
class Sp {
  Sp._();

  static const double x1 = 4, x2 = 8, x3 = 12, x4 = 16, x5 = 20, x6 = 24, x8 = 32, x10 = 40;

  /// Sides of a page.
  static const double page = 20;
}

class Rd {
  Rd._();

  static const double sm = 8, md = 12, lg = 16, xl = 24, pill = 999;
}

/// The smallest a tappable thing may be (Material and WCAG both ask for about this).
const double minTap = 48;

const Duration quick = Duration(milliseconds: 180);
