import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/home_feature/widgets/device_selection_widget.dart';
import 'package:reaprime/src/landing_feature/landing_feature.dart';
import 'package:reaprime/src/skin_feature/skin_view.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:reaprime/src/models/device/scale.dart' as device_scale;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

class PermissionsView extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;
  final SettingsController settingsController;

  const PermissionsView({
    super.key,
    required this.deviceController,
    required this.de1controller,
    required this.scaleController,
    this.pluginLoaderService,
    required this.webUIStorage,
    required this.webUIService,
    required this.settingsController,
  });

  @override
  State<PermissionsView> createState() => _PermissionsViewState();

  static String getRandomCoffeeMessage() {
    final messages = [
      "Dialing in the grinder...",
      "Preheating the portafilter...",
      "Calibrating the tamp pressure...",
      "Blooming the coffee bed...",
      "Checking water hardness...",
      "Polishing the shower screen...",
      "Degassing freshly roasted beans...",
      "Leveling the distribution tool...",
      "Priming the group head...",
      "Adjusting brew temperature to 0.1°C...",
      "Consulting the barista championship rules...",
      "Measuring TDS with lab precision...",
      "Perfecting the WDT technique...",
      "Activating bluetooth (please turn it on)...",
      "Weighing beans to 0.01g accuracy...",
      "Cleaning the espresso altar...",
      "Channeling positive vibes (not water)...",
      "Waiting for third wave to arrive...",
      "Updating espresso definitions...",
    ];
    return messages[DateTime.now().millisecondsSinceEpoch % messages.length];
  }
}

class _PermissionsViewState extends State<PermissionsView> {
  final Logger _log = Logger("PermissionsView");
  late final Future<bool> _permissionsFuture;

