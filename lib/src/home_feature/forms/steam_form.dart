import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SteamForm extends StatefulWidget {
  const SteamForm({
    super.key,
    required this.apply,
    required this.steamSettings,
  });
  final Function(SteamFormSettings) apply;
  final SteamFormSettings steamSettings;

  @override
  State<SteamForm> createState() {
    return _SteamFormState();
  }
}

class _SteamFormState extends State<SteamForm> {
  final formKey = GlobalKey<ShadFormState>();

  late SteamFormSettings steamSettings;

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
          Row(
            children: [
              Text("Steam enabled"),
              Spacer(),
              ShadSwitch(
                  value: steamSettings.steamEnabled,
                  onChanged: (val) {
                    setState(() {
                      if (val) {
                        steamSettings.targetTemp = 135;
                      }
                      steamSettings.steamEnabled = val;
                    });
                  }),
            ],
          ),
          Text("Steam temperature: ${steamSettings.targetTemp}℃"),
          ShadSlider(
            initialValue: steamSettings.steamEnabled
                ? steamSettings.targetTemp.toDouble()
                : 135,
            min: 135,
            max: 170,
            enabled: steamSettings.steamEnabled,
            onChanged: (val) {
              setState(() {
                steamSettings.targetTemp = val.toInt();
              });
            },
          ),
          Text("Steam duration: ${steamSettings.targetDuration} seconds"),
          ShadSlider(
            initialValue: steamSettings.targetDuration.toDouble(),
            min: 0,
            max: 120,
            enabled: steamSettings.steamEnabled,
            onChanged: (val) {
              setState(() {
                steamSettings.targetDuration = val.toInt();
              });
            },
          ),
          Text(
              "Steam flow: ${steamSettings.targetFlow.toStringAsFixed(1)} ml/s"),
          ShadSlider(
            initialValue: steamSettings.targetFlow.toDouble(),
            min: 0.4,
            max: 2.5,
            enabled: steamSettings.steamEnabled,
            onChanged: (val) {
              setState(() {
                steamSettings.targetFlow = val;
              });
            },
          ),
          ShadButton(
            child: const Text('Apply'),
            onPressed: () {
              widget.apply(steamSettings);
            },
          )
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
// TODO: purge mode

  SteamFormSettings({
    required this.steamEnabled,
    required this.targetTemp,
    required this.targetDuration,
    required this.targetFlow,
  });
}
