import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RinseForm extends StatefulWidget {
  final Function(De1ControllerRinseData) apply;
  final De1ControllerRinseData rinseSettings;

  const RinseForm({
    super.key,
    required this.apply,
    required this.rinseSettings,
  });

  @override
  createState() => _RinseFormState();
}

class _RinseFormState extends State<RinseForm> {
  late De1ControllerRinseData settings;

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
            min: 0,
            max: 95,
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
