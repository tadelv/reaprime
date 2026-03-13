import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_loader_service.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';

class FakeKvStore implements KeyValueStoreService {
  final Map<String, Map<String, Object>> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> set({
    String namespace = 'default',
    required String key,
    required Object value,
  }) async {
    _store.putIfAbsent(namespace, () => {})[key] = value;
  }

  @override
  Future<bool> delete({String namespace = 'default', required String key}) async {
    return _store[namespace]?.remove(key) != null;
  }

  @override
  Future<Object?> get({String namespace = 'default', required String key}) async {
    return _store[namespace]?[key];
  }

  @override
  Future<List<String>> keys({String namespace = 'default'}) async {
    return _store[namespace]?.keys.toList() ?? [];
  }

  @override
  List<String> get namespaces => _store.keys.toList();

  @override
  Future<Map<String, Object>> getAll({String namespace = 'default'}) async {
    return Map.from(_store[namespace] ?? {});
  }
}

void main() {
  group('PluginLoaderService App Store mode', () {
    test('addPlugin throws UnsupportedError when appStoreMode is true', () {
      final service = PluginLoaderService(
        kvStore: FakeKvStore(),
        appStoreMode: true,
      );

      expect(
        () => service.addPlugin('/some/path'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('addPlugin does not throw UnsupportedError when appStoreMode is false', () {
      final service = PluginLoaderService(
        kvStore: FakeKvStore(),
        appStoreMode: false,
      );

      // Should not throw UnsupportedError — will throw a different error
      // because the path doesn't exist and the service isn't initialized,
      // but it should NOT be an UnsupportedError.
      expect(
        () => service.addPlugin('/nonexistent/path'),
        throwsA(isNot(isA<UnsupportedError>())),
      );
    });
  });
}
