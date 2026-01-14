import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/shot_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/realtime_shot_feature/realtime_shot_feature.dart';
import 'package:reaprime/src/realtime_steam_feature/realtime_steam_feature.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:uuid/uuid.dart';

/// Manages DE1 state changes and handles navigation or shot tracking
/// based on the current gateway mode.
///
/// This class separates the concern of handling DE1 state changes from
/// the main app widget, providing better memory management and cleaner code.
///
class De1StateManager with WidgetsBindingObserver {
  final Logger _logger = Logger('De1StateManager');

  final De1Controller _de1Controller;
  final DeviceController _deviceController;
  final ScaleController _scaleController;
  final WorkflowController _workflowController;
  final PersistenceController _persistenceController;
  final SettingsController _settingsController;
  final GlobalKey<NavigatorState> _navigatorKey;

  StreamSubscription<Machine?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;
  ShotController? _currentShotController;
  StreamSubscription<ShotState>? _shotStateSubscription;
  StreamSubscription<ShotSnapshot>? _shotSnapshotsSubscription;

  bool _isRealtimeFeatureActive = false;
  final List<ShotSnapshot> _currentShotSnapshots = [];

  // Track previous machine state for scale power management
  MachineState? _previousMachineState;

  // Track if we're currently scanning for scales
  bool _isScanningSscales = false;

  // App lifecycle tracking
  bool _appIsInForeground = true;
  bool _navigationContextReady = false;

  De1StateManager({
    required De1Controller de1Controller,
    required DeviceController deviceController,
    required ScaleController scaleController,
    required WorkflowController workflowController,
    required PersistenceController persistenceController,
    required SettingsController settingsController,
    required GlobalKey<NavigatorState> navigatorKey,
  }) : _de1Controller = de1Controller,
       _deviceController = deviceController,
       _scaleController = scaleController,
       _workflowController = workflowController,
       _persistenceController = persistenceController,
       _settingsController = settingsController,
       _navigatorKey = navigatorKey {
    _initialize();
  }

  /// Initializes the state manager and starts listening to DE1 state changes.
  void _initialize() {
    // Start observing app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Check if navigation context is available
    _checkNavigationContext();

    _de1Subscription = _de1Controller.de1.listen(_handleDe1Change);

    // Schedule a delayed check for navigation context
    // This handles cases where the navigator key isn't ready immediately
    Future.delayed(const Duration(milliseconds: 500), () {
      _checkNavigationContext();
    });
  }

  /// Checks if navigation context is available and ready
  void _checkNavigationContext() {
    final context = _navigatorKey.currentContext;
    _navigationContextReady = context != null && context.mounted;
    _logger.fine('Navigation context ready: $_navigationContextReady');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.fine('App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _appIsInForeground = true;
        _checkNavigationContext();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _appIsInForeground = false;
        break;
    }
  }

  /// Handles changes to the connected DE1 machine.
  void _handleDe1Change(Machine? machine) {
    // Cancel any existing snapshot subscription
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;

    if (machine != null) {
      _logger.info('DE1 connected, starting to listen for state changes');
      _snapshotSubscription = machine.currentSnapshot.listen(_handleSnapshot);
    } else {
      _logger.info('DE1 disconnected');
      // Clean up any active shot controller
      _cleanupShotController();
    }
  }

  /// Handles machine snapshot updates and triggers appropriate actions
  /// based on the machine state and gateway mode.
  void _handleSnapshot(MachineSnapshot snapshot) {
    final gatewayMode = _settingsController.gatewayMode;
    final currentState = snapshot.state.state;

    _logger.finest(
      'Handling state: $currentState in mode: ${gatewayMode.name} (app foreground: $_appIsInForeground)',
    );

    // Handle scale power management based on state transitions
    // ALWAYS RUNS - regardless of app state
    _handleScalePowerManagement(currentState);

    // Check navigation context before attempting any navigation
    if (!_navigationContextReady) {
      _checkNavigationContext();
    }

    switch (currentState) {
      case MachineState.espresso:
        _handleEspressoState(snapshot, gatewayMode);
        break;
      case MachineState.steam:
        _handleSteamState(snapshot, gatewayMode);
        break;
      default:
        break;
    }

    // Update previous state for next transition
    _previousMachineState = currentState;
  }

