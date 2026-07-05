/// Phases of the app-update lifecycle, surfaced over the API
/// (`GET /api/v1/update` and `GET /ws/v1/update`).
enum AppUpdatePhase {
  /// No update known (either not checked yet, or already on the latest).
  idle,

  /// A check against GitHub releases is in progress.
  checking,

  /// An update is available but no download has started.
  available,

  /// The update APK is downloading ([AppUpdateState.progress] is set).
  downloading,

  /// The system package installer has been launched.
  installing,

  /// The last operation failed ([AppUpdateState.error] is set).
  error,
}

/// Immutable snapshot of the app-update state machine.
///
/// One source of truth lives in `UpdateCheckService` as a `BehaviorSubject`
/// of this type; the REST snapshot and the WebSocket stream both read it.
class AppUpdateState {
  final AppUpdatePhase phase;

  /// The currently running app version (`BuildInfo.version`).
  final String currentVersion;

  /// The latest version offered, once known (phase >= available).
  final String? latestVersion;

  /// Release notes for [latestVersion], if any.
  final String? releaseNotes;

  /// Where the user can get the release: the specific tag URL when known,
  /// otherwise the releases page. Always present so a skin can hand off.
  final String releaseUrl;

  /// Whether this platform can install the update in-app (Android only) AND
  /// an update is currently available.
  final bool installable;

  /// Download progress 0..1 while [phase] is downloading; null otherwise.
  final double? progress;

  /// Human-readable error message while [phase] is error; null otherwise.
  final String? error;

  const AppUpdateState({
    required this.phase,
    required this.currentVersion,
    required this.releaseUrl,
    required this.installable,
    this.latestVersion,
    this.releaseNotes,
    this.progress,
    this.error,
  });

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    String? currentVersion,
    String? latestVersion,
    String? releaseNotes,
    String? releaseUrl,
    bool? installable,
    double? progress,
    String? error,
  }) {
    return AppUpdateState(
      phase: phase ?? this.phase,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      installable: installable ?? this.installable,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'currentVersion': currentVersion,
    'latestVersion': latestVersion,
    'releaseNotes': releaseNotes,
    'releaseUrl': releaseUrl,
    'installable': installable,
    'progress': progress,
    'error': error,
  };
}
