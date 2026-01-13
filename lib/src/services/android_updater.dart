import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/services/apk_installer.dart';

/// Represents an available update from GitHub releases
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool isPrerelease;
  final String tagName;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isPrerelease,
    required this.tagName,
  });

  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String;
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    
    // Find the APK asset
    final assets = json['assets'] as List<dynamic>;
    final apkAsset = assets.firstWhere(
      (asset) => (asset['name'] as String).endsWith('.apk'),
      orElse: () => throw Exception('No APK found in release'),
    );

    return UpdateInfo(
      version: version,
      downloadUrl: apkAsset['browser_download_url'] as String,
      releaseNotes: json['body'] as String? ?? '',
      isPrerelease: json['prerelease'] as bool,
      tagName: tagName,
    );
  }
}

/// Update channel configuration
enum UpdateChannel {
  stable,
  beta,
  development;

  /// Returns true if this channel should include prereleases
  bool get includePrereleases {
    switch (this) {
      case UpdateChannel.stable:
        return false;
      case UpdateChannel.beta:
      case UpdateChannel.development:
        return true;
    }
  }

  /// Returns true if a release matches this channel based on tag naming
  bool matchesRelease(String tagName, bool isPrerelease) {
    switch (this) {
      case UpdateChannel.stable:
        return !isPrerelease && !tagName.contains('beta') && !tagName.contains('dev');
      case UpdateChannel.beta:
        return isPrerelease || tagName.contains('beta');
      case UpdateChannel.development:
        return true; // Development channel accepts all releases
    }
  }
}

/// Service for checking and installing app updates from GitHub releases
class AndroidUpdater {
  final Logger _log = Logger('AndroidUpdater');
  final String _owner;
  final String _repo;
  final http.Client _httpClient;
  final ApkInstaller _apkInstaller;

  AndroidUpdater({
    required String owner,
    required String repo,
    http.Client? httpClient,
    ApkInstaller? apkInstaller,
  })  : _owner = owner,
        _repo = repo,
        _httpClient = httpClient ?? http.Client(),
        _apkInstaller = apkInstaller ?? ApkInstaller();

  /// GitHub API URL for releases
  String get _releasesUrl => 'https://api.github.com/repos/$_owner/$_repo/releases';

  /// Check if an update is available for the given current version
  /// 
  /// [currentVersion] - The current app version (e.g., "1.2.3")
  /// [channel] - The update channel to check (stable, beta, development)
  /// 
  /// Returns [UpdateInfo] if an update is available, null otherwise
  Future<UpdateInfo?> checkForUpdate(
    String currentVersion, {
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    try {
      _log.info('Checking for updates on $channel channel (current: $currentVersion)');

      final response = await _httpClient.get(Uri.parse(_releasesUrl));

      if (response.statusCode != 200) {
        _log.warning('Failed to fetch releases: ${response.statusCode}');
        return null;
      }

      final releases = json.decode(response.body) as List<dynamic>;

      if (releases.isEmpty) {
        _log.info('No releases found');
        return null;
      }

      // Filter releases by channel
      final matchingReleases = releases.where((release) {
        final tagName = release['tag_name'] as String;
        final isPrerelease = release['prerelease'] as bool;
        return channel.matchesRelease(tagName, isPrerelease);
      }).toList();

      if (matchingReleases.isEmpty) {
        _log.info('No releases found for $channel channel');
        return null;
      }

      // Get the latest matching release
      final latestRelease = matchingReleases.first;
      final updateInfo = UpdateInfo.fromGitHubRelease(latestRelease);

      // Compare versions
      if (_isNewerVersion(updateInfo.version, currentVersion)) {
        _log.info('Update available: ${updateInfo.version}');
        return updateInfo;
      } else {
        _log.info('Already on latest version');
        return null;
      }
    } catch (e, stackTrace) {
      _log.severe('Error checking for updates', e, stackTrace);
      return null;
    }
  }

  /// Download an APK file and save it to the app's cache directory
  /// 
  /// [updateInfo] - The update information containing the download URL
  /// [onProgress] - Optional callback for download progress (0.0 to 1.0)
  /// 
  /// Returns the path to the downloaded APK file
  Future<String> downloadUpdate(
    UpdateInfo updateInfo, {
    Function(double progress)? onProgress,
  }) async {
    try {
      _log.info('Downloading update from ${updateInfo.downloadUrl}');

      final response = await _httpClient.get(Uri.parse(updateInfo.downloadUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download update: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final cacheDir = await getTemporaryDirectory();
      final apkPath = '${cacheDir.path}/update_${updateInfo.version}.apk';
      final apkFile = File(apkPath);

      await apkFile.writeAsBytes(bytes);

      _log.info('Downloaded update to $apkPath');
      return apkPath;
    } catch (e, stackTrace) {
      _log.severe('Error downloading update', e, stackTrace);
      rethrow;
    }
  }

  /// Install an APK file using the system package installer
  /// 
  /// On Android 8.0+, this requires REQUEST_INSTALL_PACKAGES permission
  /// 
  /// [apkPath] - Path to the APK file to install
  /// 
  /// Returns true if the installation was triggered successfully
  Future<bool> installUpdate(String apkPath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK installation is only supported on Android');
    }

    try {
      _log.info('Installing update from $apkPath');

      // Check if we have permission to install packages
      final canInstall = await _apkInstaller.canInstallPackages();
      if (!canInstall) {
        _log.warning('No permission to install packages, requesting permission');
        await _apkInstaller.requestInstallPermission();
        // User needs to grant permission and try again
        return false;
      }

      // Trigger the installation
      return await _apkInstaller.installApk(apkPath);
    } catch (e, stackTrace) {
      _log.severe('Error installing update', e, stackTrace);
      rethrow;
    }
  }

  /// Compare two semantic version strings
  /// 
  /// Returns true if [newVersion] is newer than [currentVersion]
  bool _isNewerVersion(String newVersion, String currentVersion) {
    // Handle dev versions
    if (currentVersion == '0.0.0-dev') {
      return true;
    }

    try {
      final newParts = _parseVersion(newVersion);
      final currentParts = _parseVersion(currentVersion);

      for (int i = 0; i < 3; i++) {
        if (newParts[i] > currentParts[i]) {
          return true;
        } else if (newParts[i] < currentParts[i]) {
          return false;
        }
      }

      return false; // Versions are equal
    } catch (e) {
      _log.warning('Error comparing versions: $e');
      return false;
    }
  }

  /// Parse a semantic version string into [major, minor, patch]
  List<int> _parseVersion(String version) {
    // Remove any suffix like -beta, -dev
    final cleanVersion = version.split('-').first;
    final parts = cleanVersion.split('.');
    
    if (parts.length != 3) {
      throw FormatException('Invalid version format: $version');
    }

    return parts.map((p) => int.parse(p)).toList();
  }

  void dispose() {
    _httpClient.close();
  }
}
