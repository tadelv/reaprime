/// Source of a firmware artifact in the catalog.
enum FirmwareArtifactSource { bundled }

/// Managed firmware artifact metadata.
///
/// Represents a known-good firmware image plus its catalog-facing metadata.
/// The bytes are loaded on demand; this model carries only the metadata needed
/// to select and validate an artifact before loading.
final class FirmwareArtifact {
  final String id;
  final FirmwareArtifactSource source;
  final String machineFamily;
  final Set<String> supportedModels;
  final int build;
  final String versionLabel;
  final String imageFormat;
  final int byteLength;
  final String sha256;
  final String channel;
  final String releaseNotes;

  const FirmwareArtifact({
    required this.id,
    required this.source,
    required this.machineFamily,
    required this.supportedModels,
    required this.build,
    required this.versionLabel,
    required this.imageFormat,
    required this.byteLength,
    required this.sha256,
    required this.channel,
    required this.releaseNotes,
  });

  factory FirmwareArtifact.fromJson(Map<String, dynamic> json) {
    return FirmwareArtifact(
      id: json['id'] as String,
      source: FirmwareArtifactSource.values.byName(json['source'] as String),
      machineFamily: json['machineFamily'] as String,
      supportedModels: Set<String>.from(
        (json['supportedModels'] as List).cast<String>(),
      ),
      build: json['build'] as int,
      versionLabel: json['versionLabel'] as String,
      imageFormat: json['imageFormat'] as String,
      byteLength: json['byteLength'] as int,
      sha256: json['sha256'] as String,
      channel: json['channel'] as String,
      releaseNotes: json['releaseNotes'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.name,
      'machineFamily': machineFamily,
      'supportedModels': supportedModels.toList(),
      'build': build,
      'versionLabel': versionLabel,
      'imageFormat': imageFormat,
      'byteLength': byteLength,
      'sha256': sha256,
      'channel': channel,
      'releaseNotes': releaseNotes,
    };
  }
}

/// Per-artifact eligibility for the connected machine.
enum FirmwareEligibilityStatus {
  /// The artifact can be applied to the connected machine.
  applicable,

  /// The artifact cannot be applied (incompatible model, etc.).
  notApplicable,

  /// Cannot determine eligibility (no machine connected).
  unknown,
}

/// Stable machine-readable eligibility reason codes.
enum FirmwareEligibilityReason {
  machineNotConnected('machine_not_connected'),
  machineModelUnknown('machine_model_unknown'),
  installedBuildUnknown('installed_build_unknown'),
  modelIncompatible('model_incompatible'),
  artifactInvalid('artifact_invalid'),
  notNewer('not_newer');

  final String code;
  const FirmwareEligibilityReason(this.code);

  static FirmwareEligibilityReason? fromCode(String code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// Eligibility result for a single artifact.
final class FirmwareEligibility {
  final FirmwareEligibilityStatus status;
  final List<String> reasons;

  const FirmwareEligibility({
    required this.status,
    this.reasons = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'reasons': reasons,
    };
  }
}
