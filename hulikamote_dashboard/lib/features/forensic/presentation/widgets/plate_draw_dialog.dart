import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/forensic_media.dart';
import '../../domain/forensic_models.dart';
import '../../domain/plate_tools_models.dart';
import '../../domain/review_controller.dart';
import 'fx.dart';

/// "Draw plate": drag a box around the plate on a photo of this ticket. The system reads what is inside; check or
/// fix the number and send it. It works whether or not the system found a plate by itself.
Future<void> showPlateDrawDialog(
  BuildContext context, {
  required ReviewController controller,
  required ForensicMedia media,
  required ForensicTicket ticket,
  ImageProvider Function(String name)? imageFor,
  VoidCallback? onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PlateDrawDialog(controller: controller, media: media, ticket: ticket, imageFor: imageFor, onSaved: onSaved),
  );
}

class _PlateDrawDialog extends StatefulWidget {
  const _PlateDrawDialog({required this.controller, required this.media, required this.ticket, this.imageFor, this.onSaved});

  final ReviewController controller;
  final ForensicMedia media;
  final ForensicTicket ticket;

  /// Replaced in tests; the app loads the photo from the backend.
  final ImageProvider Function(String name)? imageFor;
  final VoidCallback? onSaved;

  @override
  State<_PlateDrawDialog> createState() => _PlateDrawDialogState();
}

class _PlateDrawDialogState extends State<_PlateDrawDialog> {
  final _text = TextEditingController();
  late int _i = widget.controller.frameIndex.clamp(0, widget.ticket.frameCount - 1);

  Size? _picture; // the photo's own size, for its shape on screen
  ImageStream? _stream;
  ImageStreamListener? _listener;

  Offset? _from;
  Offset? _to;
  ({double w, double h})? _area;
  List<double>? _box;
  PlateBoxRead? _read;
  bool _reading = false;
  bool _saving = false;
  String? _error;

  EvidenceFrame get _frame => widget.ticket.frames[_i];

  /// The clean picture of the vehicle when the run saved one (bigger plate, no drawn lines), else the photo itself.
  String get _image => _frame.clean ?? _frame.file;

