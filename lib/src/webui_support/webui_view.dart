import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebUIView extends StatefulWidget {
  static const String routeName = "WebuiView";

  const WebUIView({super.key, required this.indexPath});

  final String indexPath;

  @override
  State<WebUIView> createState() => _WebuiViewState();
}

class _WebuiViewState extends State<WebUIView> {
  late final WebViewController _controller;
  final Logger _log = Logger("WebUI");

  @override
  void initState() {
    super.initState();
    _log.info("loading ${widget.indexPath}");

    _controller = WebViewController(onPermissionRequest: (request) {
      _log.info("onPermissionRequest:", request);
    })
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onWebResourceError: (error) {
          _log.warning("onWebResourceError", error);
        }, onHttpError: (error) {
          _log.warning("onHttpError:", error);
        }, onNavigationRequest: (request) {
          return NavigationDecision.navigate;
        }, onPageStarted: (page) {
          _log.info("loading page: $page");
        }),
      )
      ..loadRequest(Uri.http('localhost:3000'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Web UI')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
