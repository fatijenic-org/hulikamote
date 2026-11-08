import 'package:flutter/material.dart';

import '../domain/hub_models.dart';

/// One job's score: a detector's mAP as 0.71, the car matcher's "right car found" as 71%.
String fmtScore(HubJob job, double v) => job.scoreFormat == 'percent' ? '${(v * 100).round()}%' : v.toStringAsFixed(2);

/// Any of a version's numbers. Only the overall score follows the job's format; trust, coverage and ranking are shares.
String fmtStat(HubJob job, String key, double v) {
  if (key == 'cars') return v.round().toString();
  if (key == 'score') return fmtScore(job, v);
  return '${(v * 100).round()}%';
}

/// How much better (+) or worse (−) a version scores than the live one, in the job's own unit.
String? fmtDelta(HubJob job, double? live, double? other) {
  if (live == null || other == null) return null;
  final d = other - live;
  final percent = job.scoreFormat == 'percent';
  final shown = percent ? (d * 100).round().abs().toString() : d.abs().toStringAsFixed(2);
  if (num.parse(shown) == 0) return 'same as live';
  return '${d >= 0 ? '+' : '−'}$shown${percent ? ' pts' : ''} vs live';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String fmtDate(double? epochSeconds) {
  if (epochSeconds == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());
  return '${d.day} ${_months[d.month - 1]}';
}

IconData jobIcon(String job) => switch (job) {
      'vehicles' => Icons.directions_car_outlined,
      'plate' => Icons.pin_outlined,
      'helmet' => Icons.sports_motorsports_outlined,
      'cabin' => Icons.airline_seat_recline_normal_outlined,
      'reader' => Icons.text_fields,
      'matcher' => Icons.compare_arrows,
      _ => Icons.auto_fix_high,
    };

/// The folder name the upload endpoint files a model under.
String uploadCategory(String job) => switch (job) {
      'vehicles' => 'Vehicle Detectors',
      'plate' => 'Plate Models',
      'helmet' => 'Helmet Detectors',
      'cabin' => 'Cabin Models',
      'enhancer' => 'GAN Enhancers',
      _ => 'Uncategorized',
    };
