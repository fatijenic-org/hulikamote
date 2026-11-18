import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';
import '../../data/camera_api.dart';

/// "Connect phone", one click: the backend finds the HULI-KAMOTE Camera app by itself and makes it the live camera. This dialog
/// shows that it is looking, then what it found (and closes by itself) or what to do (with "Try again"). Pops `true` when the
/// phone is the live camera now.
class PhoneConnectDialog extends StatefulWidget {
  const PhoneConnectDialog({super.key, required this.api});

  final CameraApi api;

  @override
  State<PhoneConnectDialog> createState() => _PhoneConnectDialogState();
}

class _PhoneConnectDialogState extends State<PhoneConnectDialog> {
  bool _busy = true;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.api.connectPhone();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
      if (result['ok'] == true) {
        await Future<void>.delayed(const Duration(milliseconds: 900));       // long enough to read what was found
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The backend did not answer: ${'$e'.replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  bool get _found => _result?['ok'] == true;

  @override
  Widget build(BuildContext context) {
    final steps = [for (final s in (_result?['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    return AlertDialog(
      title: const Text('Connect phone'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_busy) ...[
            const Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
              SizedBox(width: Fx.s12),
              Expanded(child: Text('Looking for the phone…')),
            ]),
            const SizedBox(height: Fx.s16),
            Text(
              'On the phone: open HULI-KAMOTE Camera (it starts by itself).\nThe phone and this laptop must be on the same Wi-Fi, or USB tethering must be on.',
              style: Fx.caption(context),
            ),
          ] else if (_found) ...[
            Row(children: [
              const Icon(Icons.check_circle, color: Fx.success),
              const SizedBox(width: Fx.s12),
              Expanded(child: Text('${_result!['message']}', style: Fx.body(context))),
            ]),
            const SizedBox(height: Fx.s8),
            Text('Starting the live monitor with the phone…', style: Fx.caption(context)),
          ] else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: Fx.warning),
              const SizedBox(width: Fx.s12),
              Expanded(child: Text(_error ?? '${_result?['message'] ?? 'No phone found.'}', style: Fx.body(context))),
            ]),
            if (steps.isNotEmpty) ...[
              const SizedBox(height: Fx.s16),
              Text('WHAT WAS LOOKED AT', style: Fx.label(context)),
              const SizedBox(height: Fx.s4),
              for (final s in steps)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(s['ok'] == true ? Icons.check : Icons.close, size: 14, color: s['ok'] == true ? Fx.success : Fx.muted(context)),
                    const SizedBox(width: Fx.s8),
                    Expanded(child: Text('${s['text']}', style: Fx.caption(context))),
                  ]),
                ),
            ],
          ],
        ]),
      ),
      actions: [
        if (!_busy && !_found) FilledButton(key: const ValueKey('phone-try-again'), onPressed: _run, child: const Text('Try again')),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(_found ? 'Close' : 'Cancel')),
      ],
    );
  }
}
