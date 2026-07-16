import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/home_feature/widgets/quick_settings_widget.dart';
import 'package:reaprime/src/services/telemetry/boot_timing.dart';
import 'package:reaprime/src/services/webview_compatibility_checker.dart';
import 'package:reaprime/src/services/webview_log_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/skin_feature/simulated_webview_device.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// How the skin webview should treat a navigation target.
enum SkinNavDecision {
  exitDashboard,

  /// Internal navigation — let the webview load it.
  allow,

  /// External http(s) link — open in the system browser, keep the skin loaded.
  openExternal,

  /// Anything else — refuse the navigation.
  block,
}

/// Classifies a navigation target requested from within the skin webview.
///
/// Internal pages (localhost:3000 and the settings plugin) load in-place;
/// external http/https links open in the OS browser; everything else is
/// blocked. Pure so it can be unit-tested without a live webview.
SkinNavDecision classifySkinNavigation(Uri? url) {
  if (url == null) return SkinNavDecision.block;
  if (url.host == 'localhost' && url.path.startsWith('/__decent/')) {
    return url.toString() == skinExitDashboardUrl
        ? SkinNavDecision.exitDashboard
        : SkinNavDecision.block;
  }
  if (url.scheme == 'http' &&
      url.host == 'localhost' &&
      (url.port == 3000 ||
          (url.port == 8080 && url.path.startsWith('/api/v1/plugins/')))) {
    return SkinNavDecision.allow;
  }
  if (url.scheme == 'https' || url.scheme == 'http') {
    return SkinNavDecision.openExternal;
  }
  return SkinNavDecision.block;
}

/// JS predicate evaluated after a skin load settles: did the skin actually come
/// up? True when something rendered into `<body>`, or a skin published its
/// `window.app` bridge. A dead load — index.html parsed but none of the skin's
/// external `<script>`s executed — leaves the body empty and no globals set.
const String skinRenderedProbeJs =
    '(!!(document.body && document.body.childElementCount > 0)) '
    '|| (typeof window.app !== "undefined")';

/// Loading this URL crashes the WebView renderer process. Recreating the Flutter
/// widget alone reuses the same (wedged) renderer and does not recover a blank
/// load; crashing forces a fresh renderer via [onRenderProcessGone].
const String kRendererCrashUrl = 'chrome://crash';

/// Whether a settled skin load that came up blank should be recovered (by
/// forcing a fresh renderer). Pure so the retry policy is unit-testable without
/// a live webview, bounded by [maxRecoveries] so a skin that genuinely cannot
/// load can't spin in a crash loop.
bool shouldRecoverBlankSkin({
  required bool rendered,
  required int priorRecoveries,
  int maxRecoveries = 3,
}) =>
    !rendered && priorRecoveries < maxRecoveries;

class SkinExitCoordinator {
  bool _inProgress = false;

  bool get inProgress => _inProgress;

  bool tryStart({
    required Uri? target,
    required bool isForMainFrame,
    required Uri? topLevelUri,
  }) {
    if (_inProgress ||
        !isForMainFrame ||
        target?.toString() != skinExitDashboardUrl ||
        topLevelUri == null ||
        topLevelUri.scheme != 'http' ||
        topLevelUri.host != 'localhost' ||
        topLevelUri.port != 3000 ||
        topLevelUri.userInfo.isNotEmpty) {
      return false;
    }
    _inProgress = true;
    return true;
  }
}

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

class _SkinViewState extends State<SkinView> with WidgetsBindingObserver {
  final _log = Logger('SkinView');
  bool _isLoading = true;
  bool _isCheckingCompatibility = true;
  String? _errorMessage;
  CompatibilityResult? _compatibilityResult;
  bool _rendererCrashed = false;

  // Blank-skin self-heal. Some launches — notably right after a machine
  // power-cycle, when the reconnect burst competes with the initial page
  // load — bring the webview up with index.html parsed but none of the skin's
  // external <script>s executed: a blank page whose spinner never clears. A
  // page reload does not recover it, and neither does recreating the Flutter
  // widget — both reuse the same wedged renderer PROCESS. Only a fresh renderer
  // does (what a full app restart gives). After each load settles we probe
  // whether the skin rendered and, if not, crash the renderer to force a fresh
  // one via onRenderProcessGone, bounded by [_maxBlankRecoveries].
  static const int _maxBlankRecoveries = 3;
  Timer? _blankSkinWatchdog;
  int _blankRecoveries = 0;

