// Utils for JSON parsing
double parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value) ?? int.parse(value).toDouble();
}

double? parseOptionalDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value) ?? int.tryParse(value)?.toDouble();
}

int parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.parse(value);
}
