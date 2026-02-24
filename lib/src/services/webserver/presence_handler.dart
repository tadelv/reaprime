part of '../webserver_service.dart';

/// REST API handler for user presence heartbeats and wake schedules.
class PresenceHandler {
  final PresenceController _presenceController;
  final SettingsController _settingsController;
  final log = Logger('PresenceHandler');

  PresenceHandler({
    required PresenceController presenceController,
    required SettingsController settingsController,
  })  : _presenceController = presenceController,
        _settingsController = settingsController;

  void addRoutes(RouterPlus app) {
    app.post('/api/v1/machine/heartbeat', _heartbeatHandler);
    app.get('/api/v1/presence/settings', _getSettingsHandler);
    app.post('/api/v1/presence/settings', _updateSettingsHandler);
    app.get('/api/v1/presence/schedules', _getSchedulesHandler);
    app.post('/api/v1/presence/schedules', _addScheduleHandler);
    app.put('/api/v1/presence/schedules/<id>', _updateScheduleHandler);
    app.delete('/api/v1/presence/schedules/<id>', _deleteScheduleHandler);
  }

  /// POST /api/v1/machine/heartbeat
  /// Signals user presence. Returns `{"timeout": secondsRemaining}`.
  Future<Response> _heartbeatHandler(Request request) async {
    try {
      final seconds = _presenceController.heartbeat();
      return jsonOk({'timeout': seconds});
    } catch (e, st) {
      log.severe('Error in heartbeat handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// GET /api/v1/presence/settings
  /// Returns current presence settings and schedules.
  Future<Response> _getSettingsHandler(Request request) async {
    try {
      final schedulesJson = _settingsController.wakeSchedules;
      List<Map<String, dynamic>> schedules = [];
      if (schedulesJson.isNotEmpty && schedulesJson != '[]') {
        schedules = WakeSchedule.deserializeList(schedulesJson)
            .map((s) => s.toJson())
            .toList();
      }

      return jsonOk({
        'userPresenceEnabled': _settingsController.userPresenceEnabled,
        'sleepTimeoutMinutes': _settingsController.sleepTimeoutMinutes,
        'schedules': schedules,
      });
    } catch (e, st) {
      log.severe('Error in get settings handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// POST /api/v1/presence/settings
  /// Updates `userPresenceEnabled` and/or `sleepTimeoutMinutes`.
  Future<Response> _updateSettingsHandler(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json.containsKey('userPresenceEnabled')) {
        await _settingsController
            .setUserPresenceEnabled(json['userPresenceEnabled'] as bool);
      }
      if (json.containsKey('sleepTimeoutMinutes')) {
        await _settingsController
            .setSleepTimeoutMinutes(json['sleepTimeoutMinutes'] as int);
      }

      return jsonOk({
        'userPresenceEnabled': _settingsController.userPresenceEnabled,
        'sleepTimeoutMinutes': _settingsController.sleepTimeoutMinutes,
      });
    } catch (e, st) {
      log.severe('Error in update settings handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// GET /api/v1/presence/schedules
  /// Returns array of schedule JSON objects.
  Future<Response> _getSchedulesHandler(Request request) async {
    try {
      final schedulesJson = _settingsController.wakeSchedules;
      if (schedulesJson.isEmpty || schedulesJson == '[]') {
        return jsonOk([]);
      }

      final schedules = WakeSchedule.deserializeList(schedulesJson);
      return jsonOk(schedules.map((s) => s.toJson()).toList());
    } catch (e, st) {
      log.severe('Error in get schedules handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// POST /api/v1/presence/schedules
  /// Adds a new schedule from JSON body. Returns 201.
  Future<Response> _addScheduleHandler(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final schedule = WakeSchedule.create(
        hour: json['hour'] as int? ??
            int.parse((json['time'] as String).split(':')[0]),
        minute: json['minute'] as int? ??
            int.parse((json['time'] as String).split(':')[1]),
        daysOfWeek: json.containsKey('daysOfWeek')
            ? (json['daysOfWeek'] as List).cast<int>().toSet()
            : {},
        enabled: json['enabled'] as bool? ?? true,
      );

      final schedulesJson = _settingsController.wakeSchedules;
      List<WakeSchedule> schedules = [];
      if (schedulesJson.isNotEmpty && schedulesJson != '[]') {
        schedules = WakeSchedule.deserializeList(schedulesJson);
      }

      schedules.add(schedule);
      await _settingsController
          .setWakeSchedules(WakeSchedule.serializeList(schedules));

      return jsonCreated(schedule.toJson());
    } catch (e, st) {
      log.severe('Error in add schedule handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// PUT /api/v1/presence/schedules/:id
  /// Updates an existing schedule by ID. Returns updated schedule or 404.
  Future<Response> _updateScheduleHandler(Request request, String id) async {
    try {
      final schedulesJson = _settingsController.wakeSchedules;
      if (schedulesJson.isEmpty || schedulesJson == '[]') {
        return jsonNotFound({'error': 'Schedule not found', 'id': id});
      }

      final schedules = WakeSchedule.deserializeList(schedulesJson);
      final index = schedules.indexWhere((s) => s.id == id);
      if (index == -1) {
        return jsonNotFound({'error': 'Schedule not found', 'id': id});
      }

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final existing = schedules[index];

      int hour = existing.hour;
      int minute = existing.minute;
      if (json.containsKey('time')) {
        final timeParts = (json['time'] as String).split(':');
        hour = int.parse(timeParts[0]);
        minute = int.parse(timeParts[1]);
      }
      if (json.containsKey('hour')) hour = json['hour'] as int;
      if (json.containsKey('minute')) minute = json['minute'] as int;

      final updated = existing.copyWith(
        hour: hour,
        minute: minute,
        daysOfWeek: json.containsKey('daysOfWeek')
            ? (json['daysOfWeek'] as List).cast<int>().toSet()
            : null,
        enabled: json.containsKey('enabled') ? json['enabled'] as bool : null,
      );

      schedules[index] = updated;
      await _settingsController
          .setWakeSchedules(WakeSchedule.serializeList(schedules));

      return jsonOk(updated.toJson());
    } catch (e, st) {
      log.severe('Error in update schedule handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// DELETE /api/v1/presence/schedules/:id
  /// Deletes a schedule by ID. Returns 200.
  Future<Response> _deleteScheduleHandler(Request request, String id) async {
    try {
      final schedulesJson = _settingsController.wakeSchedules;
      if (schedulesJson.isEmpty || schedulesJson == '[]') {
        return jsonNotFound({'error': 'Schedule not found', 'id': id});
      }

      final schedules = WakeSchedule.deserializeList(schedulesJson);
      final index = schedules.indexWhere((s) => s.id == id);
      if (index == -1) {
        return jsonNotFound({'error': 'Schedule not found', 'id': id});
      }

      schedules.removeAt(index);
      await _settingsController
          .setWakeSchedules(WakeSchedule.serializeList(schedules));

      return jsonOk({'deleted': id});
    } catch (e, st) {
      log.severe('Error in delete schedule handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }
}
