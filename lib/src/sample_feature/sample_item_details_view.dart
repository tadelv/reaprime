import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Displays detailed information about a SampleItem.
class SampleItemDetailsView extends StatelessWidget {
  SampleItemDetailsView({super.key, required this.machine});

  static const routeName = '/sample_item';

  final Machine machine;

  var _lastDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    machine.onConnect();
    return Scaffold(
      appBar: AppBar(title: const Text('Item Details')),
      body: Center(
        child: StreamBuilder(
          stream: machine.currentSnapshot,
          builder: (context, snapshot) {
            var diff = snapshot.data?.timestamp.difference(_lastDate) ?? 0;
            _lastDate = snapshot.data?.timestamp ?? DateTime.now();
            return Column(
              children: [
                Text(
                  "${snapshot.data?.state.state}: ${snapshot.data?.state.substate}",
                ),
                Text(
                  "steam temp: ${snapshot.data?.steamTemperature.toStringAsFixed(2)}",
                ),
                Text(
                  "group temp: ${snapshot.data?.groupTemperature.toStringAsFixed(2)}",
                ),
                Text("flow: ${snapshot.data?.flow.toStringAsFixed(2)}"),
                Text("pressure: ${snapshot.data?.pressure.toStringAsFixed(2)}"),
                Text(
                  "target mix temp: ${snapshot.data?.targetMixTemperature.toStringAsFixed(2)}",
                ),
                Text(
                  "target head temp: ${snapshot.data?.targetGroupTemperature.toStringAsFixed(2)}",
                ),
                Text(
                  "target pressure: ${snapshot.data?.targetPressure.toStringAsFixed(2)}",
                ),
                Text("target flow: ${snapshot.data?.flow.toStringAsFixed(2)}"),
                Text("update freq: ${diff}"),
              ],
            );
          },
        ),
      ),
    );
  }
}
