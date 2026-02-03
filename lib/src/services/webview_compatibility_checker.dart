import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logging/logging.dart';

/// Result of WebView compatibility check
class CompatibilityResult {
  final bool isCompatible;
  final String reason;
  final CompatibilityIssue? issue;

  const CompatibilityResult({
    required this.isCompatible,
    required this.reason,
    this.issue,
  });

  const CompatibilityResult.compatible()
    : isCompatible = true,
      reason = 'WebView is compatible',
      issue = null;

  const CompatibilityResult.incompatible(
    String reason,
    CompatibilityIssue issue,
  ) : isCompatible = false,
      reason = reason,
      issue = issue;
}

enum CompatibilityIssue {
  knownProblematicDevice,
  oldAndroidVersion,
  webViewRenderingFailed,
  webViewNotAvailable,
}

/// Checks if the device's WebView implementation is compatible with SkinView
///
/// Combines static device detection (manufacturer/model/Android version) with
/// dynamic runtime testing to determine if the WebView can render properly.
///
/// Known issues:
/// - Teclast tablets with MediaTek chipsets have GPU driver artifacts
/// - Budget tablets with older Android versions may have rendering issues
/// - Some devices have broken hardware acceleration
class WebViewCompatibilityChecker {
  static final _log = Logger('WebViewCompatibilityChecker');
  static CompatibilityResult? _cachedResult;

  /// Checks WebView compatibility using device info and runtime test
  ///
  /// Returns cached result if available, otherwise performs full check.
  static Future<CompatibilityResult> checkCompatibility({
    bool forceRecheck = false,
  }) async {
    if (_cachedResult != null && !forceRecheck) {
      _log.fine('Using cached compatibility result: ${_cachedResult!.reason}');
      return _cachedResult!;
    }

    if (!Platform.isAndroid) {
      _log.info('Non-Android platform - WebView is compatible');
      _cachedResult = const CompatibilityResult.compatible();
      return _cachedResult!;
    }

    _log.info('Starting WebView compatibility check...');

    // Step 1: Static device detection
    final deviceCheckResult = await _checkDeviceInfo();
    if (!deviceCheckResult.isCompatible) {
      _cachedResult = deviceCheckResult;
      return _cachedResult!;
    }

    // Step 2: Runtime WebView test
    final runtimeCheckResult = await _testWebViewRendering();
    _cachedResult = runtimeCheckResult;
    return _cachedResult!;
  }

  /// Checks device manufacturer, model, and Android version
  static Future<CompatibilityResult> _checkDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      final manufacturer = androidInfo.manufacturer.toLowerCase();
      final model = androidInfo.model.toLowerCase();
      final sdkInt = androidInfo.version.sdkInt;
      final androidVersion = androidInfo.version.release;

      _log.info(
        'Device info - Manufacturer: $manufacturer, Model: $model, '
        'Android: $androidVersion (SDK $sdkInt)',
      );

      // Check for known problematic manufacturers
      if (_isProblematicManufacturer(manufacturer)) {
        final reason = 'Known WebView issues with $manufacturer devices';
        _log.warning(reason);
        return CompatibilityResult.incompatible(
          reason,
          CompatibilityIssue.knownProblematicDevice,
        );
      }

      // Check for known problematic models
      if (_isProblematicModel(model)) {
        final reason = 'Known WebView issues with device model: $model';
        _log.warning(reason);
        return CompatibilityResult.incompatible(
          reason,
          CompatibilityIssue.knownProblematicDevice,
        );
      }

      // Check Android version (require Android 8.0 / API 26+)
      if (sdkInt < 26) {
        final reason =
            'Android version too old for stable WebView: $androidVersion (SDK $sdkInt)';
        _log.warning(reason);
        return CompatibilityResult.incompatible(
          reason,
          CompatibilityIssue.oldAndroidVersion,
        );
      }

