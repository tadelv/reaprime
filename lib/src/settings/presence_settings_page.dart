import 'package:flutter/material.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class PresenceSettingsPage extends StatefulWidget {
  const PresenceSettingsPage({
    super.key,
    required this.controller,
  });

  final SettingsController controller;

  @override
  State<PresenceSettingsPage> createState() => _PresenceSettingsPageState();
}

class _PresenceSettingsPageState extends State<PresenceSettingsPage> {
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  List<WakeSchedule> _parseSchedules() {
    final json = widget.controller.wakeSchedules;
    if (json.isEmpty || json == '[]') return [];
    try {
      return WakeSchedule.deserializeList(json);
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveSchedules(List<WakeSchedule> schedules) async {
    await widget.controller.setWakeSchedules(
      WakeSchedule.serializeList(schedules),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Presence & Sleep')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  _buildUserPresenceSection(),
                  if (widget.controller.userPresenceEnabled) ...[
                    _buildSleepTimeoutSection(),
                    _buildWakeSchedulesSection(),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // MARK: - Section Builders

  Widget _buildUserPresenceSection() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShadSwitch(
            value: widget.controller.userPresenceEnabled,
            onChanged: (v) {
              widget.controller.setUserPresenceEnabled(v);
            },
            label: const Text('User Presence'),
            sublabel: const Text(
              'Enable presence-based power management. When enabled, the machine '
              'can automatically sleep after inactivity and wake on a schedule.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepTimeoutSection() {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sleep Timeout',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Automatically put the machine to sleep after a period of inactivity. '
            'The timer resets whenever the machine is used.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 16),
          DropdownButton<int>(
            isExpanded: true,
            value: widget.controller.sleepTimeoutMinutes,
            onChanged: (value) {
              if (value != null) {
                widget.controller.setSleepTimeoutMinutes(value);
              }
            },
            items: const [
              DropdownMenuItem(
                value: 0,
                child: Text('Disabled'),
              ),
              DropdownMenuItem(
                value: 15,
                child: Text('15 minutes'),
              ),
              DropdownMenuItem(
                value: 30,
                child: Text('30 minutes'),
              ),
              DropdownMenuItem(
                value: 45,
                child: Text('45 minutes'),
              ),
              DropdownMenuItem(
                value: 60,
                child: Text('60 minutes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWakeSchedulesSection() {
    final schedules = _parseSchedules();

    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wake Schedules',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Schedule times for the machine to automatically wake up. '
            'Useful for having the machine ready when you start your day.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          if (schedules.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...schedules.map((schedule) => _buildScheduleRow(schedule, schedules)),
          ],
          const SizedBox(height: 16),
          ShadButton.outline(
            onPressed: () => _addSchedule(schedules),
            child: const Text('Add Schedule'),
          ),
        ],
      ),
    );
  }

  // MARK: - Schedule Row

  Widget _buildScheduleRow(WakeSchedule schedule, List<WakeSchedule> schedules) {
    final timeOfDay = TimeOfDay(hour: schedule.hour, minute: schedule.minute);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Time display - tappable to edit
              GestureDetector(
                onTap: () => _editScheduleTime(schedule, schedules),
                child: Text(
                  timeOfDay.format(context),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Spacer(),
              // Enable/disable toggle
              ShadSwitch(
                value: schedule.enabled,
                onChanged: (v) {
                  final updated = schedules.map((s) {
                    if (s.id == schedule.id) return s.copyWith(enabled: v);
                    return s;
                  }).toList();
                  _saveSchedules(updated);
                },
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () {
                  final updated =
                      schedules.where((s) => s.id != schedule.id).toList();
                  _saveSchedules(updated);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (schedule.daysOfWeek.isEmpty)
                Chip(
                  label: Text(
                    'Every day',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  visualDensity: VisualDensity.compact,
                )
              else
                for (int day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(
                      _dayLabels[day - 1],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    selected: schedule.daysOfWeek.contains(day),
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      _toggleDay(schedule, schedules, day, selected);
                    },
                  ),
            ],
          ),
          // Show day chips toggle when "Every day" is shown
          if (schedule.daysOfWeek.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () {
                  // Switch from "every day" to explicit day selection
                  // Start with all days selected
                  final updated = schedules.map((s) {
                    if (s.id == schedule.id) {
                      return s.copyWith(
                          daysOfWeek: {1, 2, 3, 4, 5, 6, 7});
                    }
                    return s;
                  }).toList();
                  _saveSchedules(updated);
                },
                child: Text(
                  'Tap to select specific days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
          const Divider(),
        ],
      ),
    );
  }

  // MARK: - Actions

  Future<void> _addSchedule(List<WakeSchedule> schedules) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 6, minute: 0),
    );
    if (picked == null) return;

    final newSchedule = WakeSchedule(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      hour: picked.hour,
      minute: picked.minute,
      daysOfWeek: const {},
      enabled: true,
    );

    final updated = [...schedules, newSchedule];
    await _saveSchedules(updated);
  }

  Future<void> _editScheduleTime(
    WakeSchedule schedule,
    List<WakeSchedule> schedules,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
    );
    if (picked == null) return;

    final updated = schedules.map((s) {
      if (s.id == schedule.id) {
        return s.copyWith(hour: picked.hour, minute: picked.minute);
      }
      return s;
    }).toList();
    await _saveSchedules(updated);
  }

  void _toggleDay(
    WakeSchedule schedule,
    List<WakeSchedule> schedules,
    int day,
    bool selected,
  ) {
    final newDays = Set<int>.from(schedule.daysOfWeek);
    if (selected) {
      newDays.add(day);
    } else {
      newDays.remove(day);
    }

    // If all days are deselected, revert to "every day" (empty set)
    final effectiveDays = newDays.length == 7 ? <int>{} : newDays;

    final updated = schedules.map((s) {
      if (s.id == schedule.id) {
        return s.copyWith(daysOfWeek: effectiveDays);
      }
      return s;
    }).toList();
    _saveSchedules(updated);
  }
}
