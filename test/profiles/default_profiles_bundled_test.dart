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
  // `advanced_shot`. de1app writes that array out of the global ::settings, so a
  // copied one routinely describes a different shot entirely — which is how
  // `Default` came to ship 75 C and 54 C frames against a declared 90 C.
  //
  // Two things follow from derivation, and both are checked here: the frames can
  // only be the ones the generator emits, and their temperatures can only be the
  // profile's own four temperature presets, which sit within a few degrees.
  group('derived profiles agree with their own scalars', () {
    const pressureFrameNames = {
      'preinfusion temp boost',
      'preinfusion',
      'forced rise without limit',
      'rise and hold',
      'decline',
      'empty',
    };
    const flowFrameNames = {
      'preinfusion boost',
      'preinfusion',
      'hold',
      'decline',
      'empty',
    };
    const maxTemperatureSpread = 10.0;

    Iterable<MapEntry<String, Map<String, dynamic>>> derived(String type) =>
        raw.entries.where((e) => e.value['type'] == type);

    test('bundled corpus contains derived profiles to check', () {
      expect(derived('pressure').isNotEmpty || derived('flow').isNotEmpty, isTrue,
          reason: 'no pressure/flow typed profile found — has `type` moved?');
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

    test('no frame temperature contradicts the declared brew temperature', () {
      for (final type in const ['pressure', 'flow']) {
        for (final entry in derived(type)) {
          final temperatures =
              profiles[entry.key]!.steps.map((s) => s.temperature).toList();
          if (temperatures.isEmpty) continue;
          final hottest = temperatures.reduce((a, b) => a > b ? a : b);
          final coldest = temperatures.reduce((a, b) => a < b ? a : b);

          expect(hottest - coldest, lessThanOrEqualTo(maxTemperatureSpread),
              reason: '${entry.key} spans ${coldest}C to ${hottest}C across its '
                  'frames; a derived profile only uses its four temperature '
                  'presets, so this frame temperature contradicts the profile');
        }
      }
    });

    test('the pump driving each frame matches the profile type', () {
      // A derived pressure profile preinfuses on the flow pump and does
      // everything after that on the pressure pump; a derived flow profile
      // never leaves the flow pump.
      for (final entry in derived('pressure')) {
        for (final step in profiles[entry.key]!.steps) {
          final flowPumped =
              step.name.startsWith('preinfusion') || step.name == 'empty';
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
