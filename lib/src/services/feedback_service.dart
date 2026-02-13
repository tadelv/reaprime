import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/models/feedback/feedback_request.dart';
import 'package:reaprime/src/models/feedback/feedback_result.dart';

/// Service responsible for submitting user feedback as GitHub issues.
///
/// Uses the GitHub API to create issues and optionally attach logs as Gists.
class FeedbackService {
  final String _githubToken;
  final String _repo;
  final Logger _log = Logger('FeedbackService');

  static const String _githubApiBase = 'https://api.github.com';

  FeedbackService({
    required String githubToken,
    String repo = 'tadelv/reaprime',
  })  : _githubToken = githubToken,
        _repo = repo;

  /// Whether the service is configured with a valid token
  bool get isConfigured => _githubToken.isNotEmpty;

  /// Submit feedback as a GitHub issue
  Future<FeedbackSubmissionResult> submitFeedback(
    FeedbackRequest request,
  ) async {
    if (!isConfigured) {
      return FeedbackSubmissionResult.failed(
        'Feedback service is not configured. No GitHub token provided at build time.',
      );
    }

    try {
      _log.info('Submitting ${request.type.name} feedback');

      // Collect system info if requested
      String systemInfo = '';
      if (request.includeSystemInfo) {
        systemInfo = _collectSystemInfo();
      }

      // Upload logs as Gist if requested
      String? gistUrl;
      if (request.includeLogs) {
        gistUrl = await _uploadLogsAsGist();
      }

      // Build issue body
      final body = _buildIssueBody(
        request: request,
        systemInfo: systemInfo,
        gistUrl: gistUrl,
      );

      // Create GitHub issue
      final issueResult = await _createGitHubIssue(
        title: _buildIssueTitle(request),
        body: body,
        labels: _buildLabels(request),
      );

      if (issueResult == null) {
        return FeedbackSubmissionResult.failed(
          'Failed to create GitHub issue',
        );
      }

      final issueNumber = issueResult['number'] as int;
      final issueUrl = issueResult['html_url'] as String;

      // Upload screenshot as comment if provided
      if (request.screenshot != null) {
        await _addScreenshotComment(
          issueNumber: issueNumber,
          screenshot: request.screenshot!,
        );
      }

      _log.info('Feedback submitted successfully as issue #$issueNumber');
      return FeedbackSubmissionResult.succeeded(
        issueUrl: issueUrl,
        issueNumber: issueNumber,
      );
    } catch (e, st) {
      _log.severe('Failed to submit feedback', e, st);
      return FeedbackSubmissionResult.failed('Failed to submit feedback: $e');
    }
  }

  /// Collect system information for the feedback report
  String _collectSystemInfo() {
    final info = StringBuffer();
    info.writeln('**System Information:**');
    info.writeln('- App Version: ${BuildInfo.version}');
    info.writeln('- Commit: ${BuildInfo.commitShort}');
    info.writeln('- Branch: ${BuildInfo.branch}');
    info.writeln('- Platform: ${Platform.operatingSystem}');
    info.writeln('- OS Version: ${Platform.operatingSystemVersion}');
    info.writeln('- Dart Version: ${Platform.version}');
    return info.toString();
  }