  /// Handles scale power management based on machine state transitions
  void _handleScalePowerManagement(MachineState currentState) {
    final scalePowerMode = _settingsController.scalePowerMode;

    // Skip if power management is disabled
    if (scalePowerMode == ScalePowerMode.disabled) {
      return;
    }

    // Skip if no previous state (first snapshot)
    if (_previousMachineState == null) {
      return;
    }

    // Skip if state hasn't changed
    if (_previousMachineState == currentState) {
      return;
    }

    // Transition from idle to sleeping -> put scale to sleep
    if ((_previousMachineState == MachineState.idle) &&
        currentState == MachineState.sleeping) {
      _logger.info(
        'Machine going to sleep, managing scale power (mode: ${scalePowerMode.name})',
      );

      try {
        final scale = _scaleController.connectedScale();

        if (scalePowerMode == ScalePowerMode.displayOff) {
          scale.sleepDisplay().catchError((e) {
            _logger.warning('Failed to sleep scale display: $e');
          });
        } else if (scalePowerMode == ScalePowerMode.disconnect) {
          scale.disconnect().catchError((e) {
            _logger.warning('Failed to disconnect scale: $e');
          });
        }
      } catch (e) {
        // Scale not connected, skip
        _logger.finest('Scale not connected, skipping power management: $e');
      }
    }

    // Transition from sleeping to idle -> wake scale or trigger scan
    if (_previousMachineState == MachineState.sleeping &&
        currentState == MachineState.idle) {
      _logger.info('Machine waking up from sleep');

      // Check if scale is connected
      bool scaleConnected = false;
      try {
        _scaleController.connectedScale();
        scaleConnected = true;
      } catch (e) {
        scaleConnected = false;
      }

      // If scale is connected and mode is displayOff, wake the display
      if (scaleConnected && scalePowerMode == ScalePowerMode.displayOff) {
        try {
          final scale = _scaleController.connectedScale();
          scale.wakeDisplay().catchError((e) {
            _logger.warning('Failed to wake scale display: $e');
          });
        } catch (e) {
          _logger.warning('Failed to get scale for wake: $e');
        }
      }

      // Trigger device scan if no scale connected.
      if (!scaleConnected) {
        _logger.info('Scale disconnected after sleep, triggering device scan');
        _triggerScaleScan();
      }
    }
  }

  /// Triggers a device scan with 30s timeout to find and connect scales
  Future<void> _triggerScaleScan() async {
    // Prevent multiple concurrent scans
    if (_isScanningSscales) {
      _logger.fine('Scale scan already in progress, skipping');
      return;
    }

    _isScanningSscales = true;
    _logger.info('Starting device scan to find scales (30s timeout)');

    try {
      // Start the scan with autoConnect enabled
      await _deviceController.scanForDevices(autoConnect: true);

      // Wait up to 30 seconds for a scale to be found and connected
      final timeout = Duration(seconds: 30);
      final scaleConnected = await _scaleController.connectionState
          .firstWhere(
            (state) => state == dev.ConnectionState.connected,
            orElse: () => dev.ConnectionState.disconnected,
          )
          .timeout(
            timeout,
            onTimeout: () {
              _logger.info('Scale scan timed out after 30 seconds');
              return dev.ConnectionState.disconnected;
            },
          );

      if (scaleConnected == dev.ConnectionState.connected) {
        _logger.info('Scale found and connected successfully');
      } else {
        _logger.info('No scale found within timeout period');
      }
    } catch (e) {
      _logger.warning('Error during scale scan: $e');
    } finally {
      _isScanningSscales = false;
    }
  }

  /// Handles espresso state based on the current gateway mode.
  void _handleEspressoState(MachineSnapshot snapshot, GatewayMode gatewayMode) {
    switch (gatewayMode) {
      case GatewayMode.full:
        // Full gateway mode, not touching anything
        return;
      case GatewayMode.tracking:
        _handleTrackingModeForEspresso();
        break;
      case GatewayMode.disabled:
        _handleDisabledModeForEspresso();
        break;
    }
  }

  /// Handles steam state based on the current gateway mode.
  void _handleSteamState(MachineSnapshot snapshot, GatewayMode gatewayMode) {
    switch (gatewayMode) {
      case GatewayMode.full:
      case GatewayMode.tracking:
        // In full or tracking mode, do nothing for steam
        return;
      case GatewayMode.disabled:
        _handleDisabledModeForSteam();
        break;
    }
  }

  /// Handles espresso state when in tracking mode.
  void _handleTrackingModeForEspresso() {
    if (_currentShotController != null) {
      // Already tracking a shot
      return;
    }

    _logger.info(
      'Starting shot tracking in tracking mode (app foreground: $_appIsInForeground)',
    );
    _startShotController();
  }

