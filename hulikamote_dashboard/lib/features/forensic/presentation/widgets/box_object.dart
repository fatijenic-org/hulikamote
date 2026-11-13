import 'dart:ui';

import '../../data/object_previews.dart';

/// A box of Illegal parking / Illegal loading as the painter draws it.
class BoxObject {
  const BoxObject({required this.box, required this.kind, required this.at, required this.selected, this.preview});

  final Rect box; // the banned area, 0..1
  final String kind; // sign | hydrant | fire_station | corner | driveway | no_loading
  final Offset at; // where the object stands, 0..1
  final bool selected;
  final ObjectPreview? preview; // null until the backend has drawn the object
}
