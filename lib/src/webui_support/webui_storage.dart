import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:reaprime/src/settings/settings_controller.dart';

/// REA metadata for tracking WebUI skin source and version
class WebUIReaMetadata {
  final String skinId;
  final String? sourceUrl;
  final String? lastModified;
  final String? etag;
  final String? commitHash;
  final DateTime installedAt;
  final DateTime? lastChecked;

  WebUIReaMetadata({
    required this.skinId,
    this.sourceUrl,
    this.lastModified,
    this.etag,
    this.commitHash,
    required this.installedAt,
    this.lastChecked,
  });

  factory WebUIReaMetadata.fromJson(Map<String, dynamic> json) {
    return WebUIReaMetadata(
      skinId: json['skinId'] as String,
      sourceUrl: json['sourceUrl'] as String?,
      lastModified: json['lastModified'] as String?,
      etag: json['etag'] as String?,
      commitHash: json['commitHash'] as String?,
      installedAt: DateTime.parse(json['installedAt'] as String),
      lastChecked: json['lastChecked'] != null 
          ? DateTime.parse(json['lastChecked'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'skinId': skinId,
      'sourceUrl': sourceUrl,
      'lastModified': lastModified,
      'etag': etag,
      'commitHash': commitHash,
      'installedAt': installedAt.toIso8601String(),
      'lastChecked': lastChecked?.toIso8601String(),
    };
  }

  WebUIReaMetadata copyWith({
    String? sourceUrl,
    String? lastModified,
    String? etag,
    String? commitHash,
    DateTime? installedAt,
    DateTime? lastChecked,
  }) {
    return WebUIReaMetadata(
      skinId: skinId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      lastModified: lastModified ?? this.lastModified,
      etag: etag ?? this.etag,
      commitHash: commitHash ?? this.commitHash,
      installedAt: installedAt ?? this.installedAt,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Metadata for a WebUI skin
class WebUISkin {
  final String id;
  final String name;
  final String path;
  final String? description;
  final String? version;
  final bool isBundled;
  final WebUIReaMetadata? reaMetadata;

  WebUISkin({
    required this.id,
    required this.name,
    required this.path,
    this.description,
    this.version,
    this.isBundled = false,
    this.reaMetadata,
  });

  factory WebUISkin.fromJson(Map<String, dynamic> json) {
    return WebUISkin(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      description: json['description'] as String?,
      version: json['version'] as String?,
      isBundled: json['isBundled'] as bool? ?? false,
      reaMetadata: json['reaMetadata'] != null
          ? WebUIReaMetadata.fromJson(json['reaMetadata'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'description': description,
      'version': version,
      'isBundled': isBundled,
      'reaMetadata': reaMetadata?.toJson(),
    };
  }
}

/// Class that manages storage for web skins
/// - Can check hardcoded repo URLs for downloading skins
/// - Can install a skin from a Directory path (copy it over to ApplicationDocuments/web-ui/)
/// - Provides a registry of currently installed web-ui skins
class WebUIStorage {
  final _log = Logger('WebUIStorage');
  final SettingsController _settingsController;
  
  late Directory _webUIDir;
  final Map<String, WebUISkin> _installedSkins = {};
  final Map<String, WebUIReaMetadata> _skinMetadata = {};
  bool _initialized = false;

  WebUIStorage(this._settingsController);

  /// Hardcoded list of bundled asset paths
  /// These are Flutter assets that ship with the app
  static const List<String> _bundledAssetPaths = [
    // 'assets/web/',
  ];

  /// Remote WebUI source configuration
  /// Supports both GitHub releases and branch archives
  static const List<Map<String, dynamic>> _remoteWebUISources = [
    // Baseline
    {
      'type': 'github_release',
      'repo': 'tadelv/baseline.js',
      'asset': 'baseline-skin.zip',  // Optional: specific asset name
      'prerelease': true,      // Optional: include pre-releases
    },
    // Streamline Project (branch archive - no releases yet)
    {
      'type': 'github_branch',
      'repo': 'allofmeng/streamline_project',
      'branch': 'main',
    },
    // Example: GitHub Release (recommended for production)
    // {
    //   'type': 'github_release',
    //   'repo': 'username/my-skin-repo',
    //   'asset': 'my-skin.zip',  // Optional: specific asset name
    //   'prerelease': false,      // Optional: include pre-releases
    // },
    // Example: Direct URL (legacy support)
    // {
    //   'type': 'url',
    //   'url': 'https://example.com/skin.zip',
    // },
  ];

  /// Set of skin IDs that were installed from remote sources (treated as bundled)
  final Set<String> _remoteBundledSkinIds = {};

  /// Initialize the WebUIStorage service
  /// - Creates web-ui directory if it doesn't exist
  /// - Copies bundled skins from assets
  /// - Downloads remote bundled skins
  /// - Scans for installed skins
  Future<void> initialize() async {
    if (_initialized) {
      _log.fine('WebUIStorage already initialized');
      return;
    }

    // Get application documents directory
    final appDocDir = await getApplicationDocumentsDirectory();
    _webUIDir = Directory('${appDocDir.path}/web-ui');

    // Create web-ui directory if it doesn't exist
    if (!_webUIDir.existsSync()) {
      _webUIDir.createSync(recursive: true);
      _log.info('Created web-ui directory: ${_webUIDir.path}');
    }

    // Load persisted remote bundled skin IDs
    await _loadRemoteBundledSkinIds();

    // Load REA metadata for all skins
    await _loadSkinMetadata();

    // Copy bundled skins from assets
    await _copyBundledSkins();

    // Download and install remote bundled skins (includes version checking)
    await downloadRemoteSkins();

    // Scan for installed skins
    await _scanInstalledSkins();

    _initialized = true;
    _log.info('WebUIStorage initialized with ${_installedSkins.length} skins');
  }

  /// Get list of all installed WebUI skins
  List<WebUISkin> get installedSkins => _installedSkins.values.toList();

  /// Get a specific skin by ID
  WebUISkin? getSkin(String id) => _installedSkins[id];

  /// Get the default skin based on user preference
  /// Falls back to 'streamline-project' if preference not found
  /// Then falls back to first bundled skin or first available skin
  WebUISkin? get defaultSkin {
    // Try to get skin from preference
    final preferredSkinId = _settingsController.defaultSkinId;
    _log.info("selecting preferred skin: $preferredSkinId, in: ${_installedSkins}");
    if (_installedSkins.containsKey(preferredSkinId)) {
      return _installedSkins[preferredSkinId];
    }

    // Log if preferred skin not found
    if (preferredSkinId != 'streamline_project-main') {
      _log.warning('Preferred skin "$preferredSkinId" not found, falling back to default');
    }

    // Try to find streamline-project as default
    final streamlineSkin = _installedSkins['streamline_project-main'];
    if (streamlineSkin != null) {
      return streamlineSkin;
    }

    // Try to find any bundled skin
    final bundledSkin = _installedSkins.values
        .where((skin) => skin.isBundled)
        .firstOrNull;
    
    if (bundledSkin != null) {
      return bundledSkin;
    }

    // Otherwise return the first available skin
    return _installedSkins.values.firstOrNull;
  }

  /// Set the default skin by ID and persist to preferences
  Future<void> setDefaultSkin(String skinId) async {
    if (!_installedSkins.containsKey(skinId)) {
      throw Exception('Skin not found: $skinId');
    }
    
    await _settingsController.setDefaultSkinId(skinId);
    _log.info('Set default skin to: $skinId');
  }

  /// Install a WebUI skin from a local filesystem path
  /// The path can be either a directory or a zip file
  Future<void> installFromPath(String sourcePath) async {
    final source = File(sourcePath);
    final sourceDir = Directory(sourcePath);

    if (source.existsSync() && sourcePath.endsWith('.zip')) {
      // It's a zip file - extract it
      await _installFromZip(sourcePath);
    } else if (sourceDir.existsSync()) {
      // It's a directory - copy it
      await _installFromDirectory(sourceDir);
    } else {
      throw Exception('Source does not exist: $sourcePath');
    }

    // Rescan installed skins
    await _scanInstalledSkins();
  }

  /// Install a WebUI skin from a URL
  /// The URL should point to a zip file
  Future<void> installFromUrl(String url) async {
    _log.info('Downloading WebUI from URL: $url');

    try {
      // Download the zip file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      // Create temp file for the downloaded zip
      final appDocDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${appDocDir.path}/temp_webui.zip');
      await tempFile.writeAsBytes(response.bodyBytes);

      try {
        // Install from the downloaded zip
        await _installFromZip(tempFile.path);
      } finally {
        // Clean up temp file
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      }

      // Rescan installed skins
      await _scanInstalledSkins();
      
      _log.info('Successfully installed WebUI from URL: $url');
    } catch (e) {
      _log.severe('Failed to install WebUI from URL: $url', e);
      rethrow;
    }
  }

  /// Install a WebUI skin from a GitHub repository
  /// Format: "owner/repo" or "owner/repo/branch"
  Future<void> installFromGitHub(String repo, {String branch = 'main'}) async {
    // GitHub provides zip archives at: https://github.com/{owner}/{repo}/archive/refs/heads/{branch}.zip
    final parts = repo.split('/');
    if (parts.length < 2) {
      throw Exception('Invalid GitHub repo format. Use: owner/repo');
    }

    final owner = parts[0];
    final repoName = parts[1];
    final branchName = parts.length > 2 ? parts[2] : branch;
    
    final url = 'https://github.com/$owner/$repoName/archive/refs/heads/$branchName.zip';
    
    await installFromUrl(url);
  }

  /// Install a WebUI skin from a GitHub Release
  /// Uses GitHub API to fetch the latest release and download the asset
  /// 
  /// Parameters:
  /// - [repo]: Repository in format "owner/repo"
  /// - [assetName]: Optional specific asset name to download (e.g., "my-skin.zip")
  ///   If null, downloads the first .zip asset found
  /// - [includePrerelease]: If true, includes pre-release versions
  /// 
  /// Example:
  /// ```dart
  /// await webUIStorage.installFromGitHubRelease('username/my-skin-repo');
  /// await webUIStorage.installFromGitHubRelease('username/my-skin-repo', assetName: 'skin-v1.0.0.zip');
  /// ```
  Future<void> installFromGitHubRelease(
    String repo, {
    String? assetName,
    bool includePrerelease = false,
  }) async {
    final parts = repo.split('/');
    if (parts.length != 2) {
      throw Exception('Invalid GitHub repo format. Use: owner/repo');
    }

    _log.info('Installing WebUI from GitHub release: $repo');

    try {
      // Fetch latest release from GitHub API
      final apiUrl = includePrerelease
          ? 'https://api.github.com/repos/$repo/releases'
          : 'https://api.github.com/repos/$repo/releases/latest';
      
      final releaseResponse = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Streamline-Bridge-WebUI',
        },
      );
      
      if (releaseResponse.statusCode != 200) {
        throw Exception('Failed to fetch GitHub release: ${releaseResponse.statusCode}');
      }
      
      final dynamic releaseData = includePrerelease
          ? (jsonDecode(releaseResponse.body) as List).first
          : jsonDecode(releaseResponse.body);
      
      final releaseTag = releaseData['tag_name'] as String;
      final releaseName = releaseData['name'] as String;
      final assets = releaseData['assets'] as List;
      
      _log.info('Found release: $releaseName ($releaseTag)');
      
      // Find the asset to download
      dynamic targetAsset;
      if (assetName != null) {
        targetAsset = assets.firstWhere(
          (asset) => asset['name'] == assetName,
          orElse: () => throw Exception('Asset not found: $assetName'),
        );
      } else {
        targetAsset = assets.firstWhere(
          (asset) => (asset['name'] as String).endsWith('.zip'),
          orElse: () => throw Exception('No .zip asset found in release'),
        );
      }
      
      final downloadUrl = targetAsset['browser_download_url'] as String;
      
      _log.info('Downloading asset: ${targetAsset['name']}');
      
      // Download and install
      await installFromUrl(downloadUrl);
      
      _log.info('Successfully installed WebUI from GitHub release: $releaseTag');
    } catch (e) {
      _log.severe('Failed to install WebUI from GitHub release: $repo', e);
      rethrow;
    }
  }

  /// Download and install all skins from the hardcoded remote sources
  /// These skins are treated as "bundled" and cannot be removed by users
  Future<void> downloadRemoteSkins() async {
    for (final sourceConfig in _remoteWebUISources) {
      try {
        final type = sourceConfig['type'] as String;
        
        switch (type) {
          case 'github_release':
            final repo = sourceConfig['repo'] as String;
            final asset = sourceConfig['asset'] as String?;
            final prerelease = sourceConfig['prerelease'] as bool? ?? false;
            
            _log.info('Downloading remote bundled skin from GitHub release: $repo');
            await _installFromGitHubRelease(repo, asset, prerelease);
            break;
            
          case 'github_branch':
            final repo = sourceConfig['repo'] as String;
            final branch = sourceConfig['branch'] as String? ?? 'main';
            final url = 'https://github.com/$repo/archive/refs/heads/$branch.zip';
            
            _log.info('Downloading remote bundled skin from GitHub branch: $repo/$branch');
            await _installFromUrlAsRemoteBundled(url);
            break;
            
          case 'url':
            final url = sourceConfig['url'] as String;
            
            _log.info('Downloading remote bundled skin from URL: $url');
            await _installFromUrlAsRemoteBundled(url);
            break;
            
          default:
            _log.warning('Unknown remote source type: $type');
        }
      } catch (e, st) {
        _log.warning('Failed to download remote skin from $sourceConfig', e, st);
        // Continue with other sources even if one fails
      }
    }
  }

  /// Install from GitHub Release using GitHub API
  /// Supports semantic versioning and proper release tracking
  Future<void> _installFromGitHubRelease(
    String repo,
    String? assetName,
    bool includePrerelease,
  ) async {
    try {
      // Fetch latest release from GitHub API
      final apiUrl = includePrerelease
          ? 'https://api.github.com/repos/$repo/releases'
          : 'https://api.github.com/repos/$repo/releases/latest';
      
      _log.fine('Fetching GitHub release info from: $apiUrl');
      
      final releaseResponse = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Streamline-Bridge-WebUI',
        },
      );
      
      if (releaseResponse.statusCode != 200) {
        throw Exception('Failed to fetch GitHub release: ${releaseResponse.statusCode}');
      }
      
      final dynamic releaseData = includePrerelease
          ? (jsonDecode(releaseResponse.body) as List).first
          : jsonDecode(releaseResponse.body);
      
      final releaseTag = releaseData['tag_name'] as String;
      final releaseName = releaseData['name'] as String;
      final publishedAt = releaseData['published_at'] as String;
      final assets = releaseData['assets'] as List;
      
      _log.info('Found release: $releaseName ($releaseTag) published at $publishedAt');
      
      // Find the asset to download
      dynamic targetAsset;
      if (assetName != null) {
        // Look for specific asset name
        targetAsset = assets.firstWhere(
          (asset) => asset['name'] == assetName,
          orElse: () => throw Exception('Asset not found: $assetName'),
        );
      } else {
        // Look for first .zip asset
        targetAsset = assets.firstWhere(
          (asset) => (asset['name'] as String).endsWith('.zip'),
          orElse: () => throw Exception('No .zip asset found in release'),
        );
      }
      
      final downloadUrl = targetAsset['browser_download_url'] as String;
      final assetSize = targetAsset['size'] as int;
      
      _log.info('Downloading asset: ${targetAsset['name']} (${(assetSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      
      // Check if we already have this version installed
      final sourceIdentifier = 'github_release:$repo@$releaseTag';
      final existingMetadata = _skinMetadata.values.firstWhere(
        (meta) => meta.sourceUrl == sourceIdentifier,
        orElse: () => WebUIReaMetadata(
          skinId: '',
          installedAt: DateTime.now(),
        ),
      );
      
      if (existingMetadata.skinId.isNotEmpty) {
        _log.info('Release $releaseTag already installed, skipping download');
        
        // Update last checked time
        _skinMetadata[existingMetadata.skinId] = existingMetadata.copyWith(
          lastChecked: DateTime.now(),
        );
        await _saveSkinMetadata();
        return;
      }
      
      // Download the asset
      final assetResponse = await http.get(Uri.parse(downloadUrl));
      if (assetResponse.statusCode != 200) {
        throw Exception('Failed to download asset: ${assetResponse.statusCode}');
      }
      
      // Create temp file for the downloaded zip
      final appDocDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${appDocDir.path}/temp_webui_release.zip');
      await tempFile.writeAsBytes(assetResponse.bodyBytes);
      
      String installedSkinId;
      try {
        // Install from the downloaded zip
        installedSkinId = await _installFromZip(tempFile.path);
      } finally {
        // Clean up temp file
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      }
      
      // Mark this skin as remote bundled
      _remoteBundledSkinIds.add(installedSkinId);
      await _saveRemoteBundledSkinIds();
      
      // Store REA metadata with release information
      _skinMetadata[installedSkinId] = WebUIReaMetadata(
        skinId: installedSkinId,
        sourceUrl: sourceIdentifier,
        commitHash: releaseTag,
        etag: null,  // GitHub releases don't use ETags for versioning
        lastModified: publishedAt,
        installedAt: DateTime.now(),
        lastChecked: DateTime.now(),
      );
      await _saveSkinMetadata();
      
      _log.info('Successfully installed skin from GitHub release: $installedSkinId ($releaseTag)');
      
      // Rescan installed skins
      await _scanInstalledSkins();
      
    } catch (e, st) {
      _log.severe('Failed to install from GitHub release: $repo', e, st);
      rethrow;
    }
  }

  /// Internal method to install from URL and mark as remote bundled
  /// Includes version checking via HTTP headers (ETag, Last-Modified)
  Future<void> _installFromUrlAsRemoteBundled(String url) async {
    try {
      // First, do a HEAD request to check version without downloading
      final headResponse = await http.head(Uri.parse(url));
      final etag = headResponse.headers['etag'];
      final lastModified = headResponse.headers['last-modified'];
      
      // Try to find existing skin with this source URL
      final existingMetadata = _skinMetadata.values.firstWhere(
        (meta) => meta.sourceUrl == url,
        orElse: () => WebUIReaMetadata(
          skinId: '',
          installedAt: DateTime.now(),
        ),
      );

      // Check if we need to update
      bool needsUpdate = true;
      if (existingMetadata.skinId.isNotEmpty) {
        // We have this skin already, check if it's up to date
        if (etag != null && etag == existingMetadata.etag) {
          needsUpdate = false;
          _log.info('Skin from $url is up to date (ETag match)');
        } else if (lastModified != null && 
                   lastModified == existingMetadata.lastModified) {
          needsUpdate = false;
          _log.info('Skin from $url is up to date (Last-Modified match)');
        }

        // Update last checked time even if not updating
        _skinMetadata[existingMetadata.skinId] = existingMetadata.copyWith(
          lastChecked: DateTime.now(),
        );
        await _saveSkinMetadata();
      }

      if (!needsUpdate) {
        return;
      }

      _log.info('Downloading WebUI from URL: $url');

      // Download the zip file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      // Create temp file for the downloaded zip
      final appDocDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${appDocDir.path}/temp_webui.zip');
      await tempFile.writeAsBytes(response.bodyBytes);

      String? commitHash;
      
      // Extract commit hash if this is a GitHub URL
      if (url.contains('github.com')) {
        commitHash = _extractGitHubCommitHash(url);
      }

      String installedSkinId;
      try {
        // Install from the downloaded zip
        installedSkinId = await _installFromZip(tempFile.path);
      } finally {
        // Clean up temp file
        if (tempFile.existsSync()) {
          await tempFile.delete();
        }
      }

      // Mark this skin as remote bundled
      _remoteBundledSkinIds.add(installedSkinId);
      await _saveRemoteBundledSkinIds();
      
      // Store REA metadata
      _skinMetadata[installedSkinId] = WebUIReaMetadata(
        skinId: installedSkinId,
        sourceUrl: url,
        etag: etag,
        lastModified: lastModified,
        commitHash: commitHash,
        installedAt: DateTime.now(),
        lastChecked: DateTime.now(),
      );
      await _saveSkinMetadata();
      
      _log.info('Installed/updated remote bundled skin: $installedSkinId');

      // Rescan installed skins
      await _scanInstalledSkins();
      
      _log.info('Successfully installed remote bundled WebUI from URL: $url');
    } catch (e) {
      _log.severe('Failed to install WebUI from URL: $url', e);
      rethrow;
    }
  }

  /// Extract commit hash from GitHub archive URL
  /// GitHub archive URLs contain refs/heads/{branch} but we can try to get commit from API
  String? _extractGitHubCommitHash(String url) {
    try {
      // For now, just extract the branch name from the URL
      // Format: https://github.com/{owner}/{repo}/archive/refs/heads/{branch}.zip
      final match = RegExp(r'github\.com/([^/]+)/([^/]+)/archive/refs/heads/([^\.]+)\.zip')
          .firstMatch(url);
      
      if (match != null) {
        final branch = match.group(3);
        return 'branch:$branch'; // Simple branch tracking
      }
      
      return null;
    } catch (e) {
      _log.warning('Failed to extract GitHub commit hash from URL: $url', e);
      return null;
    }
  }

  /// Remove/uninstall a WebUI skin
  Future<void> removeSkin(String skinId) async {
    if (!_installedSkins.containsKey(skinId)) {
      throw Exception('Skin not found: $skinId');
    }

    final skin = _installedSkins[skinId]!;
    
    // Don't allow removing bundled skins
    if (skin.isBundled) {
      throw Exception('Cannot remove bundled skin: $skinId');
    }

    // Delete skin directory
    final skinDir = Directory(skin.path);
    if (skinDir.existsSync()) {
      await skinDir.delete(recursive: true);
      _log.info('Removed skin: $skinId');
    }

    // Remove from caches
    _installedSkins.remove(skinId);
    
    // Remove metadata
    if (_skinMetadata.containsKey(skinId)) {
      _skinMetadata.remove(skinId);
      await _saveSkinMetadata();
    }
  }

  /// Check if a skin with the given ID is installed
  bool isSkinInstalled(String skinId) {
    return _installedSkins.containsKey(skinId);
  }

  /// Get the full filesystem path for a skin
  String getSkinPath(String skinId) {
    final skin = _installedSkins[skinId];
    if (skin == null) {
      throw Exception('Skin not found: $skinId');
    }
    return skin.path;
  }

  // Private helper methods

  /// Load the persisted list of remote bundled skin IDs
  Future<void> _loadRemoteBundledSkinIds() async {
    try {
      final registryFile = File('${_webUIDir.path}/.remote_bundled_registry.json');
      if (registryFile.existsSync()) {
        final contents = await registryFile.readAsString();
        final List<dynamic> skinIds = jsonDecode(contents);
        _remoteBundledSkinIds.addAll(skinIds.cast<String>());
        _log.fine('Loaded ${_remoteBundledSkinIds.length} remote bundled skin IDs');
      }
    } catch (e) {
      _log.warning('Failed to load remote bundled skin IDs registry', e);
    }
  }

  /// Save the list of remote bundled skin IDs to disk
  Future<void> _saveRemoteBundledSkinIds() async {
    try {
      final registryFile = File('${_webUIDir.path}/.remote_bundled_registry.json');
      await registryFile.writeAsString(jsonEncode(_remoteBundledSkinIds.toList()));
      _log.fine('Saved ${_remoteBundledSkinIds.length} remote bundled skin IDs');
    } catch (e) {
      _log.warning('Failed to save remote bundled skin IDs registry', e);
    }
  }

  /// Load REA metadata for all skins from disk
  Future<void> _loadSkinMetadata() async {
    try {
      final metadataFile = File('${_webUIDir.path}/.rea_metadata.json');
      if (metadataFile.existsSync()) {
        final contents = await metadataFile.readAsString();
        final Map<String, dynamic> json = jsonDecode(contents);
        
        for (final entry in json.entries) {
          _skinMetadata[entry.key] = WebUIReaMetadata.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
        
        _log.fine('Loaded metadata for ${_skinMetadata.length} skins');
      }
    } catch (e) {
      _log.warning('Failed to load skin metadata', e);
    }
  }

  /// Save REA metadata for all skins to disk
  Future<void> _saveSkinMetadata() async {
    try {
      final metadataFile = File('${_webUIDir.path}/.rea_metadata.json');
      final json = <String, dynamic>{};
      
      for (final entry in _skinMetadata.entries) {
        json[entry.key] = entry.value.toJson();
      }
      
      await metadataFile.writeAsString(
        JsonEncoder.withIndent('  ').convert(json),
      );
      _log.fine('Saved metadata for ${_skinMetadata.length} skins');
    } catch (e) {
      _log.warning('Failed to save skin metadata', e);
    }
  }

  /// Copy bundled skins from Flutter assets to web-ui directory
  Future<void> _copyBundledSkins() async {
    for (final assetPath in _bundledAssetPaths) {
      try {
        // Extract skin ID from asset path (last folder name)
        final skinId = assetPath.split('/').where((s) => s.isNotEmpty).last;
        final destDir = Directory('${_webUIDir.path}/$skinId');

        // Check if skin already exists
        if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
          _log.fine('Bundled skin already exists: $skinId');
          continue;
        }

        // Create destination directory
        destDir.createSync(recursive: true);

        // Copy files from assets
        await _copyAssetFolder(assetPath, destDir.path);

        _log.info('Copied bundled skin: $skinId');
      } catch (e) {
        _log.warning('Failed to copy bundled skin from $assetPath', e);
      }
    }
  }

  /// Copy an entire asset folder to a destination path
  Future<void> _copyAssetFolder(String assetPath, String destPath) async {
    try {
      // List all files in the asset folder
      // Note: Flutter doesn't provide a way to list asset directories at runtime
      // So we need to know the files in advance or use a manifest file
      
      // For now, we'll try to copy common web files
      final commonFiles = [
        'index.html',
        'style.css',
        'script.js',
        'app.js',
        'main.js',
        'favicon.ico',
        'manifest.json',
        'README.md',
      ];

      for (final fileName in commonFiles) {
        try {
          final assetFile = '$assetPath$fileName';
          final content = await rootBundle.loadString(assetFile);
          final destFile = File('$destPath/$fileName');
          await destFile.writeAsString(content);
          _log.fine('Copied asset file: $fileName');
        } catch (e) {
          // File doesn't exist in assets, skip it
          continue;
        }
      }
    } catch (e) {
      _log.warning('Error copying asset folder $assetPath', e);
      rethrow;
    }
  }

  /// Scan the web-ui directory for installed skins
  Future<void> _scanInstalledSkins() async {
    _installedSkins.clear();

    if (!_webUIDir.existsSync()) {
      return;
    }

    final directories = _webUIDir.listSync().whereType<Directory>();

    for (final dir in directories) {
      try {
        final skinId = p.basename(dir.path);
        
        // Get REA metadata if it exists
        final reaMetadata = _skinMetadata[skinId];
        
        // Try to load metadata from manifest.json if it exists
        final manifestFile = File('${dir.path}/manifest.json');
        WebUISkin skin;
        
        if (manifestFile.existsSync()) {
          final manifestJson = jsonDecode(await manifestFile.readAsString());
          skin = WebUISkin(
            id: manifestJson['id'] as String? ?? skinId,
            name: manifestJson['name'] as String? ?? skinId,
            path: dir.path,
            description: manifestJson['description'] as String?,
            version: manifestJson['version'] as String?,
            isBundled: _isBundledSkin(skinId),
            reaMetadata: reaMetadata,
          );
        } else {
          // No manifest, create basic skin info
          skin = WebUISkin(
            id: skinId,
            name: skinId,
            path: dir.path,
            isBundled: _isBundledSkin(skinId),
            reaMetadata: reaMetadata,
          );
        }

        _installedSkins[skin.id] = skin;
        _log.fine('Found skin: ${skin.id} at ${skin.path}');
      } catch (e) {
        _log.warning('Failed to load skin from ${dir.path}', e);
      }
    }
  }

  /// Check if a skin ID corresponds to a bundled skin
  /// Bundled skins include both asset-bundled and remote-bundled skins
  bool _isBundledSkin(String skinId) {
    // Check if it's from asset paths
    final isAssetBundled = _bundledAssetPaths.any((path) {
      final bundledId = path.split('/').where((s) => s.isNotEmpty).last;
      return bundledId == skinId;
    });
    
    if (isAssetBundled) return true;
    
    // Check if it's from remote sources
    return _remoteBundledSkinIds.contains(skinId);
  }

  /// Install a WebUI skin from a zip file
  /// Returns the installed skin ID
  Future<String> _installFromZip(String zipPath) async {
    _log.info('Installing WebUI from zip: $zipPath');

    // Create temp extraction directory
    final appDocDir = await getApplicationDocumentsDirectory();
    final tempDir = Directory('${appDocDir.path}/temp_webui_extract');
    
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    tempDir.createSync(recursive: true);

    try {
      // Extract zip file using archive package
      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Extract files to temp directory
      for (final file in archive) {
        final filename = file.name;
        final filePath = '${tempDir.path}/$filename';
        
        if (file.isFile) {
          final outFile = File(filePath);
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        } else {
          Directory(filePath).createSync(recursive: true);
        }
      }

      // Find the actual content directory
      // (GitHub zips have a root folder like "repo-main/")
      final extractedContents = tempDir.listSync();
      Directory contentDir;
      
      if (extractedContents.length == 1 && extractedContents.first is Directory) {
        // Single root directory, use it
        contentDir = extractedContents.first as Directory;
      } else {
        // Multiple items or files, use temp dir itself
        contentDir = tempDir;
      }

      // Install from the extracted directory
      return await _installFromDirectory(contentDir);
    } finally {
      // Clean up temp directory
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// Install a WebUI skin from a directory
  /// Returns the installed skin ID
  Future<String> _installFromDirectory(Directory sourceDir) async {
    // Try to load manifest to get skin ID, otherwise use directory name
    String skinId;
    final manifestFile = File('${sourceDir.path}/manifest.json');
    
    if (manifestFile.existsSync()) {
      final manifestJson = jsonDecode(await manifestFile.readAsString());
      skinId = manifestJson['id'] as String? ?? p.basename(sourceDir.path);
    } else {
      skinId = p.basename(sourceDir.path);
    }

    // Check if skin already exists
    final destDir = Directory('${_webUIDir.path}/$skinId');
    if (destDir.existsSync()) {
      _log.warning('Skin already exists: $skinId, overwriting...');
      await destDir.delete(recursive: true);
    }

    // Create destination directory
    destDir.createSync(recursive: true);

    // Copy all files from source to destination
    await _copyDirectory(sourceDir, destDir);

    _log.info('Installed WebUI skin: $skinId at ${destDir.path}');
    
    return skinId;
  }

  /// Recursively copy a directory
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      final fileName = p.basename(entity.path);
      
      if (entity is File) {
        final newFile = File(p.join(destination.path, fileName));
        await entity.copy(newFile.path);
      } else if (entity is Directory) {
        final newDir = Directory(p.join(destination.path, fileName));
        newDir.createSync(recursive: true);
        await _copyDirectory(entity, newDir);
      }
    }
  }

  /// Reset/clear all installed skins (useful for testing)
  Future<void> reset() async {
    for (final skin in _installedSkins.values.toList()) {
      if (!skin.isBundled) {
        try {
          await removeSkin(skin.id);
        } catch (e) {
          _log.warning('Failed to remove skin during reset: ${skin.id}', e);
        }
      }
    }
    
    // Rescan to refresh state
    await _scanInstalledSkins();
  }
}



























