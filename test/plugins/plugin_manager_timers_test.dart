import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_manager.dart';

import 'plugin_test_helpers.dart';

void main() {
  late PluginManager manager;

  setUp(() {
    manager = PluginManager(kvStore: FakeKeyValueStoreService());
  });

  tearDown(() {
    manager.cancelAllOperations();
  });

  Future<List<String>> collectEvents(Duration window) async {
    final events = <String>[];
    final sub = manager.emitStream.listen(
      (e) => events.add(e['event'] as String),
    );
    await Future<void>.delayed(window);
    await sub.cancel();
    return events;
  }

  String jsTimerCount() =>
      manager.js.evaluate('String(globalThis.__debugTimers.size)').stringResult;

  Future<void> loadTimerPlugin(String jsBody) async {
    await manager.loadPlugin(
      id: 'timer.plugin',
      manifest: testManifest('timer.plugin'),
      settings: {},
      jsCode:
          '''
        function createPlugin(host) {
          return {
            id: "timer.plugin",
            onLoad() {
              $jsBody
            }
          };
        }
      ''',
    );
  }

  test(
    'setTimeout fires exactly once and removes the registry entry',
    () async {
      await loadTimerPlugin('''
      setTimeout(() => host.emit("fired", "once"), 20);
    ''');

      final events = await collectEvents(const Duration(milliseconds: 300));

      expect(events, ['fired']);
      expect(manager.activeTimerCount, 0);
      expect(jsTimerCount(), '0');
    },
  );

  test('clearTimeout cancels the matching timer', () async {
    await loadTimerPlugin('''
      const id = setTimeout(() => host.emit("bad", "fired"), 20);
      clearTimeout(id);
      setTimeout(() => host.emit("good", "fired"), 60);
    ''');

    final events = await collectEvents(const Duration(milliseconds: 300));

    expect(events, ['good']);
    expect(manager.activeTimerCount, 0);
    expect(jsTimerCount(), '0');
  });

  test('plugin unload cancels armed timers', () async {
    await loadTimerPlugin('''
      setTimeout(() => host.emit("ghost", "fired"), 60);
    ''');

    await manager.unloadPlugin('timer.plugin');
    final events = await collectEvents(const Duration(milliseconds: 200));

    expect(events, isEmpty);
    expect(manager.activeTimerCount, 0);
    expect(jsTimerCount(), '0');
  });

  test('throwing callback still removes timer and registry entry', () async {
    await loadTimerPlugin('''
      setTimeout(() => { throw new Error("boom"); }, 20);
      setTimeout(() => host.emit("afterThrow", "stillFired"), 60);
    ''');

    final events = await collectEvents(const Duration(milliseconds: 300));

    expect(events, ['afterThrow']);
    expect(manager.activeTimerCount, 0);
    expect(jsTimerCount(), '0');
  });

  test('cancelAllOperations cancels multiple plugin-owned timers', () async {
    await loadTimerPlugin('''
      setTimeout(() => host.emit("a", "fired"), 1000);
      setTimeout(() => host.emit("b", "fired"), 1000);
    ''');

    expect(manager.activeTimerCount, 2);
    manager.cancelAllOperations();
    expect(manager.activeTimerCount, 0);

    final events = await collectEvents(const Duration(milliseconds: 200));

    expect(events, isEmpty);
    expect(jsTimerCount(), '0');
  });
}
