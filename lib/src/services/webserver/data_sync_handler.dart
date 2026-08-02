import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Sync modes for data synchronization between two Decent instances.
enum SyncMode { pull, push, twoWay }

enum SyncPhaseStatus { complete, partial, failed, fatal, skipped }

class SyncPhaseOutcome {
  final SyncPhaseStatus status;
  final Map<String, dynamic> result;

  SyncPhaseOutcome({required this.status, required Map<String, dynamic> result})
    : result = Map.unmodifiable({...result, 'phaseStatus': status.name});
}

/// Exception thrown when the sync target returns an error.
class SyncTargetException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  SyncTargetException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'SyncTargetException: $message';
}

/// Handles data synchronization between two Decent instances.
///
/// Supports three modes:
/// - **pull**: Fetch data from a remote instance and import it locally.
/// - **push**: Export local data and send it to a remote instance.
/// - **two_way**: Pull then push (both directions).
///
/// Uses the existing export/import ZIP format via [DataExportHandler].
class DataSyncHandler {
  static const _requestTimeout = Duration(seconds: 30);

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
    // Parse request body
    final String bodyStr;
    try {
      bodyStr = await request.readAsString();
    } catch (e) {
      return jsonBadRequest({'error': 'Could not read request body'});
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (e) {
      return jsonBadRequest({'error': 'Invalid JSON'});
    }

    // Validate required fields
    final target = body['target'] as String?;
    if (target == null || target.isEmpty) {
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

    final modeStr = body['mode'] as String?;
    if (modeStr == null) {
      return jsonBadRequest({
        'error': 'Missing required field',
        'message': '"mode" is required. Valid values: pull, push, two_way',
      });
    }

    final SyncMode mode;
    switch (modeStr) {
      case 'pull':
        mode = SyncMode.pull;
      case 'push':
        mode = SyncMode.push;
      case 'two_way':
        mode = SyncMode.twoWay;
      default:
        return jsonBadRequest({
          'error': 'Invalid mode',
          'message': 'Valid values: pull, push, two_way',
        });
    }

    final onConflict = body['onConflict'] as String? ?? 'skip';
    final ConflictStrategy strategy;
    switch (onConflict) {
      case 'skip':
        strategy = ConflictStrategy.skip;
      case 'overwrite':
        strategy = ConflictStrategy.overwrite;
      default:
        return jsonBadRequest({
          'error': 'Invalid onConflict value',
          'message': 'Valid values: skip, overwrite',
        });
    }

    final sections = (body['sections'] as List<dynamic>?)?.cast<String>();
    final bestEffortValue = body['bestEffort'];
    if (bestEffortValue != null && bestEffortValue is! bool) {
      return jsonBadRequest({
        'error': 'Invalid bestEffort value',
        'message': '"bestEffort" must be a boolean',
      });
    }
    final bestEffort = bestEffortValue as bool? ?? false;

    // Execute sync
    final results = <String, dynamic>{};
    final phaseStatuses = <SyncPhaseStatus>[];
    SyncPhaseOutcome? pullOutcome;

    // Pull phase
    if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
      pullOutcome = await _runPhase(() => _pull(target, strategy, sections));
      results['pull'] = pullOutcome.result;
      phaseStatuses.add(pullOutcome.status);
    }

    // Push phase
    if (mode == SyncMode.push || mode == SyncMode.twoWay) {
      final pushOutcome =
          mode == SyncMode.twoWay &&
              !bestEffort &&
              pullOutcome?.status != SyncPhaseStatus.complete
          ? _skippedPushOutcome()
          : await _runPhase(() => _push(target, strategy, sections));
      results['push'] = pushOutcome.result;
      phaseStatuses.add(pushOutcome.status);
    }

    if (mode != SyncMode.twoWay) {
      return switch (phaseStatuses.single) {
        SyncPhaseStatus.complete => jsonOk(results),
        SyncPhaseStatus.partial => jsonMultiStatus(results),
        SyncPhaseStatus.failed => jsonBadGateway(results),
        SyncPhaseStatus.fatal => jsonBadGateway(results),
        SyncPhaseStatus.skipped => jsonBadGateway(results),
      };
    }

    final hasSuccessfulPhase = phaseStatuses.any(
      (status) =>
          status == SyncPhaseStatus.complete ||
          status == SyncPhaseStatus.partial,
    );
    if (!hasSuccessfulPhase) return jsonBadGateway(results);
    if (phaseStatuses.every((status) => status == SyncPhaseStatus.complete)) {
      return jsonOk(results);
    }
    return jsonMultiStatus(results);
  }

  Future<SyncPhaseOutcome> _runPhase(
    Future<SyncPhaseOutcome> Function() phase,
  ) async {
    try {
      return await phase();
    } catch (e) {
      return SyncPhaseOutcome(
        status: SyncPhaseStatus.fatal,
        result: _errorResult(e),
      );
    }
  }

