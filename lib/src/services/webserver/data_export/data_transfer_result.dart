enum DataTransferStatus { complete, partial, failed, skipped }

enum DataSectionStatus { complete, partial, failed }

class DataSectionOutcome {
  final String key;
  final DataSectionStatus status;
  final Map<String, dynamic> result;

  DataSectionOutcome({
    required this.key,
    required this.status,
    required Map<String, dynamic> result,
  }) : result = Map.unmodifiable(
         result.map(
           (key, value) => MapEntry(
             key,
             value is List ? List<dynamic>.unmodifiable(value) : value,
           ),
         ),
       );

  bool get hasProgress =>
      status == DataSectionStatus.complete ||
      status == DataSectionStatus.partial ||
      _count('imported') > 0 ||
      _count('skipped') > 0;

  Map<String, dynamic> toJson() => {...result, 'status': status.name};

  static DataSectionOutcome fromJson(String key, dynamic value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      return _failed(key, 'Invalid result for section "$key".');
    }

    final result = Map<String, dynamic>.from(value);
    final declaredStatus = result.containsKey('status')
        ? _parseStatus(result['status'])
        : null;
    if (result.containsKey('status') && declaredStatus == null) {
      return _failed(key, 'Invalid status for section "$key".');
    }

    final errors = result['errors'];
    final warnings = result['warnings'];
    if (result.containsKey('errors') && errors is! List) {
      return _failed(key, 'Invalid errors for section "$key".');
    }
    if (result.containsKey('warnings') && warnings is! List) {
      return _failed(key, 'Invalid warnings for section "$key".');
    }
    if ((result.containsKey('imported') && !_validCount(result['imported'])) ||
        (result.containsKey('skipped') && !_validCount(result['skipped']))) {
      return _failed(key, 'Invalid counts for section "$key".');
    }
    if (declaredStatus == null &&
        !result.containsKey('imported') &&
        !result.containsKey('skipped') &&
        !result.containsKey('errors')) {
      return _failed(key, 'Missing semantic result for section "$key".');
    }

    final hasErrors = errors is List && errors.isNotEmpty;
    final hasProgress =
        _countIn(result, 'imported') > 0 || _countIn(result, 'skipped') > 0;
    final derivedStatus = hasErrors
        ? hasProgress
              ? DataSectionStatus.partial
              : DataSectionStatus.failed
        : DataSectionStatus.complete;
    final status = switch (declaredStatus) {
      null => derivedStatus,
      DataSectionStatus.complete when hasErrors => derivedStatus,
      final declared => declared,
    };
    return DataSectionOutcome(key: key, status: status, result: result);
  }

  static DataSectionOutcome missing(String key) => _failed(
    key,
    'Missing expected data section "$key".',
    result: const {'imported': 0, 'skipped': 0},
  );

  static DataSectionOutcome _failed(
    String key,
    String error, {
    Map<String, dynamic> result = const {},
  }) => DataSectionOutcome(
    key: key,
    status: DataSectionStatus.failed,
    result: {
      ...result,
      'errors': [error],
    },
  );

  int _count(String key) => _countIn(result, key);

  static int _countIn(Map<String, dynamic> result, String key) {
    final value = result[key];
    return value is int && value >= 0 ? value : 0;
  }

  static bool _validCount(dynamic value) => value is int && value >= 0;

  static DataSectionStatus? _parseStatus(dynamic value) => switch (value) {
    'complete' => DataSectionStatus.complete,
    'partial' => DataSectionStatus.partial,
    'failed' => DataSectionStatus.failed,
    _ => null,
  };
}

class DataTransferPhaseOutcome {
  final DataTransferStatus status;
  final Map<String, DataSectionOutcome> sections;
  final String? error;
  final String? message;
  final String? reason;

  DataTransferPhaseOutcome({
    required this.status,
    required Map<String, DataSectionOutcome> sections,
    this.error,
    this.message,
    this.reason,
  }) : sections = Map.unmodifiable(sections);

  bool get complete => status == DataTransferStatus.complete;

  bool get partial => status == DataTransferStatus.partial;

  Map<String, dynamic> get sectionResults => {
    for (final entry in sections.entries) entry.key: entry.value.toJson(),
  };

  Map<String, dynamic> toMetadata() => {
    'status': status.name,
    'complete': complete,
    'partial': partial,
    if (error != null) 'error': error,
    if (message != null) 'message': message,
    if (reason != null) 'reason': reason,
  };

  static DataTransferPhaseOutcome fromSections({
    required Map<String, dynamic> rawSections,
    required List<String> expectedSections,
  }) {
    final sections = <String, DataSectionOutcome>{
      for (final entry in rawSections.entries)
        entry.key: DataSectionOutcome.fromJson(entry.key, entry.value),
    };
    for (final key in expectedSections) {
      if (!sections.containsKey(key)) {
        sections[key] = DataSectionOutcome.missing(key);
      }
    }

    if (expectedSections.isEmpty) {
      return DataTransferPhaseOutcome(
        status: DataTransferStatus.failed,
        sections: {},
        error: 'Invalid transfer result',
        message: 'No expected data sections were provided.',
      );
    }

    final expected = expectedSections.map((key) => sections[key]!).toList();
    final allComplete = expected.every(
      (section) => section.status == DataSectionStatus.complete,
    );
    final hasProgress = expected.any((section) => section.hasProgress);
    final status = allComplete
        ? DataTransferStatus.complete
        : hasProgress
        ? DataTransferStatus.partial
        : DataTransferStatus.failed;
    return DataTransferPhaseOutcome(status: status, sections: sections);
  }

  static DataTransferPhaseOutcome fromRemote(
    dynamic value,
    List<String> expectedSections,
  ) {
    if (value is! Map) {
      return DataTransferPhaseOutcome(
        status: DataTransferStatus.failed,
        sections: {},
        error: 'Invalid target response',
        message: 'The target returned a non-object import result.',
      );
    }

    final object = Map<String, dynamic>.from(value);
    final nested = object['sections'];
    if (nested != null && nested is! Map) {
      return DataTransferPhaseOutcome(
        status: DataTransferStatus.failed,
        sections: {},
        error: 'Invalid target response',
        message: 'The target returned an invalid sections object.',
      );
    }

    final rawSections = nested is Map
        ? Map<String, dynamic>.from(nested)
        : {
            for (final entry in object.entries)
              if (!_metadataKeys.contains(entry.key) && entry.value is Map)
                entry.key: entry.value,
          };
    return fromSections(
      rawSections: rawSections,
      expectedSections: expectedSections,
    );
  }

  static DataTransferPhaseOutcome failed({
    required String error,
    required String message,
    String? reason,
  }) => DataTransferPhaseOutcome(
    status: DataTransferStatus.failed,
    sections: const {},
    error: error,
    message: message,
    reason: reason,
  );

  static const _metadataKeys = {
    'status',
    'complete',
    'partial',
    'mode',
    'phases',
    'error',
    'message',
    'reason',
  };
}
