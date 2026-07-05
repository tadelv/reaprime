/// A 16-bit per-channel RGB colour. Range 0–65535 per channel.
///
/// JSON wire format uses a 12-character hex string: `RRRRGGGGBBBB`.
/// Missing / non-hex / wrong length → black (`Color16.off`).
class Color16 {
  final int red;
  final int green;
  final int blue;

  const Color16(this.red, this.green, this.blue)
    : assert(red >= 0 && red <= 65535),
      assert(green >= 0 && green <= 65535),
      assert(blue >= 0 && blue <= 65535);

  /// Full-off convenience.
  static const off = Color16(0, 0, 0);

  /// Encode to 12 hex chars: RRRRGGGGBBBB (upper-case).
  String toJson() => '${_hex4(red)}${_hex4(green)}${_hex4(blue)}';

  /// Parse a 12-hex-char string. On failure returns [off].
  static Color16 fromJson(dynamic hex) {
    if (hex is! String || hex.length < 12) return off;
    final r = _hex16(hex, 0);
    final g = _hex16(hex, 4);
    final b = _hex16(hex, 8);
    if (r == null || g == null || b == null) return off;
    return Color16(r.clamp(0, 65535), g.clamp(0, 65535), b.clamp(0, 65535));
  }

  /// 4 hex digits, zero-padded, upper-case.
  static String _hex4(int v) =>
      v.toRadixString(16).padLeft(4, '0').toUpperCase();

  /// Parse 4 hex digits starting at [offset] in [s]. Returns null on failure.
  static int? _hex16(String s, int offset) =>
      int.tryParse(s.substring(offset, offset + 4), radix: 16);

  @override
  bool operator ==(Object other) =>
      other is Color16 &&
      red == other.red &&
      green == other.green &&
      blue == other.blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'Color16(#${toJson()})';
}

/// A pair of colours — one for when the machine is sleeping, one for awake.
///
/// The machine FW auto-selects which colour to display based on its internal
/// state; SB always writes both.
class ZoneLedState {
  final Color16 sleeping;
  final Color16 awake;

  const ZoneLedState({this.sleeping = Color16.off, this.awake = Color16.off});

  Map<String, dynamic> toJson() => {
    'sleeping': sleeping.toJson(),
    'awake': awake.toJson(),
  };

  factory ZoneLedState.fromJson(Map<String, dynamic> json) => ZoneLedState(
    sleeping: Color16.fromJson(json['sleeping']),
    awake: Color16.fromJson(json['awake']),
  );

  @override
  bool operator ==(Object other) =>
      other is ZoneLedState &&
      sleeping == other.sleeping &&
      awake == other.awake;

  @override
  int get hashCode => Object.hash(sleeping, awake);

  @override
  String toString() => 'ZoneLedState(sleeping: $sleeping, awake: $awake)';
}

/// Configuration state for Bengle's non-addressable LED zones.
///
/// Three independently-settable RGB zones — front strip, back strip, and
/// front switch. Each zone carries a colour for both machine states
/// (sleeping / awake). The machine FW auto-selects the active colour.
///
/// All channels are 16-bit (0–65535). JSON wire format uses nested
/// zone → mode → 12-char hex strings, e.g.:
/// ```json
/// {
///   "frontStrip": {"sleeping": "FFFF80000000", "awake": "000000000000"},
///   "backStrip":  {"sleeping": "000000000000", "awake": "FFFFFFFFFFFF"},
///   "frontSwitch":{"sleeping": "FFFF00000000", "awake": "000000000000"}
/// }
/// ```
class LedStripState {
  final ZoneLedState frontStrip;
  final ZoneLedState backStrip;
  final ZoneLedState frontSwitch;

  const LedStripState({
    this.frontStrip = const ZoneLedState(),
    this.backStrip = const ZoneLedState(),
    this.frontSwitch = const ZoneLedState(),
  });

  Map<String, dynamic> toJson() => {
    'frontStrip': frontStrip.toJson(),
    'backStrip': backStrip.toJson(),
    'frontSwitch': frontSwitch.toJson(),
  };

  factory LedStripState.fromJson(Map<String, dynamic> json) => LedStripState(
    frontStrip: ZoneLedState.fromJson(
      json['frontStrip'] as Map<String, dynamic>? ?? const {},
    ),
    backStrip: ZoneLedState.fromJson(
      json['backStrip'] as Map<String, dynamic>? ?? const {},
    ),
    frontSwitch: ZoneLedState.fromJson(
      json['frontSwitch'] as Map<String, dynamic>? ?? const {},
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is LedStripState &&
      frontStrip == other.frontStrip &&
      backStrip == other.backStrip &&
      frontSwitch == other.frontSwitch;

  @override
  int get hashCode => Object.hash(frontStrip, backStrip, frontSwitch);

  @override
  String toString() =>
      'LedStripState(frontStrip: $frontStrip, '
      'backStrip: $backStrip, frontSwitch: $frontSwitch)';
}
