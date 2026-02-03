import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              _log.fine('Page started loading: $url');
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            },
            onPageFinished: (String url) {
              _log.fine('Page finished loading: $url');
              setState(() {
                _isLoading = false;
              });
            },
            onWebResourceError: (WebResourceError error) {
              _log.warning('WebView error: ${error.description}');
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to load skin: ${error.description}';
              });
            },
            onNavigationRequest: (NavigationRequest request) {
              // Allow all navigation within localhost:3000
              if (request.url.startsWith('http://localhost:3000')) {
                return NavigationDecision.navigate;
              }
              // Block external navigation
              _log.info('Blocking navigation to: ${request.url}');
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(Uri.parse('http://localhost:3000'));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streamline'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
          },
        ),
      ),
      body: _buildBody(),
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

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
