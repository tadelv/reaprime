import 'dart:convert';

import 'package:drift/drift.dart';

/// Converts a JSON map to/from a string for Drift storage.
class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) {
    return jsonDecode(fromDb) as Map<String, dynamic>;
  }

  @override
  String toSql(Map<String, dynamic> value) {
    return jsonEncode(value);
  }
}

/// Converts a nullable JSON map to/from a string.
class NullableJsonMapConverter
    extends TypeConverter<Map<String, dynamic>?, String?> {
  const NullableJsonMapConverter();

  @override
  Map<String, dynamic>? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    return jsonDecode(fromDb) as Map<String, dynamic>;
  }

  @override
  String? toSql(Map<String, dynamic>? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }
}

/// Converts a string list to/from a JSON array string.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    return (jsonDecode(fromDb) as List).cast<String>();
  }

  @override
  String toSql(List<String> value) {
    return jsonEncode(value);
  }
}

/// Converts a nullable string list to/from a JSON array string.
class NullableStringListConverter
    extends TypeConverter<List<String>?, String?> {
  const NullableStringListConverter();

  @override
  List<String>? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    return (jsonDecode(fromDb) as List).cast<String>();
  }

  @override
  String? toSql(List<String>? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }
}

/// Converts a nullable int list to/from a JSON array string.
class NullableIntListConverter extends TypeConverter<List<int>?, String?> {
  const NullableIntListConverter();

  @override
  List<int>? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    return (jsonDecode(fromDb) as List).cast<int>();
  }

  @override
  String? toSql(List<int>? value) {
    if (value == null) return null;
    return jsonEncode(value);
  }
}
