import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Sync modes for data synchronization between two Streamline Bridge instances.
enum SyncMode { pull, push, twoWay }

/// Exception thrown when the sync target returns an error.
class SyncTargetException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  SyncTargetException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'SyncTargetException: $message';
}

/// Handles data synchronization between two Streamline Bridge instances.
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
  })  : _exportHandler = exportHandler,
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
        'message':
            '"mode" is required. Valid values: pull, push, two_way',
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
    bool pullFailed = false;
    bool pushFailed = false;

    // Pull phase
    if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
      try {
        final pullResult = await _pull(target, strategy, sections);
        results['pull'] = pullResult;
      } catch (e) {
        pullFailed = true;
        results['pull'] = _errorResult(e);
      }
    }

    // Push phase
    if (mode == SyncMode.push || mode == SyncMode.twoWay) {
      try {
        final pushResult = await _push(target, strategy, sections);
        results['push'] = pushResult;
      } catch (e) {
        pushFailed = true;
        results['push'] = _errorResult(e);
      }
    }

    // Determine response status:
    // - 200: all phases succeeded
    // - 207: partial success in two_way mode (one phase failed)
    // - 502: all phases failed, or single-direction mode failed
    if (mode == SyncMode.twoWay && (pullFailed != pushFailed)) {
      return jsonMultiStatus(results);
    }

    if (pullFailed || pushFailed) {
      return jsonBadGateway(results);
    }

    return jsonOk(results);
  }

  /// Pull data from the target instance and import it locally.
  Future<Map<String, dynamic>> _pull(
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

    return await _exportHandler.importFromBytes(
      response.bodyBytes,
      strategy,
      sections: sections,
    );
  }

  /// Export local data and push it to the target instance.
  Future<Map<String, dynamic>> _push(
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

    if (response.statusCode != 200) {
      throw SyncTargetException(
        'Target returned status ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> _errorResult(Object error) {
    if (error is SyncTargetException) {
      return {
        'error': 'Target error',
        'status': error.statusCode,
        'message': error.message,
      };
    }
    if (error is http.ClientException) {
      return {
        'error': 'Target unreachable',
        'message': error.message,
      };
    }
    if (error is TimeoutException) {
      return {
        'error': 'Target unreachable',
        'message': 'Request timed out after ${_requestTimeout.inSeconds} seconds',
      };
    }
    return {
      'error': 'Sync failed',
      'message': '$error',
    };
  }
}
