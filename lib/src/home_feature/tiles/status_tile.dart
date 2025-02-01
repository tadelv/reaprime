import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/sample_feature/sample_item_list_view.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StatusTile extends StatelessWidget {
  final De1Interface de1;
  final Scale? scale;
  const StatusTile({super.key, required this.de1, this.scale});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            spacing: 5,
            children: [
              Text(
                "DE1",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              StreamBuilder(
                  stream: de1.currentSnapshot,
                  builder: (context, snapshotData) {
                    if (snapshotData.connectionState !=
                        ConnectionState.active) {
                      return Text("Waiting");
                    }
                    var snapshot = snapshotData.data!;
                    return Row(children: [
                      Text(
                          "Group: ${snapshot.groupTemperature.toStringAsFixed(1)}℃"),
                      Text(
                          "Steam: ${snapshot.steamTemperature.toStringAsFixed(1)}℃"),
                    ]);
                  }),
              StreamBuilder(
                  stream: de1.waterLevels,
                  builder: (context, waterSnapshot) {
                    if (waterSnapshot.connectionState !=
                        ConnectionState.active) {
                      return Text("Waiting");
                    }
                    var snapshot = waterSnapshot.data!;
                    return Row(children: [
                      Text("Water: ${snapshot.currentPercentage}%"),
                    ]);
                  })
            ]),
        SizedBox(height: 8),
        StreamBuilder(
          stream: de1.shotSettings,
          builder: (context, settingsSnapshot) {
            if (settingsSnapshot.connectionState != ConnectionState.active) {
              return Text("Waiting");
            }
            var settings = settingsSnapshot.data!;
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              spacing: 5,
              children: [
                Text("TG: ${settings.groupTemp}"),
								Text("HW: ${settings.targetHotWaterTemp}℃"),
                Text("HW: ${settings.targetHotWaterVolume}ml"),
                Text("HW: ${settings.targetHotWaterDuration}s"),
                Text("ST: ${settings.targetSteamTemp}℃"),
                Text("SD: ${settings.targetSteamDuration}"),
              ],
            );
          },
        ),
        SizedBox(height: 8),
        if (scale != null)
          Text(
            "Scale",
            style: TextStyle(
              fontSize: 16,
              color: Colors.blueGrey,
            ),
          ),
        SizedBox(height: 8),
        ShadButton(
          onPressed: () {
            Navigator.restorablePushNamed(
                context, SampleItemListView.routeName);
          },
          child: Icon(LucideIcons.settings),
        )
      ],
    );
  }
}