  /// Handles espresso state when in disabled mode.
  void _handleDisabledModeForEspresso() {
    if (_isRealtimeFeatureActive) {
      // Already showing realtime feature
      return;
    }

    // If we're already tracking a shot (maybe from a previous fallback)
    if (_currentShotController != null) {
      return;
    }

    // Only attempt navigation if app is in foreground AND navigation context is ready
    if (_appIsInForeground && _navigationContextReady) {
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        _logger.info('Navigating to RealtimeShotFeature in disabled mode');
        _isRealtimeFeatureActive = true;

        Navigator.pushNamed(
              context,
              RealtimeShotFeature.routeName,
              arguments: ShotController(
                scaleController: _scaleController,
                de1controller: _de1Controller,
                persistenceController: _persistenceController,
                targetProfile: _workflowController.currentWorkflow.profile,
                doseData: _workflowController.currentWorkflow.doseData,
              ),
            )
            .then((_) {
              _isRealtimeFeatureActive = false;
            })
            .catchError((error) {
              _logger.warning('Navigation failed: $error');
              _isRealtimeFeatureActive = false;
              // Fallback to tracking if navigation fails
              _startShotController();
            });
      } else {
        _logger.warning(
          'Navigation context not available, falling back to tracking',
        );
        _navigationContextReady = false;
        _startShotController(); // Fallback to tracking
      }
    } else {
      _logger.info(
        'App not in foreground or navigation not ready, starting shot tracking',
      );
      _startShotController(); // Fallback to tracking
    }
  }

  /// Handles steam state when in disabled mode.
  void _handleDisabledModeForSteam() {
    if (_isRealtimeFeatureActive) {
      // Already showing realtime feature
      return;
    }

    // Only attempt navigation if app is in foreground AND navigation context is ready
    if (!_appIsInForeground || !_navigationContextReady) {
      _logger.fine(
        'Skipping steam feature - app not in foreground or navigation not ready',
      );
      return;
    }

    final context = _navigatorKey.currentContext;
    if (context != null && context.mounted) {
      _logger.info('Navigating to RealtimeSteamFeature in disabled mode');
      _isRealtimeFeatureActive = true;

      // Use a try-catch to handle any async issues
      try {
        _de1Controller.steamData.first
            .then((steamData) {
              if (!context.mounted) {
                _logger.warning('Context no longer mounted');
                _isRealtimeFeatureActive = false;
                return;
              }
              Navigator.pushNamed(
                context,
                RealtimeSteamFeature.routeName,
                arguments: {'controller': _de1Controller, 'data': steamData},
              ).then((_) {
                _isRealtimeFeatureActive = false;
              });
            })
            .catchError((error, stackTrace) {
              _logger.warning('Error getting steam data: $error');
              _isRealtimeFeatureActive = false;
            });
      } catch (e) {
        _logger.warning('Error in steam navigation: $e');
        _isRealtimeFeatureActive = false;
      }
    } else {
      _logger.warning('Navigation context is null or not mounted');
      _navigationContextReady = false;
    }
  }

  /// Starts a new ShotController for tracking a shot in tracking mode.
  void _startShotController() {
    _logger.fine('Creating new ShotController for tracking');

    _currentShotController = ShotController(
      scaleController: _scaleController,
      de1controller: _de1Controller,
      persistenceController: _persistenceController,
      targetProfile: _workflowController.currentWorkflow.profile,
      doseData: _workflowController.currentWorkflow.doseData,
    );

    _currentShotSnapshots.clear();

    // Listen to shot snapshots
    _shotSnapshotsSubscription = _currentShotController!.shotData.listen((
      snapshot,
    ) {
      _currentShotSnapshots.add(snapshot);
    });

    // Listen to shot state changes
    _shotStateSubscription = _currentShotController!.state.listen((state) {
      if (state == ShotState.finished) {
        _logger.fine('Shot finished, cleaning up ShotController');
        _persistShotIfNeeded();
        _cleanupShotController();
      }
    });
  }

  /// Persists the shot if it's not a cleaning or calibration shot.
  void _persistShotIfNeeded() {
    final beverageType =
        _workflowController.currentWorkflow.profile.beverageType;
    if (beverageType != BeverageType.cleaning &&
        beverageType != BeverageType.calibrate &&
        _currentShotController != null) {
      _persistenceController.persistShot(
        ShotRecord(
          id: Uuid().v4(),
          timestamp: _currentShotController!.shotStartTime,
          measurements: List.from(_currentShotSnapshots),
          workflow: _workflowController.currentWorkflow,
        ),
      );
    }
  }

  /// Cleans up the current ShotController and all associated subscriptions.
  void _cleanupShotController() {
    _logger.fine('Cleaning up ShotController');

    _shotStateSubscription?.cancel();
    _shotStateSubscription = null;

    _shotSnapshotsSubscription?.cancel();
    _shotSnapshotsSubscription = null;

    _currentShotController?.dispose();
    _currentShotController = null;

    _currentShotSnapshots.clear();
  }

  /// Disposes all subscriptions and cleans up resources.
  void dispose() {
    _logger.fine('Disposing De1StateManager');

    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _cleanupShotController();

    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;

    _de1Subscription?.cancel();
    _de1Subscription = null;
  }
}
