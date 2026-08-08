part of 'visualizer_plugin_test.dart';

void registerVisualizerPluginSyncCases() {
  test('upload returns its id while follow-up tag sync is stalled', () async {
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
          return await new Promise(() => {});
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''');

    final response = await _callApi(harness.manager, 'upload', {
      'shotId': 'shot-1',
    });

    expect(response['status'], 202);
    expect(jsonDecode(response['body'] as String), {
      'visualizer_id': 'visualizer-1',
      'tag_sync_pending': true,
    });
  });

  test('lost PATCH response retains ownership through retry and removal', () async {
    final harness = await _loadPlugin('''
      globalThis.__remoteTags = [];
      globalThis.__patches = [];
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-9?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-9', tags: globalThis.__remoteTags }) };
        }
        if (url.endsWith('/shots/visualizer-9') && init.method === 'PATCH') {
          const patch = JSON.parse(init.body);
          globalThis.__patches = [...globalThis.__patches, patch];
          globalThis.__remoteTags = patch.shot.tags;
          if (globalThis.__patches.length === 1) {
            return { ok: true, json: async () => { throw new Error('lost response'); } };
          }
          return { ok: true, json: async () => ({ id: 'visualizer-9', updated_at: globalThis.__patches.length }) };
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');

    void dispatchTags(List<String> tags) => _dispatchShotUpdate(
      harness.manager,
      _shot(
        annotations: {
          'extras': {'visualizerId': 'visualizer-9', 'tags': tags},
        },
      ),
      {
        'annotations': {
          'extras': {'tags': tags},
        },
      },
    );

    dispatchTags(['local-tag']);
    await _waitForJs(
      harness.manager,
      'globalThis.__testTimers.some((timer) => timer.delay === 1000) ? true : null',
    );
    harness.manager.js.evaluate('globalThis.__runTimers(1000)');
    await _waitForJs(
      harness.manager,
      'globalThis.__patches.length === 2 ? true : null',
    );

    dispatchTags(const []);
    final patches =
        await _waitForJs(
              harness.manager,
              'globalThis.__patches.length === 3 ? globalThis.__patches : null',
            )
            as List<dynamic>;

    expect(
      ((patches.last as Map<String, dynamic>)['shot'] as Map)['tags'],
      isEmpty,
    );
  });

  test('forward sync does not advance the global back-sync cursor', () async {
    final harness = await _loadPlugin(
      '''
      globalThis.__changedUrl = null;
      globalThis.__localUpdate = null;
      globalThis.fetch = async (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-b') && init.method === 'PATCH') {
          globalThis.__forwardPatch = JSON.parse(init.body);
          return { ok: true, json: async () => ({ id: 'visualizer-b', updated_at: 120 }) };
        }
        if (url.endsWith('/me')) {
          return { ok: true, json: async () => ({ id: 'user-1' }) };
        }
        if (url.includes('/shots?sort=updated_at&items=50&page=1')) {
          globalThis.__changedUrl = url;
          return { ok: true, json: async () => ({ user_id: 'user-1', data: [{ id: 'visualizer-a', updated_at: 110 }] }) };
        }
        if (url.endsWith('/shots/visualizer-a?essentials=1')) {
          return { ok: true, json: async () => ({ id: 'visualizer-a', updated_at: 110, espresso_notes: 'remote edit' }) };
        }
        if (url.endsWith('/shots/local-a') && init.method === 'PUT') {
          globalThis.__localUpdate = JSON.parse(init.body);
          return { ok: true, json: async () => ({}) };
        }
        throw new Error('Unexpected URL: ' + url + ' ' + (init.method || 'GET'));
      };
    ''',
      settings: const {'BackSync': true},
    );
    harness.manager.dispatchEvent(_manifest.id, 'storageRead', {
      'key': 'shotMap',
      'value': jsonEncode({
        'visualizer-a': 'local-a',
        'visualizer-b': 'shot-1',
      }),
    });
    harness.manager.dispatchEvent(_manifest.id, 'storageRead', {
      'key': 'backSyncCursor',
      'value': '100',
    });

    _dispatchShotUpdate(
      harness.manager,
      _shot(
        annotations: {
          'espressoNotes': 'local edit',
          'extras': {'visualizerId': 'visualizer-b'},
        },
      ),
      {
        'annotations': {'espressoNotes': 'local edit'},
      },
    );
    await _waitForJs(harness.manager, 'globalThis.__forwardPatch');
    harness.manager.js.evaluate('globalThis.__runTimers(30000)');
    final localUpdate =
        await _waitForJs(harness.manager, 'globalThis.__localUpdate')
            as Map<String, dynamic>;
    final changedUrl =
        await _waitForJs(harness.manager, 'globalThis.__changedUrl') as String;

    expect(changedUrl, contains('updated_after=100'));
    expect(localUpdate['annotations']['espressoNotes'], 'remote edit');
  });

  test('stale success drops fields untouched by a newer revision', () async {
    final harness = await _loadPlugin('''
      globalThis.__patches = [];
      globalThis.__firstResolver = null;
      globalThis.__firstStarted = false;
      globalThis.fetch = (url, init = {}) => {
        if (url.endsWith('/shots/visualizer-9?essentials=1')) {
          return Promise.resolve({ ok: true, json: async () => ({ id: 'visualizer-9', tags: [] }) });
        }
        if (url.endsWith('/shots/visualizer-9') && init.method === 'PATCH') {
          const patch = JSON.parse(init.body);
          globalThis.__patches = [...globalThis.__patches, patch];
          if (globalThis.__patches.length === 1) {
            globalThis.__firstStarted = true;
            return new Promise((resolve) => { globalThis.__firstResolver = resolve; });
          }
          return Promise.resolve({ ok: true, json: async () => ({ id: 'visualizer-9', updated_at: 2 }) });
        }
        throw new Error('Unexpected URL: ' + url);
      };
    ''');
    _dispatchShotUpdate(
      harness.manager,
      _shot(
        annotations: {
          'espressoNotes': 'local notes',
          'extras': {'visualizerId': 'visualizer-9'},
        },
      ),
      {
        'annotations': {'espressoNotes': 'local notes'},
      },
    );
    await _waitForJs(harness.manager, 'globalThis.__firstStarted');
    _dispatchShotUpdate(
      harness.manager,
      _shot(
        annotations: {
          'espressoNotes': 'local notes',
          'extras': {
            'visualizerId': 'visualizer-9',
            'tags': ['latest'],
          },
        },
      ),
      {
        'annotations': {
          'extras': {
            'tags': ['latest'],
          },
        },
      },
    );
    harness.manager.js.evaluate('''
      globalThis.__firstResolver({ ok: true, json: async () => ({ id: 'visualizer-9', updated_at: 1 }) });
    ''');
    final patches =
        await _waitForJs(
              harness.manager,
              'globalThis.__patches.length === 2 ? globalThis.__patches : null',
            )
            as List<dynamic>;
    final latest = (patches.last as Map<String, dynamic>)['shot'] as Map;

    expect(latest['tags'], ['latest']);
    expect(latest.containsKey('espresso_notes'), isFalse);
  });
}
