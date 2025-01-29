import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/device/scale.dart';

class ScaleDebugView extends StatelessWidget {
  final Scale scale;
  var _lastDate = DateTime.now();

  ScaleDebugView({super.key, required this.scale}) 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scale debug')),
      body: Center(
        child: Column(
          children: [
            Text('${scale.name}, ${scale.deviceId}'),
            StreamBuilder(
              stream: scale.currentSnapshot,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.active) {
                  var diff =
                      snapshot.data?.timestamp.difference(_lastDate) ?? 0;
                  _lastDate = snapshot.data?.timestamp ?? DateTime.now();
                  return Column(
                    children: [
                      Text(
                        '${snapshot.data?.weight.toStringAsFixed(1)}g',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Battery: ${snapshot.data?.batteryLevel}%'),
                      Text('last update: ${diff}s ago'),
                    ],
                  );
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Text("Connecting");
                }
                return Text("Waiting for data: ${snapshot.connectionState}");
              },
            ),
          ],
        ),
      ),
    );
  }
}
