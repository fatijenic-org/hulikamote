/// Small pure rules copied from the Python engine, so the Detection Pipeline
/// page animates the same logic the backend runs instead of a lookalike.
///
/// Each function names the Python file it mirrors. Keep them in step with the
/// backend; `detection_pipeline_rules_test.dart` pins the behaviour.
library;

import 'dart:math' as math;

/// engine/yolo_inference.py: CONFIDENCE_THRESHOLD and CLASS_CONFIDENCE.
const double kDefaultCutoff = 0.45;
const double kMotorcycleCutoff = 0.25;

/// Whether the primary detector keeps a box (motorcycles have their own,
/// lower cutoff because from a CCTV angle they are hard to be sure of).
bool keepsDetection({
  required String cls,
  required double confidence,
  double cutoff = kDefaultCutoff,
}) =>
    confidence >= (cls == 'motorcycle' ? kMotorcycleCutoff : cutoff);

/// engine/ledger.py `vote`: flag when `bad` was seen in at least [share] of the
/// last 10 looks, and at least [minLooks] looks exist.
bool voteVerdict(
  List<bool> looks, {
  required int minLooks,
  required double share,
}) {
  final recent =
      looks.length > 10 ? looks.sublist(looks.length - 10) : looks;
  if (recent.length < minLooks) return false;
  final bad = recent.where((b) => b).length;
  return bad >= (share * recent.length).ceil();
}

/// engine/violations/swerving.py `count_swings`: direction reversals in a 1-D
/// signal, ignoring moves smaller than [amplitude].
int countSwings(List<double> values, double amplitude) {
  if (values.isEmpty) return 0;
  var extreme = values.first;
  var trend = 0;
  var reversals = 0;
  for (final v in values.skip(1)) {
    if (trend == 0) {
      if ((v - extreme).abs() >= amplitude) {
        trend = v > extreme ? 1 : -1;
        extreme = v;
      }
    } else if (trend * (v - extreme) > 0) {
      extreme = v; // still moving the same way: new extreme
    } else if ((v - extreme).abs() >= amplitude) {
      trend = -trend; // moved back far enough: a reversal
      extreme = v;
      reversals++;
    }
  }
  return reversals;
}

/// engine/traffic_light.py `is_blinking`: a steady on/off rhythm of 0.5 to 3 Hz
/// (period 0.33 to 2.0 s). [samples] are (time in s, amber share) pairs.
bool isBlinking(List<(double, double)> samples) {
  if (samples.length < 6 || samples.last.$1 - samples.first.$1 < 1.0) {
    return false;
  }
  final vals = [for (final s in samples) s.$2];
  final lo = vals.reduce(math.min);
  final hi = vals.reduce(math.max);
  if (hi - lo < 0.004) return false;
  final cut = lo + 0.5 * (hi - lo);
  final on = [for (final v in vals) v > cut];
  final rises = <double>[
    for (var k = 1; k < samples.length; k++)
      if (on[k] && !on[k - 1]) samples[k].$1,
  ];
  if (rises.length < 2) return false;
  final period = (rises.last - rises.first) / (rises.length - 1);
  return period >= 0.33 && period <= 2.0;
}

/// engine/violations/geometry.py `point_in_polygon` (ray casting).
bool pointInPolygon(double x, double y, List<(double, double)> polygon) {
  var inside = false;
  var j = polygon.length - 1;
  for (var i = 0; i < polygon.length; i++) {
    final (xi, yi) = polygon[i];
    final (xj, yj) = polygon[j];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

/// engine/violations/no_plate.py: a look only counts when it was fair.
/// A motorcycle must show its rear (moving up the image).
bool isFairPlateLook({
  required bool classSettled,
  required double boxWidthPx,
  required bool isMotorcycle,
  required bool movingUp,
}) {
  if (!classSettled || boxWidthPx < 60) return false;
  return !isMotorcycle || movingUp;
}

/// engine/pipeline.py `_extract_plate_text` for plate_format "ph_standard":
/// slots 1-3 are letters, slots 4-7 are digits; look-alikes are swapped.
const Map<String, String> _intToChar = {
  '0': 'O', '1': 'I', '3': 'J', '4': 'A', '6': 'G', '5': 'S', '8': 'B',
  '2': 'Z', '7': 'T', '9': 'P',
};
const Map<String, String> _charToInt = {
  'O': '0', 'I': '1', 'J': '3', 'A': '4', 'G': '6', 'S': '5', 'B': '8',
  'Z': '2', 'Q': '0', 'D': '0', 'T': '7', 'U': '0', 'Y': '7', 'P': '0',
  'F': '5', 'L': '4',
};

String cleanPhPlate(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (i <= 2) {
      out.write(_intToChar[ch] ?? ch);
    } else if (i <= 6) {
      out.write(_charToInt[ch] ?? ch);
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}
