import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hulikamote_dashboard/core/services/api_service.dart';
import 'package:hulikamote_dashboard/core/utils/app_toast.dart';
import 'package:hulikamote_dashboard/features/forensic/presentation/widgets/fx.dart';
import 'package:hulikamote_dashboard/features/training/presentation/widgets/cloud_releaser_widget.dart';

import '../../domain/hub_models.dart';
import '../hub_format.dart';

const _categories = ['Vehicle Detectors', 'Plate Models', 'Helmet Detectors', 'Cabin Models', 'GAN Enhancers', 'Uncategorized'];

/// Bring in a model made elsewhere: a .zip holding the .onnx file (and optionally classes.txt or config.json).
/// It lands in the job's list as a version; it is not live until "Use this".
Future<void> showImportDialog(BuildContext context, HubJob job, {required VoidCallback onImported}) {
  return showDialog<void>(context: context, builder: (_) => _ImportDialog(job: job, onImported: onImported));
}

/// Publish the models in the backend's models folder as GitHub releases (the old Model page's "release" panel).
Future<void> showPublishDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 760,
        height: 640,
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))),
          const Expanded(child: CloudReleaserWidget()),
        ]),
      ),
    ),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.job, required this.onImported});

  final HubJob job;
  final VoidCallback onImported;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late String _category = uploadCategory(widget.job.job);
  String? _path, _error;
  bool _busy = false;

  String? get _name => _path?.split(RegExp(r'[\\/]')).last;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null || file.path == null) return;
    setState(() {
      _path = file.path;
      _error = null;
    });
  }

  Future<void> _import() async {
    if (_path == null || !_path!.toLowerCase().endsWith('.zip')) {
      setState(() => _error = 'Choose a .zip file that holds your .onnx model.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService().uploadModel(await File(_path!).readAsBytes(), _name!, _category);
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.show(context, 'Model imported. It shows in the list: press Use this to switch to it.');
      widget.onImported();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not import it: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import a model'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pick a .zip with your .onnx file inside. Add classes.txt or config.json if you have them.', style: Fx.caption(context)),
          const SizedBox(height: Fx.s16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'File it under', border: OutlineInputBorder()),
            items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: Fx.s12),
          OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: Text(_name ?? 'Choose .zip'), onPressed: _busy ? null : _pick),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Fx.s8), child: Text(_error!, style: TextStyle(color: Fx.danger, fontSize: 13))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Import'),
        ),
      ],
    );
  }
}
