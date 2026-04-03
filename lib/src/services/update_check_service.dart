import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';

/// Service for periodically checking for app updates
class UpdateCheckService {
  final Logger _log = Logger('UpdateCheckService');
  final SettingsService _settingsService;
  final AndroidUpdater _updater;
  final WebUIStorage _webUIStorage;

  Timer? _periodicTimer;
  UpdateInfo? _availableUpdate;
  
  static const Duration _checkInterval = (const String.fromEnvironment("simulate") == "1") ? Duration(hours: 1) : Duration(hours: 12);

  UpdateCheckService({
    required SettingsService settingsService,
    AndroidUpdater? updater,
    required WebUIStorage webUIStorage,
  })  : _settingsService = settingsService,
        _updater = updater ?? AndroidUpdater(owner: 'tadelv', repo: 'reaprime'),
        _webUIStorage = webUIStorage;

  /// Get the currently available update, if any
  UpdateInfo? get availableUpdate => _availableUpdate;

  /// Check if there's an available update
  bool get hasAvailableUpdate => _availableUpdate != null;

  /// Initialize the service and start periodic checks
  Future<void> initialize() async {
    final automaticUpdateCheck = await _settingsService.automaticUpdateCheck();
    if (automaticUpdateCheck) {
      await _startPeriodicChecks();
    }
  }

  /// Start periodic update checks
  Future<void> _startPeriodicChecks() async {
    _log.info('Starting periodic update checks (every ${_checkInterval.inHours} hours)');
    
    // Check immediately if we haven't checked recently
    final lastCheck = await _settingsService.lastUpdateCheckTime();
    if (lastCheck == null || DateTime.now().difference(lastCheck) > _checkInterval) {
      await checkForUpdate();
      await _updateSkins();
    }

    // Schedule periodic checks
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_checkInterval, (_) async {
      await checkForUpdate();
      await _updateSkins();
    });
  }

  /// Stop periodic update checks
  void _stopPeriodicChecks() {
    _log.info('Stopping periodic update checks');
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Update all skins with known sources
  Future<void> _updateSkins() async {
    try {
      _log.info('Updating skins...');
      await _webUIStorage.updateAllSkins();
      _log.info('Skin update complete');
    } catch (e, st) {
      _log.warning('Error updating skins', e, st);
    }
  }

  /// Manually check for updates
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      _log.info('Checking for updates (current: ${BuildInfo.version})');

      final updateInfo = await _updater.checkForUpdate(
        BuildInfo.version,
        channel: UpdateChannel.stable,
      );

      await _settingsService.setLastUpdateCheckTime(DateTime.now());

      if (updateInfo != null) {
        // Check if user has skipped this version
        final skipped = await _settingsService.skippedVersion();
        if (skipped != null && skipped == updateInfo.version) {
          _log.info('Update ${updateInfo.version} skipped by user');
          _availableUpdate = null;
          return null;
        }
        _log.info('Update available: ${updateInfo.version}');
        _availableUpdate = updateInfo;
      } else {
        _log.info('No update available');
        _availableUpdate = null;
      }

      return updateInfo;
    } catch (e, stackTrace) {
      _log.warning('Error checking for updates', e, stackTrace);
      return null;
    }
  }

  /// Get the GitHub releases page URL
  String getReleasesUrl() {
    return 'https://github.com/tadelv/reaprime/releases';
  }

  /// Get the specific release URL if an update is available
  String? getReleaseUrl() {
    if (_availableUpdate == null) return null;
    return 'https://github.com/tadelv/reaprime/releases/tag/${_availableUpdate!.tagName}';
  }

  /// Enable automatic update checks
  Future<void> enableAutomaticChecks() async {
    await _settingsService.setAutomaticUpdateCheck(true);
    await _startPeriodicChecks();
  }

  /// Disable automatic update checks
  Future<void> disableAutomaticChecks() async {
    await _settingsService.setAutomaticUpdateCheck(false);
    _stopPeriodicChecks();
    _availableUpdate = null;
  }

  /// Clear the available update notification
  void clearAvailableUpdate() {
    _availableUpdate = null;
  }

  /// Skip the current update version permanently
  Future<void> skipCurrentUpdate() async {
    final version = _availableUpdate?.version;
    if (version != null) {
      _log.info('User skipped update: $version');
      await _settingsService.setSkippedVersion(version);
    }
    _availableUpdate = null;
  }

  /// Dispose of resources
  void dispose() {
    _periodicTimer?.cancel();
    _updater.dispose();
  }
}
