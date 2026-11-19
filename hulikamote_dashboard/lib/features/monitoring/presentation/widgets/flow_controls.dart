import 'package:flutter/material.dart';

import '../../../forensic/presentation/widgets/fx.dart';

/// The controls over the live picture: a "Layers" checklist (road zones, road arrows, learned flow arrows: what is drawn over the video),
/// the Counterflow demo reversal (the opposite direction counts as legal, so ordinary traffic is flagged), and "learn the flow again".
/// [flow] is what the backend reports in the camera status: `learning`, `counterflow`, `reversed`, `cells`.
class FlowControls extends StatefulWidget {
  const FlowControls({
    super.key,
    required this.flow,
    required this.showArrows,
    required this.busy,
    required this.onShowArrows,
    required this.onReverse,
    required this.onRelearn,
    required this.showRoadArrows,
    required this.onShowRoadArrows,
    required this.showRoadZones,
    required this.onShowRoadZones,
  });

  final Map flow;

  /// The arrows of the flow the camera learned.
  final bool showArrows;
  final bool busy;
  final ValueChanged<bool> onShowArrows;
  final ValueChanged<bool> onReverse;
  final VoidCallback onRelearn;

  /// The arrows of the incoming / outgoing sides of the road (from the setup).
  final bool showRoadArrows;
  final ValueChanged<bool> onShowRoadArrows;

  /// The outlines and labels of the set-up and learned zones.
  final bool showRoadZones;
  final ValueChanged<bool> onShowRoadZones;

  @override
  State<FlowControls> createState() => _FlowControlsState();
}

class _FlowControlsState extends State<FlowControls> {
  final LayerLink _link = LayerLink();
  final GlobalKey _button = GlobalKey();
  OverlayEntry? _menu;

  // What the checklist shows: kept here so it changes at once (the open menu is not rebuilt by the screen).
  late bool _zones = widget.showRoadZones, _roadArrows = widget.showRoadArrows, _flowArrows = widget.showArrows;

  @override
  void didUpdateWidget(covariant FlowControls old) {
    super.didUpdateWidget(old);
    _zones = widget.showRoadZones;
    _roadArrows = widget.showRoadArrows;
    _flowArrows = widget.showArrows;
    _menu?.markNeedsBuild();
  }

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  void _close() {
    _menu?.remove();
    _menu = null;
    if (mounted) setState(() {});
  }

  /// Opens the checklist above the button when the button is in the lower half of the screen, below it otherwise.
  void _open() {
    if (_menu != null) {
      _close();
      return;
    }
    final box = _button.currentContext?.findRenderObject() as RenderBox?;
    final up = box == null || box.localToGlobal(Offset.zero).dy > MediaQuery.sizeOf(context).height / 2;
    _menu = OverlayEntry(builder: (_) => _menuBody(up));
    Overlay.of(context).insert(_menu!);
    setState(() {});
  }

  void _set(void Function() change, VoidCallback notify) {
    setState(change);
    notify();
    _menu?.markNeedsBuild();
  }

  Widget _menuBody(bool up) {
    final learning = widget.flow['learning'] == true;
    Widget item(Key key, String title, String hint, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
      key: key,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(title),
      subtitle: Text(hint, style: const TextStyle(fontSize: 11)),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
    );
    return Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _close)),
      CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: up ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: up ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, up ? -6 : 6),
        child: Align(
          alignment: up ? Alignment.bottomLeft : Alignment.topLeft,
          child: Material(
            key: const ValueKey('layers-menu'),
            elevation: 8,
            borderRadius: BorderRadius.circular(Fx.radiusSm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: IntrinsicWidth(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  item(const ValueKey('layer-zones'), 'Road zones', 'Outlines and names of the zones', _zones,
                      (v) => _set(() => _zones = v, () => widget.onShowRoadZones(v))),
                  item(const ValueKey('layer-road-arrows'), 'Road arrows', 'Incoming and outgoing sides of the road', _roadArrows,
                      (v) => _set(() => _roadArrows = v, () => widget.onShowRoadArrows(v))),
                  if (learning)
                    item(const ValueKey('layer-flow-arrows'), 'Flow arrows', 'The traffic direction the camera learned', _flowArrows,
                        (v) => _set(() => _flowArrows = v, () => widget.onShowArrows(v))),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final learning = widget.flow['learning'] == true;
    final counterflow = widget.flow['counterflow'] == true;
    final reversed = widget.flow['reversed'] == true;
    final cells = (widget.flow['cells'] as num?)?.toInt() ?? 0;
    final busy = widget.busy;
    const note = TextStyle(color: Colors.white70, fontSize: 12);
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(Fx.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Fx.s8, vertical: Fx.s4),
        child: Wrap(spacing: Fx.s8, runSpacing: Fx.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          CompositedTransformTarget(
            link: _link,
            child: ActionChip(
              key: _button,
              avatar: const Icon(Icons.layers_outlined, size: 16),
              label: const Text('Layers'),
              tooltip: 'Choose what is drawn over the video: road zones, road arrows, flow arrows',
              onPressed: _open,
            ),
          ),
          if (counterflow)
            FilterChip(
              key: const ValueKey('flow-reverse-toggle'),
              avatar: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Reverse flow (demo)'),
              tooltip: 'Demo: the opposite direction counts as legal, so ordinary traffic is flagged as counterflow. '
                  'Tickets made now are tests: do not confirm or send them.',
              selected: reversed,
              onSelected: busy ? null : widget.onReverse,
            ),
          if (learning) Text(cells == 0 ? 'Learning the flow…' : 'Flow learned', style: note),
          if (learning)
            IconButton(
              key: const ValueKey('flow-relearn'),
              tooltip: 'Learn the flow again',
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : widget.onRelearn,
            ),
          if (reversed)
            const Text('Test on: tickets made now are tests', style: TextStyle(color: Color(0xFFFFB04D), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
