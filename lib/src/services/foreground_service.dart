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
        // Set up recurring event to keep service alive (interval in milliseconds)
        eventAction: ForegroundTaskEventAction.repeat(60000), // 1 minute
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
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
      
      if (started == const ServiceRequestSuccess()) {
        _log.info("Foreground service started successfully");
      } else {
        _log.warning("Failed to start foreground service, $started");
      }
    } catch (e, st) {
      _log.severe("Error starting foreground service", e, st);
    }
  }

  static Future<void> stop() async {
    try {
      final stopped = await FlutterForegroundTask.stopService();
      if (stopped == ServiceRequestSuccess()) {
        _log.info("Foreground service stopped successfully");
      } else {
        _log.warning("Failed to stop foreground service, $stopped");
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
  final _log = Logger("ForegroundTaskHandler");
  int _eventCount = 0;

  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter sendPort) async {
    _log.info("Foreground service started at $timestamp");
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _log.info("Foreground service destroyed. Timeout: $isTimeout");
  }

  // This method is called periodically based on the interval set in ForegroundTaskOptions
  // It's critical to keep the service alive - if this doesn't run, Android will kill the service
  @override
  void onRepeatEvent(DateTime timestamp) {
    _eventCount++;
    
    // Update notification to show the service is alive
    FlutterForegroundTask.updateService(
      notificationTitle: 'Streamline Active',
      notificationText: 'Maintaining connections (${_formatUptime()})',
    );
    
    // Log periodically to confirm service is running
    if (_eventCount % 5 == 0) {
      _log.fine('Foreground service heartbeat: $_eventCount events, uptime: ${_formatUptime()}');
    }
  }

  String _formatUptime() {
    final minutes = _eventCount;
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }
}



