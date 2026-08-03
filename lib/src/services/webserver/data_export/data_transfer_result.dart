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
    if (result.containsKey('errors') &&
        (errors is! List || errors.any((value) => value is! String))) {
      return _failed(key, 'Invalid errors for section "$key".');
    }
    if (result.containsKey('warnings') &&
        (warnings is! List || warnings.any((value) => value is! String))) {
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
    return DataSectionOutcome(
      key: key,
      status: _mostSevere(declaredStatus, derivedStatus),
      result: result,
    );
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

  static DataSectionStatus _mostSevere(
    DataSectionStatus? declared,
    DataSectionStatus derived,
  ) {
    final statuses = [derived, ?declared];
    if (statuses.contains(DataSectionStatus.failed)) {
      return DataSectionStatus.failed;
    }
    if (statuses.contains(DataSectionStatus.partial)) {
      return DataSectionStatus.partial;
    }
    return DataSectionStatus.complete;
  }
}

class DataTransferPhaseOutcome {
  final DataTransferStatus status;
  final Map<String, DataSectionOutcome> sections;
  final String? error;
  final String? message;
  final String? reason;
  final int? statusCode;

  DataTransferPhaseOutcome({
    required this.status,
    required Map<String, DataSectionOutcome> sections,
    this.error,
    this.message,
    this.reason,
    this.statusCode,
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
    if (statusCode != null) 'statusCode': statusCode,
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

    final allComplete = sections.values.every(
      (section) => section.status == DataSectionStatus.complete,
    );
    final hasProgress = sections.values.any((section) => section.hasProgress);
    final status = allComplete
        ? DataTransferStatus.complete
        : hasProgress
        ? DataTransferStatus.partial
        : DataTransferStatus.failed;
    return DataTransferPhaseOutcome(status: status, sections: sections);
  }

  static DataTransferPhaseOutcome fromRemote(
    dynamic value,
    List<String> expectedSections, {
    DataTransferStatus? minimumStatus,
  }) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      return DataTransferPhaseOutcome(
        status: DataTransferStatus.failed,
        sections: {},
        error: 'Invalid target response',
        message: 'The target returned a non-object import result.',
      );
    }

    final object = Map<String, dynamic>.from(value);
    final declaredStatus = object.containsKey('status')
        ? _parseRemoteStatus(object['status'])
        : null;
    if (object.containsKey('status') && declaredStatus == null) {
      return _invalidRemote('The target returned an invalid phase status.');
    }

    final complete = object['complete'];
    final partial = object['partial'];
    if ((object.containsKey('complete') && complete is! bool) ||
        (object.containsKey('partial') && partial is! bool)) {
      return _invalidRemote('The target returned invalid phase flags.');
    }
    if (complete == true && partial == true) {
      return _invalidRemote('The target returned contradictory phase flags.');
    }
    if ((complete == true &&
            declaredStatus != null &&
            declaredStatus != DataTransferStatus.complete) ||
        (partial == true &&
            declaredStatus != null &&
            declaredStatus != DataTransferStatus.partial) ||
        (complete == false &&
            partial == false &&
            declaredStatus == DataTransferStatus.complete)) {
      return _invalidRemote('The target returned contradictory phase status.');
    }

    final error = object['error'];
    final message = object['message'];
    final reason = object['reason'];
    if ((error != null && error is! String) ||
        (message != null && message is! String) ||
        (reason != null && reason is! String)) {
      return _invalidRemote('The target returned invalid phase metadata.');
    }

    final nested = object['sections'];
    if (nested != null &&
        (nested is! Map || nested.keys.any((key) => key is! String))) {
      return _invalidRemote('The target returned an invalid sections object.');
    }

    if (nested != null &&
        object.keys.any(
          (key) => key != 'sections' && !_metadataKeys.contains(key),
        )) {
      return _invalidRemote(
        'The target returned both structured and flat section results.',
      );
    }
    if (nested == null &&
        object.entries.any(
          (entry) => !_metadataKeys.contains(entry.key) && entry.value is! Map,
        )) {
      return _invalidRemote('The target returned a malformed section result.');
    }

    final rawSections = nested is Map
        ? Map<String, dynamic>.from(nested)
        : {
            for (final entry in object.entries)
              if (!_metadataKeys.contains(entry.key)) entry.key: entry.value,
          };
    final outcome = fromSections(
      rawSections: rawSections,
      expectedSections: expectedSections,
    );
    final status = _remoteStatus(
      outcome.status,
      declaredStatus: declaredStatus,
      complete: complete as bool?,
      partial: partial as bool?,
      hasError: error != null,
      minimumStatus: minimumStatus,
    );
    return DataTransferPhaseOutcome(
      status: status,
      sections: outcome.sections,
      error: error as String? ?? outcome.error,
      message: message as String? ?? outcome.message,
      reason: reason as String? ?? outcome.reason,
    );
  }

  static DataTransferPhaseOutcome _invalidRemote(String message) =>
      DataTransferPhaseOutcome(
        status: DataTransferStatus.failed,
        sections: {},
        error: 'Invalid target response',
        message: message,
      );

  static DataTransferStatus _remoteStatus(
    DataTransferStatus derived, {
    required DataTransferStatus? declaredStatus,
    required bool? complete,
    required bool? partial,
    required bool hasError,
    DataTransferStatus? minimumStatus,
  }) {
    final statuses = [derived];
    if (declaredStatus != null) statuses.add(declaredStatus);
    if (partial == true) statuses.add(DataTransferStatus.partial);
    if (hasError) statuses.add(DataTransferStatus.failed);
    if (minimumStatus != null) statuses.add(minimumStatus);
    if (complete == false &&
        partial != true &&
        declaredStatus != DataTransferStatus.partial &&
        derived == DataTransferStatus.complete) {
      statuses.add(DataTransferStatus.failed);
    }
    if (statuses.contains(DataTransferStatus.failed)) {
      return DataTransferStatus.failed;
    }
    if (statuses.contains(DataTransferStatus.partial)) {
      return DataTransferStatus.partial;
    }
    return DataTransferStatus.complete;
  }

  static DataTransferStatus? _parseRemoteStatus(dynamic value) =>
      switch (value) {
        'complete' => DataTransferStatus.complete,
        'partial' => DataTransferStatus.partial,
        'failed' => DataTransferStatus.failed,
        _ => null,
      };

  static DataTransferPhaseOutcome failed({
    required String error,
    required String message,
    String? reason,
    int? statusCode,
  }) => DataTransferPhaseOutcome(
    status: DataTransferStatus.failed,
    sections: const {},
    error: error,
    message: message,
    reason: reason,
    statusCode: statusCode,
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
    'statusCode',
  };
}
