import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/launcher/widgets/browser_hero_card.dart';
import 'package:reaprime/src/launcher/widgets/destination_card.dart';
import 'package:reaprime/src/launcher/widgets/skin_unavailable_card.dart';
import 'package:reaprime/src/launcher/widgets/status_bar.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/settings/settings_view.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LauncherView extends StatelessWidget {
  static const routeName = '/home';

  const LauncherView({
    super.key,
    required this.de1Controller,
    required this.scaleController,
    required this.webUIService,
    required this.pluginLoaderService,
    this.batteryController,
    this.decentAccountService,
  });

  final De1Controller de1Controller;
  final ScaleController scaleController;
  final WebUIService webUIService;
  final PluginLoaderService pluginLoaderService;
  final BatteryController? batteryController;
  final DecentAccountService? decentAccountService;

  bool get _supportsWebView =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS || Platform.isWindows;

  bool get _isDegradedAndroid {
    if (!Platform.isAndroid) return false;
    // SDK version check would go here; for now we rely on the
    // onboarding warning step and keep this as a layout hint.
    // The launcher shows the browser hero card on platforms without WebView.
    return false;
  }

  bool get _showBrowserHero => !_supportsWebView || _isDegradedAndroid;

  bool get _canReturnToSkin => _supportsWebView && webUIService.isServing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Status bar
          StatusBar(
            de1Controller: de1Controller,
            scaleController: scaleController,
            batteryController: batteryController,
            webUIService: webUIService,
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 24,
                    children: [
                      // Return to skin — hero button or unavailable explanation
                      if (_canReturnToSkin)
                        _ReturnToSkinButton(onTap: () {
                          Navigator.of(context).pushNamed(SkinView.routeName);
                        })
                      else
                        _buildSkinUnavailable(context),

                      // Browser hero card (no WebView or degraded)
                      if (_showBrowserHero)
                        BrowserHeroCard(
                          deviceIp: webUIService.deviceIp(),
                        ),

                      // Destination grid
                      _buildGrid(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkinUnavailable(BuildContext context) {
    final reason = !_supportsWebView
        ? SkinUnavailableReason.noWebView
        : SkinUnavailableReason.notServing;

    return SkinUnavailableCard(
      reason: reason,
      onPickSkin: () {
        // Navigate to settings for now; will be standalone skin selector in PR2
        Navigator.of(context).pushNamed(SettingsView.routeName);
      },
      onSendFeedback: () {
        // Navigate to settings where feedback is accessible
        Navigator.of(context).pushNamed(SettingsView.routeName);
      },
    );
  }

  Widget _buildGrid(BuildContext context) {
    final destinations = <_Destination>[
      _Destination(
        icon: LucideIcons.settings,
        label: 'Settings',
        route: SettingsView.routeName,
      ),
      _Destination(
        icon: LucideIcons.bluetooth,
        label: 'Devices',
        // Device management is inside settings for now; standalone in PR2
        route: SettingsView.routeName,
      ),
      _Destination(
        icon: LucideIcons.database,
        label: 'Data',
        // Data management is inside settings for now; standalone in PR2
        route: SettingsView.routeName,
      ),
      _Destination(
        icon: LucideIcons.palette,
        label: 'Skins',
        // Skin selector is inside settings for now; standalone in PR2
        route: SettingsView.routeName,
      ),
      if (decentAccountService != null)
        _Destination(
          icon: LucideIcons.user,
          label: 'Account',
          route: SettingsView.routeName,
        ),
      if (pluginLoaderService.availablePlugins.isNotEmpty)
        _Destination(
          icon: LucideIcons.puzzle,
          label: 'Plugins',
          route: '/plugins',
        ),
      _Destination(
        icon: LucideIcons.wrench,
        label: 'Advanced',
        route: SettingsView.routeName,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 400 ? 4 : 3;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: destinations
              .map((d) => DestinationCard(
                    icon: d.icon,
                    label: d.label,
                    onTap: () =>
                        Navigator.of(context).pushNamed(d.route),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _Destination {
  final IconData icon;
  final String label;
  final String route;

  const _Destination({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class _ReturnToSkinButton extends StatelessWidget {
  const _ReturnToSkinButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadButton(
      size: ShadButtonSize.lg,
      leading: const Icon(LucideIcons.arrowLeft, size: 18),
      onPressed: onTap,
      child: Text(
        'Return to Skin',
        style: theme.textTheme.p.copyWith(
          color: theme.colorScheme.primaryForeground,
        ),
      ),
    );
  }
}
