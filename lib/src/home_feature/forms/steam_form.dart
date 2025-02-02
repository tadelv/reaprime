import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SteamForm extends StatefulWidget {
  const SteamForm({
    super.key,
    required this.apply,
		required this.shotSettings,
  });

  final Function(Map<Object, dynamic>) apply;
	final De1ShotSettings shotSettings;

  @override
  State<SteamForm> createState() {
    return _SteamFormState();
  }
}

class _SteamFormState extends State<SteamForm> {
  final formKey = GlobalKey<ShadFormState>();

  @override
  Widget build(BuildContext context) {
    return ShadForm(
        key: formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              ShadSwitchFormField(
                  id: 'enabled',
                  label: const Text('Steam enabled'),
                  initialValue: widget.shotSettings.targetSteamDuration > 0),
              ShadInputFormField(
                id: 'temperature',
                label: const Text('Steam Temperature'),
								initialValue: widget.shotSettings.targetSteamTemp.toString(),
                validator: (v) => ((int.tryParse(v) ?? -1) >= 0 &&
                        (int.tryParse(v) ?? 0) < 170)
                    ? null
                    : "Enter valid temperature for steam",
              ),
              ShadButton(
                child: const Text('Apply'),
                onPressed: () {
                  if (formKey.currentState!.saveAndValidate()) {
                    widget.apply(formKey.currentState!.value);
                  }
                },
              )
            ],
          ),
        ));
  }
} 

class SteamFormSettings {
  bool steamEnabled;
  int targetTemp;
  int targetDuration;
  double targetFlow;
// TODO: purge mode and power mode

  SteamFormSettings({
    required this.steamEnabled,
    required this.targetTemp,
    required this.targetDuration,
    required this.targetFlow,
  });

  factory SteamFormSettings.fromForm(Map<Object, dynamic> form) {
    return SteamFormSettings(
        steamEnabled: form['enabled'] == true,
        targetTemp: int.tryParse(form['temperature']) ?? 0,
        targetDuration: int.tryParse(form['duration']) ?? 0,
        targetFlow: double.tryParse(form['flow']) ?? 0);
  }

  factory SteamFormSettings.fromShotSettings(De1ShotSettings shotSettings) {
    return SteamFormSettings(
        steamEnabled: shotSettings.targetSteamDuration > 0,
        targetTemp: shotSettings.targetSteamTemp,
        targetDuration: shotSettings.targetSteamDuration,
        targetFlow: 0.5);
  }
}
