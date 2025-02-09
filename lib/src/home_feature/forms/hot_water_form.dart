import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HotWaterForm extends StatefulWidget {
  final Function(HotWaterFormSettings) apply;
  final HotWaterFormSettings hotWaterSettings;

  const HotWaterForm(
      {super.key, required this.apply, required this.hotWaterSettings});

  @override
  State<StatefulWidget> createState() => _HotWaterFormState();
}

class _HotWaterFormState extends State<HotWaterForm> {
  late HotWaterFormSettings hotWaterSettings;

  @override
  void initState() {
    hotWaterSettings = widget.hotWaterSettings;
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
          Text("Temperature: ${hotWaterSettings.targetTemperature}℃"),
          ShadSlider(
            initialValue: hotWaterSettings.targetTemperature.toDouble(),
            min: 50,
            max: 95,
            onChanged: (val) {
              setState(() {
                hotWaterSettings.targetTemperature = val.toInt();
              });
            },
          ),
          Text("Volume: ${hotWaterSettings.volume} ml"),
          ShadSlider(
            initialValue: hotWaterSettings.volume.toDouble(),
            min: 0,
            max: 250,
            onChanged: (val) {
              setState(() {
                hotWaterSettings.volume = val.toInt();
              });
            },
          ),
          Text("Duration: ${hotWaterSettings.duration} seconds"),
          ShadSlider(
            initialValue: hotWaterSettings.duration.toDouble(),
            min: 0,
            max: 60,
            onChanged: (val) {
              setState(() {
                hotWaterSettings.duration = val.toInt();
              });
            },
          ),
          Text("Flow rate: ${hotWaterSettings.flow.toStringAsFixed(1)} ml/s"),
          ShadSlider(
            initialValue: hotWaterSettings.flow.toDouble(),
            min: 1.0,
            max: 8.0,
            onChanged: (val) {
              setState(() {
                hotWaterSettings.flow = val;
              });
            },
          ),
          ShadButton(
            child: const Text('Apply'),
            onPressed: () {
              widget.apply(hotWaterSettings);
            },
          )
        ],
      ),
    );
  }
}

class HotWaterFormSettings {
  int targetTemperature;
  double flow;
  int volume;
  int duration;

  HotWaterFormSettings({
    required this.targetTemperature,
    required this.flow,
    required this.volume,
    required this.duration,
  });

  HotWaterFormSettings copyWith({
    int? targetTemperature,
    double? flow,
    int? volume,
    int? duration,
  }) {
    return HotWaterFormSettings(
      targetTemperature: targetTemperature ?? this.targetTemperature,
      flow: flow ?? this.flow,
      volume: volume ?? this.volume,
      duration: duration ?? this.duration,
    );
  }
}
