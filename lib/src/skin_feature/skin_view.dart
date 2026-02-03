import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Displays the WebUI skin in a full-screen webview
/// 
/// This view is only shown on mobile/desktop platforms (iOS, Android, macOS)
/// and provides a webview interface to the locally-served WebUI at localhost:3000.
/// 
/// The view includes a back button in the app bar to navigate to the home dashboard.
class SkinView extends StatefulWidget {
  const SkinView({super.key});

  static const routeName = '/skin';

  @override
  State<SkinView> createState() => _SkinViewState();
}

class _SkinViewState extends State<SkinView> {
  final _log = Logger('SkinView');
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    try {
      _log.info('Initializing WebView for platform: ${Platform.operatingSystem}');
      
      // On Android, create controller with platform-specific parameters
      if (Platform.isAndroid) {
        _log.info('Creating Android WebView controller');
        
        final androidController = WebViewController.fromPlatformCreationParams(
          AndroidWebViewControllerCreationParams(),
        );
        
        // Configure Android-specific WebView settings
        final androidWebViewController = androidController.platform as AndroidWebViewController;
        
        // Disable media playback gesture requirement
        androidWebViewController.setMediaPlaybackRequiresUserGesture(false);
        
        // Enable DOM storage and database for better compatibility
        androidWebViewController.setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (request) async {
            return GeolocationPermissionsResponse(allow: false, retain: false);
          },
        );
        
        // Try to improve compatibility by explicitly enabling certain features
        _log.info('Configured Android WebView settings');
        
        _controller = androidController;
      } else {
        _log.info('Creating standard WebView controller');
        _controller = WebViewController();
      }
      
      _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      _log.info('JavaScript mode set to unrestricted');
      
      // setBackgroundColor with transparency is not supported on macOS
      // Only set background color on iOS and Android
      if (Platform.isIOS || Platform.isAndroid) {
        _controller.setBackgroundColor(Colors.white);
        _log.info('Background color set to white');
      }
      
      _controller
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              _log.info('Page started loading: $url');
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            },
            onPageFinished: (String url) {
              _log.info('Page finished loading: $url');
              setState(() {
                _isLoading = false;
              });
            },
            onWebResourceError: (WebResourceError error) {
              _log.severe('WebView resource error - Code: ${error.errorCode}, Type: ${error.errorType}, Description: ${error.description}');
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to load skin: ${error.description}';
              });
            },
            onNavigationRequest: (NavigationRequest request) {
              // Allow all navigation within localhost:3000
              if (request.url.startsWith('http://localhost:3000')) {
                _log.fine('Allowing navigation to: ${request.url}');
                return NavigationDecision.navigate;
              }
              // Block external navigation
              _log.info('Blocking navigation to: ${request.url}');
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(Uri.parse('http://localhost:3000'));
      
      _log.info('WebView load request issued for http://localhost:3000');
    } catch (e, stackTrace) {
      _log.severe('Failed to initialize WebView', e, stackTrace);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to initialize WebView: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Scaffold for proper widget constraints on Android, but make it fullscreen
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

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
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
                  Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
                },
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    // Wrap WebView in RepaintBoundary to help with rendering issues
    return Stack(
      children: [
        RepaintBoundary(
          child: WebViewWidget(controller: _controller),
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
