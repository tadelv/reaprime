import 'dart:async';
import 'dart:io';

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
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' as dev;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

class PermissionsView extends StatelessWidget {
  final Logger _log = Logger("PermissionsView");
  final DeviceController deviceController;
  final De1Controller de1controller;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;
  final SettingsController settingsController;

  PermissionsView({
    super.key,
    required this.deviceController,
    required this.de1controller,
    this.pluginLoaderService,
    required this.webUIStorage,
    required this.webUIService,
    required this.settingsController,
  });

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
            future: checkPermissions(),
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

  Future<bool> checkPermissions() async {
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
      await UniversalBle.availabilityStream.firstWhere(
        (e) => e == AvailabilityState.poweredOn,
      );
    }

    // Initialize WebUI storage and service BEFORE device controller
    _log.info('Initializing WebUI storage...');
    try {
      await webUIStorage.initialize();
      _log.info('WebUI storage initialized successfully');
    } catch (e) {
      _log.severe('Failed to initialize WebUI storage', e);
      // Continue anyway - we can still use the app without WebUI
    }

    // Start WebUI service if we have a default skin
    final defaultSkin = webUIStorage.defaultSkin;
    if (defaultSkin != null) {
      _log.info('Starting WebUI service with skin: ${defaultSkin.name}');
      try {
        await webUIService.serveFolderAtPath(defaultSkin.path);
        _log.info('WebUI service started successfully');
      } catch (e) {
        _log.severe('Failed to start WebUI service', e);
        // Continue anyway - we can still use the app without WebUI
      }
    } else {
      _log.warning('No default skin available, WebUI service not started');
    }

    // Initialize plugins after WebUI is ready
    if (pluginLoaderService != null) {
      try {
        await pluginLoaderService!.initialize();
      } catch (e) {
        // Log error but don't fail the permissions check
        _log.warning('Failed to initialize plugins: $e');
      }
    }

    // Initialize device controller last
    await deviceController.initialize();

    return true;
  }

  Widget _de1Picker(BuildContext context) {
    return Center(
      child: DeviceDiscoveryView(
        de1controller: de1controller,
        deviceController: deviceController,
        settingsController: settingsController,
        webUIService: webUIService,
        webUIStorage: webUIStorage,
        logger: _log,
      ),
    );
  }
}

class DeviceDiscoveryView extends StatefulWidget {
  final DeviceController deviceController;
  final De1Controller de1controller;
  final SettingsController settingsController;
  final WebUIService webUIService;
  final WebUIStorage webUIStorage;
  final Logger logger;

  const DeviceDiscoveryView({
    super.key,
    required this.deviceController,
    required this.de1controller,
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
  String? _autoConnectingDeviceId;

  late StreamSubscription<List<dev.Device>> _discoverySubscription;

  final Duration _timeoutDuration = Duration(seconds: 10);

  /// Determines the correct route to navigate to after device connection
  ///
  /// Returns SkinView route for mobile/desktop platforms (iOS, Android, macOS)
  /// if WebUI is available and serving. Otherwise returns LandingFeature route.
  String _getNavigationRoute() {
    // Check platform - only use WebView on iOS, Android, macOS
    final supportedPlatforms =
        Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

    if (!supportedPlatforms) {
      widget.logger.info(
        'Platform not supported for WebView, using Landing page',
      );
      return LandingFeature.routeName;
    }

    // Check if WebUI service is serving
    if (!widget.webUIService.isServing) {
      widget.logger.warning('WebUI service is not serving, using Landing page');
      return LandingFeature.routeName;
    }

    // Check if default skin is available
    final defaultSkin = widget.webUIStorage.defaultSkin;
    if (defaultSkin == null) {
      widget.logger.warning('No default skin available, using Landing page');
      return LandingFeature.routeName;
    }

    widget.logger.info('Navigating to SkinView with skin: ${defaultSkin.name}');
    return SkinView.routeName;
  }

  @override
  void initState() {
    super.initState();

    _discoverySubscription = widget.deviceController.deviceStream.listen((
      data,
    ) {
      widget.logger.fine("device stream update: $data");
      final discoveredDevices = data.whereType<De1Interface>().toList();

      // Show devices immediately when first one is detected
      if (discoveredDevices.isNotEmpty) {
        setState(() {
          _state = DiscoveryState.foundMany;
        });

        // Check if we should auto-connect to preferred machine
        final preferredMachineId = widget.settingsController.preferredMachineId;
        if (preferredMachineId != null) {
          final preferredMachine = discoveredDevices.firstWhere(
            (device) => device.deviceId == preferredMachineId,
            orElse: () => discoveredDevices.first,
          );

          // Set auto-connecting state to show progress indicator
          setState(() {
            _autoConnectingDeviceId = preferredMachine.deviceId;
          });

          // Auto-connect to preferred machine
          widget.de1controller
              .connectToDe1(preferredMachine)
              .then((_) {
                if (mounted) {
                  final route = _getNavigationRoute();
                  // Push both routes to stack: HomeScreen first, then the target route
                  Navigator.popAndPushNamed(context, HomeScreen.routeName);
                  if (route == SkinView.routeName) {
                    Navigator.of(context).pushNamed(SkinView.routeName);
                  }
                }
              })
              .catchError((error) {
                // Clear auto-connecting state on error
                if (mounted) {
                  setState(() {
                    _autoConnectingDeviceId = null;
                  });
                }
                widget.logger.severe('Auto-connect failed: $error');
              });
          _discoverySubscription.cancel();
        }
      }
    });

    // If 10 seconds elapsed without finding any devices, show no devices found
    Future.delayed(_timeoutDuration, () {
      final discoveredDevices =
          widget.deviceController.devices.whereType<De1Interface>().toList();
      _discoverySubscription.cancel();

      if (mounted) {
        setState(() {
          _isScanning = false;
          if (discoveredDevices.isEmpty) {
            _state = DiscoveryState.foundNone;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _discoverySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case DiscoveryState.searching:
        return _searchingView(context);
      case DiscoveryState.foundMany:
        return SizedBox(height: 500, width: 300, child: _resultsView(context));
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
              Text(
                'Scanning for devices...',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        
        // Device list
        DeviceSelectionWidget(
          deviceController: widget.deviceController,
          de1Controller: widget.de1controller,
          settingsController: widget.settingsController,
          showHeader: true,
          headerText: "Select a machine from the list",
          autoConnectingDeviceId: _autoConnectingDeviceId,
          onDeviceSelected: (de1) {
            final route = _getNavigationRoute();
            // Push both routes to stack: HomeScreen first, then the target route
            Navigator.popAndPushNamed(context, HomeScreen.routeName);
            if (route == SkinView.routeName) {
              Navigator.of(context).pushNamed(SkinView.routeName);
            }
          },
        ),
        
        // Action buttons (shown when scanning is complete)
        if (!_isScanning)
          SizedBox(
            width: 300,
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: ShadButton.outline(
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
            ) {
              if (mounted) {
                final route = _getNavigationRoute();
                // Push both routes to stack: HomeScreen first, then the target route
                Navigator.popAndPushNamed(context, HomeScreen.routeName);
                if (route == SkinView.routeName) {
                  Navigator.of(context).pushNamed(SkinView.routeName);
                }
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

enum DiscoveryState { searching, foundMany, foundNone }





