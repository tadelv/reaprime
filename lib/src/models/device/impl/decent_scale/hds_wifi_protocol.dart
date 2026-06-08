import 'dart:convert';

/// Half Decent Scale WiFi protocol: command strings and frame parsing.
///
/// The scale streams UTF-8 JSON over a WebSocket at `ws://<host>:80/snapshot`.
/// Weight frames are *untyped* (`{"grams": 25.66, "ms": 12345}`) for backward
/// compatibility; everything else carries a `"type"` field (`status`,
/// `button`, `power`, `rate`, `error`). Authoritative source:
/// github.com/decentespresso/openscale.
class HdsWifiCommands {
  HdsWifiCommands._();

  /// Fast stream rate (10 Hz). Sent on connect.
  static const rate10k = 'rate 10k';
  static const eventsOn = 'events on';
  static const status = 'status';
  static const tare = 'tare';
  static const timerStart = 'timer start';
  static const timerStop = 'timer stop';
  static const timerReset = 'timer reset';
  static const displayOn = 'display on';
  static const displayOff = 'display off';

  /// Commands sent, in order, immediately after the WebSocket opens.
  static const handshake = [rate10k, eventsOn, status];
}

/// A parsed Half Decent Scale WiFi JSON frame.
class HdsWifiFrame {
  /// Frame type (`status`, `button`, `power`, `rate`, `error`), or null for
  /// the untyped weight frames the scale streams continuously.
  final String? type;

  /// Weight in grams. Present in untyped weight frames and `status` frames.
  final double? grams;

  /// Battery level percent (`status` frames).
  final int? batteryPercent;

  /// Charging state (`status` frames).
  final bool? charging;

  /// Whether the scale's timer is running (`status` frames).
  final bool? timerRunning;

  /// The raw decoded object, for fields not surfaced as typed getters.
  final Map<String, dynamic> raw;

  HdsWifiFrame({
    this.type,
    this.grams,
    this.batteryPercent,
    this.charging,
    this.timerRunning,
    required this.raw,
  });

  /// A weight reading is available whenever the frame carries `grams`.
  bool get hasWeight => grams != null;

  bool get isStatus => type == 'status';

  /// Either a weight sample or a `status` frame confirms a genuine HDS
  /// endpoint — the basis of the connection recognition gate.
  bool get confirmsHds => grams != null || type == 'status';

  /// The scale announced it is powering off.
  bool get isPowerOff => type == 'power' && raw['event'] == 'power_off';

  /// Parse [raw] JSON text. Returns null for empty/blank input, malformed
  /// JSON, or any JSON that is not an object — malformed input is swallowed,
  /// never thrown, so a stray frame can't drop the connection.
  static HdsWifiFrame? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return HdsWifiFrame(
      type: decoded['type'] as String?,
      grams: _toDouble(decoded['grams']),
      batteryPercent: _toInt(decoded['battery_percent']),
      charging: decoded['charging'] as bool?,
      timerRunning: decoded['timer_running'] as bool?,
      raw: decoded,
    );
  }

  static double? _toDouble(dynamic v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  static int? _toInt(dynamic v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}
