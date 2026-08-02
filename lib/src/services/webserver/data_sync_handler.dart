import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_result.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

enum SyncMode { pull, push, twoWay }

class SyncTargetException implements Exception {
  final String error;
  final String message;

  const SyncTargetException(this.error, this.message);

  @override
  String toString() => 'SyncTargetException: $message';
}

class _LocalExportException implements Exception {
  final Object cause;

  const _LocalExportException(this.cause);
}

class DataSyncHandler {
  static const _requestTimeout = Duration(seconds: 30);
  static const _skippedPushMessage =
      'Push was not attempted because pull did not complete.';

  final DataExportHandler _exportHandler;
  final http.Client _httpClient;
  final Logger _log = Logger('DataSyncHandler');

  DataSyncHandler({
    required DataExportHandler exportHandler,
    required http.Client httpClient,
  }) : _exportHandler = exportHandler,
       _httpClient = httpClient;

  void addRoutes(RouterPlus app) {
    app.post('/api/v1/data/sync', _handleSync);
  }

  Future<Response> _handleSync(Request request) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(await request.readAsString());
    } catch (_) {
      return jsonBadRequest({'error': 'Invalid JSON'});
    }
    if (decoded is! Map) {
      return jsonBadRequest({
        'error': 'Invalid JSON',
        'message': 'The request body must be a JSON object.',
      });
    }
    final body = Map<String, dynamic>.from(decoded);

    final target = body['target'];
    if (target is! String || target.isEmpty) {
      return jsonBadRequest({
        'error': 'Missing required field',
        'message': '"target" is required',
      });
    }
    final targetUri = Uri.tryParse(target);
    if (targetUri == null ||
        !targetUri.hasScheme ||
        (targetUri.scheme != 'http' && targetUri.scheme != 'https')) {
      return jsonBadRequest({
        'error': 'Invalid target URL',
        'message':
            '"target" must be a valid HTTP/HTTPS URL (e.g., http://192.168.1.50:8080)',
      });
    }

    final modeValue = body['mode'];
    if (modeValue is! String) {
      return jsonBadRequest({
        'error': 'Missing required field',
        'message': '"mode" is required. Valid values: pull, push, two_way',
      });
    }
    final mode = _parseMode(modeValue);
    if (mode == null) {
      return jsonBadRequest({
        'error': 'Invalid mode',
        'message': 'Valid values: pull, push, two_way',
      });
    }

    final onConflict = body['onConflict'];
    if (onConflict != null && onConflict is! String) {
      return jsonBadRequest({
        'error': 'Invalid onConflict value',
        'message': 'Valid values: skip, overwrite',
      });
    }
    final strategy = _parseStrategy(onConflict as String? ?? 'skip');
    if (strategy == null) {
      return jsonBadRequest({
        'error': 'Invalid onConflict value',
        'message': 'Valid values: skip, overwrite',
      });
    }

    final continueValue = body['continueOnPullFailure'];
    if (continueValue != null && continueValue is! bool) {
      return jsonBadRequest({
        'error': 'Invalid continueOnPullFailure value',
        'message': 'continueOnPullFailure must be a boolean',
      });
    }
    final continueOnPullFailure = continueValue as bool? ?? false;
    if (continueOnPullFailure && mode != SyncMode.twoWay) {
      return jsonBadRequest({
        'error': 'Invalid continueOnPullFailure value',
        'message': 'continueOnPullFailure applies only to two_way mode',
      });
    }

    final sectionsResult = _parseSections(body['sections'], mode);
    if (sectionsResult.error != null) {
      return jsonBadRequest(sectionsResult.error!);
    }
    final sections = sectionsResult.sections;
    final expectedSections = sections ?? _exportHandler.sectionKeys;

    DataTransferPhaseOutcome? pull;
    DataTransferPhaseOutcome? push;

    if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
      try {
        pull = await _pull(target, strategy, expectedSections);
      } catch (error) {
        pull = _failure(error);
      }
    }

    if (mode == SyncMode.push) {
      try {
        push = await _push(target, strategy, sections, expectedSections);
      } catch (error) {
        push = _failure(error);
      }
    } else if (mode == SyncMode.twoWay) {
      if (pull!.complete || continueOnPullFailure) {
        try {
          push = await _push(target, strategy, sections, expectedSections);
        } catch (error) {
          push = _failure(error);
        }
      } else {
        push = DataTransferPhaseOutcome(
          status: DataTransferStatus.skipped,
          sections: {},
          reason: 'pull_not_complete',
          message: _skippedPushMessage,
        );
      }
    }

    return _response(mode: mode, pull: pull, push: push);
  }

  Future<DataTransferPhaseOutcome> _pull(
    String target,
    ConflictStrategy strategy,
    List<String> expectedSections,
  ) async {
    _log.info('Pulling data from $target');
    final response = await _httpClient
        .get(Uri.parse('$target/api/v1/data/export'))
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw SyncTargetException(
        'Target error',
        'Target returned status ${response.statusCode}',
      );
    }

    final outcome = await _exportHandler.importFromBytes(
      response.bodyBytes,
      strategy,
      sections: expectedSections,
    );
    return outcome.phase;
  }

  Future<DataTransferPhaseOutcome> _push(
    String target,
    ConflictStrategy strategy,
    List<String>? sections,
    List<String> expectedSections,
  ) async {
    _log.info('Pushing data to $target');
    final List<int> zipBytes;
    try {
      zipBytes = await _exportHandler.exportToBytes(sections: sections);
    } catch (error) {
      throw _LocalExportException(error);
    }

    final response = await _httpClient
        .post(
          Uri.parse('$target/api/v1/data/import?onConflict=${strategy.name}'),
          body: zipBytes,
          headers: {'Content-Type': 'application/octet-stream'},
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200 && response.statusCode != 207) {
      throw SyncTargetException(
        'Target error',
        'Target returned status ${response.statusCode}',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      return DataTransferPhaseOutcome.failed(
        error: 'Invalid target response',
        message: 'The target returned invalid JSON.',
        reason: 'invalid_json',
      );
    }
    return DataTransferPhaseOutcome.fromRemote(decoded, expectedSections);
  }

  Response _response({
    required SyncMode mode,
    required DataTransferPhaseOutcome? pull,
    required DataTransferPhaseOutcome? push,
  }) {
    final phases = [pull, push].whereType<DataTransferPhaseOutcome>().toList();
    final status = _operationStatus(mode, phases);
    final result = <String, dynamic>{
      'status': status.name,
      'complete': status == DataTransferStatus.complete,
      'partial': status == DataTransferStatus.partial,
      'mode': _wireMode(mode),
      if (pull != null) 'pull': pull.sectionResults,
      if (push != null) 'push': push.sectionResults,
      'phases': {
        if (pull != null) 'pull': pull.toMetadata(),
        if (push != null) 'push': push.toMetadata(),
      },
    };

    if (status == DataTransferStatus.complete) return jsonOk(result);
    if (mode == SyncMode.twoWay && status == DataTransferStatus.partial) {
      return jsonMultiStatus(result);
    }
    return jsonBadGateway(result);
  }

  DataTransferStatus _operationStatus(
    SyncMode mode,
    List<DataTransferPhaseOutcome> phases,
  ) {
    if (phases.every((phase) => phase.complete)) {
      return DataTransferStatus.complete;
    }
    if (mode == SyncMode.twoWay &&
        phases.any(
          (phase) =>
              phase.status == DataTransferStatus.complete ||
              phase.status == DataTransferStatus.partial,
        )) {
      return DataTransferStatus.partial;
    }
    if (mode != SyncMode.twoWay &&
        phases.any((phase) => phase.status == DataTransferStatus.partial)) {
      return DataTransferStatus.partial;
    }
    return DataTransferStatus.failed;
  }

  DataTransferPhaseOutcome _failure(Object error) {
    if (error is InvalidBackupException) {
      return DataTransferPhaseOutcome.failed(
        error: 'Invalid backup archive',
        message: error.message,
        reason: error.reason,
      );
    }
    if (error is _LocalExportException) {
      return DataTransferPhaseOutcome.failed(
        error: 'Local export failed',
        message: '${error.cause}',
        reason: 'local_export_failed',
      );
    }
    if (error is SyncTargetException) {
      return DataTransferPhaseOutcome.failed(
        error: error.error,
        message: error.message,
        reason: 'target_error',
      );
    }
    if (error is http.ClientException) {
      return DataTransferPhaseOutcome.failed(
        error: 'Target unreachable',
        message: error.message,
        reason: 'target_unreachable',
      );
    }
    if (error is TimeoutException) {
      return DataTransferPhaseOutcome.failed(
        error: 'Target unreachable',
        message: 'Request timed out after ${_requestTimeout.inSeconds} seconds',
        reason: 'timeout',
      );
    }
    return DataTransferPhaseOutcome.failed(
      error: 'Sync failed',
      message: '$error',
      reason: 'unexpected_error',
    );
  }

  _SectionsResult _parseSections(dynamic value, SyncMode mode) {
    if (value == null) {
      if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
        final modeName = mode == SyncMode.twoWay ? 'two_way' : 'pull';
        return _SectionsResult.errorResult({
          'error': 'Missing required field',
          'message':
              '"sections" is required and must not be empty for $modeName mode',
        });
      }
      return const _SectionsResult(null);
    }
    if (value is! List || value.any((section) => section is! String)) {
      return _SectionsResult.errorResult({
        'error': 'Invalid sections value',
        'message': 'sections must be an array of section names',
      });
    }

    final sections = <String>[];
    for (final section in value.cast<String>()) {
      if (!sections.contains(section)) sections.add(section);
    }
    if (sections.isEmpty) {
      return _SectionsResult.errorResult({
        'error': 'Invalid sections value',
        'message': 'sections must not be empty',
      });
    }
    final unknown = sections
        .where((section) => !_exportHandler.sectionKeys.contains(section))
        .toList(growable: false);
    if (unknown.isNotEmpty) {
      return _SectionsResult.errorResult({
        'error': 'Unknown section',
        'message': 'Unknown data section(s): ${unknown.join(', ')}',
      });
    }
    return _SectionsResult(sections);
  }

  SyncMode? _parseMode(String value) => switch (value) {
    'pull' => SyncMode.pull,
    'push' => SyncMode.push,
    'two_way' => SyncMode.twoWay,
    _ => null,
  };

  String _wireMode(SyncMode mode) => switch (mode) {
    SyncMode.pull => 'pull',
    SyncMode.push => 'push',
    SyncMode.twoWay => 'two_way',
  };

  ConflictStrategy? _parseStrategy(String value) => switch (value) {
    'skip' => ConflictStrategy.skip,
    'overwrite' => ConflictStrategy.overwrite,
    _ => null,
  };
}

class _SectionsResult {
  final List<String>? sections;
  final Map<String, dynamic>? error;

  const _SectionsResult(this.sections) : error = null;

  const _SectionsResult.errorResult(this.error) : sections = null;
}
