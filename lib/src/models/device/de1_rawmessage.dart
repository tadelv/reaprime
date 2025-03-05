final class De1RawMessage {
  final De1RawMessageType type;
  final De1RawOperationType operation;
  final String characteristicUUID;
  final String payload;

  De1RawMessage({
    required this.type,
    required this.operation,
    required this.characteristicUUID,
    required this.payload,
  });

  factory De1RawMessage.fromJson(Map<String, dynamic> json) {
    return De1RawMessage(
        type: De1RawMessageType.values[json['type']],
        operation: De1RawOperationType.values[json['operation']],
        characteristicUUID: json['characteristicUUID'],
        payload: json['payload']);
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'operation': operation.name,
      'characteristicUUID': characteristicUUID,
      'payload': payload
    };
  }
}

enum De1RawMessageType { request, response }

enum De1RawOperationType { read, write, notify }
