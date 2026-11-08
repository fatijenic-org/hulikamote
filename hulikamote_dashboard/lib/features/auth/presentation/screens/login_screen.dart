import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/shell/officer_mode.dart';
import '../../../forensic/presentation/widgets/fx.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _showPassword = false;

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600)); // Mock network delay
    if (!mounted) return;
    // An officer starts on the Overview; the full view keeps going straight to Video Analysis.
    context.go(OfficerMode.enabled.value ? '/overview' : '/offline-video');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Fx.page(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Fx.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FxCard(
              padding: const EdgeInsets.all(Fx.s32),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Fx.accent),
                          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 27),
                        ),
                      ),
                      const SizedBox(width: Fx.s12),
                      Text('HULI-KAMOTE', style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ]),
                    const SizedBox(height: Fx.s24),
                    Semantics(header: true, child: Text('Sign in', style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700))),
                    const SizedBox(height: Fx.s4),
                    Text('Traffic violation review for LTO officers.', style: Fx.caption(context)),
                    const SizedBox(height: Fx.s24),
                    TextField(
                      autofocus: true,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: Fx.s16),
                    TextField(
                      obscureText: !_showPassword,
                      enabled: !_isLoading,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'Hide password' : 'Show password',
                          icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: Fx.s8),
                    Text('Demo build: any username and password signs you in.', style: Fx.caption(context)),
                    const SizedBox(height: Fx.s24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
