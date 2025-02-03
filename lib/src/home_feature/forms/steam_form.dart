import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SteamForm extends StatefulWidget {
  const SteamForm({
    super.key,
    required this.apply,
		required this.steamSettings,
  }) ;
  final Function(Map<Object, dynamic>) apply;
	final SteamFormSettings steamSettings;

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
              ShadSlider(
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
// TODO: purge mode 

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
