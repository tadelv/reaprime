import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';

/// Parses de1app profiles_v2 JSON into a [ProfileRecord].
///
/// The v2 profile JSON format is compatible with Bridge's [Profile.fromJson],
/// so this is a thin wrapper that handles the conversion and hash generation.
class ProfileV2Parser {
  static ProfileRecord parse(Map<String, dynamic> json) {
    final profile = Profile.fromJson(json);
    return ProfileRecord.create(profile: profile);
  }
}
