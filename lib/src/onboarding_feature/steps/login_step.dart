import 'package:flutter/material.dart';
import 'package:reaprime/src/account/decent_login_form.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

OnboardingStep createLoginStep({
  required DecentAccountService accountService,
  required SettingsController settingsController,
}) {
  return OnboardingStep(
    id: 'login',
    // Only show while the user hasn't seen the step and isn't already linked.
    // Skipping marks the step seen so it doesn't reappear on every launch —
    // the account can always be linked later from Settings.
    shouldShow: () async =>
        !settingsController.accountStepSeen &&
        !(await accountService.isLoggedIn()),
    builder: (controller) => LoginStepWidget(
      accountService: accountService,
      onComplete: () async {
        await settingsController.setAccountStepSeen(true);
        controller.advance();
      },
    ),
  );
}

class LoginStepWidget extends StatelessWidget {
  final DecentAccountService accountService;
  final VoidCallback onComplete;

  const LoginStepWidget({
    super.key,
    required this.accountService,
    required this.onComplete,
  });

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
            DecentLoginForm(
              accountService: accountService,
              onSuccess: onComplete,
              secondaryLabel: 'Skip for now',
              onSecondary: onComplete,
            ),
          ],
        ),
      ),
    );
  }
}
