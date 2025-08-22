import 'device.dart';

abstract class Sensor extends Device {
  Stream<Map<String, dynamic>> get data;

  Future<Map<String, dynamic>> execute(
      String commandId, Map<String, dynamic>? parameters);

  SensorInfo get info;
}

class SensorInfo {
  final String name;
  final String vendor;
  final List<DataChannel> dataChannels;
  final List<CommandDescriptor>? commands;

  SensorInfo(
      {required this.name,
      required this.vendor,
      required this.dataChannels,
      required this.commands});
}

class CommandDescriptor {
  final String id;
  final String? name;
  final String? description;
  final Map<String, dynamic>? paramsSchema;
  final Map<String, dynamic>? resultsSchema;

  CommandDescriptor(
      {required this.id,
      required this.name,
      required this.description,
      required this.paramsSchema,
      required this.resultsSchema});
}

class DataChannel {
  final String key;
  final String type;
  final String? unit;

  DataChannel({required this.key, required this.type, this.unit});
}
