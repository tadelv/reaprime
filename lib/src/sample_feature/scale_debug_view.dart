import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:shadcn_ui/shadcn_ui.dart' hide Scale;

class ScaleDebugView extends StatefulWidget {
  final Scale scale;

  const ScaleDebugView({super.key, required this.scale});

  @override
  State<ScaleDebugView> createState() => _ScaleDebugViewState();
}

class _ScaleDebugViewState extends State<ScaleDebugView> {
  var _lastDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    widget.scale.onConnect();
    return Scaffold(
      appBar: AppBar(title: const Text('Scale debug')),
      body: Center(
        child: Column(
          children: [
            Text('${widget.scale.name}, ${widget.scale.deviceId}'),
            StreamBuilder(
              stream: widget.scale.currentSnapshot,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.active) {
                  Duration diff =
                      snapshot.data?.timestamp.difference(_lastDate) ??
                      Duration.zero;
                  _lastDate = snapshot.data?.timestamp ?? DateTime.now();
                  return Column(
                    spacing: 12,
                    children: [
                      Text(
                        '${snapshot.data?.weight.toStringAsFixed(1)}g',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Battery: ${snapshot.data?.batteryLevel}%'),
                      Text('last update: ${diff.inMilliseconds}ms ago'),
                      FilledButton(
                        onPressed: () async {
                          await widget.scale.tare();
                        },
                        child: Text("Tare"),
                      ),
                      FilledButton(
                        onPressed: () async {
                          await widget.scale.wakeDisplay();
                        },
                        child: Text("Wake"),
                      ),
                      FilledButton(
                        onPressed: () async {
                          await widget.scale.sleepDisplay();
                        },
                        child: Text("Sleep"),
                      ),
                      FilledButton(
                        onPressed: () async {
                          await widget.scale.disconnect();
                          if (!context.mounted) {
                            return;
                          }
                          Navigator.of(context).pop();
                        },
                        child: Text("Disconnect"),
                      ),
                    ],
                  );
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Column(
                    children: [
                      Text("Connecting"),
                      ShadButton(child: Text("disconnect"),
                      onPressed: () async {
                          await widget.scale.disconnect();
                        },)
                    ],
                  );
                }
                return Text("Waiting for data: ${snapshot.connectionState}");
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void deactivate() {
    //widget.scale.disconnect();
    super.deactivate();
  }
}
