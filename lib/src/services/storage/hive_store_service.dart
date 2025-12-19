import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';

class HiveStoreService implements KeyValueStoreService {
  final String defaultNamespace;
  final Map<String, Box> _boxes = {};
  HiveStoreService({required this.defaultNamespace});

  @override
  Future<bool> delete({String? namespace, required String key}) async {
    final box = await _getOrCreateNamespace(namespace ?? defaultNamespace);
    await box.delete(key);
    return true;
  }

  @override
  Future<Object?> get({String? namespace, required String key}) async {
    final box = await _getOrCreateNamespace(namespace ?? defaultNamespace);
    return await box.get(key);
  }

  @override
  Future<void> initialize() async {
    await Hive.initFlutter("store");
    _boxes["default"] = await Hive.openBox(defaultNamespace);
  }

  @override
  Future<List<String>> keys({String? namespace }) async {
    final box = await _getOrCreateNamespace(namespace ?? defaultNamespace);
    return box.keys.map((e) => e.toString()).toList();
  }

  @override
  Future<void> set({
    String? namespace ,
    required String key,
    required Object value,
  }) async {
    final box = await _getOrCreateNamespace(namespace ?? defaultNamespace);
    await box.put(key, value);
  }

  Future<Box> _getOrCreateNamespace(String namespace) async {
    if (_boxes.containsKey(namespace)) {
      return _boxes[namespace]!;
    }
    _boxes[namespace] = await Hive.openBox(namespace);
    return _boxes[namespace]!;
  }
}
