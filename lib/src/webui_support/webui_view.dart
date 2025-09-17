import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class WebUIView extends StatefulWidget {
  static const String routeName = "WebuiView";

  const WebUIView({super.key, required this.indexPath});

  final String indexPath;

  @override
  State<WebUIView> createState() => _WebuiViewState();
}

class _WebuiViewState extends State<WebUIView> {
  InAppWebViewController? _controller;
  final Logger _log = Logger("WebUI");
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    // mediaPlaybackRequiresUserGesture: false,
    // allowsInlineMediaPlayback: true,
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
  );

  PullToRefreshController? pullToRefreshController;

  @override
  void initState() {
    super.initState();
    _log.info("loading ${widget.indexPath}");
    // if (kDebugMode) {
    //   InAppWebViewController.setWebContentsDebuggingEnabled(true);
    // }
    pullToRefreshController = kIsWeb ||
            [TargetPlatform.iOS, TargetPlatform.android]
                .contains(defaultTargetPlatform)
        ? PullToRefreshController(
            settings: PullToRefreshSettings(
              color: Colors.blue,
            ),
            onRefresh: () async {
              if (defaultTargetPlatform == TargetPlatform.android) {
                _controller?.reload();
              } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                _controller?.loadUrl(
                    urlRequest: URLRequest(url: await _controller?.getUrl()));
              }
            },
          )
        : null;
    // _controller = WebViewController(onPermissionRequest: (request) {
    //   _log.info("onPermissionRequest:", request);
    // })
    //   ..clearCache()
    //   ..setJavaScriptMode(JavaScriptMode.unrestricted)
    //   ..setNavigationDelegate(
    //     NavigationDelegate(onWebResourceError: (error) {
    //       _log.warning("onWebResourceError", error);
    //       _log.warning("${error.description}\n${error.errorCode}");
    //     }, onHttpError: (error) {
    //       _log.warning("onHttpError:", error);
    //       _log.warning(
    //           "${error.runtimeType}, ${error.response?.statusCode}, ${error.response?.headers}");
    //     }, onNavigationRequest: (request) {
    //       return NavigationDecision.navigate;
    //     }, onPageStarted: (page) {
    //       _log.info("loading page: $page");
    //     }),
    //   )
    //   ..loadRequest(Uri.parse(widget.indexPath));
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return _linuxBody(context);
    }
    return Scaffold(
      appBar: null, //AppBar(title: const Text('Local Web UI')),
      body: _body(context),
    );
  }

  Widget _linuxBody(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Web UI")),
      body: Column(
        children: [
          Text("REA Web UI running, but unsupported on Linux currently"),
          ShadButton(
            child: Text("Open UI in browser"),
            onPressed: () async {
                final url  = Uri.parse('http://localhost:3000');
                await launchUrl(url);
              },
          )
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    return Stack(children: [
      InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('http://localhost:3000')),
          onWebViewCreated: (controller) {
            _controller = controller;
          },
          pullToRefreshController: pullToRefreshController,
          onProgressChanged: (controller, progress) {
            if (progress == 100) {
              pullToRefreshController?.endRefreshing();
            }
          },
          initialSettings: settings,
          onConsoleMessage: (controller, consoleMessage) {
            if (kDebugMode) {
              _log.fine("console: ${consoleMessage.message}");
            }
          },
          onReceivedHttpError: (controller, request, response) {
            _log.warning("received error: ${request}, ${response}");
          },
          onReceivedError: (controller, request, error) {
            _log.warning("received error: ", error);
          }),
      ShadButton.ghost(
        child: Text("close"),
        onPressed: () {
          Navigator.of(context).pop();
        },
      )
    ]);
  }
  // Widget _body(BuildContext context) {
  //   if (WebViewPlatform.instance is AndroidWebViewPlatform) {
  //     return WebViewWidget.fromPlatformCreationParams(
  //         params: PlatformWebViewWidgetCreationParams(
  //             controller: _controller.platform));
  //   }
  //   return WebViewWidget(controller: _controller);
  // }
}
