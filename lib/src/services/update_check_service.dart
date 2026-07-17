import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/services/app_update_state.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';

/// Service for periodically checking for app updates
class UpdateCheckService {
  final Logger _log = Logger('UpdateCheckService');
  final SettingsService _settingsService;
  final AndroidUpdater _updater;
  final WebUIStorage _webUIStorage;

  /// Whether this platform can install an update in-app (Android only).
  /// Injectable so the state machine is testable off-device.
  final bool _isAndroid;

  Timer? _periodicTimer;
  UpdateInfo? _availableUpdate;

  /// Single source of truth for the API surface (`/api/v1/update`,
  /// `/ws/v1/update`). Derived from [_availableUpdate] plus the current phase.
  late final BehaviorSubject<AppUpdateState> _state;

  static const Duration _checkInterval =
      (String.fromEnvironment("simulate") == "1")
      ? Duration(hours: 1)
      : Duration(hours: 12);

  UpdateCheckService({
    required SettingsService settingsService,
    AndroidUpdater? updater,
    required WebUIStorage webUIStorage,
    bool? platformIsAndroid,
  }) : _settingsService = settingsService,
       _updater = updater ?? AndroidUpdater(owner: 'tadelv', repo: 'reaprime'),
       _webUIStorage = webUIStorage,
       _isAndroid = platformIsAndroid ?? Platform.isAndroid {
    _state = BehaviorSubject.seeded(_snapshot(AppUpdatePhase.idle));
  }

  /// Get the currently available update, if any
  UpdateInfo? get availableUpdate => _availableUpdate;

  /// Check if there's an available update
  bool get hasAvailableUpdate => _availableUpdate != null;

  /// Live app-update state for the API (replays the latest value on listen).
  Stream<AppUpdateState> get updateState => _state.stream;

  /// Synchronous snapshot of the current app-update state (for the REST read).
  AppUpdateState get currentState => _state.value;

  /// Whether an in-app install can be triggered on this platform.
  bool get canInstall => _isAndroid;

  /// Build an [AppUpdateState] for [phase] from the current [_availableUpdate].
  AppUpdateState _snapshot(
    AppUpdatePhase phase, {
    double? progress,
    String? error,
  }) {
    final update = _availableUpdate;
    final hasUpdate = update != null;
    return AppUpdateState(
      phase: phase,
      currentVersion: BuildInfo.version,
      latestVersion: update?.version,
      releaseNotes: update?.releaseNotes,
      releaseUrl: hasUpdate ? getReleaseUrl()! : getReleasesUrl(),
      installable: _isAndroid && hasUpdate,
      progress: progress,
      error: error,
    );
  }

  void _emit(AppUpdatePhase phase, {double? progress, String? error}) {
    _state.add(_snapshot(phase, progress: progress, error: error));
  }

  bool get _inProgress => const {
    AppUpdatePhase.checking,
    AppUpdatePhase.downloading,
    AppUpdatePhase.installing,
  }.contains(_state.value.phase);

  /// API command: force a re-check. No-op (coalesced) if an operation is
  /// already in flight.
  Future<void> requestCheck() async {
    if (_inProgress) return;
    await checkForUpdate();
  }

  /// API command: ensure an update is known (auto-checking if needed), then
  /// download and launch the system installer. No-op (coalesced) if an
  /// operation is already in flight. Only call when [canInstall] is true.
  Future<void> downloadAndInstall() async {
    if (_inProgress) return;
    if (!_isAndroid) return;

    // Auto-check if we have no known update yet.
    if (_availableUpdate == null) {
      await checkForUpdate();
      if (_availableUpdate == null) {
        // Already on the latest (checkForUpdate settled to idle).
        return;
      }
    }

    final update = _availableUpdate!;
    try {
      _emit(AppUpdatePhase.downloading, progress: 0);
      // Throttle to ~1% steps — the raw callback fires per network chunk
      // (thousands of times for a multi-MB APK), which would flood the WS.
      var lastEmitted = 0.0;
      final path = await _updater.downloadUpdate(
        update,
        onProgress: (p) {
          if (p - lastEmitted >= 0.01 || p >= 1.0) {
            lastEmitted = p;
            _emit(AppUpdatePhase.downloading, progress: p);
          }
        },
      );

      _emit(AppUpdatePhase.installing);
      final started = await _updater.installUpdate(path);
      if (!started) {
        _emit(
          AppUpdatePhase.error,
          error: 'Installation permission required. Grant it and retry.',
        );
      }
      // On success the OS installer takes over; the process is replaced.
    } catch (e, st) {
      _log.severe('Update download/install failed', e, st);
      _emit(AppUpdatePhase.error, error: 'Update failed: $e');
    }
  }

  /// Initialize the service and start periodic checks
  Future<void> initialize() async {
    final automaticUpdateCheck = await _settingsService.automaticUpdateCheck();
    if (automaticUpdateCheck) {
      await _startPeriodicChecks();
    }
  }

  /// Start periodic update checks
  Future<void> _startPeriodicChecks() async {
    _log.info(
      'Starting periodic update checks (every ${_checkInterval.inHours} hours)',
    );

    // Check immediately if we haven't checked recently
    final lastCheck = await _settingsService.lastUpdateCheckTime();
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) > _checkInterval) {
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
      _emit(AppUpdatePhase.checking);
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
          // Still return updateInfo — manual "Check for updates" button
          // should show the dialog even if auto-banner is suppressed.
        } else {
          _log.info('Update available: ${updateInfo.version}');
          _availableUpdate = updateInfo;
        }
      } else {
        _log.info('No update available');
        _availableUpdate = null;
      }

      _emit(
        _availableUpdate != null
            ? AppUpdatePhase.available
            : AppUpdatePhase.idle,
      );
      return updateInfo;
    } catch (e, stackTrace) {
      _log.warning('Error checking for updates', e, stackTrace);
      _emit(AppUpdatePhase.error, error: 'Update check failed: $e');
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
    _emit(AppUpdatePhase.idle);
  }

  /// Force an update to appear for testing. Only use in debug builds.
  ///
  /// [downloadUrl] points at a real APK so the download/install path can be
  /// exercised end-to-end; defaults to the latest released Android APK.
  void debugForceUpdate({
    String version = '99.0.0',
    String? downloadUrl,
  }) {
    _log.info('DEBUG: forcing fake update notification ($version)');
    _availableUpdate = UpdateInfo(
      version: version,
      downloadUrl:
          downloadUrl ??
          'https://github.com/tadelv/reaprime/releases/download/v0.7.7/decent-android-0.7.7.apk',
      releaseNotes: 'Forced update for testing the update API.',
      isPrerelease: false,
      tagName: 'v$version',
    );
    _emit(AppUpdatePhase.available);
  }

  /// Skip the current update version permanently
  Future<void> skipCurrentUpdate() async {
    final version = _availableUpdate?.version;
    if (version != null) {
      _log.info('User skipped update: $version');
      await _settingsService.setSkippedVersion(version);
    }
    _availableUpdate = null;
    _emit(AppUpdatePhase.idle);
  }

  /// Dispose of resources
  void dispose() {
    _periodicTimer?.cancel();
    _updater.dispose();
    _state.close();
  }
}
