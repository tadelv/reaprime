import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class WaterLevelsForm extends StatefulWidget {
  final Function(De1WaterLevels) apply;
  final De1WaterLevels levels;

  const WaterLevelsForm({
    super.key,
    required this.apply,
    required this.levels,
  });

  @override
  State<StatefulWidget> createState() {
    return _WaterLevelsFormState();
  }
}

class _WaterLevelsFormState extends State<WaterLevelsForm> {
  late De1WaterLevels settings;

  @override
  void initState() {
    settings = widget.levels;
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
          Text("Refill warning level: ${settings.warningThresholdPercentage}%"),
          ShadSlider(
            initialValue: settings.warningThresholdPercentage.toDouble(),
            min: 0,
            max: 30,
						divisions: 6,
            onChanged: (val) {
              setState(() {
                settings = De1WaterLevels(
                  currentPercentage: settings.currentPercentage,
                  warningThresholdPercentage: val.toInt(),
                );
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
