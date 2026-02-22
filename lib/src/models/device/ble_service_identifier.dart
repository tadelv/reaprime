class BleServiceIdentifier {
  final String? _short;
  final String? _long;

  BleServiceIdentifier.short(String uuid16bit)
      : _short = uuid16bit.toLowerCase(),
        _long = null;

  BleServiceIdentifier.long(String uuid128bit)
      : _short = null,
        _long = uuid128bit.toLowerCase();

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
