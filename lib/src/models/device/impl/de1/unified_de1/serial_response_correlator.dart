import 'dart:async';
import 'dart:typed_data';

final class SerialResponseCorrelator {
  final _pending = <String, Completer<ByteData>>{};

  bool get hasPending => _pending.isNotEmpty;

  Future<ByteData> register(String representation, Duration timeout) {
    if (!RegExp(r'^[A-Z]$').hasMatch(representation)) {
      throw ArgumentError.value(representation, 'representation');
    }
    if (_pending.containsKey(representation)) {
      throw StateError('A serial $representation request is already pending');
    }

    final completer = Completer<ByteData>();
    _pending[representation] = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_pending[representation], completer)) {
          _pending.remove(representation);
        }
        throw TimeoutException(
          'Serial $representation response timed out',
          timeout,
        );
      },
    );
  }

  bool complete(String representation, ByteData data) {
    final completer = _pending.remove(representation);
    if (completer == null) return false;
    completer.complete(data);
    return true;
  }

  void remove(String representation) {
    _pending.remove(representation);
  }

  void fail(String representation, Object error, StackTrace stackTrace) {
    _pending.remove(representation)?.completeError(error, stackTrace);
  }

  void failAll(Object error, [StackTrace? stackTrace]) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error, stackTrace ?? StackTrace.current);
    }
  }
}