  @override
  void initState() {
    super.initState();
    _permissionsFuture = _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Streamline')),
      body: SafeArea(child: _permissions(context)),
    );
  }

  Widget _permissions(context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Streamline is starting ...'),
          FutureBuilder(
            future: _permissionsFuture,
            builder: (context, result) {
              switch (result.connectionState) {
                case ConnectionState.none:
                  return Text("Unknown");
                case ConnectionState.waiting:
                  return _initializingView(context);
                case ConnectionState.active:
                case ConnectionState.done:
                  return _de1Picker(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _initializingView(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        SizedBox(width: 200, child: ShadProgress()),
        Text(
          PermissionsView.getRandomCoffeeMessage(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // await Permission.ignoreBatteryOptimizations.request();
      await Permission.manageExternalStorage.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetooth.request();
      await Permission.locationWhenInUse.request();
      await Permission.locationAlways.request();

      // Request notification permission for Android 13+ (API 33+)
      // This allows foreground service notification to appear in notification drawer
      if (Platform.isAndroid) {
        await Permission.notification.request();

        // CRITICAL: Request battery optimization exemption
        // This prevents Android from killing the app in the background
        final batteryOptStatus =
            await Permission.ignoreBatteryOptimizations.status;
        if (!batteryOptStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      }
    } else {
      try {
        await UniversalBle.availabilityStream.firstWhere(
          (e) => e == AvailabilityState.poweredOn,
        ).timeout(Duration(seconds: 5));
      } on TimeoutException {
        _log.warning('Bluetooth availability check timed out, continuing without BLE');
      }
    }

    // Telemetry consent prompt is shown as a dialog after device picker loads
    // (see _DeviceDiscoveryState.initState). This keeps startup non-blocking
    // while still prompting the user (PRIV-03, PRIV-04).

    // Initialize WebUI storage and service BEFORE device controller
    _log.info('Initializing WebUI storage...');
    try {
      await widget.webUIStorage.initialize();
      _log.info('WebUI storage initialized successfully');
    } catch (e) {
      _log.severe('Failed to initialize WebUI storage', e);
      // Continue anyway - we can still use the app without WebUI
    }

    // Start WebUI service if we have a default skin
    final defaultSkin = widget.webUIStorage.defaultSkin;
    if (defaultSkin != null) {
      _log.info('Starting WebUI service with skin: ${defaultSkin.name}');
      try {
        await widget.webUIService.serveFolderAtPath(defaultSkin.path);
        _log.info('WebUI service started successfully');
      } catch (e) {
        _log.severe('Failed to start WebUI service', e);
        // Continue anyway - we can still use the app without WebUI
      }
    } else {
      _log.warning('No default skin available, WebUI service not started');
    }

    // Initialize plugins after WebUI is ready
    if (widget.pluginLoaderService != null) {
      try {
        await widget.pluginLoaderService!.initialize();
      } catch (e) {
        // Log error but don't fail the permissions check
        _log.warning('Failed to initialize plugins: $e');
      }
    }

    // Initialize device controller last
    await widget.deviceController.initialize();

    return true;
  }

  Widget _de1Picker(BuildContext context) {
    return Center(
      child: DeviceDiscoveryView(
        de1controller: widget.de1controller,
        deviceController: widget.deviceController,
        scaleController: widget.scaleController,
        settingsController: widget.settingsController,
        webUIService: widget.webUIService,
        webUIStorage: widget.webUIStorage,
        logger: _log,
      ),
    );
  }
}

class DeviceDiscoveryView extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  final ScaleController scaleController;
  final SettingsController settingsController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final Logger logger;

  const DeviceDiscoveryView({
    super.key,
    required this.deviceController,
    required this.de1controller,
    required this.scaleController,
    required this.settingsController,
    required this.webUIService,
    required this.webUIStorage,
    required this.logger,
  });

  @override
  State<StatefulWidget> createState() => _DeviceDiscoveryState();
}

class _DeviceDiscoveryState extends State<DeviceDiscoveryView> {
  DiscoveryState _state = DiscoveryState.searching;
  bool _isScanning = true; // Start as true since we begin scanning immediately
  String? _connectingDeviceId;
  String? _connectionError;
  // When set, the discovery subscription will auto-connect to this device
  // when it appears. Persists through fallback from direct-connect to full scan.
  String? _autoConnectDeviceId;

  De1Interface? _selectedMachine;
  dev.Device? _selectedScale;

  late StreamSubscription<List<dev.Device>> _discoverySubscription;

  // On Linux, BLE scanning and connection is much slower due to BlueZ quirks:
  // 12s scan + 3s settle + ~7s prep scan + connect + service discovery.
  // Total can be ~35s, so we use a generous 50s timeout.
  final Duration _timeoutDuration = Duration(seconds: Platform.isLinux ? 50 : 10);

  /// Navigates to the appropriate screen after device connection
  ///
  /// Ensures WebUI is ready before navigating to SkinView on supported platforms.
  /// Falls back to LandingFeature if WebUI is not available.
  Future<void> _navigateAfterConnection() async {
    // Check platform - only use WebView on iOS, Android, macOS
    final supportedPlatforms =
        Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

    if (!supportedPlatforms) {
      widget.logger.info(
        'Platform not supported for WebView, using Landing page',
      );
      _navigateToRoute(LandingFeature.routeName);
      return;
    }

    // Ensure WebUI is ready
    if (!widget.webUIService.isServing) {
      widget.logger.info('WebUI not serving, attempting to start...');
      
      final defaultSkin = widget.webUIStorage.defaultSkin;
      if (defaultSkin != null) {
        try {
          await widget.webUIService.serveFolderAtPath(defaultSkin.path);
          widget.logger.info('WebUI service started successfully');
        } catch (e) {
          widget.logger.severe('Failed to start WebUI service: $e');
          _navigateToRoute(LandingFeature.routeName);
          return;
        }
      } else {
        widget.logger.warning('No default skin available, using Landing page');
        _navigateToRoute(LandingFeature.routeName);
        return;
      }
    }

    // Wait a brief moment for WebUI to be fully ready
    await Future.delayed(const Duration(milliseconds: 500));

    widget.logger.info('Navigating to SkinView');
    _navigateToRoute(SkinView.routeName);
  }

  /// Helper to navigate to a specific route
  void _navigateToRoute(String route) {
    if (!mounted) return;

    if (route == SkinView.routeName) {
      // Push both routes to stack: HomeScreen first, then SkinView on top
      Navigator.popAndPushNamed(context, HomeScreen.routeName);
      Navigator.of(context).pushNamed(SkinView.routeName);
    } else {
      // For LandingFeature or any other route, navigate directly
      Navigator.popAndPushNamed(context, route);
    }
  }

  Future<void> _handleDeviceTapped(De1Interface de1) async {
    if (_connectingDeviceId != null) return; // guard against double-tap
    setState(() {
      _connectingDeviceId = de1.deviceId;
      _connectionError = null;
    });
    try {
      await widget.de1controller.connectToDe1(de1);
      if (mounted) {
        await _navigateAfterConnection();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectingDeviceId = null;
          _connectionError = 'Failed to connect: $e';
        });
      }
      widget.logger.severe('Manual connect failed: $e');
    }
  }

  Widget _directConnectingView(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        SizedBox(width: 200, child: ShadProgress()),
        Text(
          'Connecting to your machine...',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextButton(
          onPressed: _fallbackToFullScan,
          child: Text('Scan for all devices', style: theme.textTheme.muted),
        ),
      ],
    );
  }

  void _fallbackToFullScan({bool keepAutoConnect = false}) {
    if (!keepAutoConnect) {
      _autoConnectDeviceId = null;
    }
    setState(() {
      _state = DiscoveryState.searching;
    });
    widget.deviceController.scanForDevices(autoConnect: false);
  }

  Future<void> _startDirectConnect(String deviceId) async {
    final found = await widget.deviceController.scanForSpecificDevice(deviceId);

    if (!mounted) return;

    if (!found) {
      widget.logger.info('Preferred device $deviceId not found, falling back to full scan');
      _fallbackToFullScan(keepAutoConnect: true);
      _startNormalScanWithTimeout();
      return;
    }

    // Device is now in the stream — find and connect
    final device = widget.deviceController.devices
        .whereType<De1Interface>()
        .firstWhereOrNull((d) => d.deviceId == deviceId);

    if (device == null) {
      widget.logger.warning('Device appeared then vanished: $deviceId');
      _fallbackToFullScan();
      _startNormalScanWithTimeout();
      return;
    }

    setState(() {
      _connectingDeviceId = device.deviceId;
    });

    try {
      await widget.de1controller.connectToDe1(device);
      if (mounted) await _navigateAfterConnection();
    } catch (e) {
      widget.logger.severe('Direct connect failed: $e');
      if (mounted) {
        setState(() {
          _connectingDeviceId = null;
        });
        _fallbackToFullScan();
        _startNormalScanWithTimeout();
      }
    }
  }

  void _startNormalScanWithTimeout() {
    Future.delayed(_timeoutDuration, () {
      if (!mounted) return;
      final discoveredDevices =
          widget.deviceController.devices.whereType<De1Interface>().toList();
      setState(() {
        _isScanning = false;
        if (discoveredDevices.isEmpty && _state != DiscoveryState.foundMany) {
          _state = DiscoveryState.foundNone;
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();

    // Show telemetry consent dialog once (non-blocking, after frame renders)
    if (!widget.settingsController.telemetryConsentDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showTelemetryConsentDialog();
      });
    }

    final preferredMachineId = widget.settingsController.preferredMachineId;

    if (preferredMachineId != null) {
      // Fast-connect path: scan specifically for the preferred device
      _state = DiscoveryState.directConnecting;
      _autoConnectDeviceId = preferredMachineId;
      _startDirectConnect(preferredMachineId);
    }

    // Always listen to device stream for the normal foundMany path
    _discoverySubscription = widget.deviceController.deviceStream.listen((data) {
      final discoveredMachines = data.whereType<De1Interface>().toList();
      if (discoveredMachines.isEmpty) return;

      // Auto-connect if the preferred machine appeared (handles late discovery
      // after targeted scan timeout + fallback to full scan)
      if (_autoConnectDeviceId != null && _connectingDeviceId == null) {
        final target = discoveredMachines.firstWhereOrNull(
          (d) => d.deviceId == _autoConnectDeviceId,
        );
        if (target != null) {
          _autoConnectDeviceId = null; // consume — only try once
          _handleDeviceTapped(target);
          return;
        }
      }

      if (_state != DiscoveryState.directConnecting) {
        setState(() {
          _state = DiscoveryState.foundMany;
        });
      }
    });

    // Normal search path: start a full scan (initialize() no longer auto-scans
    // to avoid competing with a targeted scan)
    if (preferredMachineId == null) {
      widget.deviceController.scanForDevices(autoConnect: false);
      _startNormalScanWithTimeout();
    }
  }

  @override
  void dispose() {
    _discoverySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case DiscoveryState.directConnecting:
        return _directConnectingView(context);
      case DiscoveryState.searching:
        return _searchingView(context);
      case DiscoveryState.foundMany:
        return _resultsView(context);
      case DiscoveryState.foundNone:
        return _noDevicesFoundView(context);
    }
  }

  Widget _searchingView(BuildContext context) {
    return Column(
      spacing: 16,
      children: [
        SizedBox(width: 200, child: ShadProgress()),
        Text(
          PermissionsView.getRandomCoffeeMessage(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Future<void> _handleContinue() async {
    if (_selectedMachine == null) return;

    // Connect to scale if selected (fire and forget — doesn't block navigation)
    if (_selectedScale != null) {
      final scale = _selectedScale!;
      final scaleDevice = widget.deviceController.devices
          .whereType<device_scale.Scale>()
          .firstWhereOrNull((s) => s.deviceId == scale.deviceId);
      if (scaleDevice != null) {
        widget.scaleController.connectToScale(scaleDevice);
      }
    }

    // Connect to machine (this triggers navigation)
    await _handleDeviceTapped(_selectedMachine!);
  }

  Widget _resultsView(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        // Scanning indicator
        if (_isScanning)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              Text('Scanning for devices...', style: theme.textTheme.muted),
            ],
          ),

        // Two-column device lists
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 300, maxWidth: 500),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Machine column
              Expanded(
                child: DeviceSelectionWidget(
                  deviceController: widget.deviceController,
                  deviceType: dev.DeviceType.machine,
                  showHeader: true,
                  headerText: "Machines",
                  connectingDeviceId: _connectingDeviceId,
                  errorMessage: _connectionError,
                  selectedDeviceId: _selectedMachine?.deviceId,
                  preferredDeviceId: widget.settingsController.preferredMachineId,
                  onPreferredChanged: (id) =>
                      widget.settingsController.setPreferredMachineId(id),
                  onDeviceTapped: (device) {
                    setState(() {
                      _selectedMachine = device as De1Interface;
                    });
                  },
                ),
              ),
              SizedBox(width: 16),
              // Scale column
              Expanded(
                child: DeviceSelectionWidget(
                  deviceController: widget.deviceController,
                  deviceType: dev.DeviceType.scale,
                  showHeader: true,
                  headerText: "Scales",
                  selectedDeviceId: _selectedScale?.deviceId,
                  preferredDeviceId: widget.settingsController.preferredScaleId,
                  onPreferredChanged: (id) =>
                      widget.settingsController.setPreferredScaleId(id),
                  onDeviceTapped: (device) {
                    setState(() {
                      _selectedScale = device;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // Continue button (always visible)
        ShadButton(
          onPressed: _selectedMachine != null && _connectingDeviceId == null
              ? _handleContinue
              : null,
          child: _connectingDeviceId != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    Text('Connecting...'),
                  ],
                )
              : Text('Continue'),
        ),

        // ReScan and Dashboard below
        if (!_isScanning && _connectingDeviceId == null)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              ShadButton.outline(
                onPressed: _retryScan,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 16),
                    Text('ReScan'),
                  ],
                ),
              ),
              ShadButton.secondary(
                onPressed: () {
                  Navigator.popAndPushNamed(context, HomeScreen.routeName);
                },
                child: Text('Dashboard'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _noDevicesFoundView(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 600),
      child: ShadCard(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 24,
            children: [
              Icon(
                LucideIcons.searchX,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
              Column(
                spacing: 8,
                children: [
                  Text(
                    'No Decent Machines Found',
                    style: theme.textTheme.h3,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'The scan completed but no Decent machines were discovered.',
                    style: theme.textTheme.muted,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              Column(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isScanning)
                    ShadButton(
                      onPressed: null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          Text('Scanning...'),
                        ],
                      ),
                    )
                  else
                    ShadButton(
                      onPressed: _retryScan,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          Icon(LucideIcons.refreshCw, size: 16),
                          Text('Scan Again'),
                        ],
                      ),
                    ),
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: ShadButton.outline(
                          onPressed: _exportLogs,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: [
                              Icon(LucideIcons.fileText, size: 16),
                              Text('Export Logs'),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ShadButton.secondary(
                          onPressed: () {
                            Navigator.popAndPushNamed(
                              context,
                              HomeScreen.routeName,
                            );
                          },
                          child: Text('Continue to Dashboard'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _troubleshootingItem(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    final theme = ShadTheme.of(context);
    return Row(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        Expanded(child: Text(text, style: theme.textTheme.small)),
      ],
    );
  }

  Future<void> _showTelemetryConsentDialog() async {
    final result = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Help Improve Streamline'),
        description: const Text(
          'Share anonymous crash reports and diagnostics to help us fix '
          'connectivity issues. No personal data is collected — BLE addresses '
          'and IPs are hashed before sending.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No thanks'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    await widget.settingsController.setTelemetryConsentDialogShown(true);
    if (result == true) {
      await widget.settingsController.setTelemetryConsent(true);
      widget.logger.info('Telemetry consent granted by user');
    } else {
      widget.logger.info('Telemetry consent declined by user');
    }
  }

  Future<void> _retryScan() async {
    setState(() {
      _isScanning = true;
    });

    try {
      await widget.deviceController.scanForDevices(autoConnect: false);

      // Wait for scan to complete
      await Future.delayed(_timeoutDuration);

      if (mounted) {
        final discoveredDevices =
            widget.deviceController.devices.whereType<De1Interface>().toList();

        setState(() {
          _isScanning = false;
          if (discoveredDevices.isEmpty) {
            _state = DiscoveryState.foundNone;
          } else if (discoveredDevices.length == 1) {
            // Auto-connect if only one device found
            widget.de1controller.connectToDe1(discoveredDevices.first).then((
              _,
            ) async {
              if (mounted) {
                await _navigateAfterConnection();
              }
            });
          } else {
            _state = DiscoveryState.foundMany;
          }
        });
      }
    } catch (e) {
      widget.logger.severe('Retry scan failed: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final logFile = File('${docs.path}/log.txt');

      if (!await logFile.exists()) {
        if (mounted) {
          showShadDialog(
            context: context,
            builder:
                (context) => ShadDialog(
                  title: Text('No Logs Found'),
                  description: Text('Log file does not exist yet.'),
                  actions: [
                    ShadButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('OK'),
                    ),
                  ],
                ),
          );
        }
        return;
      }

      final bytes = await logFile.readAsBytes();
      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'R1-logs-${DateTime.now().millisecondsSinceEpoch}.txt',
        dialogTitle: 'Choose where to save logs',
        bytes: bytes,
      );

      if (outputFile != null) {
        final destination = File(outputFile);
        await destination.writeAsBytes(bytes);

        if (mounted) {
          showShadDialog(
            context: context,
            builder:
                (context) => ShadDialog(
                  title: Text('Logs Exported'),
                  description: Text(
                    'Logs have been successfully exported to:\n$outputFile',
                  ),
                  actions: [
                    ShadButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('OK'),
                    ),
                  ],
                ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showShadDialog(
          context: context,
          builder:
              (context) => ShadDialog(
                title: Text('Export Failed'),
                description: Text('Failed to export logs: $e'),
                actions: [
                  ShadButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK'),
                  ),
                ],
              ),
        );
      }
    }
  }
}

enum DiscoveryState { directConnecting, searching, foundMany, foundNone }









