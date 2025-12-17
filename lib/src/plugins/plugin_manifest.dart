class PluginManifest {
  final String id;
  final String name;
  final String author;
  final String version;
  final int apiVersion;
  final Set<String> permissions;
  final Map<String, dynamic> settings;

  PluginManifest({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.apiVersion,
    required this.permissions,
    required this.settings,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'],
      name: json['name'],
      author: json['author'],
      version: json['version'],
      apiVersion: json['apiVersion'],
      permissions: Set<String>.from(json['permissions'] ?? []),
      settings: json['settings'] ?? {},
    );
  }
}
