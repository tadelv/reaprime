import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';

class StatusTile extends StatelessWidget {
  final De1Interface de1;
  final Scale? scale;
  const StatusTile({super.key, required this.de1, this.scale});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
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
                  })
            ]),
            SizedBox(height: 8),
            if (scale != null)
              Text(
                "Scale",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
