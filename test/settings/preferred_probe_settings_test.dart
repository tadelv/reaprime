import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/settings/settings_service.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesSettingsService preferred probe settings', () {
    late SharedPreferencesSettingsService service;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      service = SharedPreferencesSettingsService();
    });

    tearDown(() {
      SharedPreferencesAsyncPlatform.instance = null;
    });

    test('preferredSteamProbeId defaults to null and round-trips', () async {
      expect(await service.preferredSteamProbeId(), isNull);

      await service.setPreferredSteamProbeId('steam-probe-1');
      expect(await service.preferredSteamProbeId(), 'steam-probe-1');

      await service.setPreferredSteamProbeId(null);
      expect(await service.preferredSteamProbeId(), isNull);
    });

    test('preferredShotProbeId defaults to null and round-trips', () async {
      expect(await service.preferredShotProbeId(), isNull);

      await service.setPreferredShotProbeId('shot-probe-1');
      expect(await service.preferredShotProbeId(), 'shot-probe-1');

      await service.setPreferredShotProbeId(null);
      expect(await service.preferredShotProbeId(), isNull);
    });

    test('combustionDefaultChannel defaults to core and round-trips', () async {
      expect(
        await service.combustionDefaultChannel(),
        CombustionConstants.channelCore,
      );

      await service.setCombustionDefaultChannel(CombustionConstants.channelT1);
      expect(
        await service.combustionDefaultChannel(),
        CombustionConstants.channelT1,
      );
    });
  });
}
