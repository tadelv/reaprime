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

enum SyncPhaseStatus { complete, partial, fatal }

class SyncPhaseOutcome {
  final SyncPhaseStatus status;
  final Map<String, dynamic> result;

  const SyncPhaseOutcome({required this.status, required this.result});
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

    // Execute sync
    final results = <String, dynamic>{};
    var fatalPhases = 0;
    var partialPhase = false;

    // Pull phase
    if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
      final pullOutcome = await _runPhase(
        () => _pull(target, strategy, sections),
      );
      results['pull'] = pullOutcome.result;
      fatalPhases += pullOutcome.status == SyncPhaseStatus.fatal ? 1 : 0;
      partialPhase |= pullOutcome.status == SyncPhaseStatus.partial;
    }

    // Push phase
    if (mode == SyncMode.push || mode == SyncMode.twoWay) {
      final pushOutcome = await _runPhase(
        () => _push(target, strategy, sections),
      );
      results['push'] = pushOutcome.result;
      fatalPhases += pushOutcome.status == SyncPhaseStatus.fatal ? 1 : 0;
      partialPhase |= pushOutcome.status == SyncPhaseStatus.partial;
    }

    if (fatalPhases > 0 && mode == SyncMode.twoWay && fatalPhases < 2) {
      return jsonMultiStatus(results);
    }

    if (fatalPhases > 0) {
      return jsonBadGateway(results);
    }

    if (partialPhase) return jsonMultiStatus(results);

    return jsonOk(results);
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
    );
    return SyncPhaseOutcome(
      status: outcome.isPartial
          ? SyncPhaseStatus.partial
          : SyncPhaseStatus.complete,
      result: outcome.toJson(),
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

    return SyncPhaseOutcome(
      status: response.statusCode == 207
          ? SyncPhaseStatus.partial
          : SyncPhaseStatus.complete,
      result: Map<String, dynamic>.from(decoded),
    );
  }

  Map<String, dynamic> _errorResult(Object error) {
    if (error is InvalidBackupException) {
      return {'error': 'Invalid backup archive', 'message': error.message};
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
