import 'package:flutter/material.dart';

import '../../domain/time_format.dart';

/// A time that can be typed ("1:15.5"). It takes the new value when Enter is pressed or the box loses focus, and goes back
/// to the real value if what was typed is not a time.
class TimeField extends StatefulWidget {
  const TimeField({super.key, required this.label, required this.value, required this.enabled, required this.onSubmit, required this.onSetToPlayhead});

  final String label;
  final double value;
  final bool enabled;
  final bool Function(double seconds) onSubmit;
  final VoidCallback onSetToPlayhead;

  @override
  State<TimeField> createState() => TimeFieldState();
}

class TimeFieldState extends State<TimeField> {
  late final _controller = TextEditingController(text: formatClock(widget.value));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(TimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) _controller.text = formatClock(widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = parseClock(_controller.text);
    final changed = parsed != null && (parsed - widget.value).abs() > 0.0005;
    final accepted = changed && widget.onSubmit(parsed);
    _controller.text = formatClock(accepted ? parsed : widget.value);       // what was typed, or back to what it really is
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        suffixIcon: IconButton(
          tooltip: '${widget.label} = the playhead',
          icon: const Icon(Icons.my_location, size: 16),
          visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? widget.onSetToPlayhead : null,
        ),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}
