import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
      ..clearCache()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onWebResourceError: (error) {
          _log.warning("onWebResourceError", error);
          _log.warning("${error.description}\n${error.errorCode}");
        }, onHttpError: (error) {
          _log.warning("onHttpError:", error);
          _log.warning(
              "${error.runtimeType}, ${error.response?.statusCode}, ${error.response?.headers}");
        }, onNavigationRequest: (request) {
          return NavigationDecision.navigate;
        }, onPageStarted: (page) {
          _log.info("loading page: $page");
        }),
      )
      ..loadRequest(
          Uri.parse('http://${WebUIService.serverIP()}:3000/index.html'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Web UI')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return WebViewWidget.fromPlatformCreationParams(
          params: PlatformWebViewWidgetCreationParams(
              controller: _controller.platform));
    }
    return WebViewWidget(controller: _controller);
  }
}