  /// Read the log file and upload it as a GitHub Gist
  Future<String?> _uploadLogsAsGist() async {
    try {
      String? logContent;

      // Try Android log path first
      if (Platform.isAndroid) {
        final androidLogFile =
            File('/storage/emulated/0/Download/REA1/log.txt');
        if (await androidLogFile.exists()) {
          logContent = await androidLogFile.readAsString();
        }
      }

      // Fall back to app documents directory
      if (logContent == null) {
        final docs = await getApplicationDocumentsDirectory();
        final logFile = File('${docs.path}/log.txt');
        if (await logFile.exists()) {
          logContent = await logFile.readAsString();
        }
      }

      if (logContent == null || logContent.isEmpty) {
        _log.info('No log file found to upload');
        return null;
      }

      // Truncate if too large (GitHub Gist has limits)
      const maxLogSize = 500000; // ~500KB
      if (logContent.length > maxLogSize) {
        logContent =
            '... (truncated, showing last ${maxLogSize ~/ 1024}KB) ...\n${logContent.substring(logContent.length - maxLogSize)}';
      }

      final response = await http.post(
        Uri.parse('$_githubApiBase/gists'),
        headers: _authHeaders,
        body: jsonEncode({
          'description': 'ReaPrime feedback logs - ${DateTime.now().toIso8601String()}',
          'public': false,
          'files': {
            'reaprime_logs.txt': {
              'content': logContent,
            },
          },
        }),
      );

      if (response.statusCode == 201) {
        final gistData = jsonDecode(response.body) as Map<String, dynamic>;
        final gistUrl = gistData['html_url'] as String;
        _log.info('Logs uploaded as Gist: $gistUrl');
        return gistUrl;
      } else {
        _log.warning(
          'Failed to create Gist: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      _log.warning('Failed to upload logs as Gist', e);
      return null;
    }
  }

  /// Build the title for the GitHub issue
  String _buildIssueTitle(FeedbackRequest request) {
    final prefix = '[${request.type.displayName}]';
    // Use first line or first 80 chars of description as title
    final firstLine = request.description.split('\n').first;
    final title = firstLine.length > 80
        ? '${firstLine.substring(0, 77)}...'
        : firstLine;
    return '$prefix $title';
  }

  /// Build the body content for the GitHub issue
  String _buildIssueBody({
    required FeedbackRequest request,
    required String systemInfo,
    String? gistUrl,
  }) {
    final body = StringBuffer();

    body.writeln('## Description');
    body.writeln(request.description);
    body.writeln();

    if (systemInfo.isNotEmpty) {
      body.writeln('## System Info');
      body.writeln(systemInfo);
      body.writeln();
    }

    if (gistUrl != null) {
      body.writeln('## Logs');
      body.writeln('Application logs: $gistUrl');
      body.writeln();
    }

    body.writeln('---');
    body.writeln(
      '_Submitted via in-app feedback on ${request.timestamp.toIso8601String()}_',
    );

    return body.toString();
  }

  /// Build the labels for the GitHub issue
  List<String> _buildLabels(FeedbackRequest request) {
    return ['user-feedback', request.type.issueLabel];
  }

  /// Create a GitHub issue via the API
  Future<Map<String, dynamic>?> _createGitHubIssue({
    required String title,
    required String body,
    required List<String> labels,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_githubApiBase/repos/$_repo/issues'),
        headers: _authHeaders,
        body: jsonEncode({
          'title': title,
          'body': body,
          'labels': labels,
        }),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        _log.severe(
          'Failed to create issue: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      _log.severe('Failed to create GitHub issue', e);
      return null;
    }
  }

  /// Add a screenshot as a comment on the issue using base64 encoding
  Future<void> _addScreenshotComment({
    required int issueNumber,
    required List<int> screenshot,
  }) async {
    try {
      final base64Image = base64Encode(screenshot);
      final commentBody =
          '## Screenshot\n\n![Screenshot](data:image/png;base64,$base64Image)';

      final response = await http.post(
        Uri.parse(
          '$_githubApiBase/repos/$_repo/issues/$issueNumber/comments',
        ),
        headers: _authHeaders,
        body: jsonEncode({
          'body': commentBody,
        }),
      );

      if (response.statusCode == 201) {
        _log.info('Screenshot added to issue #$issueNumber');
      } else {
        _log.warning(
          'Failed to add screenshot comment: ${response.statusCode}',
        );
      }
    } catch (e) {
      _log.warning('Failed to add screenshot comment', e);
    }
  }

  /// Common auth headers for GitHub API requests
  Map<String, String> get _authHeaders => {
        'Authorization': 'token $_githubToken',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      };
}
