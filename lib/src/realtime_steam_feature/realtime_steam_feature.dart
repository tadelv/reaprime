import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/util/shot_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RealtimeSteamFeature extends StatefulWidget {
  static const routeName = '/steam';

  final De1Controller de1Controller;

  const RealtimeSteamFeature({
    super.key,
    required this.de1Controller,
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

    // Check gateway mode
    SettingsService().gatewayMode().then((mode) {
      setState(() {
        _gatewayMode = mode == GatewayMode.full;
      });
    });

    // Subscribe to DE1 data
    _steamSubscription = _de1Controller.connectedDe1().currentSnapshot
        .map((snapshot) => ShotSnapshot(machine: snapshot))
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _steamSnapshots.add(snapshot);
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

  void _startSteam() async {
    if (!_steamActive) {
      setState(() {
        _steamActive = true;
        _remainingTime = _steamDuration;
        _steamStartTime = DateTime.now();
        _steamSnapshots.clear();
      });

      // Get current shot settings and update steam settings
      final currentSettings = await _de1Controller.connectedDe1().shotSettings.first;
      await _de1Controller.connectedDe1().updateShotSettings(
        currentSettings.copyWith(
          targetSteamTemp: 150, // Default steam temperature
          targetSteamDuration: _steamDuration,
        ),
      );

      // Set steam flow
      await _de1Controller.connectedDe1().setSteamFlow(_steamFlow);

      // Start steam mode
      _de1Controller.connectedDe1().requestState(MachineState.steam);

      // Start countdown timer
      _steamTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            if (_remainingTime > 0) {
              _remainingTime--;
            } else {
              _stopSteam();
              timer.cancel();
            }
          });
        }
      });
    }
  }

  void _stopSteam() {
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
        _remainingTime += 10;
      });

      // Update steam duration
      final currentSettings = await _de1Controller.connectedDe1().shotSettings.first;
      await _de1Controller.connectedDe1().updateShotSettings(
        currentSettings.copyWith(
          targetSteamDuration: _remainingTime,
        ),
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
              _steamControls(context),
              _countdownBar(context),
              _flowSlider(context),
              _durationControls(context),
              _actionButtons(context),
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
          SizedBox(
            width: 150,
            child: Text(
              "MT: ${_steamSnapshots.lastOrNull?.machine.mixTemperature.toStringAsFixed(1)}℃",
              style: const TextStyle(color: Colors.orange),
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
        ShadButton(
          onPressed: _steamActive ? null : _startSteam,
          child: const Text('Start Steam'),
        ),
        const SizedBox(width: 16),
        ShadButton.destructive(
          onPressed: _steamActive ? _stopSteam : null,
          child: const Text('Stop Steam'),
        ),
      ],
    );
  }

  Widget _countdownBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            'Steam Flow: ${_steamFlow.toStringAsFixed(1)} ml/s',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _steamFlow,
            min: 0.5,
            max: 5.0,
            divisions: 45,
            label: _steamFlow.toStringAsFixed(1),
            onChanged: _steamActive
                ? null
                : (value) {
                    setState(() {
                      _steamFlow = value;
                    });
                  },
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
            onPressed: _steamActive
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
            onPressed: _steamActive
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
            onPressed: _steamActive
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
