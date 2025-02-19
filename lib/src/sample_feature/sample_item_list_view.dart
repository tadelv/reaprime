import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../settings/settings_view.dart';
import 'sample_item_details_view.dart';

/// Displays a list of SampleItems.
class SampleItemListView extends StatelessWidget {
  const SampleItemListView({
    super.key,
    required this.controller,
  });

  static const routeName = '/debug';

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Items'),
        actions: [
          IconButton(
            onPressed: () async {
              await controller.scanForDevices();
            },
            icon: const Icon(LucideIcons.radar),
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
