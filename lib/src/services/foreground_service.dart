import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logging/logging.dart';

class ForegroundTaskService {
  static final _log = Logger("ForegroundTaskService");
  
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  static Future<void> start() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        _log.info("Foreground service already running");
        return;
      }

      final started = await FlutterForegroundTask.startService(
        notificationTitle: "Reaprime talking to DE1",
        notificationText: "Tap to return to Reaprime",
        callback: startCallback,
      );
      
      if (started) {
        _log.info("Foreground service started successfully");
      } else {
        _log.warning("Failed to start foreground service");
      }
    } catch (e, st) {
      _log.severe("Error starting foreground service", e, st);
    }
  }

  static Future<void> stop() async {
    try {
      final stopped = await FlutterForegroundTask.stopService();
      if (stopped) {
        _log.info("Foreground service stopped successfully");
      } else {
        _log.warning("Failed to stop foreground service");
      }
    } catch (e, st) {
      _log.severe("Error stopping foreground service", e, st);
    }
  }
}

@pragma(
  'vm:entry-point',
) // This decorator means that this function calls native code
void startCallback() {
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter sendPort) async {
    Logger("Foreground").info("starting foreground");
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // TODO: implement onDestroy
    // throw UnimplementedError();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // TODO: implement onRepeatEvent
  }
}
