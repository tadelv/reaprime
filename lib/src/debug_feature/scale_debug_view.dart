import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide Scale;

class ScaleDebugView extends StatefulWidget {
  final Scale scale;

  /// When true, calls [scale.onConnect()] in initState for raw inspection.
  /// When false, assumes the device is already connected via ConnectionManager.
  final bool inspect;

  const ScaleDebugView({
    super.key,
    required this.scale,
    this.inspect = false,
  });

  @override
  State<ScaleDebugView> createState() => _ScaleDebugViewState();
}

class _ScaleDebugViewState extends State<ScaleDebugView> {
  var _lastDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.inspect) {
      widget.scale.onConnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: StreamBuilder<ScaleSnapshot>(
            stream: widget.scale.currentSnapshot,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.active) {
                final diff = snapshot.data?.timestamp.difference(_lastDate) ??
                    Duration.zero;
                _lastDate = snapshot.data?.timestamp ?? DateTime.now();
                return _buildActiveView(theme, snapshot.data!, diff);
              } else if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Connecting…', style: theme.textTheme.muted),
                    ],
                  ),
                );
              }
              return Center(
                child: Text(
                  'Waiting for data',
                  style: theme.textTheme.muted,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ShadThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text('Scale Debug', style: theme.textTheme.h4),
          const SizedBox(width: 8),
          Text(
            widget.scale.deviceId,
            style: theme.textTheme.muted,
          ),
          const Spacer(),
          ShadButton.destructive(
            size: ShadButtonSize.sm,
            child: const Text('Disconnect'),
            onPressed: () async {
              await widget.scale.disconnect();
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveView(
    ShadThemeData theme,
    ScaleSnapshot data,
    Duration diff,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Weight hero
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.weight.toStringAsFixed(1),
                style: theme.textTheme.h1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'grams',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Battery + latency
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Battery: ${data.batteryLevel}%',
              style: theme.textTheme.muted,
            ),
            const SizedBox(width: 16),
            Text(
              '${diff.inMilliseconds}ms ago',
              style: theme.textTheme.muted,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Tare button
        ShadButton(
          child: const Text('Tare'),
          onPressed: () async {
            await widget.scale.tare();
          },
        ),
        const SizedBox(height: 16),

        // Display controls row
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                child: const Text('Wake'),
                onPressed: () async {
                  await widget.scale.wakeDisplay();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadButton.outline(
                child: const Text('Sleep'),
                onPressed: () async {
                  await widget.scale.sleepDisplay();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Timer controls row
        Text('Timer', style: theme.textTheme.small),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                child: const Text('Start'),
                onPressed: () async {
                  await widget.scale.startTimer();
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                child: const Text('Stop'),
                onPressed: () async {
                  await widget.scale.stopTimer();
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                child: const Text('Reset'),
                onPressed: () async {
                  await widget.scale.resetTimer();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
