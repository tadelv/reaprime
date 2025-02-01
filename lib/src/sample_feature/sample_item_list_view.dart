import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:reaprime/src/controllers/device_controller.dart';

import '../settings/settings_view.dart';
import 'sample_item_details_view.dart';

/// Displays a list of SampleItems.
class SampleItemListView extends StatelessWidget {
  const SampleItemListView({
    super.key,
    required this.controller,
  });

  static const routeName = '/';

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    FlutterForegroundTask.startService(
      notificationTitle: "Reaprime talking to DE1",
      notificationText: "Tap to return to Reaprime",
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sample Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to the settings page. If the user leaves and returns
              // to the app after it has been killed while running in the
              // background, the navigation stack is restored.
              Navigator.restorablePushNamed(context, SettingsView.routeName);
            },
          ),
          IconButton(
            onPressed: () async {
              await controller.scanForDevices();
            },
            icon: const Icon(Icons.radar),
          ),
        ],
      ),

      body: StreamBuilder(
        stream: controller.deviceStream,
        builder: (buildContext, data) {
          return ListView.builder(
            // Providing a restorationId allows the ListView to restore the
            // scroll position when a user leaves and returns to the app after it
            // has been killed while running in the background.
            restorationId: 'sampleItemListView',
            itemCount: data.data?.length ?? 0,
            itemBuilder: (BuildContext context, int index) {
              final item = controller.devices[index];

              return ListTile(
                title: Text('${item.type.name} ${item.name} : ${item.deviceId}'),
                leading: const CircleAvatar(
                  // Display the Flutter Logo image asset.
                  foregroundImage: AssetImage('assets/images/flutter_logo.png'),
                ),
                onTap: () {
                  // Navigate to the details page. If the user leaves and returns to
                  // the app after it has been killed while running in the
                  // background, the navigation stack is restored.
                  Navigator.restorablePushNamed(
                    context,
                    De1DebugView.routeName,
                    arguments: item.deviceId,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
