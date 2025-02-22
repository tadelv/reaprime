import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Displays detailed information about a SampleItem.
class De1DebugView extends StatefulWidget {
  const De1DebugView({super.key, required this.machine});

  static const routeName = '/debug_details';

  final De1Interface machine;

  @override
  State<De1DebugView> createState() => _De1DebugViewState();
}

class _De1DebugViewState extends State<De1DebugView> {
  var _lastDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item Details')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Flex(
            direction: Axis.horizontal,
            children: [
              Expanded(
                child: Flexible(
                  flex: 1,
                  child: StreamBuilder(
                    stream: widget.machine.currentSnapshot,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.active) {
                        var diff =
                            snapshot.data?.timestamp.difference(_lastDate) ?? Duration.zero;
                        _lastDate = snapshot.data?.timestamp ?? DateTime.now();
                        return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: machineState(snapshot, diff));
                      } else if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Text("Connecting");
                      }
                      return Text(
                        "Waiting for data: ${snapshot.connectionState}",
                      );
                    },
                  ),
                ),
              ),
              Flexible(
                  flex: 1,
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: _shotSettings(widget.machine.shotSettings))),
              Flexible(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _waterLevels(widget.machine.waterLevels),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> machineState(
    AsyncSnapshot<MachineSnapshot> snapshot,
    Duration diff,
  ) {
    return [
      Text("${snapshot.data?.state.state}: ${snapshot.data?.state.substate}"),
      Text("steam temp: ${snapshot.data?.steamTemperature.toStringAsFixed(2)}"),
      Text("group temp: ${snapshot.data?.groupTemperature.toStringAsFixed(2)}"),
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
      Text("update freq: ${diff.inMilliseconds}ms"),
      _stateButton(snapshot),
    ];
  }

  Widget _stateButton(AsyncSnapshot<MachineSnapshot> snapshot) {
    if (snapshot.data != null) {
      if (snapshot.data!.state.state == MachineState.sleeping) {
        return OutlinedButton(
          onPressed: () {
            widget.machine.requestState(MachineState.idle);
          },
          child: Text("Wake"),
        );
      } else {
        return OutlinedButton(
          onPressed: () {
            widget.machine.requestState(MachineState.sleeping);
          },
          child: Text("Sleep"),
        );
      }
    }
    return SizedBox();
  }

  Widget _shotSettings(Stream<De1ShotSettings> shotSettings) {
    return StreamBuilder(
      stream: shotSettings,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text("${snapshot.data!.steamSetting}")]);
        }
        return Text("Waiting for data ${snapshot.connectionState}");
      },
    );
  }

  Widget _waterLevels(Stream<De1WaterLevels> waterLevels) {
    return StreamBuilder(
      stream: waterLevels,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("water level: ${snapshot.data!.currentPercentage}%"),
            ],
          );
        }
        return Text("Waiting for data ${snapshot.connectionState}");
      },
    );
  }
}
