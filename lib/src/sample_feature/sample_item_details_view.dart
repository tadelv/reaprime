import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Displays detailed information about a SampleItem.
class SampleItemDetailsView extends StatelessWidget {
  const SampleItemDetailsView({super.key, required this.machine});

  static const routeName = '/sample_item';

  final Machine machine;

  @override
  Widget build(BuildContext context) {
    machine.onConnect();
    return Scaffold(
      appBar: AppBar(title: const Text('Item Details')),
      body: Center(
        child: StreamBuilder(
          stream: machine.currentSnapshot,
          builder: (context, snapshot) {
            return Column(
              children: [
                Text("${snapshot.data?.state.state}"),
                Text("${snapshot.data?.steamTemperature.toStringAsFixed(2)}"),
                Text("${snapshot.data?.groupTemperature.toStringAsFixed(2)}"),
              ],
            );
          },
        ),
      ),
    );
  }
}
