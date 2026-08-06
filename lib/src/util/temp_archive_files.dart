import 'dart:async';
import 'dart:io';

/// Owns a unique temporary directory for one transfer operation.
///
/// Every export/import/sync creates its own [TempArchiveDir] so concurrent
/// transfers use isolated locations and can never delete each other's files.
/// [dispose] removes the directory recursively; it is idempotent and safe to
/// call from `finally` blocks and cleanup callbacks.
class TempArchiveDir {
  late final Directory _dir;

  /// Creates the unique temporary directory.
  static Future<TempArchiveDir> create([String prefix = 'reaprime-']) async {
    final result = TempArchiveDir._();
    result._dir = await Directory.systemTemp.createTemp(prefix);
    return result;
  }

  TempArchiveDir._();

  Directory get directory => _dir;

  String get path => _dir.path;

  /// Path to a new file inside this temp directory.
  String filePath(String name) => '${_dir.path}${Platform.pathSeparator}$name';

  bool _disposed = false;

  /// Deletes the temporary directory recursively. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (await _dir.exists()) {
        await _dir.delete(recursive: true);
      }
    } catch (_) {
      // Best effort cleanup.
    }
  }
}

/// Schedules a deferred cleanup for files that must outlive the operation
/// that created them (e.g. a ZIP handed to the OS share sheet, which the
/// receiving app may read asynchronously). Files are deleted after
/// [gracePeriod] unless [cancel] is called first.
class DeferredFileCleanup {
  final File file;
  final Duration gracePeriod;
  Timer? _timer;

  DeferredFileCleanup(
    this.file, {
    this.gracePeriod = const Duration(minutes: 5),
  });

  /// Starts the grace timer.
  void start() {
    _timer ??= Timer(gracePeriod, () {
      file.delete().then((_) {}, onError: (_) {});
    });
  }

  /// Cancels the pending deletion (e.g. the operation failed).
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
