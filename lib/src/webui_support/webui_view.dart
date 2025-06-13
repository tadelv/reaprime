import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebUIView extends StatefulWidget {
  static const String routeName = "WebuiView";

  const WebUIView({super.key});

  @override
  State<WebUIView> createState() => _WebuiViewState();
}

class _WebuiViewState extends State<WebUIView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadFlutterAsset('assets/web/index.html'); // 👈 Load your local HTML
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Local Web UI')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
