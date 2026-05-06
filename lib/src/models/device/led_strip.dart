/// State of Bengle's non-addressable LED strip.
///
/// Front and back are independently settable, but each bank is a single
/// colour — not individually addressable per-LED. All channels 0–255.
/// JSON wire format uses hex colour strings, e.g. `'AABBCC'` (no `#`).
class LedStripState {
  final int frontRed;
  final int frontGreen;
  final int frontBlue;
  final int backRed;
  final int backGreen;
  final int backBlue;

  const LedStripState({
    this.frontRed = 0,
    this.frontGreen = 0,
    this.frontBlue = 0,
    this.backRed = 0,
    this.backGreen = 0,
    this.backBlue = 0,
  });

  String _rgb(int r, int g, int b) =>
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  Map<String, dynamic> toJson() => {
        'front': _rgb(frontRed, frontGreen, frontBlue),
        'back': _rgb(backRed, backGreen, backBlue),
      };

  factory LedStripState.fromJson(Map<String, dynamic> json) {
    return LedStripState(
      frontRed: _hexChannel(json['front'], 0),
      frontGreen: _hexChannel(json['front'], 1),
      frontBlue: _hexChannel(json['front'], 2),
      backRed: _hexChannel(json['back'], 0),
      backGreen: _hexChannel(json['back'], 1),
      backBlue: _hexChannel(json['back'], 2),
    );
  }

  /// Extract a single 0–255 channel from a 6-char hex string like `'AABBCC'`.
  /// [hex] at position [i] (0=r, 1=g, 2=b). Missing / non-hex → 0.
  static int _hexChannel(dynamic hex, int i) {
    if (hex is! String || hex.length < 6) return 0;
    final sub = hex.substring(i * 2, i * 2 + 2);
    return int.tryParse(sub, radix: 16)?.clamp(0, 255) ?? 0;
  }

  @override
  bool operator ==(Object other) =>
      other is LedStripState &&
      frontRed == other.frontRed &&
      frontGreen == other.frontGreen &&
      frontBlue == other.frontBlue &&
      backRed == other.backRed &&
      backGreen == other.backGreen &&
      backBlue == other.backBlue;

  @override
  int get hashCode => Object.hash(
        frontRed, frontGreen, frontBlue,
        backRed, backGreen, backBlue,
      );

  @override
  String toString() =>
      'LedStripState(front: ($frontRed,$frontGreen,$frontBlue), '
      'back: ($backRed,$backGreen,$backBlue))';
}
