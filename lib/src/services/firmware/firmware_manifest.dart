import 'dart:convert';

import 'package:reaprime/src/models/device/firmware_artifact.dart';
import 'package:reaprime/src/services/firmware/de1_firmware_header.dart';

/// Parsed contents of `assets/firmware/manifest.json`.
///
/// The manifest declares the catalog of bundled firmware artifacts available
/// offline. Each entry carries metadata plus an internal asset path for
/// loading the actual bytes through the Flutter asset bundle.
final class FirmwareManifest {
  final int schemaVersion;
  final List<FirmwareManifestEntry> entries;

  const FirmwareManifest({required this.schemaVersion, required this.entries});

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'] as int;
    final entriesJson = json['artifacts'] as List;
    final entries = entriesJson
        .map((e) => FirmwareManifestEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final manifest = FirmwareManifest(
      schemaVersion: schemaVersion,
      entries: entries,
    );
    manifest._validate();
    return manifest;
  }

  factory FirmwareManifest.parse(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return FirmwareManifest.fromJson(json);
  }

  void _validate() {
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported manifest schema version: $schemaVersion',
      );
    }
    if (entries.isEmpty) {
      throw const FormatException('Firmware manifest has no artifacts');
    }

    const supportedModels = {'DE1Pro', 'DE1XL', 'DE1XXL', 'DE1XXXL'};
    final digestPattern = RegExp(r'^[0-9a-f]{64}$');
    final ids = <String>{};
    for (final entry in entries) {
      final artifact = entry.artifact;
      if (artifact.id.isEmpty || !ids.add(artifact.id)) {
        throw FormatException('Duplicate or empty artifact ID: ${artifact.id}');
      }
      if (artifact.source != FirmwareArtifactSource.bundled ||
          artifact.machineFamily != 'de1' ||
          artifact.imageFormat != 'de1') {
        throw FormatException('Unsupported artifact type: ${artifact.id}');
      }
      if (!digestPattern.hasMatch(artifact.sha256)) {
        throw FormatException('Invalid SHA-256 digest for ${artifact.id}');
      }
      if (artifact.supportedModels.isEmpty ||
          !supportedModels.containsAll(artifact.supportedModels)) {
        throw FormatException('Unknown supported model for ${artifact.id}');
      }
      if (artifact.build <= 0 || artifact.byteLength <= 0) {
        throw FormatException('Invalid numeric metadata for ${artifact.id}');
      }
      if (!entry.assetPath.startsWith('assets/firmware/') ||
          entry.expectedHeaderBoardMarker != 0xDE100001 ||
          entry.expectedBodyByteCount <= 0 ||
          entry.expectedBodyByteCount >
              artifact.byteLength - De1FirmwareHeader.byteLength ||
          entry.expectedCpuByteCount <= 0 ||
          entry.expectedCpuByteCount > entry.expectedBodyByteCount ||
          entry.provenance.isEmpty) {
        throw FormatException('Invalid image metadata for ${artifact.id}');
      }
    }
  }
}

/// A single entry in the bundled firmware manifest.
///
/// Extends [FirmwareArtifact] with fields private to the bundled catalog
/// (asset path, expected header/body/CPU metadata).
final class FirmwareManifestEntry {
  final FirmwareArtifact artifact;

  /// Flutter asset key, e.g. `assets/firmware/de1/de1-1352.bin`.
  final String assetPath;

  /// Expected DE1 header board marker (0xDE100001).
  final int expectedHeaderBoardMarker;

  /// Expected image-body byte count from the DE1 header.
  final int expectedBodyByteCount;

  /// Expected CPU byte count from the DE1 header.
  final int expectedCpuByteCount;

  /// Provenance/build reference sufficient to identify the supplied image.
  final String provenance;

  const FirmwareManifestEntry({
    required this.artifact,
    required this.assetPath,
    required this.expectedHeaderBoardMarker,
    required this.expectedBodyByteCount,
    required this.expectedCpuByteCount,
    required this.provenance,
  });

  factory FirmwareManifestEntry.fromJson(Map<String, dynamic> json) {
    return FirmwareManifestEntry(
      artifact: FirmwareArtifact.fromJson(json),
      assetPath: json['assetPath'] as String,
      expectedHeaderBoardMarker: json['expectedHeaderBoardMarker'] as int,
      expectedBodyByteCount: json['expectedBodyByteCount'] as int,
      expectedCpuByteCount: json['expectedCpuByteCount'] as int,
      provenance: json['provenance'] as String,
    );
  }
}
