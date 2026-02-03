import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shows an informational dialog explaining the Gateway Mode settings
///
/// This dialog explains the three gateway modes (Disabled, Full, Tracking)
/// and when to use them. It can be reused in both the Settings view and
/// the Home screen quick settings card.
///
/// Usage:
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.info_outline),
///   onPressed: () => showGatewayModeInfoDialog(context),
/// )
/// ```
void showGatewayModeInfoDialog(BuildContext context) {
  showShadDialog(
    context: context,
    builder:
        (context) => ShadDialog(
          title: const Text('Gateway Mode'),
          description: const Text(
            'Control whether Rea acts as a gateway for external clients',
          ),
          actions: [
            ShadButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              _GatewayModeOption(
                title: 'Disabled',
                description:
                    'Gateway is completely disabled. Rea has full control over the machine, shot execution, and all parameters. External clients cannot control the machine.',
                icon: Icons.block,
                color: Colors.grey,
              ),
              _GatewayModeOption(
                title: 'Full',
                description:
                    'Full gateway mode. Rea has no control - external clients have complete control over the machine, shot execution, profiles, and all parameters. Rea only displays status and graphs.',
                icon: Icons.open_in_browser,
                color: Colors.blue,
              ),
              _GatewayModeOption(
                title: 'Tracking',
                description:
                    'Hybrid mode. Rea will not show graphs but will monitor the shot. When the target weight is reached, Rea will automatically stop the shot. External clients can still control most parameters.',
                icon: Icons.track_changes,
                color: Colors.orange,
              ),
              const SizedBox(height: 8),
              Builder(
                builder:
                    (context) => Text(
                      'Use gateway mode when you want to control Rea from external applications like web dashboards, mobile apps, or automation systems.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
              ),
            ],
          ),
        ),
  );
}

/// Internal widget for displaying a single gateway mode option
class _GatewayModeOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _GatewayModeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Icon(icon, size: 24, color: color),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
