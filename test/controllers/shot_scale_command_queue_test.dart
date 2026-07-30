import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/shot_scale_command_queue.dart';

import '../helpers/test_scale.dart';

void main() {
  late TestScale scale;
  late ShotScaleCommandQueue queue;
  late int connectionGeneration;

  setUp(() {
    scale = TestScale();
    connectionGeneration = 0;
    queue = ShotScaleCommandQueue(
      scale,
      isCurrent: () => connectionGeneration == 0,
    );
  });

  tearDown(() {
    queue.dispose();
    scale.dispose();
  });

  test('runs commands once in FIFO order', () async {
    final blocked = Completer<void>();
    scale.resetTimerHandler = () => blocked.future;

    queue.enqueue(ShotScaleCommand.timerReset, (scale) => scale.resetTimer());
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
    await Future<void>.delayed(Duration.zero);

    expect(scale.commandCalls, ['reset']);
    blocked.complete();
    await queue.settled;
    expect(scale.commandCalls, ['reset', 'start']);
  });

  test('a failed command does not poison later work', () async {
    scale.resetTimerHandler = () => Future.error(StateError('failed'));

    queue.enqueue(ShotScaleCommand.timerReset, (scale) => scale.resetTimer());
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
    await queue.settled;

    expect(scale.commandCalls, ['reset', 'start']);
  });

  test('dispose prevents queued commands from starting', () async {
    final blocked = Completer<void>();
    scale.resetTimerHandler = () => blocked.future;

    queue.enqueue(ShotScaleCommand.timerReset, (scale) => scale.resetTimer());
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
    await Future<void>.delayed(Duration.zero);
    queue.dispose();
    blocked.complete();
    await queue.settled;

    expect(scale.commandCalls, ['reset']);
  });

  test('connection generation change prevents queued commands', () async {
    final blocked = Completer<void>();
    var completed = false;

    queue.enqueue(
      ShotScaleCommand.preparingTare,
      (_) => blocked.future,
      onSuccess: () => completed = true,
    );
    queue.enqueue(ShotScaleCommand.timerReset, (scale) => scale.resetTimer());
    queue.enqueue(ShotScaleCommand.timerStart, (scale) => scale.startTimer());
    await Future<void>.delayed(Duration.zero);
    connectionGeneration++;
    blocked.complete();
    await queue.settled;

    expect(scale.commandCalls, isEmpty);
    expect(completed, isFalse);
  });
}