  /// Pull data from the target instance and import it locally.
  Future<SyncPhaseOutcome> _pull(
    String target,
    ConflictStrategy strategy,
    List<String>? sections,
  ) async {
    _log.info('Pulling data from $target');

    final uri = Uri.parse('$target/api/v1/data/export');
    final response = await _httpClient.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw SyncTargetException(
        'Target returned status ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final outcome = await _exportHandler.importFromBytes(
      response.bodyBytes,
      strategy,
      sections: sections,
      strictSections: sections != null,
    );
    return SyncPhaseOutcome(
      status: switch (outcome.status) {
        DataOutcomeStatus.complete => SyncPhaseStatus.complete,
        DataOutcomeStatus.partial => SyncPhaseStatus.partial,
        DataOutcomeStatus.failed => SyncPhaseStatus.failed,
        DataOutcomeStatus.skipped => SyncPhaseStatus.skipped,
      },
      result: outcome.toSyncJson(),
    );
  }

  /// Export local data and push it to the target instance.
  Future<SyncPhaseOutcome> _push(
    String target,
    ConflictStrategy strategy,
    List<String>? sections,
  ) async {
    _log.info('Pushing data to $target');

    final zipBytes = await _exportHandler.exportToBytes(sections: sections);

    final uri = Uri.parse(
      '$target/api/v1/data/import?onConflict=${strategy.name}',
    );
    final response = await _httpClient
        .post(
          uri,
          body: zipBytes,
          headers: {'Content-Type': 'application/octet-stream'},
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200 && response.statusCode != 207) {
      throw SyncTargetException(
        'Target returned status ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw SyncTargetException(
        'Target returned invalid JSON',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    if (decoded is! Map) {
      throw SyncTargetException(
        'Target returned invalid JSON',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final result = Map<String, dynamic>.from(decoded);
    final sectionResults = result.entries
        .where((entry) => entry.key != 'phaseStatus' && entry.value is Map)
        .toList(growable: false);
    if (sectionResults.isEmpty) {
      throw SyncTargetException(
        'Target returned no section results',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final failedSections = sectionResults
        .where((entry) => _isFailedSection(entry.value))
        .length;
    final allSectionsComplete = sectionResults.every(
      (entry) => _isCompleteSection(entry.value),
    );

    return SyncPhaseOutcome(
      status: response.statusCode == 207
          ? failedSections == sectionResults.length
                ? SyncPhaseStatus.failed
                : SyncPhaseStatus.partial
          : allSectionsComplete
          ? SyncPhaseStatus.complete
          : failedSections == sectionResults.length
          ? SyncPhaseStatus.failed
          : SyncPhaseStatus.partial,
      result: result,
    );
  }

  SyncPhaseOutcome _skippedPushOutcome() => SyncPhaseOutcome(
    status: SyncPhaseStatus.skipped,
    result: {
      'message':
          'Push skipped because pull did not complete. Set bestEffort to true to continue.',
      'reason': 'pull_not_complete',
    },
  );

  bool _hasSectionErrors(Object? value) {
    if (value is! Map) return false;
    final status = value['status'];
    if (status == 'partial' || status == 'failed' || status == 'skipped') {
      return true;
    }
    final errors = value['errors'];
    if (errors == null) return false;
    if (errors is! List) return true;
    return errors.isNotEmpty;
  }

  bool _isCompleteSection(Object? value) {
    if (value is! Map) return false;
    final status = value['status'];
    if (status is String) return status == DataOutcomeStatus.complete.name;
    return !_hasSectionErrors(value);
  }

  bool _isFailedSection(Object? value) {
    if (value is! Map) return true;
    final status = value['status'];
    if (status is String) {
      return status == DataOutcomeStatus.failed.name ||
          status == DataOutcomeStatus.skipped.name;
    }
    if (!_hasSectionErrors(value)) return false;
    final imported = value['imported'];
    final skipped = value['skipped'];
    return !((imported is num && imported > 0) ||
        (skipped is num && skipped > 0));
  }

  Map<String, dynamic> _errorResult(Object error) {
    if (error is InvalidBackupException) {
      return {'error': 'Invalid backup archive', 'message': error.message};
    }
    if (error is DataExportException) {
      return {
        'error': 'Local export failed',
        'message': error.message,
        'sections': error.failedSections.toList(growable: false),
      };
    }
    if (error is SyncTargetException) {
      return {
        'error': 'Target error',
        'status': error.statusCode,
        'message': error.message,
      };
    }
    if (error is http.ClientException) {
      return {'error': 'Target unreachable', 'message': error.message};
    }
    if (error is TimeoutException) {
      return {
        'error': 'Target unreachable',
        'message':
            'Request timed out after ${_requestTimeout.inSeconds} seconds',
      };
    }
    return {'error': 'Sync failed', 'message': '$error'};
  }
}
