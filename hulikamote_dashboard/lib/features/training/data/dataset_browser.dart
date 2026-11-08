import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../forensic/data/harvest_source.dart';
import '../../forensic/domain/harvest_models.dart';

/// The picture files of a model's ORIGINAL dataset, by split. Names only: nothing is read until a picture is shown.
class DatasetListing {
  const DatasetListing(this.bySplit);

  /// split (train / val / test, or `all`) -> file names, sorted. For car-matching data a name is `identity/file.jpg`.
  final Map<String, List<String>> bySplit;

  int get total => bySplit.values.fold(0, (a, l) => a + l.length);

  /// The source of a picture: the part of its file name before "__"; hand-made pictures have none ("legacy").
  static String sourceOf(String name) {
    final file = name.split('/').last;
    final i = file.indexOf('__');
    return i > 0 ? file.substring(0, i) : 'legacy';
  }

  /// Pictures per source, biggest first.
  List<MapEntry<String, int>> get sources {
    final counts = <String, int>{};
    for (final names in bySplit.values) {
      for (final n in names) {
        counts.update(sourceOf(n), (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}

/// Where the Training Studio gets the original pictures of a model (and their boxes) from.
abstract class DatasetBrowser {
  /// The pictures of the model's original dataset, or null when it has none on disk.
  /// Throws [HarvestException] when the Training Lab folder cannot be found.
  Future<DatasetListing?> list(String modelKey, {bool refresh = false});

  ImageProvider image(String modelKey, String split, String name, {int? width});

  /// The boxes drawn for that picture (YOLO files, normalised); empty when it has none.
  Future<List<HarvestBox>> boxes(String modelKey, String split, String name);

  /// The text label of a plate crop; null for everything else.
  Future<String?> text(String modelKey, String split, String name);
}

class _Layout {
  const _Layout(this.images, {this.labels, this.nested = false, this.text = false});

  final String images; // folder with <split>/<file> (or <identity>/<file> when nested), relative to the lab
  final String? labels; // folder with <split>/<stem>.txt
  final bool nested;
  final bool text;
}

/// Reads `training_lab/datasets` straight from disk (the dashboard and the lab live on the same computer).
class LocalDatasetBrowser implements DatasetBrowser {
  LocalDatasetBrowser({LocalHarvestSource? lab}) : _lab = lab ?? LocalHarvestSource();

  final LocalHarvestSource _lab;
  final Map<String, DatasetListing?> _cache = {};

  static const _layouts = {
    'plate_specialist': _Layout('datasets/plate_specialist/images', labels: 'datasets/plate_specialist/labels'),
    'helmet_specialist': _Layout('datasets/helmet_specialist/images', labels: 'datasets/helmet_specialist/labels'),
    'cabin_specialist': _Layout('datasets/cabin_specialist/images', labels: 'datasets/cabin_specialist/labels'),
    'primary_anchor': _Layout('datasets/primary_anchor/images', labels: 'datasets/primary_anchor/labels'),
    'plate_ocr': _Layout('datasets/plate_ocr/images', labels: 'datasets/plate_ocr/labels', text: true),
    'plate_enhancer': _Layout('datasets/sr_plates/clean'),
    'reid': _Layout('datasets/reid_public/images/simveri', nested: true),
  };

  static bool _isImage(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png') || p.endsWith('.webp') || p.endsWith('.bmp');
  }

  static String _base(String path) => path.replaceAll('\\', '/').split('/').last;

  String _requireLab() {
    final lab = _lab.findLab();
    if (lab == null) {
      throw HarvestException('Could not find the training_lab folder. Start the dashboard from the project, or set HULIKAMOTE_LAB.');
    }
    return lab;
  }

  @override
  Future<DatasetListing?> list(String modelKey, {bool refresh = false}) async {
    final layout = _layouts[modelKey];
    if (layout == null) return null;
    if (!refresh && _cache.containsKey(modelKey)) return _cache[modelKey];
    final root = Directory('${_requireLab()}/${layout.images}');
    if (!root.existsSync()) return _cache[modelKey] = null;
    final out = <String, List<String>>{};
    if (layout.nested) {
      final names = <String>[];
      await for (final dir in root.list()) {
        if (dir is! Directory) continue;
        final id = _base(dir.path);
        await for (final f in dir.list()) {
          if (f is File && _isImage(f.path)) names.add('$id/${_base(f.path)}');
        }
      }
      if (names.isNotEmpty) out['all'] = names..sort();
    } else {
      for (final split in const ['train', 'val', 'test']) {
        final dir = Directory('${root.path}/$split');
        if (!dir.existsSync()) continue;
        final names = <String>[];
        await for (final f in dir.list()) {
          if (f is File && _isImage(f.path)) names.add(_base(f.path));
        }
        if (names.isNotEmpty) out[split] = names..sort();
      }
    }
    return _cache[modelKey] = out.isEmpty ? null : DatasetListing(out);
  }

  String _path(_Layout layout, String split, String name) =>
      layout.nested ? '${_requireLab()}/${layout.images}/$name' : '${_requireLab()}/${layout.images}/$split/$name';

  @override
  ImageProvider image(String modelKey, String split, String name, {int? width}) {
    final provider = FileImage(File(_path(_layouts[modelKey]!, split, name)));
    return width == null ? provider : ResizeImage(provider, width: width);
  }

  Future<String?> _label(String modelKey, String split, String name) async {
    final layout = _layouts[modelKey];
    if (layout?.labels == null) return null;
    final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final file = File('${_requireLab()}/${layout!.labels}/$split/$stem.txt');
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<HarvestBox>> boxes(String modelKey, String split, String name) async {
    if (_layouts[modelKey]?.text == true) return const [];
    final raw = await _label(modelKey, split, name);
    if (raw == null) return const [];
    final out = <HarvestBox>[];
    for (final line in raw.split('\n')) {
      final p = line.trim().split(RegExp(r'\s+'));
      if (p.length != 5) continue;
      final v = [for (final s in p) double.tryParse(s)];
      if (v.contains(null)) continue;
      out.add(HarvestBox(cls: v[0]!.toInt(), cx: v[1]!, cy: v[2]!, w: v[3]!, h: v[4]!));
    }
    return out;
  }

  @override
  Future<String?> text(String modelKey, String split, String name) async {
    if (_layouts[modelKey]?.text != true) return null;
    final raw = await _label(modelKey, split, name);
    if (raw == null) return null;
    final first = raw.split('\n').first.trim();
    final i = first.indexOf(' ');
    return i > 0 ? first.substring(i + 1).trim() : null;
  }
}