  /// Plates are kept the way the OCR writes them: capitals and digits only.
  String get _typed => _text.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener!);
    _text.dispose();
    super.dispose();
  }

  ImageProvider get _provider => (widget.imageFor ?? widget.media.evidence)(_image);

  void _load() {
    _stream?.removeListener(_listener!);
    _picture = null;
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _picture = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      },
      onError: (_, _) {
        if (mounted) setState(() => _error = 'This photo is no longer on disk.');
      },
    );
    _listener = listener;
    _stream = _provider.resolve(ImageConfiguration.empty)..addListener(listener);
  }

  void _go(int delta) {
    final next = _i + delta;
    if (next < 0 || next >= widget.ticket.frameCount) return;
    setState(() {
      _i = next;
      _clear();
      _error = null;
    });
    _load();
  }

  void _clear() {
    _from = _to = null;
    _box = null;
    _read = null;
    _text.clear();
  }

  void _finishDrag() {
    final from = _from, to = _to, area = _area;
    if (from == null || to == null || area == null) return;
    final box = boxFromDrag((x: from.dx, y: from.dy), (x: to.dx, y: to.dy), area);
    setState(() => _box = box);
    if (box != null) _readBox(box);
  }

  Future<void> _readBox(List<double> box) async {
    setState(() {
      _reading = true;
      _error = null;
      _read = null;
    });
    try {
      final read = await widget.controller.readPlateBox(_image, box);
      if (!mounted) return;
      setState(() {
        _read = read;
        _text.text = read.text;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _use() async {
    final plate = _typed;
    if (plate.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final c = widget.controller;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final crop = _read?.crop;
    final ok = await c.setPlate(widget.ticket, plate);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = c.error ?? 'Could not save the plate.';
      });
      return;
    }
    // The picture of the box and the right number go to the training data, like a plate typed by hand.
    if (crop != null) await c.sendPlateFeedbackImage(widget.ticket, crop, plate);
    widget.onSaved?.call();
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Plate sent: $plate'), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(Fx.s24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1000, maxHeight: size.height * 0.92),
        child: Padding(
          padding: const EdgeInsets.all(Fx.s16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Draw the plate', style: Fx.title(context)),
                  Text('Drag a box around the plate. Check the number, then send it.', style: Fx.caption(context)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous photo', onPressed: _i > 0 ? () => _go(-1) : null),
              Text('Photo ${_i + 1} of ${t.frameCount}', style: Fx.caption(context)),
              IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next photo', onPressed: _i < t.frameCount - 1 ? () => _go(1) : null),
              IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: Fx.s8),
            Expanded(child: Container(color: Colors.black, child: _canvas())),
            const SizedBox(height: Fx.s12),
            _result(context),
          ]),
        ),
      ),
    );
  }

  Widget _canvas() {
    final picture = _picture;
    if (picture == null) {
      return Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.white70)) : const CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: picture.width / picture.height,
        child: LayoutBuilder(builder: (context, box) {
          _area = (w: box.maxWidth, h: box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => setState(() {
              _clear();
              _from = _to = d.localPosition;
            }),
            onPanUpdate: (d) => setState(() {
              _to = d.localPosition;
              _box = boxFromDrag((x: _from!.dx, y: _from!.dy), (x: _to!.dx, y: _to!.dy), _area!, minPixels: 0);
            }),
            onPanEnd: (_) => _finishDrag(),
            child: Stack(fit: StackFit.expand, children: [
              Image(image: _provider, fit: BoxFit.fill, gaplessPlayback: true),
              CustomPaint(painter: _BoxPainter(_box)),
            ]),
          );
        }),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final read = _read;
    if (_reading) {
      return const Padding(padding: EdgeInsets.all(Fx.s8), child: LinearProgressIndicator());
    }
    if (read == null) {
      return Row(children: [
        Icon(_error == null ? Icons.crop_free : Icons.error_outline, size: 18, color: _error == null ? Fx.muted(context) : Fx.danger),
        const SizedBox(width: Fx.s8),
        Expanded(
          child: Text(
            _error ?? (_box == null ? 'No box yet. Press and drag on the photo.' : 'The box is too small. Draw it again.'),
            style: Fx.caption(context).copyWith(color: _error == null ? null : Fx.danger),
          ),
        ),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (read.crop != null)
        Container(
          width: 160,
          height: 64,
          margin: const EdgeInsets.only(right: Fx.s12),
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: FxImage(image: widget.media.thumb(read.crop!, width: 400), fit: BoxFit.contain, radius: 8, errorLabel: ''),
        ),
      SizedBox(
        width: 260,
        child: TextField(
          controller: _text,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
            LengthLimitingTextInputFormatter(12),
            TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
          ],
          style: Fx.plate.copyWith(fontSize: 22),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'Type the number you see',
            isDense: true,
            filled: true,
            fillColor: Fx.raised(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(Fx.radiusSm), borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => _use(),
        ),
      ),
      const SizedBox(width: Fx.s12),
      Expanded(
        child: Text(
          read.text.isEmpty ? 'The system could not read this box. Type the number you see.' : 'The system read this. Fix it if it is wrong.',
          style: Fx.caption(context),
        ),
      ),
      TextButton(onPressed: _saving ? null : () => setState(_clear), child: const Text('Draw again')),
      const SizedBox(width: Fx.s8),
      FilledButton.icon(
        onPressed: (_typed.isEmpty || _saving) ? null : _use,
        icon: const Icon(Icons.send, size: 18),
        label: const Text('Use this plate'),
      ),
    ]);
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.box);

  final List<double>? box;

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    if (b == null) return;
    final rect = Rect.fromLTRB(b[0] * size.width, b[1] * size.height, b[2] * size.width, b[3] * size.height);
    canvas.drawRect(rect, Paint()..color = Fx.warning.withValues(alpha: 0.18));
    canvas.drawRect(rect, Paint()
      ..color = Fx.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.box != box;
}
