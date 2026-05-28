import 'package:flutter/material.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

OnboardingStep createLoginStep({
  required DecentAccountService accountService,
}) {
  return OnboardingStep(
    id: 'login',
    shouldShow: () async => !(await accountService.isLoggedIn()),
    builder: (controller) => LoginStepWidget(
      accountService: accountService,
      onComplete: controller.advance,
    ),
  );
}

class LoginStepWidget extends StatefulWidget {
  final DecentAccountService accountService;
  final VoidCallback onComplete;

  const LoginStepWidget({
    super.key,
    required this.accountService,
    required this.onComplete,
  });

  @override
  State<LoginStepWidget> createState() => _LoginStepWidgetState();
}

class _LoginStepWidgetState extends State<LoginStepWidget> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Link Your Decent Account',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Sync your profiles, beans, and shots across devices.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ShadInput(
              controller: _emailController,
              placeholder: const Text('Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            ShadInput(
              controller: _passwordController,
              placeholder: const Text('Password'),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            ShadButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loading ? null : widget.onComplete,
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ok = await widget.accountService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (ok) {
        widget.onComplete();
      } else {
        setState(() {
          _error = 'Login failed. Check your email and password.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error. Check your connection and try again.';
        _loading = false;
      });
    }
  }
}
