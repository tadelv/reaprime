// lib/build_info.dart
class BuildInfo {
  static const String commit = String.fromEnvironment('COMMIT', defaultValue: 'unknown');
  static const String commitShort = String.fromEnvironment('COMMIT_SHORT', defaultValue: 'unknown');
  static const String branch = String.fromEnvironment('BRANCH', defaultValue: 'unknown');
  static const String buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: 'unknown'); // ISO8601
  static const String version = String.fromEnvironment('VERSION', defaultValue: '0.0.0-dev');
}
