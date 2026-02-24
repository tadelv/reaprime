import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';

class PresenceNavigatorObserver extends NavigatorObserver {
  final PresenceController _presenceController;

  PresenceNavigatorObserver({required PresenceController presenceController})
      : _presenceController = presenceController;

  @override
  void didPush(Route route, Route? previousRoute) {
    _presenceController.heartbeat();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _presenceController.heartbeat();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    _presenceController.heartbeat();
  }
}
