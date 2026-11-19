import 'package:flutter/material.dart';

import '../../features/forensic/presentation/widgets/fx.dart';
import '../services/backend_control.dart';
import '../utils/app_toast.dart';

/// The backend's status light and its controls, kept under the logo of the side menu: Start (one click, when it is off), Force restart
/// and Shut down (in the menu). Shows "Starting" while the models load.
class BackendStatusTile extends StatefulWidget {
  const BackendStatusTile({super.key, required this.expanded, this.control});

  final bool expanded;

  /// The backend to control; the app's own by default.
  final BackendControl? control;

  @override
  State<BackendStatusTile> createState() => _BackendStatusTileState();
}

enum _Action { start, restart, stop }

class _BackendStatusTileState extends State<BackendStatusTile> {
  late final BackendControl _control = widget.control ?? BackendControl.instance;
  late final bool _watching = widget.control != null || BackendControl.pollsByDefault;

  @override
  void initState() {
    super.initState();
    if (_watching) _control.watch();
  }

  @override
  void dispose() {
    if (_watching) _control.unwatch();
    super.dispose();
  }

  (Color, String, String) _look(BackendState s) => switch (s) {
    BackendState.running => (Fx.success, 'Running', 'The backend answers.'),
    BackendState.starting => (Fx.warning, 'Starting…', 'The models are loading. This can take a minute.'),
    BackendState.stopping => (Fx.warning, 'Stopping…', 'The backend is being ended.'),
    BackendState.failed => (Fx.danger, 'Problem', _control.error ?? 'The backend has a problem.'),
    BackendState.offline => (Fx.danger, 'Off', 'The backend is not running.'),
    BackendState.unknown => (Colors.grey, 'Checking…', 'Asking the backend.'),
  };

  Future<void> _run(_Action action) async {
    switch (action) {
      case _Action.start:
        await _control.start();
      case _Action.restart:
        await _control.restart();
      case _Action.stop:
        await _control.stop();
    }
    if (!mounted) return;
    final error = _control.error;
    if (error != null) AppToast.show(context, error, isError: true);
  }

  PopupMenuItem<_Action> _item(_Action a, IconData icon, String text, {required bool enabled, Color? color}) => PopupMenuItem(
    value: a,
    enabled: enabled,
    child: Row(children: [Icon(icon, size: 18, color: enabled ? color : null), const SizedBox(width: Fx.s12), Text(text)]),
  );

  List<PopupMenuEntry<_Action>> _menu(BackendState s) {
    final off = s == BackendState.offline || s == BackendState.failed || s == BackendState.unknown;
    return [
      _item(_Action.start, Icons.play_arrow, 'Start the backend', enabled: off && !_control.busy, color: Fx.success),
      _item(_Action.restart, Icons.restart_alt, 'Force restart', enabled: !_control.busy, color: Fx.warning),
      _item(_Action.stop, Icons.power_settings_new, 'Shut down', enabled: !_control.busy && s != BackendState.offline, color: Fx.danger),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _control,
      builder: (context, _) {
        final state = _control.state;
        final (color, label, hint) = _look(state);
        final working = state == BackendState.starting || state == BackendState.stopping;
        final off = state == BackendState.offline || state == BackendState.failed;
        final dot = working
            ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

        final menu = PopupMenuButton<_Action>(
          key: const ValueKey('backend-menu'),
          tooltip: 'Backend actions',
          position: PopupMenuPosition.under,
          onSelected: _run,
          itemBuilder: (_) => _menu(state),
          icon: Icon(Icons.more_vert, size: 20, color: Fx.muted(context)),
        );

        if (!widget.expanded) {
          // collapsed: the light only; a click starts it when it is off, else opens the menu
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Fx.s4),
            child: Tooltip(
              message: 'Backend: $label. $hint',
              child: off && !_control.busy
                  ? InkWell(key: const ValueKey('backend-start'), onTap: () => _run(_Action.start), customBorder: const CircleBorder(), child: Padding(padding: const EdgeInsets.all(Fx.s8), child: dot))
                  : PopupMenuButton<_Action>(
                      key: const ValueKey('backend-menu'),
                      position: PopupMenuPosition.under,
                      onSelected: _run,
                      itemBuilder: (_) => _menu(state),
                      child: Padding(padding: const EdgeInsets.all(Fx.s8), child: dot),
                    ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(Fx.s12, 0, Fx.s12, Fx.s4),
          child: Container(
            padding: const EdgeInsets.only(left: Fx.s12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Fx.radiusSm),
              border: Border.all(color: Fx.border(context)),
              color: color.withValues(alpha: 0.07),
            ),
            child: Row(children: [
              dot,
              const SizedBox(width: Fx.s8),
              Expanded(
                child: Tooltip(
                  message: hint,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Fx.s8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('BACKEND', style: Fx.label(context)),
                      Text(label, key: const ValueKey('backend-state'), style: TextStyle(fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
              if (off)
                FilledButton.icon(
                  key: const ValueKey('backend-start'),
                  onPressed: _control.busy ? null : () => _run(_Action.start),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Start'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: Fx.s12)),
                ),
              menu,
            ]),
          ),
        );
      },
    );
  }
}
