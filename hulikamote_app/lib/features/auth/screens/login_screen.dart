import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/demo_accounts.dart';
import '../../../core/services/friendly_error.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../main/screens/main_screen.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/connection_dialog.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.api});

  /// Injected by tests; the app talks to the system.
  final PortalApi? api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Built when needed: the way in (online or same Wi-Fi) can change from this very page.
  PortalApi get _api => widget.api ?? PortalApi();

  final _plate = TextEditingController();
  final _password = TextEditingController();
  List<DemoAccount> _demo = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    DemoAccounts.load().then((list) {
      if (mounted) setState(() => _demo = list);
    });
    if (!AppConfig.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changeConnection();
      });
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _changeConnection() async {
    await showConnectionDialog(context);
    if (mounted) setState(() {});
  }

  Future<void> _signIn([DemoAccount? demo]) async {
    if (demo != null) {
      _plate.text = demo.plate;
      _password.text = demo.password;
    }
    if (!AppConfig.ready) {
      await _changeConnection();
      if (!mounted || !AppConfig.ready) return;
    }
    if (_plate.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your plate number and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await _api.login(_plate.text, _password.text);
      await Session.save(account);
      PushNotificationService.registerCurrentUser();         // in the background: signing in must not wait for it
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Sp.page, vertical: Sp.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const BrandHeader(),
                  const SizedBox(height: Sp.x8),
                  Semantics(header: true, child: Text('Welcome back', style: context.text.headlineMedium)),
                  const SizedBox(height: Sp.x2),
                  Text('Sign in with your plate number to see your records and file an appeal.', style: context.text.bodyLarge?.copyWith(color: context.muted)),
                  const SizedBox(height: Sp.x6),
                  AppField(
                    controller: _plate,
                    label: 'Plate number',
                    icon: Icons.directions_car_outlined,
                    capitalization: TextCapitalization.characters,
                    action: TextInputAction.next,
                    autofill: const [AutofillHints.username],
                    formatters: [LengthLimitingTextInputFormatter(14)],
                    enabled: !_busy,
                  ),
                  const SizedBox(height: Sp.x4),
                  AppField(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    password: true,
                    action: TextInputAction.done,
                    autofill: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                    enabled: !_busy,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Sp.x4),
                    InfoBanner(message: _error!, tone: Tone.danger),
                  ],
                  const SizedBox(height: Sp.x6),
                  AppButton(label: 'Sign in', onPressed: () => _signIn(), loading: _busy),
                  const SizedBox(height: Sp.x2),
                  AppButton(
                    label: 'Create an account with my plate',
                    kind: AppButtonKind.text,
                    onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(api: widget.api))),
                  ),
                  if (_demo.isNotEmpty) ...[
                    const SizedBox(height: Sp.x6),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.x3), child: Text('Demo accounts', style: context.text.labelLarge?.copyWith(color: context.muted))),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: Sp.x3),
                    Wrap(spacing: Sp.x2, runSpacing: Sp.x2, alignment: WrapAlignment.center, children: [
                      for (final account in _demo)
                        ActionChip(
                          avatar: CircleAvatar(
                            backgroundColor: context.colors.primaryContainer,
                            child: Text(InitialsAvatar.initials(account.name), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.colors.onPrimaryContainer)),
                          ),
                          label: Text(account.name),
                          tooltip: 'Sign in as ${account.name} (${account.plate})',
                          onPressed: _busy ? null : () => _signIn(account),
                        ),
                    ]),
                  ],
                  const SizedBox(height: Sp.x6),
                  Center(child: ConnectionPill(onTap: _busy ? () {} : _changeConnection)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
