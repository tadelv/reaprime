import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/home_feature/widgets/quick_settings_widget.dart';
import 'package:reaprime/src/services/webview_compatibility_checker.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// Displays the WebUI skin in a full-screen webview
///
/// This view is only shown on mobile/desktop platforms (iOS, Android, macOS)
/// and provides a webview interface to the locally-served WebUI at localhost:3000.
///
/// The view includes a back button in the app bar to navigate to the home dashboard.
class SkinView extends StatefulWidget {
  const SkinView({
    super.key,
    required this.settingsController,
    required this.webViewLogService,
    required this.deviceIp,
  });

  final SettingsController settingsController;
  final WebViewLogService webViewLogService;
  final String deviceIp;

  static const routeName = '/skin';

  @override
  State<SkinView> createState() => _SkinViewState();
}

class _SkinViewState extends State<SkinView> {
  final _log = Logger('SkinView');
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isCheckingCompatibility = true;
  String? _errorMessage;
  CompatibilityResult? _compatibilityResult;

  late InAppWebViewSettings _settings;

  bool _didShowExit = false;

  @override
  void initState() {
    super.initState();
    _checkCompatibilityAndInit();
  }

  @override
  void dispose() {
    _log.fine("disposing");
    super.dispose();
  }

  Future<void> _checkCompatibilityAndInit() async {
    _log.info('Checking WebView compatibility...');

    // Clear all cached WebView data and force service workers to
    // bypass their cache. This prevents a stale SW from a previously-
    // loaded skin serving cached HTML/CSS/JS that references assets
    // from the wrong skin directory.
    await InAppWebViewController.clearAllCache();
    if (Platform.isAndroid &&
        ServiceWorkerController.isClassSupported()) {
      await ServiceWorkerController.setCacheMode(CacheMode.LOAD_NO_CACHE);
      _log.fine('Service worker cache mode set to LOAD_NO_CACHE');
    }

    final result = await WebViewCompatibilityChecker.checkCompatibility();

    setState(() {
      _compatibilityResult = result;
      _isCheckingCompatibility = false;
    });

    if (result.isCompatible) {
      _log.info('WebView is compatible, initializing...');
      _initializeSettings();
    } else {
      _log.warning('WebView is not compatible: ${result.reason}');
    }
  }

  void _initializeSettings() {
    _log.info(
      'Initializing InAppWebView settings for platform: ${Platform.operatingSystem}',
    );

    // Simple, standard WebView settings for modern devices
    // Problematic devices are filtered out by WebViewCompatibilityChecker
    _settings = InAppWebViewSettings(
      // JavaScript
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,

      // Media
      mediaPlaybackRequiresUserGesture: false,

      // Security - restrict file access for localhost-only content
      allowFileAccessFromFileURLs: false,
      allowUniversalAccessFromFileURLs: false,

      // Navigation
      useShouldOverrideUrlLoading: true,

      // Caching
      cacheEnabled: false,

      // Zoom - disable for consistent UI
      supportZoom: false,
      builtInZoomControls: false,
      enableViewportScale: true,

      // Scrollbars - hide on all platforms
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,

      // displayZoomControls: false,
      userAgent: "Streamline-Bridge",
    );

    _log.info('InAppWebView settings initialized');
  }

