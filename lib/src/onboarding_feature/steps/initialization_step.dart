import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/foreground_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../onboarding_controller.dart';

final _log = Logger('InitializationStep');

/// Creates an [OnboardingStep] that initializes core services.
///
/// Always shown — runs WebUI storage/service init, plugin loading,
/// and device controller initialization on every launch.
OnboardingStep createInitializationStep({
  required DeviceController deviceController,
  required De1Controller de1Controller,
  PluginLoaderService? pluginLoaderService,
  required WebUIStorage webUIStorage,
  required WebUIService webUIService,
}) {
  return OnboardingStep(
    id: 'initialization',
    shouldShow: () async => true,
    builder: (controller) => _InitializationStepView(
      onboardingController: controller,
      deviceController: deviceController,
      de1Controller: de1Controller,
      pluginLoaderService: pluginLoaderService,
      webUIStorage: webUIStorage,
      webUIService: webUIService,
    ),
  );
}

class _InitializationStepView extends StatefulWidget {
  final OnboardingController onboardingController;
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final PluginLoaderService? pluginLoaderService;
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;

  const _InitializationStepView({
    required this.onboardingController,
    required this.deviceController,
    required this.de1Controller,
    this.pluginLoaderService,
    required this.webUIStorage,
    required this.webUIService,
  });

  @override
  State<_InitializationStepView> createState() =>
      _InitializationStepViewState();
}

class _InitializationStepViewState extends State<_InitializationStepView> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize WebUI storage
    _log.info('Initializing WebUI storage...');
    try {
      await widget.webUIStorage.initialize();
      _log.info('WebUI storage initialized successfully');
    } catch (e) {
      _log.severe('Failed to initialize WebUI storage', e);
    }

    // Start WebUI service with default skin
    final defaultSkin = widget.webUIStorage.defaultSkin;
    if (defaultSkin != null) {
      _log.info('Starting WebUI service with skin: ${defaultSkin.name}');
      try {
        await widget.webUIService.serveFolderAtPath(defaultSkin.path);
        _log.info('WebUI service started successfully');
      } catch (e) {
        _log.severe('Failed to start WebUI service', e);
      }
    } else {
      _log.warning('No default skin available, WebUI service not started');
    }

    // Initialize plugins
    if (widget.pluginLoaderService != null) {
      try {
        await widget.pluginLoaderService!.initialize();
      } catch (e) {
        _log.warning('Failed to initialize plugins: $e');
      }
    }

    // Initialize device controller
    await widget.deviceController.initialize();

    // Start foreground service on Android (permissions already granted
    // by the preceding permissions step or a previous launch).
    if (Platform.isAndroid) {
      await ForegroundTaskService.start();
      ForegroundTaskService.watchMachineConnection(
        widget.de1Controller.de1,
      );
    }

    widget.onboardingController.advance();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return Column(
                spacing: 16,
                children: [
                  SizedBox(width: 200, child: ShadProgress()),
                  Text(
                    'Streamline is starting...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
