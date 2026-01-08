import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:uuid/uuid.dart';

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
@immutable
class ProfileRecord extends Equatable {
  /// Unique identifier for this profile record
  final String id;

  /// The actual profile data
  final Profile profile;

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
    this.parentId,
    this.visibility = Visibility.visible,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  /// Create a new profile record with generated ID and timestamps
  factory ProfileRecord.create({
    required Profile profile,
    String? parentId,
    bool isDefault = false,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now();
    return ProfileRecord(
      id: const Uuid().v4(),
      profile: profile,
      parentId: parentId,
      visibility: Visibility.visible,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
      metadata: metadata,
    );
  }

  /// Create a copy with updated fields
  ProfileRecord copyWith({
    String? id,
    Profile? profile,
    String? parentId,
    Visibility? visibility,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return ProfileRecord(
      id: id ?? this.id,
      profile: profile ?? this.profile,
      parentId: parentId ?? this.parentId,
      visibility: visibility ?? this.visibility,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profile': profile.toJson(),
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
      parentId: json['parentId'] as String?,
      visibility: VisibilityExtension.fromString(json['visibility'] as String),
      isDefault: json['isDefault'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        profile,
        parentId,
        visibility,
        isDefault,
        createdAt,
        updatedAt,
        metadata,
      ];
}
