class BleServiceIdentifier {
  final String? _short;
  final String? _long;

  static final _shortPattern = RegExp(r'^[0-9a-fA-F]{4}$');
  static final _longPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  BleServiceIdentifier.short(String uuid16bit)
      : _short = _validateShort(uuid16bit),
        _long = null;

  BleServiceIdentifier.long(String uuid128bit)
      : _short = null,
        _long = _validateLong(uuid128bit);

  BleServiceIdentifier.both(String? short, String? long)
      : _short =
            short != null && short.isNotEmpty ? _validateShort(short) : null,
        _long = long != null && long.isNotEmpty ? _validateLong(long) : null {
    if (_short == null && _long == null) {
      throw ArgumentError(
          'At least one UUID (short or long) must be provided');
    }
  }

  static String _validateShort(String uuid) {
    if (!_shortPattern.hasMatch(uuid)) {
      throw ArgumentError(
          'Short UUID must be exactly 4 hex characters: $uuid');
    }
    return uuid.toLowerCase();
  }

  static String _validateLong(String uuid) {
    if (!_longPattern.hasMatch(uuid)) {
      throw ArgumentError(
          'Long UUID must match pattern xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx: $uuid');
    }
    return uuid.toLowerCase();
  }

  String get short {
    if (_short != null) return _short;
    // Extract short from long if it matches base UUID pattern
    if (_long != null &&
        _long.startsWith('0000') &&
        _long.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return _long.substring(4, 8);
    }
    throw StateError('Cannot extract short UUID from custom 128-bit UUID');
  }

  String get long {
    if (_long != null) return _long;
    if (_short != null) {
      // Bluetooth SIG base UUID expansion
      return '0000$_short-0000-1000-8000-00805f9b34fb';
    }
    throw StateError('No UUID available');
  }
}
