import 'package:flutter/material.dart';

class DocScene {
  final double w;
  final double h;
  final String aria;
  final List<DocPrimitive> primitives;

  const DocScene({
    required this.w,
    required this.h,
    required this.aria,
    required this.primitives,
  });

  factory DocScene.fromJson(Map<String, dynamic> json) {
    final w = (json['w'] as num?)?.toDouble() ?? 760.0;
    final h = (json['h'] as num?)?.toDouble() ?? 240.0;
    final aria = json['aria'] as String? ?? '';
    final primsRaw = (json['primitives'] as List<dynamic>?) ?? [];
    final primitives = <DocPrimitive>[];

    for (final item in primsRaw) {
      if (item is Map<String, dynamic>) {
        final p = DocPrimitive.fromJson(item);
        if (p != null) primitives.add(p);
      }
    }

    return DocScene(
      w: w,
      h: h,
      aria: aria,
      primitives: primitives,
    );
  }
}

sealed class DocPrimitive {
  const DocPrimitive();

  static DocPrimitive? fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    switch (type) {
      case 'rect':
        return RectPrimitive(
          x: (json['x'] as num?)?.toDouble() ?? 0.0,
          y: (json['y'] as num?)?.toDouble() ?? 0.0,
          w: (json['w'] as num?)?.toDouble() ?? 0.0,
          h: (json['h'] as num?)?.toDouble() ?? 0.0,
          rx: (json['rx'] as num?)?.toDouble() ?? 0.0,
          role: json['role'] as String? ?? 'bx',
          dash: json['dash'] as bool? ?? false,
        );
      case 'line':
        return LinePrimitive(
          x1: (json['x1'] as num?)?.toDouble() ?? 0.0,
          y1: (json['y1'] as num?)?.toDouble() ?? 0.0,
          x2: (json['x2'] as num?)?.toDouble() ?? 0.0,
          y2: (json['y2'] as num?)?.toDouble() ?? 0.0,
          role: json['role'] as String? ?? 'ar',
          arrow: json['arrow'] as bool? ?? false,
          dash: json['dash'] as bool? ?? false,
          width: (json['width'] as num?)?.toDouble() ?? 1.6,
        );
      case 'circle':
        return CirclePrimitive(
          cx: (json['cx'] as num?)?.toDouble() ?? 0.0,
          cy: (json['cy'] as num?)?.toDouble() ?? 0.0,
          r: (json['r'] as num?)?.toDouble() ?? 0.0,
          role: json['role'] as String? ?? 'circle',
          fillSurface: json['fill_surface'] as bool? ?? false,
        );
      case 'polygon':
        final rawPts = (json['points'] as List<dynamic>?) ?? [];
        final points = <Offset>[];
        for (final pt in rawPts) {
          if (pt is List && pt.length >= 2) {
            points.add(Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble()));
          }
        }
        return PolygonPrimitive(
          points: points,
          role: json['role'] as String? ?? 'zone',
        );
      case 'polyline':
        final rawPts = (json['points'] as List<dynamic>?) ?? [];
        final points = <Offset>[];
        for (final pt in rawPts) {
          if (pt is List && pt.length >= 2) {
            points.add(Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble()));
          }
        }
        return PolylinePrimitive(
          points: points,
          role: json['role'] as String? ?? 'path',
          dash: json['dash'] as bool? ?? false,
        );
      case 'path':
        return PathPrimitive(
          d: json['d'] as String? ?? '',
          role: json['role'] as String? ?? 'path',
          dash: json['dash'] as bool? ?? false,
          width: (json['width'] as num?)?.toDouble() ?? 2.0,
        );
      case 'text':
        return TextPrimitive(
          x: (json['x'] as num?)?.toDouble() ?? 0.0,
          y: (json['y'] as num?)?.toDouble() ?? 0.0,
          text: json['text'] as String? ?? '',
          role: json['role'] as String? ?? 'sk',
          anchor: json['anchor'] as String? ?? 'start',
        );
      default:
        return null;
    }
  }
}

class RectPrimitive extends DocPrimitive {
  final double x;
  final double y;
  final double w;
  final double h;
  final double rx;
  final String role;
  final bool dash;

  const RectPrimitive({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rx = 0.0,
    required this.role,
    this.dash = false,
  });
}

class LinePrimitive extends DocPrimitive {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String role;
  final bool arrow;
  final bool dash;
  final double width;

  const LinePrimitive({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.role,
    this.arrow = false,
    this.dash = false,
    this.width = 1.6,
  });
}

class CirclePrimitive extends DocPrimitive {
  final double cx;
  final double cy;
  final double r;
  final String role;
  final bool fillSurface;

  const CirclePrimitive({
    required this.cx,
    required this.cy,
    required this.r,
    required this.role,
    this.fillSurface = false,
  });
}

class PolygonPrimitive extends DocPrimitive {
  final List<Offset> points;
  final String role;

  const PolygonPrimitive({
    required this.points,
    required this.role,
  });
}

class PolylinePrimitive extends DocPrimitive {
  final List<Offset> points;
  final String role;
  final bool dash;

  const PolylinePrimitive({
    required this.points,
    required this.role,
    this.dash = false,
  });
}

class PathPrimitive extends DocPrimitive {
  final String d;
  final String role;
  final bool dash;
  final double width;

  const PathPrimitive({
    required this.d,
    required this.role,
    this.dash = false,
    this.width = 2.0,
  });
}

class TextPrimitive extends DocPrimitive {
  final double x;
  final double y;
  final String text;
  final String role;
  final String anchor;

  const TextPrimitive({
    required this.x,
    required this.y,
    required this.text,
    required this.role,
    this.anchor = 'start',
  });
}
