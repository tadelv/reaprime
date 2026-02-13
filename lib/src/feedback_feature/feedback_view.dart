import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reaprime/src/app.dart';
import 'package:reaprime/src/controllers/feedback_controller.dart';
import 'package:reaprime/src/models/feedback/feedback_request.dart';
import 'package:reaprime/src/services/feedback_service.dart';
import 'package:reaprime/src/services/screenshot_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the feedback dialog for submitting user feedback.
///
/// The [githubToken] is injected at build time via --dart-define.
void showFeedbackDialog(BuildContext context, {required String githubToken}) {
  showShadDialog(
    context: context,
    builder: (context) => FeedbackDialog(githubToken: githubToken),
  );
}

/// Dialog for collecting and submitting user feedback as a GitHub issue.
class FeedbackDialog extends StatefulWidget {
  final String githubToken;

  const FeedbackDialog({super.key, required this.githubToken});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final TextEditingController _descriptionController = TextEditingController();

  late final FeedbackController _controller;

  FeedbackType _selectedType = FeedbackType.bug;
  bool _includeLogs = true;
  bool _includeSystemInfo = true;
  Uint8List? _screenshot;

  @override
  void initState() {
    super.initState();
    _controller = FeedbackController(
      service: FeedbackService(githubToken: widget.githubToken),
    );
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _captureScreenshot() async {
    // Close dialog temporarily to capture clean screenshot
    Navigator.of(context).pop();

    // Small delay to let dialog close
    await Future.delayed(const Duration(milliseconds: 300));

    final navigatorContext = NavigationService.context;
    if (navigatorContext == null || !navigatorContext.mounted) return;

    final bytes = await ScreenshotService.captureScreen(navigatorContext);

    if (navigatorContext.mounted) {
      // Re-open the dialog with screenshot data
      showShadDialog(
        context: navigatorContext,
        builder: (context) => _ReopenedFeedbackDialog(
          githubToken: widget.githubToken,
          description: _descriptionController.text,
          selectedType: _selectedType,
          includeLogs: _includeLogs,
          includeSystemInfo: _includeSystemInfo,
          screenshot: bytes,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    if (!_controller.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Feedback is not configured. Build with --dart-define=GITHUB_FEEDBACK_TOKEN=<token>',
          ),
        ),
      );
      return;
    }

    final request = FeedbackRequest(
      description: _descriptionController.text.trim(),
      type: _selectedType,
      includeLogs: _includeLogs,
      includeSystemInfo: _includeSystemInfo,
      screenshot: _screenshot,
    );

    await _controller.submitFeedback(request);
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('Send Feedback'),
      description: const Text(
        'Feedback will be submitted as a public GitHub issue.',
      ),
      actions: _buildActions(context),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_controller.state == FeedbackState.success) {
      return _buildSuccessContent(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // Feedback type selector
        Text(
          'Type',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        ShadSelect<FeedbackType>(
          initialValue: _selectedType,
          enabled: !_controller.isSubmitting,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedType = value);
            }
          },
          selectedOptionBuilder: (context, value) =>
              Text(value.displayName),
          options: FeedbackType.values
              .map(
                (type) => ShadOption(
                  value: type,
                  child: Text(type.displayName),
                ),
              )
              .toList(),
          placeholder: const Text('Select type...'),
        ),
        const SizedBox(height: 12),
        // Description
        Text(
          'Description',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        ShadInput(
          controller: _descriptionController,
          placeholder: const Text('Describe your feedback...'),
          maxLines: 5,
          minLines: 3,
          enabled: !_controller.isSubmitting,
        ),
        const SizedBox(height: 12),
        // Options
        ShadSwitch(
          value: _includeLogs,
          onChanged: _controller.isSubmitting
              ? null
              : (v) => setState(() => _includeLogs = v),
          label: const Text('Include application logs'),
          sublabel: const Text('Logs will be uploaded as a private Gist'),
        ),
        const SizedBox(height: 8),
        ShadSwitch(
          value: _includeSystemInfo,
          onChanged: _controller.isSubmitting
              ? null
              : (v) => setState(() => _includeSystemInfo = v),
          label: const Text('Include system information'),
          sublabel: const Text('App version, platform, and OS version'),
        ),
        const SizedBox(height: 8),
        // Screenshot section
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                onPressed: _controller.isSubmitting ? null : _captureScreenshot,
                child: Text(
                  _screenshot != null ? 'Retake Screenshot' : 'Take Screenshot',
                ),
              ),
            ),
            if (_screenshot != null) ...[
              const SizedBox(width: 8),
              ShadButton.destructive(
                size: ShadButtonSize.sm,
                onPressed: _controller.isSubmitting
                    ? null
                    : () => setState(() => _screenshot = null),
                child: const Text('Remove'),
              ),
            ],
          ],
        ),
        if (_screenshot != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _screenshot!,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ],
        // Error message
        if (_controller.state == FeedbackState.error &&
            _controller.lastResult?.errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _controller.lastResult!.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSuccessContent(BuildContext context) {
    final result = _controller.lastResult!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          'Feedback submitted!',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Issue #${result.issueNumber}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (result.issueUrl != null)
          ShadButton.outline(
            onPressed: () async {
              await launchUrl(Uri.parse(result.issueUrl!));
            },
            child: const Text('View on GitHub'),
          ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_controller.state == FeedbackState.success) {
      return [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ];
    }

    return [
      ShadButton.outline(
        onPressed:
            _controller.isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ShadButton(
        onPressed: _controller.isSubmitting ? null : _submit,
        child: _controller.isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Submit'),
      ),
    ];
  }
}

/// Internal dialog used when re-opening the feedback dialog after
/// capturing a screenshot. Preserves the user's previous input.
class _ReopenedFeedbackDialog extends StatefulWidget {
  final String githubToken;
  final String description;
  final FeedbackType selectedType;
  final bool includeLogs;
  final bool includeSystemInfo;
  final Uint8List? screenshot;

  const _ReopenedFeedbackDialog({
    required this.githubToken,
    required this.description,
    required this.selectedType,
    required this.includeLogs,
    required this.includeSystemInfo,
    this.screenshot,
  });

  @override
  State<_ReopenedFeedbackDialog> createState() =>
      _ReopenedFeedbackDialogState();
}

class _ReopenedFeedbackDialogState extends State<_ReopenedFeedbackDialog> {
  late final TextEditingController _descriptionController;
  late final FeedbackController _controller;

  late FeedbackType _selectedType;
  late bool _includeLogs;
  late bool _includeSystemInfo;
  late Uint8List? _screenshot;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.description);
    _controller = FeedbackController(
      service: FeedbackService(githubToken: widget.githubToken),
    );
    _controller.addListener(_onControllerChanged);
    _selectedType = widget.selectedType;
    _includeLogs = widget.includeLogs;
    _includeSystemInfo = widget.includeSystemInfo;
    _screenshot = widget.screenshot;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    final request = FeedbackRequest(
      description: _descriptionController.text.trim(),
      type: _selectedType,
      includeLogs: _includeLogs,
      includeSystemInfo: _includeSystemInfo,
      screenshot: _screenshot,
    );

    await _controller.submitFeedback(request);
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('Send Feedback'),
      description: const Text(
        'Feedback will be submitted as a public GitHub issue.',
      ),
      actions: _buildActions(context),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_controller.state == FeedbackState.success) {
      final result = _controller.lastResult!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          Text(
            'Feedback submitted!',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Issue #${result.issueNumber}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (result.issueUrl != null)
            ShadButton.outline(
              onPressed: () async {
                await launchUrl(Uri.parse(result.issueUrl!));
              },
              child: const Text('View on GitHub'),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Type',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        ShadSelect<FeedbackType>(
          initialValue: _selectedType,
          enabled: !_controller.isSubmitting,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedType = value);
            }
          },
          selectedOptionBuilder: (context, value) =>
              Text(value.displayName),
          options: FeedbackType.values
              .map(
                (type) => ShadOption(
                  value: type,
                  child: Text(type.displayName),
                ),
              )
              .toList(),
          placeholder: const Text('Select type...'),
        ),
        const SizedBox(height: 12),
        Text(
          'Description',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        ShadInput(
          controller: _descriptionController,
          placeholder: const Text('Describe your feedback...'),
          maxLines: 5,
          minLines: 3,
          enabled: !_controller.isSubmitting,
        ),
        const SizedBox(height: 12),
        ShadSwitch(
          value: _includeLogs,
          onChanged: _controller.isSubmitting
              ? null
              : (v) => setState(() => _includeLogs = v),
          label: const Text('Include application logs'),
          sublabel: const Text('Logs will be uploaded as a private Gist'),
        ),
        const SizedBox(height: 8),
        ShadSwitch(
          value: _includeSystemInfo,
          onChanged: _controller.isSubmitting
              ? null
              : (v) => setState(() => _includeSystemInfo = v),
          label: const Text('Include system information'),
          sublabel: const Text('App version, platform, and OS version'),
        ),
        const SizedBox(height: 8),
        if (_screenshot != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Screenshot attached',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              ShadButton.destructive(
                size: ShadButtonSize.sm,
                onPressed: _controller.isSubmitting
                    ? null
                    : () => setState(() => _screenshot = null),
                child: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _screenshot!,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ],
        if (_controller.state == FeedbackState.error &&
            _controller.lastResult?.errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _controller.lastResult!.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_controller.state == FeedbackState.success) {
      return [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ];
    }

    return [
      ShadButton.outline(
        onPressed:
            _controller.isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ShadButton(
        onPressed: _controller.isSubmitting ? null : _submit,
        child: _controller.isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Submit'),
      ),
    ];
  }
}

