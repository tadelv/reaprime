import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../onboarding_controller.dart';

/// Creates an [OnboardingStep] that shows a welcome screen.
///
/// shouldShow is determined by the caller — typically shown when onboarding
/// has not yet been completed.
OnboardingStep createWelcomeStep() {
  return OnboardingStep(
    id: 'welcome',
    shouldShow: () async => true,
    builder: (controller) => _WelcomeStepView(controller: controller),
  );
}

class _WelcomeStepView extends StatelessWidget {
  final OnboardingController controller;

  const _WelcomeStepView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Scaffold(
      body: Semantics(
        explicitChildNodes: true,
        label: 'Welcome screen',
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Welcome to Streamline Bridge',
                  style: theme.textTheme.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Control your Decent espresso machine, manage profiles, and track your shots — right here or from any device on your network.',
                  style: theme.textTheme.p,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Coming from the Decent app? You can import your data next.',
                  style: theme.textTheme.muted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ShadButton(
                  onPressed: controller.advance,
                  child: const Text('Get Started'),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
