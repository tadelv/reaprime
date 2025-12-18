import 'package:collection/collection.dart';

class PluginManifest {
  final String id;
  final String name;
  final String author;
  final String description;
  final String version;
  final int apiVersion;
  final Set<PluginPermissions> permissions;
  final Map<String, dynamic> settings;
  final PluginApi? api;

  PluginManifest({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.version,
    required this.apiVersion,
    required this.permissions,
    required this.settings,
    required this.api,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'],
      name: json['name'],
      author: json['author'],
      description: json['description'],
      version: json['version'],
      apiVersion: json['apiVersion'],
      permissions: PluginPermissionsFromJson.fromJson(json['permissions']),
      settings: json['settings'] ?? {},
      api: json['api'] != null ? PluginApi.fromJsonList(json['api']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'author': author,
      'description': description,
      'version': version,
      'apiVersion': apiVersion,
      'permissions': permissions.map((e) => e.name).toList(),
      'settings': settings,
      'api': api?.toJson(),
    };
  }
}

enum PluginPermissions {
  log,
  emit,
  api,
  pluginStorage,
  shotsStorage;

  static PluginPermissions? fromString(String value) {
    return PluginPermissions.values.firstWhereOrNull((e) => e.name == value);
  }
}

extension PluginPermissionsFromJson on PluginPermissions {
  static Set<PluginPermissions> fromJson(dynamic json) {
    if (json is! List<dynamic>) {
      return <PluginPermissions>{};
    }
    final rawPermissions = Set<String>.from(json);
    return rawPermissions.fold(<PluginPermissions>[], (acc, e) {
      final perm = PluginPermissions.fromString(e);
      if (perm != null) {
        acc.add(perm);
      }
      return acc;
    }).toSet();
  }
}

final class PluginApi {
  PluginApi();
  factory PluginApi.fromJsonList(List<dynamic> json) {
    return PluginApi();
  }

  Map<String, dynamic> toJson() {
    return {};
  }
}
