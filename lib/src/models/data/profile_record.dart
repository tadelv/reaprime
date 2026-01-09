import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_hash.dart';

/// Visibility state of a profile record
enum Visibility {
  /// Profile is visible and usable
  visible,

  /// Profile is hidden from normal views but not deleted
  hidden,

  /// Profile is soft-deleted (can be purged later)
  deleted,
}

/// Extension to convert visibility enum to/from string
extension VisibilityExtension on Visibility {
  String get name {
    switch (this) {
      case Visibility.visible:
        return 'visible';
      case Visibility.hidden:
        return 'hidden';
      case Visibility.deleted:
        return 'deleted';
    }
  }

  static Visibility fromString(String value) {
    switch (value.toLowerCase()) {
      case 'visible':
        return Visibility.visible;
      case 'hidden':
        return Visibility.hidden;
      case 'deleted':
        return Visibility.deleted;
      default:
        throw ArgumentError('Invalid visibility value: $value');
    }
  }
}

/// Envelope around Profile with metadata for storage and versioning
/// 
/// Uses content-based hashing for profile identification:
/// - `id`: Hash of execution-relevant fields (profile hash)
/// - `metadataHash`: Hash of presentation fields
/// - `compoundHash`: Combined hash of both
@immutable
class ProfileRecord extends Equatable {
  /// Unique identifier based on profile content hash
  /// Format: profile:<first_16_chars_of_hash>
  final String id;

  /// The actual profile data
  final Profile profile;

  /// Hash of metadata fields (title, author, notes)
  final String metadataHash;

  /// Combined hash of profile hash + metadata hash
  final String compoundHash;

  /// Reference to the parent profile this was derived from (for versioning)
  final String? parentId;

  /// Current visibility state
  final Visibility visibility;

  /// Whether this is a bundled default profile (cannot be deleted)
  final bool isDefault;

  /// When this record was created
  final DateTime createdAt;

  /// When this record was last updated
  final DateTime updatedAt;

  /// Extensible metadata for future use
  final Map<String, dynamic>? metadata;

  const ProfileRecord({
    required this.id,
    required this.profile,
    required this.metadataHash,
    required this.compoundHash,
    this.parentId,
    this.visibility = Visibility.visible,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  /// Create a new profile record with content-based hash ID
  /// 
  /// The ID is automatically calculated from the profile's execution-relevant
  /// fields, ensuring identical profiles have identical IDs across all installations.
  factory ProfileRecord.create({
    required Profile profile,
    String? parentId,
    bool isDefault = false,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now();
    final hashes = ProfileHash.calculateAll(profile);
    
    return ProfileRecord(
      id: hashes.profileHash,
      profile: profile,
      metadataHash: hashes.metadataHash,
      compoundHash: hashes.compoundHash,
      parentId: parentId,
      visibility: Visibility.visible,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  /// 
  /// Note: If the profile is updated, hashes will be recalculated automatically.
  ProfileRecord copyWith({
    String? id,
    Profile? profile,
    String? metadataHash,
    String? compoundHash,
    String? parentId,
    Visibility? visibility,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    final newProfile = profile ?? this.profile;
    final hashes = ProfileHash.calculateAll(newProfile);
    
    return ProfileRecord(
      id: id ?? hashes.profileHash,
      profile: newProfile,
      metadataHash: metadataHash ?? hashes.metadataHash,
      compoundHash: compoundHash ?? hashes.compoundHash,
      parentId: parentId ?? this.parentId,
      visibility: visibility ?? this.visibility,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        id,
        profile,
        metadataHash,
        compoundHash,
        parentId,
        visibility,
        isDefault,
        createdAt,
        updatedAt,
        metadata,
      ];

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile': profile.toJson(),
      'metadataHash': metadataHash,
      'compoundHash': compoundHash,
      'parentId': parentId,
      'visibility': visibility.name,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Create from JSON
  factory ProfileRecord.fromJson(Map<String, dynamic> json) {
    return ProfileRecord(
      id: json['id'] as String,
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      metadataHash: json['metadataHash'] as String,
      compoundHash: json['compoundHash'] as String,
      parentId: json['parentId'] as String?,
      visibility: VisibilityExtension.fromString(json['visibility'] as String),
      isDefault: json['isDefault'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}
