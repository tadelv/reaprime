import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RinseForm extends StatefulWidget {
  final Function(RinseData) apply;
  final RinseData rinseSettings;

  const RinseForm({
    super.key,
    required this.apply,
    required this.rinseSettings,
  });

  @override
  createState() => _RinseFormState();
}

class _RinseFormState extends State<RinseForm> {
  late RinseData settings;

  @override
  void initState() {
    settings = widget.rinseSettings;
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
          Text("Temperature: ${settings.targetTemperature}℃"),
          ShadSlider(
            initialValue: settings.targetTemperature.toDouble(),
            min: 5,
            max: 95,
            divisions: 18,
            thumbRadius: 15,
            trackHeight: 15,
            onChanged: (val) {
              setState(() {
                settings.targetTemperature = val.toInt();
              });
            },
          ),
          Text("Duration: ${settings.duration} seconds"),
          ShadSlider(
            initialValue: settings.duration.toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            thumbRadius: 15,
            trackHeight: 15,
            onChanged: (val) {
              setState(() {
                settings.duration = val.toInt();
              });
            },
          ),
          Text("Flow rate: ${settings.flow.toStringAsFixed(1)} ml/s"),
          ShadSlider(
            initialValue: settings.flow,
            min: 1.0,
            max: 8.0,
            divisions: 14,
            thumbRadius: 15,
            trackHeight: 15,
            onChanged: (val) {
              setState(() {
                settings.flow = val;
              });
            },
          ),
          ShadButton(
            child: const Text('Apply'),
            onPressed: () {
              widget.apply(settings);
            },
          )
        ],
      ),
    );
  }
}
