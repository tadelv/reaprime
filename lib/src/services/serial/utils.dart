import 'dart:typed_data';

// ---- Device-specific detection helpers ----
final _hdsRegex = RegExp(r'\d+ Weight: .*');
bool isDecentScale(List<String> messages, List<Uint8List> captures) {
  print("is HDS: checking ${messages.length}, ${messages}");
  return captures.any(
        (Uint8List bytes) =>
            bytes.length > 5 &&
            bytes[0] == 0x03 &&
            bytes[1] == 0xCE &&
            bytes[4] == 0 &&
            bytes[5] == 0,
      ) ||
      messages.any((t) => _hdsRegex.hasMatch(t));
}

final _sbRegex = RegExp(
  // r'^\d+ (?:nan|[+-]?(?:\d+(?:\.\d+)?|\.\d+)) [+-]?(?:\d+(?:\.\d+)?|\.\d+) [+-]?(?:\d+(?:\.\d+)?|\.\d+) [+-]?(?:\d+(?:\.\d+)?|\.\d+)$');
  r'^\d+ (?:nan|[+-]?[0-9]*[.]?[0-9]+) [+-]?[0-9]*[.]?[0-9]+ [+-]?[0-9]*[.]?[0-9]+ [+-]?[0-9]*[.]?[0-9]+',
);
bool isSensorBasket(List<String> messages) {
  return messages.any((t) => _sbRegex.hasMatch(t));
}

bool isDE1(List<String> data, List<int> bytes) {
  print("figuring out $data");
  return data.any((e) => e.startsWith("[M]"));
}
