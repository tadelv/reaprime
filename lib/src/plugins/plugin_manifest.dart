class PluginManifest {
  final String id;
  final String version;
  final int apiVersion;
  final Set<String> permissions;

  PluginManifest({
    required this.id,
    required this.version,
    required this.apiVersion,
    required this.permissions,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'],
      version: json['version'],
      apiVersion: json['apiVersion'],
      permissions: Set<String>.from(json['permissions'] ?? []),
    );
  }
}
