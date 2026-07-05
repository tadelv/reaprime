import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/app_update_state.dart';

void main() {
  group('AppUpdateState', () {
    test('toJson emits phase name and all fields', () {
      const state = AppUpdateState(
        phase: AppUpdatePhase.available,
        currentVersion: '0.6.1',
        latestVersion: '0.6.2',
        releaseNotes: 'notes',
        releaseUrl: 'https://github.com/tadelv/reaprime/releases/tag/v0.6.2',
        installable: true,
        progress: null,
        error: null,
      );

      expect(state.toJson(), {
        'phase': 'available',
        'currentVersion': '0.6.1',
        'latestVersion': '0.6.2',
        'releaseNotes': 'notes',
        'releaseUrl': 'https://github.com/tadelv/reaprime/releases/tag/v0.6.2',
        'installable': true,
        'progress': null,
        'error': null,
      });
    });

    test('idle snapshot keeps nullable fields null', () {
      const state = AppUpdateState(
        phase: AppUpdatePhase.idle,
        currentVersion: '0.6.1',
        releaseUrl: 'https://github.com/tadelv/reaprime/releases',
        installable: false,
      );

      final json = state.toJson();
      expect(json['phase'], 'idle');
      expect(json['latestVersion'], isNull);
      expect(json['progress'], isNull);
      expect(json['error'], isNull);
      expect(json['installable'], false);
    });

    test('copyWith overrides only provided fields', () {
      const base = AppUpdateState(
        phase: AppUpdatePhase.available,
        currentVersion: '0.6.1',
        latestVersion: '0.6.2',
        releaseUrl: 'https://example/tag',
        installable: true,
      );

      final downloading = base.copyWith(
        phase: AppUpdatePhase.downloading,
        progress: 0.5,
      );

      expect(downloading.phase, AppUpdatePhase.downloading);
      expect(downloading.progress, 0.5);
      expect(downloading.latestVersion, '0.6.2');
      expect(downloading.installable, true);
    });
  });
}