  void _showExitInstructions() {
    String instructions;

    if (Platform.isIOS) {
      instructions =
          'Swipe right from the left side of the screen to return to Dashboard';
    } else if (Platform.isAndroid) {
      instructions = 'Use system back button to return to Dashboard';
    } else if (Platform.isMacOS) {
      instructions = 'Press ⌘D or use View → Back to Dashboard to return';
    } else {
      // Fallback for other platforms
      instructions = 'Use back navigation to return to Dashboard';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(instructions),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        showCloseIcon: true,
        // action: SnackBarAction(
        //   label: 'Dismiss',
        //   onPressed: () {
        //     ScaffoldMessenger.of(context).hideCurrentSnackBar();
        //   },
        // ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar for fullscreen appearance
      body: SafeArea(
        // Allow content to extend into system UI areas for true fullscreen
        top: false,
        bottom: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildIncompatibilityMessage() {
    final result = _compatibilityResult!;

    IconData icon;
    Color iconColor;
    String title;
    String description;

    switch (result.issue) {
      case CompatibilityIssue.knownProblematicDevice:
        icon = Icons.tablet_android;
        iconColor = Colors.orange;
        title = 'WebView Not Supported';
        description =
            'Your device has known compatibility issues with the embedded web view.\n\n${result.reason}';
        break;
      case CompatibilityIssue.oldAndroidVersion:
        icon = Icons.phone_android;
        iconColor = Colors.orange;
        title = 'Android Version Too Old';
        description =
            'Your Android version does not support the required WebView features.\n\n${result.reason}';
        break;
      case CompatibilityIssue.webViewRenderingFailed:
        icon = Icons.warning;
        iconColor = Colors.red;
        title = 'WebView Test Failed';
        description =
            'The WebView compatibility test failed on your device.\n\n${result.reason}';
        break;
      case CompatibilityIssue.webViewNotAvailable:
        icon = Icons.error;
        iconColor = Colors.red;
        title = 'WebView Not Available';
        description =
            'Unable to initialize WebView on your device.\n\n${result.reason}';
        break;
      default:
        icon = Icons.info;
        iconColor = Colors.blue;
        title = 'Compatibility Issue';
        description = result.reason;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            Icon(icon, size: 48, color: iconColor),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            const Divider(),
            Text(
              'You can use an external browser instead:',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _openInExternalBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open in Browser'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop();
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Dashboard'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Show address'),
                  onPressed: () {
                    QuickSettingsWidget.showQRCodeDialog(context, widget.deviceIp);
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () async {
                    _log.info('Retrying compatibility check...');
                    setState(() {
                      _isCheckingCompatibility = true;
                      _compatibilityResult = null;
                    });
                    WebViewCompatibilityChecker.clearCache();
                    await _checkCompatibilityAndInit();
                  },
                  child: const Text('Retry Compatibility Check'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _compatibilityResult = null;
                    });
                    _initializeSettings();
                  },
                  child: const Text('Ignore and load anyway'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExternalBrowser() async {
    final url = Uri.parse('http://localhost:3000');
    _log.info('Opening WebUI in external browser: $url');

    try {
      final canLaunch = await canLaunchUrl(url);
      if (canLaunch) {
        await launchUrl(url, mode: LaunchMode.externalApplication);

        // Return to dashboard after opening browser
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        _log.warning('Cannot launch URL: $url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Unable to open browser. Please open $url manually.',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      _log.severe('Failed to open external browser', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening browser: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildBody() {
    // Show compatibility check in progress
    if (_isCheckingCompatibility) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16,
          children: [
            const CircularProgressIndicator(),
            Text(
              'Checking device compatibility...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    // Show incompatibility message if check failed
    if (_compatibilityResult != null && !_compatibilityResult!.isCompatible) {
      return _buildIncompatibilityMessage();
    }

    // Show error message if WebView failed to load
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              Text(
                'WebView Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop();
                },
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('http://localhost:3000')),
          initialSettings: _settings,
          onWebViewCreated: (controller) {
            _log.info('InAppWebView created');
            _controller = controller;
          },
          onLoadStart: (controller, url) {
            _log.info('Page started loading: $url');
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onLoadStop: (controller, url) async {
            _log.info('Page finished loading: $url');
            setState(() {
              _isLoading = false;
            });

            // Inject CSS to hide scrollbars in web content
            // await controller.evaluateJavascript(source: '''
            //   (function() {
            //     var style = document.createElement('style');
            //     style.textContent = `
            //       ::-webkit-scrollbar {
            //         display: none !important;
            //         width: 0 !important;
            //         height: 0 !important;
            //       }
            //       * {
            //         scrollbar-width: none !important;
            //         -ms-overflow-style: none !important;
            //       }
            //       html, body {
            //         overflow: overlay !important;
            //       }
            //     `;
            //     document.head.appendChild(style);
            //   })();
            // ''');

            // Show exit instructions snackbar
            if (mounted && _didShowExit == false) {
              _didShowExit = true;
              _showExitInstructions();
            }
          },
          onReceivedError: (controller, request, error) {
            _log.severe(
              'WebView error - Code: ${error.type}, Description: ${error.description}',
            );
            setState(() {
              _isLoading = false;
              _errorMessage = 'Failed to load skin: ${error.description}';
            });
          },
          onReceivedHttpError: (controller, request, errorResponse) {
            _log.warning('HTTP error - Status: ${errorResponse.statusCode}');
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url.toString();

            // Allow all navigation within localhost:3000
            if (url.startsWith('http://localhost:3000')) {
              _log.fine('Allowing navigation to: $url');
              return NavigationActionPolicy.ALLOW;
            }

            // Block external navigation
            _log.info('Blocking navigation to: $url');
            return NavigationActionPolicy.CANCEL;
          },
          onConsoleMessage: (controller, consoleMessage) {
            // Route to dedicated webview log service (file + stream)
            final skinId = widget.settingsController.defaultSkinId;
            widget.webViewLogService.log(
              skinId,
              consoleMessage.messageLevel.toString(),
              consoleMessage.message,
            );
            // Also log at FINEST for app-level debug visibility
            _log.finest(
              'WebView Console [$skinId] [${consoleMessage.messageLevel}]: ${consoleMessage.message}',
            );
          },
        ),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