      _log.info('Device info check passed');
      return const CompatibilityResult.compatible();
    } catch (e, stackTrace) {
      _log.severe('Failed to get device info', e, stackTrace);
      // If we can't get device info, assume incompatible for safety
      return CompatibilityResult.incompatible(
        'Unable to determine device compatibility: $e',
        CompatibilityIssue.webViewNotAvailable,
      );
    }
  }

  /// Tests WebView by creating a headless instance and verifying it can render
  static Future<CompatibilityResult> _testWebViewRendering() async {
    _log.info('Starting runtime WebView test...');

    try {
      final completer = Completer<CompatibilityResult>();
      HeadlessInAppWebView? headlessWebView;

      // Create a simple HTML page to test rendering
      final testHtml = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { margin: 0; padding: 20px; font-family: sans-serif; }
            #test { background: linear-gradient(45deg, #667eea 0%, #764ba2 100%); 
                    color: white; padding: 20px; border-radius: 8px; }
          </style>
        </head>
        <body>
          <div id="test">WebView Test</div>
          <script>
            // Test JavaScript execution
            window.testResult = document.getElementById('test') ? 'ok' : 'fail';
          </script>
        </body>
        </html>
      ''';

      headlessWebView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(data: testHtml),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: false,
        ),
        onLoadStop: (controller, url) async {
          _log.fine('Headless WebView loaded, testing JavaScript...');
          try {
            // Test 1: Can we execute JavaScript?
            final jsResult = await controller.evaluateJavascript(
              source: 'window.testResult',
            );

            if (jsResult != 'ok') {
              _log.warning('JavaScript execution test failed: $jsResult');
              completer.complete(
                CompatibilityResult.incompatible(
                  'WebView JavaScript execution failed',
                  CompatibilityIssue.webViewRenderingFailed,
                ),
              );
              await headlessWebView?.dispose();
              return;
            }

            // Test 2: Can we access DOM elements?
            final domTest = await controller.evaluateJavascript(
              source: '''
                (function() {
                  try {
                    const elem = document.getElementById('test');
                    return elem && elem.textContent === 'WebView Test' ? 'ok' : 'fail';
                  } catch(e) {
                    return 'error: ' + e.message;
                  }
                })()
              ''',
            );

            if (domTest != 'ok') {
              _log.warning('DOM access test failed: $domTest');
              completer.complete(
                CompatibilityResult.incompatible(
                  'WebView DOM manipulation failed',
                  CompatibilityIssue.webViewRenderingFailed,
                ),
              );
              await headlessWebView?.dispose();
              return;
            }

            // Test 3: Check if CSS is applied (gradient background)
            final cssTest = await controller.evaluateJavascript(
              source: '''
                (function() {
                  try {
                    const elem = document.getElementById('test');
                    const style = window.getComputedStyle(elem);
                    return style.background.includes('gradient') || 
                           style.backgroundImage.includes('gradient') ? 'ok' : 'fail';
                  } catch(e) {
                    return 'error: ' + e.message;
                  }
                })()
              ''',
            );

            if (cssTest != 'ok') {
              _log.warning('CSS rendering test failed: $cssTest');
              completer.complete(
                CompatibilityResult.incompatible(
                  'WebView CSS rendering may be unreliable',
                  CompatibilityIssue.webViewRenderingFailed,
                ),
              );
              await headlessWebView?.dispose();
              return;
            }

            _log.info('Runtime WebView test passed - all checks OK');
            completer.complete(const CompatibilityResult.compatible());
            await headlessWebView?.dispose();
          } catch (e, stackTrace) {
            _log.severe('Error during WebView testing', e, stackTrace);
            completer.complete(
              CompatibilityResult.incompatible(
                'WebView test error: $e',
                CompatibilityIssue.webViewRenderingFailed,
              ),
            );
            await headlessWebView?.dispose();
          }
        },
        onReceivedError: (controller, request, error) {
          _log.warning('WebView error during test: ${error.description}');
          completer.complete(
            CompatibilityResult.incompatible(
              'WebView failed to load: ${error.description}',
              CompatibilityIssue.webViewRenderingFailed,
            ),
          );
          headlessWebView?.dispose();
        },
        onReceivedHttpError: (controller, request, errorResponse) {
          _log.warning('HTTP error during test: ${errorResponse.statusCode}');
          completer.complete(
            CompatibilityResult.incompatible(
              'WebView HTTP error: ${errorResponse.statusCode}',
              CompatibilityIssue.webViewRenderingFailed,
            ),
          );
          headlessWebView?.dispose();
        },
      );

      await headlessWebView.run();

      // Wait for test to complete with timeout
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log.warning('WebView test timed out');
          headlessWebView?.dispose();
          return CompatibilityResult.incompatible(
            'WebView test timed out - may be too slow on this device',
            CompatibilityIssue.webViewRenderingFailed,
          );
        },
      );
    } catch (e, stackTrace) {
      _log.severe('Failed to run WebView test', e, stackTrace);
      return CompatibilityResult.incompatible(
        'WebView test failed: $e',
        CompatibilityIssue.webViewNotAvailable,
      );
    }
  }

  /// Checks if manufacturer is known to have WebView issues
  static bool _isProblematicManufacturer(String manufacturer) {
    final problematic = [
      'teclast', // Known GPU driver issues
      'allwinner', // Budget SoCs with rendering problems
      'rockchip', // Budget ARM SoCs with GPU issues
    ];

    for (final brand in problematic) {
      if (manufacturer.contains(brand)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if device model is known to have WebView issues
  static bool _isProblematicModel(String model) {
    final problematic = [
      'p80', // Teclast P80 series
      'p20', // Teclast P20 series
      'p10', // Teclast P10 series
      'm40', // Teclast M40 series
      // Add more problematic models as discovered
    ];

    for (final modelPattern in problematic) {
      if (model.contains(modelPattern)) {
        return true;
      }
    }

    // Check for MediaTek chipset indicators in model name
    if (model.contains('mt') && model.length > 3) {
      // Pattern like "mt8183" or "tablet_mt6797"
      final mtIndex = model.indexOf('mt');
      if (mtIndex >= 0 && mtIndex + 2 < model.length) {
        final afterMt = model.substring(mtIndex + 2);
        // Check if followed by digits (indicates chipset model)
        if (afterMt.isNotEmpty &&
            afterMt[0].codeUnitAt(0) >= '0'.codeUnitAt(0) &&
            afterMt[0].codeUnitAt(0) <= '9'.codeUnitAt(0)) {
          _log.warning('Possible MediaTek chipset detected in model: $model');
          // Don't automatically fail, but log warning
        }
      }
    }

    return false;
  }

  /// Clears the cached compatibility result
  static void clearCache() {
    _log.fine('Clearing compatibility cache');
    _cachedResult = null;
  }
}
