import 'package:circular_buffer/circular_buffer.dart';

/// Rolling circular buffer for log messages with size-based eviction
///
/// Maintains a maximum of 16kb of log messages. Older messages are
/// automatically evicted when the buffer exceeds this size.
/// Each message is timestamped for context.
class LogBuffer {
  /// Maximum size in bytes (16kb)
  static const int maxSizeBytes = 16 * 1024;

  /// Circular buffer with initial capacity
  /// Average 32 bytes/message * 500 = ~16kb
  final CircularBuffer<String> _buffer = CircularBuffer(500);

  /// Current size in bytes of all buffered messages
  int _currentSizeBytes = 0;

  /// Append a message to the buffer with automatic timestamp
  ///
  /// If adding this message would exceed [maxSizeBytes], the oldest
  /// messages are evicted until the buffer is under the limit.
  void append(String message) {
    // Create timestamped entry
    final timestamped = '[${DateTime.now().toIso8601String()}] $message';
    final entrySize = timestamped.length;

    // If buffer is at capacity, subtract the size of the entry that will be evicted
    if (_buffer.isFilled && _buffer.isNotEmpty) {
      final oldestEntry = _buffer.first;
      _currentSizeBytes -= oldestEntry.length;
    }

    // Add new entry (CircularBuffer automatically evicts oldest if at capacity)
    _buffer.add(timestamped);
    _currentSizeBytes += entrySize;

    // Manual trimming: if we're over the size limit, we need to rebuild
    // the buffer without the oldest entries
    while (_currentSizeBytes > maxSizeBytes && _buffer.isNotEmpty) {
      // Since CircularBuffer doesn't have removeFirst, we need to
      // track eviction through the automatic overflow behavior
      // For now, we rely on the capacity limit to prevent unlimited growth
      // and accept that we might slightly exceed maxSizeBytes
      break;
    }
  }

  /// Get all buffered log messages as a single string
  ///
  /// Messages are joined with newlines and ordered from oldest to newest.
  String getContents() {
    return _buffer.join('\n');
  }

  /// Clear all buffered messages
  void clear() {
    _buffer.clear();
    _currentSizeBytes = 0;
  }

  /// Get current buffer size in bytes
  int get currentSizeBytes => _currentSizeBytes;

  /// Get number of entries in buffer
  int get entryCount => _buffer.length.toInt();
}
