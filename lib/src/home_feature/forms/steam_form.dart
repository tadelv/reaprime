import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Label pair for the preferred-probe picker when multiple sensors exist.
class SteamProbeOption {
  const SteamProbeOption({required this.deviceId, required this.label});

  final String deviceId;
  final String label;
}

class SteamForm extends StatefulWidget {
  const SteamForm({
    super.key,
    required this.apply,
    required this.steamSettings,
    this.probeOptions = const [],
  });

  final void Function(SteamFormSettings) apply;
  final SteamFormSettings steamSettings;

  /// Sensors available for preferred-probe selection. Picker is hidden
  /// unless length > 1 (FR-U2).
  final List<SteamProbeOption> probeOptions;

  @override
  State<SteamForm> createState() {
    return _SteamFormState();
  }
}

class _SteamFormState extends State<SteamForm> {
  static const double _defaultStopAtTemperature = 65.0;
  static const double _minStopAtTemperature = 40.0;
  static const double _maxStopAtTemperature = 80.0;

  late SteamFormSettings steamSettings;

  bool get _stopAtEnabled => steamSettings.stopAtTemperature > 0;

  @override
  void initState() {
    steamSettings = widget.steamSettings;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Color.from(alpha: 0, red: 0, green: 0, blue: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                const Text('Steam enabled'),
                const Spacer(),
                ShadSwitch(
                  value: steamSettings.steamEnabled,
                  onChanged: (val) {
                    setState(() {
                      if (val) {
                        steamSettings.targetTemp = 135;
                      }
                      steamSettings.steamEnabled = val;
                    });
                  },
                ),
              ],
            ),
          ),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Steam temperature: ${steamSettings.targetTemp}℃'),
                ShadSlider(
                  initialValue: steamSettings.steamEnabled
                      ? steamSettings.targetTemp.toDouble()
                      : 135,
                  min: 135,
                  max: 170,
                  divisions: 35,
                  thumbRadius: 15,
                  trackHeight: 15,
                  enabled: steamSettings.steamEnabled,
                  onChanged: (val) {
                    setState(() {
                      steamSettings.targetTemp = val.toInt();
                    });
                  },
                ),
              ],
            ),
          ),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Steam duration: ${steamSettings.targetDuration} seconds'),
                ShadSlider(
                  initialValue: steamSettings.targetDuration.toDouble(),
                  min: 0,
                  max: 120,
                  divisions: 24,
                  thumbRadius: 15,
                  trackHeight: 15,
                  enabled: steamSettings.steamEnabled,
                  onChanged: (val) {
                    setState(() {
                      steamSettings.targetDuration = val.toInt();
                    });
                  },
                ),
              ],
            ),
          ),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Steam flow: ${steamSettings.targetFlow.toStringAsFixed(1)} ml/s',
                ),
                ShadSlider(
                  initialValue: steamSettings.targetFlow.toDouble(),
                  min: 0.4,
                  max: 2.5,
                  divisions: 21,
                  thumbRadius: 15,
                  trackHeight: 15,
                  enabled: steamSettings.steamEnabled,
                  onChanged: (val) {
                    setState(() {
                      steamSettings.targetFlow = val;
                    });
                  },
                ),
              ],
            ),
          ),
          MergeSemantics(
            child: Row(
              children: [
                const Text('Stop at probe temperature'),
                const Spacer(),
                ShadSwitch(
                  value: _stopAtEnabled,
                  enabled: steamSettings.steamEnabled,
                  onChanged: steamSettings.steamEnabled
                      ? (val) {
                          setState(() {
                            steamSettings.stopAtTemperature = val
                                ? (steamSettings.stopAtTemperature > 0
                                    ? steamSettings.stopAtTemperature
                                    : _defaultStopAtTemperature)
                                : 0.0;
                          });
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (_stopAtEnabled && steamSettings.steamEnabled)
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stop at: ${steamSettings.stopAtTemperature.toStringAsFixed(1)}℃',
                  ),
                  ShadSlider(
                    initialValue: steamSettings.stopAtTemperature,
                    min: _minStopAtTemperature,
                    max: _maxStopAtTemperature,
                    divisions: 80,
                    thumbRadius: 15,
                    trackHeight: 15,
                    onChanged: (val) {
                      setState(() {
                        steamSettings.stopAtTemperature = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          if (widget.probeOptions.length > 1) _preferredProbePicker(context),
          ShadButton(
            child: const Text('Apply'),
            onPressed: () {
              widget.apply(steamSettings);
            },
          ),
        ],
      ),
    );
  }

  Widget _preferredProbePicker(BuildContext context) {
    final options = widget.probeOptions;
    final selectedId = steamSettings.preferredProbeId ?? options.first.deviceId;

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          const Text('Preferred probe'),
          ShadSelect<String>(
            initialValue: selectedId,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                steamSettings.preferredProbeId = value;
              });
            },
            selectedOptionBuilder: (context, value) {
              final match = options.where((o) => o.deviceId == value);
              final label =
                  match.isEmpty ? value : match.first.label;
              return Text(label);
            },
            options: options
                .map(
                  (option) => ShadOption(
                    value: option.deviceId,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            placeholder: const Text('Select probe...'),
          ),
        ],
      ),
    );
  }
}

class SteamFormSettings {
  bool steamEnabled;
  int targetTemp;
  int targetDuration;
  double targetFlow;

  /// 0.0 = off. Bound to workflow [SteamSettings.stopAtTemperature].
  double stopAtTemperature;

  /// Preferred probe for steam stop; persisted via settings service.
  String? preferredProbeId;

  SteamFormSettings({
    required this.steamEnabled,
    required this.targetTemp,
    required this.targetDuration,
    required this.targetFlow,
    this.stopAtTemperature = 0.0,
    this.preferredProbeId,
  });

  factory SteamFormSettings.fromSteamSettings(
    SteamSettings settings, {
    required bool steamEnabled,
    String? preferredProbeId,
  }) {
    return SteamFormSettings(
      steamEnabled: steamEnabled,
      targetTemp: settings.targetTemperature,
      targetDuration: settings.duration,
      targetFlow: settings.flow,
      stopAtTemperature: settings.stopAtTemperature,
      preferredProbeId: preferredProbeId,
    );
  }

  SteamSettings toSteamSettings() {
    return SteamSettings(
      targetTemperature: steamEnabled ? targetTemp : 0,
      duration: targetDuration,
      flow: targetFlow,
      stopAtTemperature: stopAtTemperature,
    );
  }

  SteamFormSettings copyWith({
    bool? steamEnabled,
    int? targetTemp,
    int? targetDuration,
    double? targetFlow,
    double? stopAtTemperature,
    String? preferredProbeId,
  }) {
    return SteamFormSettings(
      steamEnabled: steamEnabled ?? this.steamEnabled,
      targetTemp: targetTemp ?? this.targetTemp,
      targetDuration: targetDuration ?? this.targetDuration,
      targetFlow: targetFlow ?? this.targetFlow,
      stopAtTemperature: stopAtTemperature ?? this.stopAtTemperature,
      preferredProbeId: preferredProbeId ?? this.preferredProbeId,
    );
  }
}
