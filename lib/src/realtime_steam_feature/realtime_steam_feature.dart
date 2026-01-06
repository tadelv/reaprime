import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/util/shot_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RealtimeSteamFeature extends StatefulWidget {
  static const routeName = '/steam';

  final De1Controller de1Controller;
  final SteamSettings initialSteamSettings;
  final GatewayMode gatewayMode;

  const RealtimeSteamFeature({
    super.key,
    required this.de1Controller,
    required this.initialSteamSettings,
    required this.gatewayMode,
  });

  @override
  State<StatefulWidget> createState() => _RealtimeSteamFeatureState();
}

class _RealtimeSteamFeatureState extends State<RealtimeSteamFeature> {
  late De1Controller _de1Controller;
  final List<ShotSnapshot> _steamSnapshots = [];
  late StreamSubscription<ShotSnapshot> _steamSubscription;
  late bool _gatewayMode;
  bool _steamActive = false;
  double _steamFlow = 1.0; // Default steam flow in ml/s
  int _steamDuration = 30; // Default steam duration in seconds
  int _remainingTime = 0;
  Timer? _steamTimer;
  DateTime? _steamStartTime;

  @override
  void initState() {
    super.initState();
    _de1Controller = widget.de1Controller;
    _steamFlow = widget.initialSteamSettings.flow;
    _steamDuration = widget.initialSteamSettings.duration;
    _remainingTime = _steamDuration;
    _steamStartTime = DateTime.now();

    _gatewayMode = widget.gatewayMode == GatewayMode.full;

    // Subscribe to DE1 data
    _steamSubscription = _de1Controller
        .connectedDe1()
        .currentSnapshot
        .map((snapshot) => ShotSnapshot(machine: snapshot))
        .listen((snapshot) {
          final bool isMachineSteaming =
              snapshot.machine.state.state == MachineState.steam;

          if (mounted) {
            setState(() {
              // Update active state only when it changes
              if (_steamActive != isMachineSteaming) {
                // Clear snapshots when transitioning from idle to steam
                if (!_steamActive && isMachineSteaming) {
                  _steamSnapshots.clear();
                }
                
                _steamActive = isMachineSteaming;
              }

              // Add snapshot only when actively steaming
              if (_steamActive) {
                print("adding snap");
                _steamSnapshots.add(snapshot);
              }
            });
          }
        });

    _steamTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingTime > 0) {
            _remainingTime--;
          } else {
            // _stopSteam();
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _steamSubscription.cancel();
    _stopSteamTimer();
    super.dispose();
  }

  void _stopSteam() {
    print("stop steam ${_steamActive}");
    if (_steamActive) {
      setState(() {
        _steamActive = false;
        _remainingTime = 0;
      });

      // Stop steam by going to idle state
      _de1Controller.connectedDe1().requestState(MachineState.idle);

      _stopSteamTimer();
    }
  }

  void _extendSteam() async {
    if (_steamActive) {
      setState(() {
        _steamDuration += 10;
      });

      // Update steam duration
      final currentSettings =
          await _de1Controller.connectedDe1().shotSettings.first;
      await _de1Controller.connectedDe1().updateShotSettings(
        currentSettings.copyWith(targetSteamDuration: _steamDuration),
      );
    }
  }

  void _stopSteamTimer() {
    _steamTimer?.cancel();
    _steamTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    // Navigation guard - only allow if gateway mode is 'tracking' or 'disabled'
    if (_gatewayMode) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Steam Feature Not Available',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'Steam feature is only available when gateway mode is "tracking" or "disabled"',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ShadButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              _steamStats(context),
              ShotChart(
                shotSnapshots: _steamSnapshots,
                shotStartTime: _steamStartTime ?? DateTime.now(),
              ),
              Row(
                spacing: 16.0,
                children: [
                SizedBox(width: 16.0,),
                  _countdownBar(context),
                  _steamControls(context),
                  _flowSlider(context),
                ],
              ),
              Row(
                spacing: 16.0,
                children: [_durationControls(context), Spacer(), _actionButtons(context)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _steamStats(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.headlineSmall!,
      child: Row(
        children: [
          const Spacer(),
          SizedBox(
            width: 200,
            child: Text(
              "Time: ${_remainingTime}s",
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 150,
            child: Text(
              "${_steamSnapshots.lastOrNull?.machine.flow.toStringAsFixed(1)}ml/s",
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 150,
            child: Text(
              "${_steamSnapshots.lastOrNull?.machine.pressure.toStringAsFixed(1)}bar",
              style: const TextStyle(color: Colors.green),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 150,
            child: Text(
              "ST: ${_steamSnapshots.lastOrNull?.machine.steamTemperature}℃",
              style: const TextStyle(color: Colors.red),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _steamControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShadButton.destructive(
          onPressed: () {
            _stopSteam();
          },
          child: const Text('Stop Steam'),
        ),
      ],
    );
  }

  Widget _countdownBar(BuildContext context) {
    return Flexible(
      flex: 2,
      child: Column(
        children: [
          LinearProgressIndicator(
            value: _steamDuration > 0 ? (_remainingTime / _steamDuration) : 0,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              _steamActive ? Colors.blue : Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Remaining: $_remainingTime seconds',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _flowSlider(BuildContext context) {
    return Flexible(
      flex: 3,
      child: Column(
      spacing: 12.0,
        children: [
          Text(
            'Steam Flow: ${_steamFlow.toStringAsFixed(1)} ml/s',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ShadSlider(
              initialValue: _steamFlow,
              min: 0.4,
              max: 2.0,
              divisions: 16,
              thumbRadius: 16.0,
              trackHeight: 24.0,
              label: _steamFlow.toStringAsFixed(1),
              onChanged: (value) async {
                await _de1Controller.connectedDe1().setSteamFlow(value);
                setState(() {
                  _steamFlow = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _durationControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShadButton.outline(
            onPressed:
                _steamActive
                    ? null
                    : () {
                      setState(() {
                        _steamDuration = 15;
                      });
                    },
            child: const Text('15s'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            onPressed:
                _steamActive
                    ? null
                    : () {
                      setState(() {
                        _steamDuration = 30;
                      });
                    },
            child: const Text('30s'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            onPressed:
                _steamActive
                    ? null
                    : () {
                      setState(() {
                        _steamDuration = 60;
                      });
                    },
            child: const Text('60s'),
          ),
          const SizedBox(width: 16),
          ShadButton(
            onPressed: _steamActive ? _extendSteam : null,
            child: const Text('+10s'),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShadButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

