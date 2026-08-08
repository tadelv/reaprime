import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/plugins/plugin_manager.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';

final _pluginSource = File(
  'assets/plugins/visualizer.reaplugin/plugin.js',
).readAsStringSync();
final _manifest = PluginManifest.fromJson(
  jsonDecode(
        File(
          'assets/plugins/visualizer.reaplugin/manifest.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

class _FakeKeyValueStore implements KeyValueStoreService {
  Map<(String, String), Object> _values = const {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> set({
    String namespace = 'default',
    required String key,
    required Object value,
  }) async {
    _values = {..._values, (namespace, key): value};
  }

  @override
  Future<bool> delete({
    String namespace = 'default',
    required String key,
  }) async {
    final storageKey = (namespace, key);
    final existed = _values.containsKey(storageKey);
    _values = Map.fromEntries(
      _values.entries.where((entry) => entry.key != storageKey),
    );
    return existed;
  }

  @override
  Future<Object?> get({
    String namespace = 'default',
    required String key,
  }) async => _values[(namespace, key)];

  @override
  Future<List<String>> keys({String namespace = 'default'}) async => _values
      .keys
      .where((key) => key.$1 == namespace)
      .map((key) => key.$2)
      .toList();

  @override
  List<String> get namespaces =>
      _values.keys.map((key) => key.$1).toSet().toList();

  @override
  Future<Map<String, Object>> getAll({String namespace = 'default'}) async =>
      Map.fromEntries(
        _values.entries
            .where((entry) => entry.key.$1 == namespace)
            .map((entry) => MapEntry(entry.key.$2, entry.value)),
      );
}

class _Harness {
  const _Harness(this.manager, this.store);

  final PluginManager manager;
  final _FakeKeyValueStore store;
}

Map<String, dynamic> _shot({
  Map<String, dynamic>? annotations,
  Map<String, dynamic>? context,
}) => {
  'id': 'shot-1',
  'annotations': annotations ?? <String, dynamic>{},
  'workflow': {
    'profile': {'target_weight': 36},
    'context': context ?? <String, dynamic>{},
  },
  'measurements': [
    for (var i = 0; i < 4; i++)
      {
        'machine': {
          'timestamp': '2026-01-01T00:00:0${i * 2}Z',
          'state': {'substate': 'pouring'},
          'profileFrame': [0, 0, 1, 2][i],
          'pressure': 9,
          'targetPressure': 9,
          'flow': 2,
          'targetFlow': 2,
          'mixTemperature': 93,
          'groupTemperature': 92,
          'targetGroupTemperature': 93,
          'targetMixTemperature': 93,
        },
        'scale': {'weight': i * 10, 'weightFlow': 2},
      },
  ],
};

Future<_Harness> _loadPlugin(
  String fetchSource, {
  _FakeKeyValueStore? store,
}) async {
  final keyValueStore = store ?? _FakeKeyValueStore();
  final manager = PluginManager(kvStore: keyValueStore);
  final setupResult = manager.js.evaluate('''
    globalThis.__testTimers = [];
    globalThis.__nextTimerId = 1;
    globalThis.__timerSet = (pluginId, generation, callback, delay = 0) => {
      if (delay === 5000) {
        callback();
        return 0;
      }
      const timer = { id: globalThis.__nextTimerId++, callback, delay };
      globalThis.__testTimers = [...globalThis.__testTimers, timer];
      return timer.id;
    };
    globalThis.__timerClear = (pluginId, id) => {
      globalThis.__testTimers = globalThis.__testTimers.filter((timer) => timer.id !== id);
    };
    globalThis.__runTimers = (delay) => {
      const ready = globalThis.__testTimers.filter((timer) => timer.delay === delay);
      globalThis.__testTimers = globalThis.__testTimers.filter((timer) => timer.delay !== delay);
      for (const timer of ready) timer.callback();
    };
    $fetchSource
    globalThis.__fetchFor = (pluginId, generation, url, init = {}) => globalThis.fetch(url, init);
  ''');
  expect(setupResult.isError, isFalse, reason: setupResult.stringResult);
  await manager.loadPlugin(
    id: _manifest.id,
    manifest: _manifest,
    settings: {
      'Username': 'user',
      'Password': 'password',
      'LengthThreshold': 0,
    },
    jsCode: _pluginSource,
  );
  addTearDown(() => manager.unloadPlugin(_manifest.id));
  return _Harness(manager, keyValueStore);
}

Future<Object?> _waitForJs(PluginManager manager, String expression) async {
  for (var i = 0; i < 500; i++) {
    manager.js.executePendingJob();
    final result = manager.js.evaluate('JSON.stringify(($expression) ?? null)');
    expect(result.isError, isFalse, reason: result.stringResult);
    final value = jsonDecode(result.stringResult);
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for JavaScript expression: $expression');
}

Future<Map<String, dynamic>> _callApi(
  PluginManager manager,
  String endpoint,
  Map<String, dynamic> body,
) async {
  const requestId = 'request-1';
  final response = manager.registerPendingHttp(_manifest.id, requestId);
  manager.dispatchEvent(_manifest.id, 'httpRequest', {
    'requestId': requestId,
    'endpoint': endpoint,
    'method': 'POST',
    'headers': <String, String>{},
    'body': body,
  });
  return response.timeout(const Duration(seconds: 5));
}

Future<Object?> _waitForStored(
  _Harness harness,
  String key,
  bool Function(Object? value) matches,
) async {
  for (var i = 0; i < 500; i++) {
    harness.manager.js.executePendingJob();
    final value = await harness.store.get(namespace: _manifest.id, key: key);
    if (matches(value)) return value;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for stored value: $key');
}

void _startAutoUpload(PluginManager manager) {
  manager.dispatchEvent(_manifest.id, 'stateUpdate', {
    'state': {'state': 'espresso'},
  });
  manager.dispatchEvent(_manifest.id, 'stateUpdate', {
    'state': {'state': 'idle'},
  });
}

void _dispatchShotUpdate(
  PluginManager manager,
  Map<String, dynamic> shot,
  Map<String, dynamic> patch,
) {
  manager.dispatchEvent(_manifest.id, 'shotUpdated', {
    'id': 'shot-1',
    'shot': shot,
    'patch': patch,
  });
}

void main() {
  test(
    'Visualizer upload encodes state_change as non-zero stage markers',
    () async {
      final shot = _shot();
      final harness = await _loadPlugin('''
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/latest')) {
          return { ok: true, json: async () => ({ id: 'shot-1' }) };
        }
        if (url.endsWith('/shots/shot-1')) {
          return { ok: true, json: async () => (${jsonEncode(shot)}) };
        }
        if (url.endsWith('/shots/upload')) {
          const start = init.body.indexOf('\\r\\n\\r\\n') + 4;
          const end = init.body.lastIndexOf('\\r\\n--');
          globalThis.__visualizerUpload = JSON.parse(init.body.slice(start, end));
          return { ok: true, json: async () => ({ id: 'visualizer-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && init.method === 'PUT') {
          return { ok: true, json: async () => ({}) };
        }
        if (url.endsWith('/shots/visualizer-1?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-1') && init.method === 'PATCH') {
          return { ok: true, json: async () => ({ id: 'visualizer-1', updated_at: 1 }) };
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');

      _startAutoUpload(harness.manager);
      final upload =
          await _waitForJs(harness.manager, 'globalThis.__visualizerUpload')
              as Map<String, dynamic>;

      expect(upload['state_change'], [1, 1, 2, 3]);
    },
  );

  test('upload PATCHes deduped recipe and review tags', () async {
    final shot = _shot(
      annotations: {
        'extras': {
          'tags': ['bright', 'floral'],
        },
      },
      context: {
        'extras': {
          'tags': ['fast shot', 'washed', 'bright'],
        },
      },
    );
    final harness = await _loadPlugin('''
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/latest')) {
          return { ok: true, json: async () => ({ id: 'shot-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && (!init.method || init.method === 'GET')) {
          return { ok: true, json: async () => (${jsonEncode(shot)}) };
        }
        if (url.endsWith('/shots/upload')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && init.method === 'PUT') {
          return { ok: true, json: async () => ({}) };
        }
        if (url.endsWith('/shots/visualizer-1?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-1') && init.method === 'PATCH') {
          globalThis.__tagPatch = JSON.parse(init.body);
          return { ok: true, json: async () => ({ id: 'visualizer-1', updated_at: 1 }) };
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''');

    _startAutoUpload(harness.manager);
    final patch =
        await _waitForJs(harness.manager, 'globalThis.__tagPatch')
            as Map<String, dynamic>;

    expect((patch['shot'] as Map<String, dynamic>)['tags'], [
      'fast shot',
      'washed',
      'bright',
      'floral',
    ]);
  });

  test(
    'upload forwards edits made in flight and only suppresses its mapping write',
    () async {
      final initialShot = _shot();
      final editedDuringUpload = _shot(
        annotations: {
          'extras': {
            'tags': ['during-upload'],
          },
        },
      );
      final editedAfterMapping = _shot(
        annotations: {
          'extras': {
            'visualizerId': 'visualizer-1',
            'tags': ['after-mapping'],
          },
        },
      );
      final harness = await _loadPlugin('''
      globalThis.__currentShot = ${jsonEncode(initialShot)};
      globalThis.__tagPatches = [];
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/latest')) {
          return { ok: true, json: async () => ({ id: 'shot-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && (!init.method || init.method === 'GET')) {
          return { ok: true, json: async () => globalThis.__currentShot };
        }
        if (url.endsWith('/shots/upload')) {
          globalThis.__uploadStarted = true;
          return await new Promise((resolve) => {
            globalThis.__finishUpload = () => resolve({
              ok: true,
              json: async () => ({ id: 'visualizer-1' }),
            });
          });
        }
        if (url.endsWith('/shots/shot-1') && init.method === 'PUT') {
          return { ok: true, json: async () => ({}) };
        }
        if (url.endsWith('/shots/visualizer-1?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-1') && init.method === 'PATCH') {
          globalThis.__tagPatches = [
            ...globalThis.__tagPatches,
            JSON.parse(init.body),
          ];
          return { ok: true, json: async () => ({ id: 'visualizer-1', updated_at: globalThis.__tagPatches.length }) };
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''');

      _startAutoUpload(harness.manager);
      await _waitForJs(harness.manager, 'globalThis.__uploadStarted');
      _dispatchShotUpdate(harness.manager, editedDuringUpload, {
        'annotations': {
          'extras': {
            'tags': ['during-upload'],
          },
        },
      });
      final finishUpload = harness.manager.js.evaluate('''
        globalThis.__currentShot = ${jsonEncode(editedDuringUpload)};
        globalThis.__finishUpload();
      ''');
      expect(finishUpload.isError, isFalse, reason: finishUpload.stringResult);
      final firstPatch =
          await _waitForJs(
                harness.manager,
                'globalThis.__tagPatches.length === 1 ? globalThis.__tagPatches[0] : null',
              )
              as Map<String, dynamic>;
      expect((firstPatch['shot'] as Map<String, dynamic>)['tags'], [
        'during-upload',
      ]);

      _dispatchShotUpdate(harness.manager, editedDuringUpload, {
        'annotations': {
          'extras': {'visualizerId': 'visualizer-1'},
        },
      });
      _dispatchShotUpdate(harness.manager, editedAfterMapping, {
        'annotations': {
          'extras': {
            'tags': ['after-mapping'],
          },
        },
      });
      final secondPatch =
          await _waitForJs(
                harness.manager,
                'globalThis.__tagPatches.length === 2 ? globalThis.__tagPatches[1] : null',
              )
              as Map<String, dynamic>;
      expect((secondPatch['shot'] as Map<String, dynamic>)['tags'], [
        'after-mapping',
      ]);
    },
  );

  test('forward sync preserves current Visualizer tags', () async {
    final harness = await _loadPlugin('''
      globalThis.__remoteTags = ['remote'];
      globalThis.__tagPatches = [];
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-9?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-9', tags: globalThis.__remoteTags }) };
        }
        if (url.endsWith('/shots/visualizer-9') && init.method === 'PATCH') {
          globalThis.__tagPatch = JSON.parse(init.body);
          globalThis.__tagPatches = [...globalThis.__tagPatches, globalThis.__tagPatch];
          globalThis.__remoteTags = globalThis.__tagPatch.shot.tags;
          return { ok: true, json: async () => ({ id: 'visualizer-9', updated_at: 1 }) };
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');
    final shot = _shot(
      annotations: {
        'extras': {
          'visualizerId': 'visualizer-9',
          'tags': ['local'],
          'visualizer': {
            'tags': ['stale-removed'],
          },
        },
      },
      context: {
        'extras': {
          'tags': ['recipe'],
        },
      },
    );

    _dispatchShotUpdate(harness.manager, shot, {
      'annotations': {
        'extras': {
          'tags': ['local'],
        },
      },
    });
    final patch =
        await _waitForJs(harness.manager, 'globalThis.__tagPatch')
            as Map<String, dynamic>;

    expect((patch['shot'] as Map<String, dynamic>)['tags'], [
      'recipe',
      'local',
      'remote',
    ]);

    _dispatchShotUpdate(
      harness.manager,
      _shot(
        annotations: {
          'extras': {'visualizerId': 'visualizer-9'},
        },
      ),
      {
        'annotations': {
          'extras': {'tags': <String>[]},
        },
        'workflow': {
          'context': {
            'extras': {'tags': <String>[]},
          },
        },
      },
    );
    final clearedPatch =
        await _waitForJs(
              harness.manager,
              'globalThis.__tagPatches.length === 2 ? globalThis.__tagPatches[1] : null',
            )
            as Map<String, dynamic>;
    expect((clearedPatch['shot'] as Map<String, dynamic>)['tags'], ['remote']);
  });

  test('ancestor replacements clear tags', () async {
    final harness = await _loadPlugin('''
      globalThis.__patches = [];
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-9?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-9', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-9') && init.method === 'PATCH') {
          globalThis.__patches = [...globalThis.__patches, JSON.parse(init.body)];
          return { ok: true, json: async () => ({ id: 'visualizer-9', updated_at: globalThis.__patches.length }) };
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');
    harness.manager.dispatchEvent(_manifest.id, 'storageRead', {
      'key': 'shotMap',
      'value': jsonEncode({'visualizer-9': 'shot-1'}),
    });
    final patches = <Map<String, dynamic>>[
      {
        'annotations': {'extras': null},
      },
      {'annotations': null},
      {
        'workflow': {
          'context': {'extras': null},
        },
      },
      {
        'workflow': {'context': null},
      },
    ];

    for (var i = 0; i < patches.length; i++) {
      _dispatchShotUpdate(harness.manager, _shot(), patches[i]);
      final sent =
          await _waitForJs(
                harness.manager,
                'globalThis.__patches.length > $i ? globalThis.__patches[$i] : null',
              )
              as Map<String, dynamic>;
      expect((sent['shot'] as Map<String, dynamic>)['tags'], isEmpty);
    }
  });

  test(
    'rapid tag edits survive a stale failure and keep the latest state',
    () async {
      final harness = await _loadPlugin('''
      globalThis.__requests = [];
      globalThis.__resolvers = [];
      globalThis.fetch = (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-9?essentials=1')) {
          return Promise.resolve({ ok: true, json: async () => ({ id: 'visualizer-9', tags: [] }) });
        }
        if (url.endsWith('/shots/visualizer-9') && init.method === 'PATCH') {
          globalThis.__requests = [...globalThis.__requests, JSON.parse(init.body)];
          return new Promise((resolve) => {
            globalThis.__resolvers = [...globalThis.__resolvers, resolve];
          });
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');
      Map<String, dynamic> shotWithTag(String tag) => _shot(
        annotations: {
          'extras': {
            'visualizerId': 'visualizer-9',
            'tags': [tag],
          },
        },
      );
      Map<String, dynamic> patchWithTag(String tag) => {
        'annotations': {
          'extras': {
            'tags': [tag],
          },
        },
      };

      _dispatchShotUpdate(
        harness.manager,
        shotWithTag('old'),
        patchWithTag('old'),
      );
      await _waitForJs(
        harness.manager,
        'globalThis.__requests.length === 1 ? true : null',
      );
      _dispatchShotUpdate(
        harness.manager,
        shotWithTag('latest'),
        patchWithTag('latest'),
      );
      harness.manager.js.evaluate('''
      globalThis.__resolvers[0]({
        ok: false,
        status: 400,
        statusText: 'Bad Request',
        text: async () => 'stale request',
      });
    ''');
      final requests =
          await _waitForJs(
                harness.manager,
                'globalThis.__requests.length === 2 ? globalThis.__requests : null',
              )
              as List<dynamic>;
      final second = requests[1] as Map<String, dynamic>;
      expect((second['shot'] as Map<String, dynamic>)['tags'], ['latest']);
      harness.manager.js.evaluate('''
      globalThis.__resolvers[1]({
        ok: true,
        json: async () => ({ id: 'visualizer-9', updated_at: 2 }),
      });
    ''');
      expect(
        await _waitForStored(
          harness,
          'pendingLocalSync',
          (value) => value == '{}',
        ),
        '{}',
      );
    },
  );

  test('partial upload preserves its id and retries tag sync', () async {
    final shot = _shot(
      annotations: {
        'extras': {
          'tags': ['bright'],
        },
      },
    );
    final harness = await _loadPlugin('''
      globalThis.__patchFails = true;
      globalThis.__patchAttempts = 0;
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/shot-1') && (!init.method || init.method === 'GET')) {
          return {
            ok: true,
            json: async () => (${jsonEncode(shot)}),
            text: async () => '${jsonEncode(shot)}',
          };
        }
        if (url.endsWith('/shots/upload')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && init.method === 'PUT') {
          return { ok: true, json: async () => ({}) };
        }
        if (url.endsWith('/shots/visualizer-1?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-1') && init.method === 'PATCH') {
          globalThis.__patchAttempts++;
          if (globalThis.__patchFails) {
            return {
              ok: false,
              status: 503,
              statusText: 'Service Unavailable',
              text: async () => 'retry',
            };
          }
          return { ok: true, json: async () => ({ id: 'visualizer-1', updated_at: 2 }) };
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''');

    final response = await _callApi(harness.manager, 'upload', {
      'shotId': 'shot-1',
    });
    final body = jsonDecode(response['body'] as String) as Map<String, dynamic>;

    expect(response['status'], 202);
    expect(body, {'visualizer_id': 'visualizer-1', 'tag_sync_pending': true});
    expect(
      await _waitForStored(
        harness,
        'lastVisualizerId',
        (value) => value == 'visualizer-1',
      ),
      'visualizer-1',
    );
    final shotMap =
        await _waitForStored(
              harness,
              'shotMap',
              (value) => value is String && value.contains('visualizer-1'),
            )
            as String;
    expect(jsonDecode(shotMap), {'visualizer-1': 'shot-1'});
    final pending =
        await _waitForStored(
              harness,
              'pendingLocalSync',
              (value) => value is String && value.contains('bright'),
            )
            as String;
    expect(
      ((jsonDecode(pending) as Map<String, dynamic>)['visualizer-1']
          as Map<String, dynamic>)['update'],
      {
        'tags': ['bright'],
      },
    );
    expect(
      await _waitForJs(
        harness.manager,
        'globalThis.__testTimers.length > 0 ? globalThis.__testTimers.map((timer) => timer.delay) : null',
      ),
      contains(1000),
    );
    final syncStatusResponse = await _callApi(
      harness.manager,
      'forwardSyncStatus',
      {},
    );
    final syncStatus =
        jsonDecode(syncStatusResponse['body'] as String)
            as Map<String, dynamic>;
    expect(syncStatus['running'], isEmpty);
    expect(syncStatus['pending'], ['visualizer-1']);

    final retryResult = harness.manager.js.evaluate('''
      globalThis.__patchFails = false;
      globalThis.__runTimers(1000);
    ''');
    expect(retryResult.isError, isFalse, reason: retryResult.stringResult);
    expect(
      await _waitForJs(
        harness.manager,
        'globalThis.__patchAttempts === 2 ? globalThis.__patchAttempts : null',
      ),
      2,
    );
    final cleared = await _waitForStored(
      harness,
      'pendingLocalSync',
      (value) => value == '{}',
    );
    expect(cleared, '{}');
  });

  test(
    'permanent tag failure returns partial success with upload id',
    () async {
      final shot = _shot(
        annotations: {
          'extras': {
            'tags': ['bright'],
          },
        },
      );
      final harness = await _loadPlugin('''
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/shot-1') && (!init.method || init.method === 'GET')) {
          return {
            ok: true,
            json: async () => (${jsonEncode(shot)}),
            text: async () => '${jsonEncode(shot)}',
          };
        }
        if (url.endsWith('/shots/upload')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1' }) };
        }
        if (url.endsWith('/shots/shot-1') && init.method === 'PUT') {
          return { ok: true, json: async () => ({}) };
        }
        if (url.endsWith('/shots/visualizer-1?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-1', tags: [] }) };
        }
        if (url.endsWith('/shots/visualizer-1') && init.method === 'PATCH') {
          return {
            ok: false,
            status: 400,
            statusText: 'Bad Request',
            text: async () => 'invalid tags',
          };
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''');

      final response = await _callApi(harness.manager, 'upload', {
        'shotId': 'shot-1',
      });
      final body =
          jsonDecode(response['body'] as String) as Map<String, dynamic>;

      expect(response['status'], 207);
      expect(body['visualizer_id'], 'visualizer-1');
      expect(body['tag_sync_error'], contains('HTTP 400'));
    },
  );

  test('plugin source and manifest versions match', () {
    final sourceVersion = RegExp(
      r'version:\s*"([^"]+)"',
    ).firstMatch(_pluginSource)?.group(1);

    expect(sourceVersion, _manifest.version);
  });
}
