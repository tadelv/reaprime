import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_hash.dart';

/// Guards the curated bundled default profiles (issue #242): every manifest
/// entry parses, no leftover Visualizer/import cruft in titles or notes, and no
/// two profiles share execution content (which would collide on the content-hash
/// id and silently drop one at seed time).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> files;
  final profiles = <String, Profile>{};
  final raw = <String, Map<String, dynamic>>{};

  setUpAll(() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/defaultProfiles/manifest.json'),
    ) as Map<String, dynamic>;
    files = (manifest['profiles'] as List).cast<String>();
    for (final f in files) {
      final json = jsonDecode(
        await rootBundle.loadString('assets/defaultProfiles/$f'),
      ) as Map<String, dynamic>;
      raw[f] = json;
      profiles[f] = Profile.fromJson(json);
    }
  });

  test('manifest is non-empty and every entry parses', () {
    expect(files, isNotEmpty);
    expect(profiles.length, files.length);
  });

  test('notes carry no Visualizer/import boilerplate', () {
    for (final entry in profiles.entries) {
      final notes = entry.value.notes;
      expect(notes.contains('Downloaded from'), isFalse, reason: entry.key);
      expect(notes.toLowerCase().contains('visualizer'), isFalse,
          reason: entry.key);
    }
  });

  test('titles carry no leftover category prefix', () {
    final prefix = RegExp(r'^(Visualizer|Espresso)/');
    for (final entry in profiles.entries) {
      expect(prefix.hasMatch(entry.value.title), isFalse,
          reason: '${entry.value.title} (${entry.key})');
    }
  });

  test('no two profiles share execution content (no hash collisions)', () {
    final byHash = <String, String>{};
    for (final entry in profiles.entries) {
      final hash = ProfileHash.calculateProfileHash(entry.value);
      final clash = byHash[hash];
      expect(clash, isNull,
          reason: 'identical content: ${entry.key} == $clash');
      byHash[hash] = entry.key;
    }
  });

  test('the four Baseline variants are present with canonical titles', () {
    final titles = profiles.values.map((p) => p.title).toSet();
    expect(titles, containsAll(<String>[
      'Baseline • Ultra Low Contact',
      'Baseline • Low Contact • 4 Bar',
      'Baseline • Medium Contact • 6 Bar',
      'Baseline • High Contact • 8 Bar',
    ]));
  });

  // A `pressure`/`flow` typed profile is settings_2a/2b in de1app, and its frames
  // are derived from the profile's scalars rather than copied from the stored
  // `advanced_shot`. Rationale in doc/AI_STORAGE_NOTES.md.
  group('derived profiles agree with their own scalars', () {
    // The full vocabulary either generator can emit. `empty` is de1app's
    // all-durations-zero fallback and is deliberately absent: no bundled profile
    // should ship one, and whitelisting it here would bless a corpus that did.
    const pressureFrameNames = {
      'preinfusion temp boost',
      'preinfusion',
      'forced rise without limit',
      'rise and hold',
      'decline',
    };
    const flowFrameNames = {
      'preinfusion boost',
      'preinfusion',
      'hold',
      'decline',
    };
    const maxTemperatureSpread = 10.0;
    const brewTemperatureRange = (min: 75.0, max: 100.0);

    // Pinned, not discovered. `derived()` reads the profile's own `type`, so a
    // profile misclassified as `advanced` would silently exempt itself from every
    // check below — which is exactly the shape of the bug being guarded against.
    const expectedDerived = {
      '7g_basket.json',
      'Classic_Italian_espresso.json',
      'Default1.json',
      'Flow_profile_for_milky_drinks.json',
      'Flow_profile_for_straight_espresso.json',
      'Gentle_and_sweet1.json',
      'Preinfuse_then_45ml_of_water.json',
      'Traditional_lever_machine.json',
      'Trendy_6_bar_low_pressure_shot.json',
      'Two_spring_lever_machine_to_9_bar.json',
      'manual_flow.json',
      'manual_pressure.json',
    };

    // The stop target each of these must brew to. de1app resolves these from the
    // plain `final_desired_shot_weight`/`_volume` for legacy types; reading the
    // `_advanced` spelling instead is what made Classic Italian stop at 60 g.
    const expectedTargets = {
      '7g_basket.json': (weight: 35.0, volume: 36.0),
      'Classic_Italian_espresso.json': (weight: 36.0, volume: 36.0),
      'Default1.json': (weight: 36.0, volume: 36.0),
      'Gentle_and_sweet1.json': (weight: 36.0, volume: 36.0),
      'Preinfuse_then_45ml_of_water.json': (weight: 36.0, volume: 36.0),
    };

    Iterable<MapEntry<String, Map<String, dynamic>>> derived(String type) =>
        raw.entries.where((e) => e.value['type'] == type);

    test('exactly the expected profiles are derived', () {
      final actual = {
        ...derived('pressure').map((e) => e.key),
        ...derived('flow').map((e) => e.key),
      };

      expect(actual, equals(expectedDerived),
          reason: 'a profile entering or leaving the derived set changes which '
              'files the checks below cover; update the list deliberately');
    });

    test('derived profiles stop where de1app stops', () {
      for (final entry in expectedTargets.entries) {
        final profile = profiles[entry.key];
        expect(profile, isNotNull, reason: '${entry.key} is not bundled');
        expect(profile!.targetWeight, equals(entry.value.weight),
            reason: '${entry.key} target weight');
        expect(profile.targetVolume, equals(entry.value.volume),
            reason: '${entry.key} target volume');
      }
    });

    test('frames come only from the generator vocabulary', () {
      for (final type in const ['pressure', 'flow']) {
        final allowed = type == 'pressure' ? pressureFrameNames : flowFrameNames;
        for (final entry in derived(type)) {
          for (final step in profiles[entry.key]!.steps) {
            expect(allowed, contains(step.name),
                reason: '${entry.key} ($type) ships frame "${step.name}", '
                    'which no $type generator produces — the stored '
                    'advanced_shot was copied instead of derived');
          }
        }
      }
    });

    // Two independent bounds. The spread catches a stale array mixing hot and cold
    // frames (`Default` spanned 36 C); the absolute range catches one that is
    // uniformly wrong, which a spread check alone would pass.
    test('no two frames differ by more than 10 C', () {
      for (final type in const ['pressure', 'flow']) {
        for (final entry in derived(type)) {
          final temperatures =
              profiles[entry.key]!.steps.map((s) => s.temperature).toList();
          if (temperatures.isEmpty) continue;
          final hottest = temperatures.reduce((a, b) => a > b ? a : b);
          final coldest = temperatures.reduce((a, b) => a < b ? a : b);

          expect(hottest - coldest, lessThanOrEqualTo(maxTemperatureSpread),
              reason: '${entry.key} spans ${coldest}C to ${hottest}C across its '
                  'frames, which no set of temperature presets produces');
        }
      }
    });

    test('every frame brews within a plausible temperature range', () {
      for (final type in const ['pressure', 'flow']) {
        for (final entry in derived(type)) {
          for (final step in profiles[entry.key]!.steps) {
            expect(step.temperature,
                inInclusiveRange(
                    brewTemperatureRange.min, brewTemperatureRange.max),
                reason: '${entry.key} frame "${step.name}" brews at '
                    '${step.temperature}C');
          }
        }
      }
    });

    test('the pump driving each frame matches the profile type', () {
      // A derived pressure profile preinfuses on the flow pump and does
      // everything after that on the pressure pump; a derived flow profile
      // never leaves the flow pump.
      for (final entry in derived('pressure')) {
        for (final step in profiles[entry.key]!.steps) {
          final flowPumped = step.name.startsWith('preinfusion');
          expect(step is ProfileStepFlow, equals(flowPumped),
              reason: '${entry.key} frame "${step.name}" is driven by the '
                  'wrong pump for a derived pressure profile');
        }
      }
      for (final entry in derived('flow')) {
        for (final step in profiles[entry.key]!.steps) {
          expect(step, isA<ProfileStepFlow>(),
              reason: '${entry.key} frame "${step.name}" is not on the flow '
                  'pump in a flow profile');
        }
      }
    });
  });

  // D5's ordering hazard: `_parseBeverageType` falls back to espresso, so shipping a
  // corpus value the enum does not know turns 13 tea profiles into espresso silently.
  // Asserting the raw string round-trips catches that for every bundled profile,
  // rather than only for the values this change happened to add.
  test('every bundled beverage type survives parsing', () {
    for (final entry in raw.entries) {
      final wire = entry.value['beverage_type'] as String;

      expect(BeverageType.tryParse(wire), isNotNull,
          reason: '${entry.key} carries beverage_type "$wire", which no '
              'BeverageType accepts — it would parse as espresso');
      expect(profiles[entry.key]!.beverageType.wireName, equals(wire),
          reason: '${entry.key} does not round-trip its beverage type');
    }
  });

  test('the tea and filter profiles kept their de1app types', () {
    final byType = <String, int>{};
    for (final p in profiles.values) {
      byType[p.beverageType.wireName] = (byType[p.beverageType.wireName] ?? 0) + 1;
    }

    expect(byType['tea_portafilter'], equals(12));
    expect(byType['tea'], equals(1));
    expect(byType['filter'], equals(2));
  });

  test('every manifest entry has recorded provenance', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/defaultProfiles/manifest.json'),
    ) as Map<String, dynamic>;
    final provenance = manifest['provenance'] as Map<String, dynamic>?;

    expect(provenance, isNotNull,
        reason: 'manifest records no provenance at all');
    for (final f in files) {
      expect(provenance!.containsKey(f), isTrue,
          reason: 'no provenance recorded for $f');
      expect((provenance[f] as Map)['source'], isNotNull, reason: f);
    }
  });
}
