import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/friendly_error.dart';
import '../../../core/services/portal_api.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/session.dart';
import '../../../core/ui/app_theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/utils/plate.dart';
import '../../main/screens/main_screen.dart';

/// Create an account with a plate number. The first account for a plate keeps it; tickets already confirmed for that
/// plate show up straight away.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.api});

  /// Injected by tests; the app talks to the system.
  final PortalApi? api;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  PortalApi get _api => widget.api ?? PortalApi();

  final _name = TextEditingController();
  final _plate = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _touched = <String>{};          // fields the person has used: only those show their problem while typing
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  Map<String, String> get _errors => signUpErrors(
        name: _name.text, plate: _plate.text, password: _password.text, repeat: _repeat.text, email: _email.text);

  /// The problem to show under a field: after the first attempt for all, before that only for fields already used.
  String? _show(String field) => (_submitted || _touched.contains(field)) ? _errors[field] : null;

  void _changed(String field) => setState(() => _touched.add(field));

  @override
  void dispose() {
    for (final c in [_name, _plate, _email, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (_errors.isNotEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final account = await _api.register(
        name: _name.text.trim(),
        plate: _plate.text.trim(),
        password: _password.text,
        email: _email.text.trim(),
      );
      await Session.save(account);
      PushNotificationService.registerCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Your plate number is how you sign in and how your records find you. One account per plate.', style: context.text.bodyLarge?.copyWith(color: context.muted)),
                  const SizedBox(height: Sp.x6),
                  AppField(
                    controller: _name,
                    label: 'Full name',
                    icon: Icons.person_outline,
                    capitalization: TextCapitalization.words,
                    action: TextInputAction.next,
                    autofill: const [AutofillHints.name],
                    errorText: _show('name'),
                    onChanged: (_) => _changed('name'),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: Sp.x4),
                  AppField(
                    controller: _plate,
                    label: 'Plate number',
                    helper: 'As on your registration, for example ABC 1234.',
                    icon: Icons.directions_car_outlined,
                    capitalization: TextCapitalization.characters,
                    action: TextInputAction.next,
                    formatters: [LengthLimitingTextInputFormatter(14)],
                    errorText: _show('plate'),
                    onChanged: (_) => _changed('plate'),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: Sp.x4),
                  AppField(
                    controller: _email,
                    label: 'E-mail (optional)',
                    helper: 'Your notices are also sent here.',
                    icon: Icons.mail_outline,
                    keyboard: TextInputType.emailAddress,
                    action: TextInputAction.next,
                    autofill: const [AutofillHints.email],
                    errorText: _show('email'),
                    onChanged: (_) => _changed('email'),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: Sp.x4),
                  AppField(
                    controller: _password,
                    label: 'Password',
                    helper: passwordHint(_password.text),
                    icon: Icons.lock_outline,
                    password: true,
                    action: TextInputAction.next,
                    autofill: const [AutofillHints.newPassword],
                    errorText: _show('password'),
                    onChanged: (_) => _changed('password'),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: Sp.x4),
                  AppField(
                    controller: _repeat,
                    label: 'Repeat the password',
                    icon: Icons.lock_outline,
                    password: true,
                    action: TextInputAction.done,
                    errorText: _show('repeat'),
                    onChanged: (_) => _changed('repeat'),
                    onSubmitted: (_) => _submit(),
                    enabled: !_busy,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Sp.x4),
                    InfoBanner(message: _error!, tone: Tone.danger),
                  ],
                  const SizedBox(height: Sp.x6),
                  AppButton(label: 'Create account', onPressed: _submit, loading: _busy),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
