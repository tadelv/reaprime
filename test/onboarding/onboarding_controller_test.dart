import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';

void main() {
  test('evaluates shouldShow and skips steps that return false', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'always-skip',
        shouldShow: () async => false,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'always-show',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();
    expect(controller.currentStep.id, 'always-show');
    expect(controller.activeSteps, hasLength(1));
  });

  test('advance() moves to next step', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'step-1',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'step-2',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();
    expect(controller.currentStep.id, 'step-1');

    controller.advance();
    expect(controller.currentStep.id, 'step-2');
  });

  test('advance() on last step emits completed', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'only-step',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();

    expectLater(controller.completedStream, emits(true));
    controller.advance();
  });

  test('currentStepStream emits on advance', () async {
    final controller = OnboardingController(steps: [
      OnboardingStep(
        id: 'step-1',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
      OnboardingStep(
        id: 'step-2',
        shouldShow: () async => true,
        builder: (_) => const SizedBox(),
      ),
    ]);

    await controller.initialize();

    expectLater(
      controller.currentStepStream.map((s) => s.id),
      emitsInOrder(['step-1', 'step-2']),
    );

    controller.advance();
  });
}
