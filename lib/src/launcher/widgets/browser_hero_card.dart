import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hero card shown when the platform has no WebView support or is a degraded
/// Android version. Displays the webUI URL, QR code, and action buttons so
/// users can connect from another device's browser.
class BrowserHeroCard extends StatelessWidget {
  const BrowserHeroCard({
    super.key,
    required this.deviceIp,
    this.port = 3000,
  });

  final String deviceIp;
  final int port;

  String get _url =>
      'http://$deviceIp:$port/?_=${DateTime.now().millisecondsSinceEpoch}';

  String get _displayUrl => 'http://$deviceIp:$port';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(
                LucideIcons.globe,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              Text(
                'Open in browser',
                style: theme.textTheme.h4,
              ),
            ],
          ),
          Text(
            'For the best experience, open the UI on a phone or laptop browser.',
            style: theme.textTheme.muted,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              // QR code
              SizedBox(
                width: 120,
                height: 120,
                child: PrettyQrView.data(
                  data: _url,
                  decoration: PrettyQrDecoration(
                    quietZone: PrettyQrQuietZone.standard,
                    shape: PrettyQrSquaresSymbol(
                      unifiedFinderPattern: true,
                      color: theme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),
              // URL + actions
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    SelectableText(
                      _displayUrl,
                      style: theme.textTheme.p.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          leading: const Icon(LucideIcons.copy, size: 14),
                          child: const Text('Copy URL'),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('URL copied'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        ShadButton(
                          size: ShadButtonSize.sm,
                          leading: const Icon(
                              LucideIcons.externalLink, size: 14),
                          child: const Text('Open Browser'),
                          onPressed: () {
                            launchUrl(Uri.parse(_url));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Widget Previews --

@Preview(name: 'Browser Hero Card', group: 'Launcher')
Widget browserHeroCardPreview() {
  return ShadApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: 500,
          child: BrowserHeroCard(deviceIp: '192.168.1.42'),
        ),
      ),
    ),
  );
}
