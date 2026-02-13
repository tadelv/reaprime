part of '../webserver_service.dart';

/// REST API handler for submitting user feedback as GitHub issues
class FeedbackHandler {
  final FeedbackService _service;

  FeedbackHandler({required FeedbackService service}) : _service = service;

  void addRoutes(RouterPlus app) {
    // Submit feedback
    app.post('/api/v1/feedback', _handleSubmitFeedback);
  }

  /// POST /api/v1/feedback
  /// Body: { description: string, type: string, includeLogs?: bool, includeSystemInfo?: bool }
  Future<Response> _handleSubmitFeedback(Request request) async {
    try {
      if (!_service.isConfigured) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'Service unavailable',
            'message':
                'Feedback service is not configured. Build with --dart-define=GITHUB_FEEDBACK_TOKEN=<token>',
          }),
        );
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (!json.containsKey('description') ||
          (json['description'] as String).trim().isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required field',
            'message': 'Request must contain a non-empty "description" field',
          }),
        );
      }

      final feedbackRequest = FeedbackRequest.fromJson(json);
      final result = await _service.submitFeedback(feedbackRequest);

      if (result.success) {
        return Response(
          201,
          body: jsonEncode(result.toJson()),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.internalServerError(
          body: jsonEncode(result.toJson()),
        );
      }
    } catch (e, st) {
      log.severe('Error in _handleSubmitFeedback', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }
}