  /// Mirrors an outstanding Android-global WebView.pauseTimers(). Static on
  /// purpose: the paused state lives in the shared renderer process, not in
  /// this State object, so it must survive SkinView dispose/recreate cycles.
  static bool _globalTimersPaused = false;

  InAppWebViewController? _webViewController;
  final _skinExitCoordinator = SkinExitCoordinator();
  Uri? _mainFrameUri;

  bool _didShowExit = false;

  /// The skin URL with cache-busting param
  String get _skinUrl =>
      'http://localhost:3000/?_=${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _checkCompatibilityAndInit();
  }

  @override
  void dispose() {
    _log.fine("disposing");
    _blankPageTimer?.cancel();
    _blankPageTimer = null;
    _blankSkinWatchdog?.cancel();
    _blankSkinWatchdog = null;
    // Balance an outstanding global timer pause before this State (and its
    // controller) are gone: on Android the pause outlives the webview, and a
    // SkinView disposed while backgrounded (machine power-cycle: disconnect,
    // then USB re-attach navigates a fresh stack) would otherwise hand the
    // NEXT webview a paused renderer scheduler — the blank-skin wedge.
    final controller = _webViewController;
    if (_globalTimersPaused && controller != null) {
      _resumeLeakedTimerPause(controller, 'dispose');
    }
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Timer? _blankPageTimer;
  bool _didBlank = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    if (state == AppLifecycleState.paused) {
      if (_webViewController == null) return;
      _log.info('App backgrounded — pausing WebView and loading blank page');
      try {
        if (InAppWebViewController.isMethodSupported(.pause)) {
          _webViewController?.pause();
        }
      } on UnimplementedError catch (e) {
        _log.warning("Unimplemented: ", e);
      } catch (e, st) {
        _log.severe("Unexpected: ", e, st);
      }
      try {
        if (InAppWebViewController.isMethodSupported(.pauseTimers)) {
          _webViewController?.pauseTimers();
          // On Android this pauses layout, parsing and JS timers for ALL
          // WebViews in the shared renderer process, and the paused state
          // outlives this widget and its webview. Track it so dispose() /
          // onWebViewCreated() can balance a pause the resumed event misses.
          _globalTimersPaused = true;
        }
      } on UnimplementedError catch (e) {
        _log.warning("Unimplemented: ", e);
      } catch (e, st) {
        _log.severe("Unexpected: ", e, st);
      }
      _didBlank = false;
      _blankPageTimer?.cancel();
      _blankPageTimer = Timer(Duration(minutes: 10), () {
        _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')),
        );
        _didBlank = true;
      });
    } else if (state == AppLifecycleState.resumed) {
      // Bookkeeping first, NOT gated on the controller existing: a resumed
      // event can arrive while the webview is still being created (or after
      // a renderer crash nulled the controller). The stale blank-page timer
      // must never fire into a foregrounded skin, and a pause that the
      // controller-gated code below cannot balance is healed in
      // onWebViewCreated instead.
      _blankPageTimer?.cancel();
      _blankPageTimer = null;
      if (_webViewController == null) return;
      _log.info('App foregrounded — resuming WebView and reloading skin');
      try {
        if (InAppWebViewController.isMethodSupported(.resumeTimers)) {
          _webViewController?.resumeTimers();
          _globalTimersPaused = false;
        }
      } on UnimplementedError catch (e) {
        _log.warning("Unimplemented: ", e);
      } catch (e, st) {
        _log.severe("Unexpected: ", e, st);
      }
      try {
        if (InAppWebViewController.isMethodSupported(.resume)) {
          _webViewController?.resume();
        }
      } on UnimplementedError catch (e) {
        _log.warning("Unimplemented: ", e);
      } catch (e, st) {
        _log.severe("Unexpected: ", e, st);
      }
      if (_didBlank) {
        _didBlank = false;
        _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(_skinUrl)),
        );
      }
    }
  }

  Future<void> _checkCompatibilityAndInit() async {
    _log.info('Checking WebView compatibility...');

    // Clear HTTP cache. Note: this does NOT clear service worker
    // CacheStorage on Android — the SW is bypassed via a cache-
    // busting query param on the initial URL instead.
    //
    // Skipped on Windows: flutter_inappwebview_windows has no native
    // handler for clearAllCache, and awaiting it hangs SkinView on
    // "Checking compatibility...".
    if (!Platform.isWindows) {
      try {
        await InAppWebViewController.clearAllCache();
        _log.fine('WebView cache cleared');
      } catch (e, st) {
        _log.warning('clearAllCache failed, continuing', e, st);
      }
    }

    final result = await WebViewCompatibilityChecker.checkCompatibility();

    setState(() {
      _compatibilityResult = result;
      _isCheckingCompatibility = false;
    });

    if (result.isCompatible) {
      _log.info('WebView is compatible');
    } else {
      _log.warning('WebView is not compatible: ${result.reason}');
    }
  }

  InAppWebViewSettings _createSettings() {
    return InAppWebViewSettings(
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
      userAgent: "Decent",

      // Memory management: let Android kill the renderer process (not the app)
      // when the WebView is not visible and memory is tight.
      rendererPriorityPolicy: RendererPriorityPolicy(
        rendererRequestedPriority: RendererPriority.RENDERER_PRIORITY_BOUND,
        waivedWhenNotVisible: false,
      ),
      useOnRenderProcessGone: true,
    );
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
    } else if (Platform.isWindows) {
      instructions = 'Press Alt+Backspace to return to Dashboard';
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
        action: SnackBarAction(
          label: "Don't show again",
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            unawaited(
              widget.settingsController.setShowSkinExitInstructions(false),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar for fullscreen appearance
      body: SafeArea(
        // Edge-to-edge: the skin webview owns the entire screen on every side.
        // left/right default to true, which insets the webview and lets the
        // scaffold background bleed through as a 1px line on the right (most
        // visible on dark skins). Disable all four for true fullscreen.
        top: false,
        bottom: false,
        left: false,
        right: false,
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
      case CompatibilityIssue.webView2RuntimeMissing:
        icon = Icons.download;
        iconColor = Colors.orange;
        title = 'WebView2 Runtime Missing';
        description =
            'Microsoft Edge WebView2 Runtime is required to display the '
            'skin on Windows. Install it and restart the app.';
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
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Dashboard'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Show address'),
                  onPressed: () {
                    QuickSettingsWidget.showQRCodeDialog(
                      context,
                      widget.deviceIp,
                    );
                  },
                ),
                if (result.issue == CompatibilityIssue.webView2RuntimeMissing)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Install WebView2'),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
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

  /// Launches an external link from the skin in the OS browser. Failures are
  /// logged only — the skin stays put, so a dead link is a no-op, not a crash.
  Future<void> _launchExternal(Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _log.warning('Cannot launch external URL: $uri');
      }
    } catch (e, st) {
      _log.severe('Failed to launch external URL: $uri', e, st);
    }
  }

  Future<void> _openInExternalBrowser() async {
    final url = Uri.parse(
      'http://localhost:3000?_=${DateTime.now().millisecondsSinceEpoch}',
    );
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
                  Navigator.of(context).pop();
                },
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rendererCrashed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 16,
          children: [
            const CircularProgressIndicator(),
            Text(
              'Reloading skin...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    if (Platform.isWindows) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.backspace, alt: true): () {
            Navigator.of(context).pop();
          },
        },
        child: _buildWebViewStack(),
      );
    }

    return _buildWebViewStack();
  }

  Widget _buildWebViewStack() {
    return ValueListenableBuilder<SimulatedWebViewDevice?>(
      valueListenable: simulatedWebViewDevice,
      builder: (context, simulatedDevice, _) {
        return Stack(
          // Android-only: device-pixel-ratio rounding lays the Android WebView out
          // ~1px short on the right/bottom on some devices, revealing the background
          // as a hairline (flutter_webview_plugin#356/#654, flutter_inappwebview#1542).
          // On Android, size the webview 1px past those edges inside a Clip.none
          // Stack so it covers every pixel; the OS clips the off-screen bleed.
          // Other platforms don't have this compositing quirk.
          clipBehavior: Platform.isAndroid ? Clip.none : Clip.hardEdge,
          children: [
            Positioned.fill(
              right: Platform.isAndroid ? -1 : 0,
              bottom: Platform.isAndroid ? -1 : 0,
              child: _buildWebView(simulatedDevice),
            ),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }

  Widget _buildWebView(SimulatedWebViewDevice? simulatedDevice) {
    return InAppWebView(
      key: ValueKey(simulatedDevice?.id ?? 'native-webview'),
      // Cache-busting param bypasses stale service workers: a SW
      // caches responses by exact URL, so /?_=<ts> won't match
      // its cached '/' and falls through to the network.
      initialUrlRequest: URLRequest(url: WebUri(_skinUrl)),
      initialSettings: _createSettings(),
      initialUserScripts: _initialUserScripts(simulatedDevice),
      onWebViewCreated: (controller) {
        _log.info('InAppWebView created');
        _webViewController = controller;
        // A brand-new webview can inherit a paused renderer scheduler from a
        // global pauseTimers() that was never balanced (SkinView disposed
        // while backgrounded, or `resumed` delivered before this webview
        // existed). Resume is a no-op when nothing is paused, so always
        // balance here — the initial load must never start wedged.
        _resumeLeakedTimerPause(controller, 'onWebViewCreated');
      },
      onLoadStart: (controller, url) {
        _log.info('Page started loading: $url');
        _mainFrameUri = url;
        // Webview is up — final cold-boot milestone (idempotent).
        BootTiming.mark('webview');
        BootTiming.complete();
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
        // A load that never settles (subresources wedged) is itself a blank;
        // arm a generous watchdog. onLoadStop re-arms a short render-grace one.
        _armBlankSkinWatchdog(url, const Duration(seconds: 12));
      },
      onLoadStop: (controller, url) async {
        _log.info('Page finished loading: $url');
        setState(() {
          _isLoading = false;
        });
        // Give the skin a moment to render, then verify it actually did.
        _armBlankSkinWatchdog(url, const Duration(seconds: 3));

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
        if (mounted &&
            !_didShowExit &&
            widget.settingsController.showSkinExitInstructions) {
          _didShowExit = true;
          _showExitInstructions();
        }
      },
      onReceivedError: (controller, request, error) {
        if (_skinExitCoordinator.inProgress &&
            request.url.toString() == skinExitDashboardUrl) {
          return;
        }
        _log.severe(
          'WebView error - Code: ${error.type}, Description: ${error.description}',
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load skin: ${error.description}';
        });
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        _log.warning('HTTP error - Status: ${errorResponse.statusCode}');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        // Our own blank-load recovery loads the renderer-crash URL; allow it
        // through (loadUrl usually bypasses this callback, but be explicit).
        if (uri?.toString() == kRendererCrashUrl) {
          return NavigationActionPolicy.ALLOW;
        }
        switch (classifySkinNavigation(uri)) {
          case SkinNavDecision.exitDashboard:
            if (_skinExitCoordinator.tryStart(
              target: uri,
              isForMainFrame: navigationAction.isForMainFrame,
              topLevelUri: _mainFrameUri,
            )) {
              _log.info('Skin requested dashboard');
              if (mounted) Navigator.of(context).pop();
            } else {
              _log.warning('Rejected skin dashboard request');
            }
            return NavigationActionPolicy.CANCEL;
          case SkinNavDecision.allow:
            _log.fine('Allowing navigation to: $uri');
            return NavigationActionPolicy.ALLOW;
          case SkinNavDecision.openExternal:
            // Open in the system browser and stay on the skin.
            _log.info('Opening external link in system browser: $uri');
            unawaited(_launchExternal(uri!));
            return NavigationActionPolicy.CANCEL;
          case SkinNavDecision.block:
            _log.info('Blocking navigation to: $uri');
            return NavigationActionPolicy.CANCEL;
        }
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
      onRenderProcessGone: (controller, detail) {
        _log.warning(
          'WebView renderer process gone — '
          'didCrash: ${detail.didCrash}, '
          'rendererPriorityAtExit: ${detail.rendererPriorityAtExit}',
        );
        _webViewController = null;
        // Show reload UI, then rebuild the WebView after a brief delay
        setState(() {
          _rendererCrashed = true;
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _rendererCrashed = false;
            });
          }
        });
      },
    );
  }

  /// Balance a (possibly leaked) global WebView.pauseTimers().
  ///
  /// On Android, pauseTimers() pauses layout, parsing and JavaScript timers
  /// for ALL WebViews in the shared renderer process, and that state outlives
  /// both this widget and its webview — only resumeTimers() (or renderer
  /// death) clears it. If the pause is never balanced, the next webview in
  /// the same renderer wedges mid-parse: index.html's inline scripts run but
  /// no external <script> ever executes and readyState stays 'loading' — the
  /// blank-skin-on-launch bug. resumeTimers() is a no-op when nothing is
  /// paused (and guarded per-webview on iOS), so over-calling is harmless.
  void _resumeLeakedTimerPause(
    InAppWebViewController controller,
    String where,
  ) {
    final wasLeaked = _globalTimersPaused;
    try {
      if (InAppWebViewController.isMethodSupported(.resumeTimers)) {
        controller.resumeTimers();
        _globalTimersPaused = false;
        if (wasLeaked) {
          _log.warning(
            'balanced a leaked global WebView timer pause ($where) — '
            'without this the skin would load blank (parser wedged)',
          );
        }
      }
    } on UnimplementedError catch (e) {
      _log.warning("Unimplemented: ", e);
    } catch (e, st) {
      _log.severe("Unexpected: ", e, st);
    }
  }

  /// Arm the blank-skin watchdog — for the skin URL only, never about:blank
  /// (which we deliberately load when backgrounded). Replaces any pending probe.
  void _armBlankSkinWatchdog(WebUri? url, Duration delay) {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (!(url?.toString() ?? '').startsWith('http://localhost:3000')) return;
    _blankSkinWatchdog?.cancel();
    _blankSkinWatchdog = Timer(delay, _probeSkinAndRecover);
  }

  /// After a load settles, ask the page whether the skin actually rendered.
  /// A blank result (or a probe that throws) recreates the webview, up to
  /// [_maxBlankRecoveries]; a healthy render refills the recovery budget.
  Future<void> _probeSkinAndRecover() async {
    final controller = _webViewController;
    if (!mounted || controller == null) return;
    bool rendered;
    try {
      final res = await controller
          .evaluateJavascript(source: skinRenderedProbeJs)
          .timeout(const Duration(seconds: 5));
      rendered = res == true || res == 'true' || res == 1;
    } catch (e, st) {
      _log.warning('skin-render probe failed; treating as blank', e, st);
      rendered = false;
    }
    if (rendered) {
      _blankRecoveries = 0; // a healthy load refills the recovery budget
      return;
    }
    if (!shouldRecoverBlankSkin(
      rendered: rendered,
      priorRecoveries: _blankRecoveries,
      maxRecoveries: _maxBlankRecoveries,
    )) {
      _log.severe(
        'skin still blank after $_blankRecoveries recoveries — giving up',
      );
      return;
    }
    _blankRecoveries++;
    _log.warning(
      'skin loaded blank — restarting renderer '
      '(attempt $_blankRecoveries/$_maxBlankRecoveries)',
    );
    _crashRendererForRecovery();
  }

  /// Force a fresh renderer process. Recreating the Flutter widget reuses the
  /// same (wedged) renderer, so a blank load does not recover; crashing the
  /// current renderer trips [onRenderProcessGone], which recreates the webview
  /// with a NEW renderer and reloads the skin clean. loadUrl is not an in-page
  /// navigation, so it bypasses shouldOverrideUrlLoading — the crash URL loads
  /// directly.
  void _crashRendererForRecovery() {
    _webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(kRendererCrashUrl)),
    );
  }

  /// Scripts injected into the skin at document start, before any page script
  /// runs. Always carries the host-identity beacon; appends the simulated-device
  /// shims only on desktop (macOS/Windows/Linux) when simulated WebViews are
  /// enabled and a device is selected.
  UnmodifiableListView<UserScript> _initialUserScripts(
    SimulatedWebViewDevice? simulatedDevice,
  ) {
    return UnmodifiableListView<UserScript>([
      _hostIdentityScript(),
      ...?_simulatedDeviceScripts(simulatedDevice),
    ]);
  }

  /// A deterministic "you are inside reaprime" beacon for skins.
  ///
  /// Skins serve from localhost:3000, which is *also* reachable from an ordinary
  /// browser on the tablet's :3000 port — so a skin needs a reliable way to tell
  /// "embedded in reaprime" apart from "opened in a browser" (e.g. Beanie shows a
  /// full-screen tap-to-wake overlay only inside reaprime). The webview user-agent
  /// override ("Decent") isn't dependable — some Android System WebView builds
  /// drop it — and the flutter_inappwebview JS bridge is gated by a bridge secret
  /// in v6 and isn't reliably exposed as a page global. This user script is the
  /// dependable signal: injected at document start in the page content world, so
  /// it's visible to skin JS regardless of UA or bridge state, and it never exists
  /// in a plain browser because it isn't part of the served HTML.
  UserScript _hostIdentityScript() {
    // jsonEncode the whole payload so quotes/newlines in any value can't break
    // out of the injected source. Platform.operatingSystem already yields
    // 'android'/'ios'/'macos'/'windows'/'linux'.
    final payload = jsonEncode({
      'app': 'decent.app',
      'platform': Platform.operatingSystem,
      'version': BuildInfo.version,
      'build': BuildInfo.buildNumber,
      'commit': BuildInfo.commitShort,
    });
    return UserScript(
      source:
          '''
(function () {
  try {
    Object.defineProperty(window, '__DECENT_HOST__', {
      value: Object.freeze($payload),
      configurable: false,
      writable: false,
      enumerable: false
    });
  } catch (_) {}
})();
''',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      contentWorld: ContentWorld.PAGE,
    );
  }

  UnmodifiableListView<UserScript>? _simulatedDeviceScripts(
    SimulatedWebViewDevice? simulatedDevice,
  ) {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    if (!widget.settingsController.enableSimulatedWebViews ||
        !isDesktop ||
        simulatedDevice == null) {
      return null;
    }

    final dpr = simulatedDevice.devicePixelRatio.toStringAsFixed(6);
    final surfaceWidth = simulatedDevice.webViewSurfaceSize.width.toInt();
    final surfaceHeight = simulatedDevice.webViewSurfaceSize.height.toInt();
    final cssWidth = simulatedDevice.viewportSize.width.toStringAsFixed(3);
    final cssHeight = simulatedDevice.viewportSize.height.toStringAsFixed(3);
    final screenWidth = simulatedDevice.screenSize.width.toStringAsFixed(3);
    final screenHeight = simulatedDevice.screenSize.height.toStringAsFixed(3);
    final outerWidth = simulatedDevice.outerWidth.toStringAsFixed(3);
    final maxTouchPoints = simulatedDevice.maxTouchPoints;
    final platform = simulatedDevice.platform;

    return UnmodifiableListView<UserScript>([
      UserScript(
        source:
            '''
(function () {
  const define = (target, key, value) => {
    try {
      Object.defineProperty(target, key, {
        configurable: true,
        get: () => value
      });
    } catch (_) {}
  };

  define(window, 'devicePixelRatio', $dpr);
  define(window, 'innerWidth', $cssWidth);
  define(window, 'innerHeight', $cssHeight);
  define(window, 'outerWidth', $outerWidth);
  define(window, 'outerHeight', $cssHeight);
  define(window.screen, 'width', $screenWidth);
  define(window.screen, 'height', $screenHeight);
  define(window.screen, 'availWidth', $screenWidth);
  define(window.screen, 'availHeight', $screenHeight);
  define(navigator, 'maxTouchPoints', $maxTouchPoints);
  define(navigator, 'platform', '$platform');
  define(window, 'ontouchstart', null);
  define(document, 'ontouchstart', null);
  define(document.documentElement, 'ontouchstart', null);

  define(window.visualViewport, 'width', $surfaceWidth / $dpr);
  define(window.visualViewport, 'height', $surfaceHeight / $dpr);

  const nativeMatchMedia = window.matchMedia
    ? window.matchMedia.bind(window)
    : null;
  const touchMedia = new Map([
    ['(pointer:coarse)', true],
    ['(any-pointer:coarse)', true],
    ['(hover:none)', true],
    ['(any-hover:none)', true],
    ['(pointer:fine)', false],
    ['(any-pointer:fine)', false],
    ['(hover:hover)', false],
    ['(any-hover:hover)', false]
  ]);
  window.matchMedia = (query) => {
    const normalized = String(query).replace(/\\s+/g, '').toLowerCase();
    const simulatedMatch = touchMedia.get(normalized);
    const nativeResult = nativeMatchMedia ? nativeMatchMedia(query) : null;
    if (simulatedMatch === undefined) {
      return nativeResult;
    }
    return {
      matches: simulatedMatch,
      media: nativeResult ? nativeResult.media : String(query),
      onchange: null,
      addListener: nativeResult && nativeResult.addListener
        ? nativeResult.addListener.bind(nativeResult)
        : () => {},
      removeListener: nativeResult && nativeResult.removeListener
        ? nativeResult.removeListener.bind(nativeResult)
        : () => {},
      addEventListener: nativeResult && nativeResult.addEventListener
        ? nativeResult.addEventListener.bind(nativeResult)
        : () => {},
      removeEventListener: nativeResult && nativeResult.removeEventListener
        ? nativeResult.removeEventListener.bind(nativeResult)
        : () => {},
      dispatchEvent: nativeResult && nativeResult.dispatchEvent
        ? nativeResult.dispatchEvent.bind(nativeResult)
        : () => false
    };
  };
})();
''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        contentWorld: ContentWorld.PAGE,
      ),
    ]);
  }
}
