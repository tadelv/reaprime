import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/scale.dart';

enum ShotScaleCommand {
  preparingTare,
  timerReset,
  pourTare,
  timerStart,
  timerStop,
}

class ShotScaleCommandQueue {
  final Scale _scale;
  final bool Function() _isCurrent;
  final Logger _log;
  final Set<ShotScaleCommand> _requested = {};
  Future<void> _tail = Future.value();
  int _generation = 0;

  ShotScaleCommandQueue(
    this._scale, {
    required bool Function() isCurrent,
    Logger? logger,
  }) : _isCurrent = isCurrent,
       _log = logger ?? Logger('ShotScaleCommandQueue');

  Future<void> get settled => _tail;

  void enqueue(
    ShotScaleCommand command,
    Future<void> Function(Scale scale) operation, {
    void Function()? onStart,
    void Function()? onSuccess,
    void Function(Object error)? onFailure,
  }) {
    if (!_requested.add(command)) return;
    final generation = _generation;
    _tail = _tail.then((_) async {
      if (generation != _generation || !_isCurrent()) return;
      try {
        onStart?.call();
        await operation(_scale);
        if (generation == _generation && _isCurrent()) onSuccess?.call();
      } catch (error, stackTrace) {
        _log.warning('${command.name} failed', error, stackTrace);
        if (generation != _generation || !_isCurrent()) return;
        try {
          onFailure?.call(error);
        } catch (callbackError, callbackStackTrace) {
          _log.warning(
            '${command.name} failure callback failed',
            callbackError,
            callbackStackTrace,
          );
        }
      }
    });
  }

  void dispose() {
    _generation++;
  }
}
