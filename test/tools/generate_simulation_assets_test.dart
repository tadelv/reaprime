import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/import/parsers/tcl_shot_parser.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';

/// The DE1 reports at ~5 Hz through de1app and the source shots inherit that
/// irregular cadence. MockDe1 streams at 100 ms, so the recordings are
/// resampled onto a uniform 10 Hz grid here (linear interpolation of the
/// continuous channels; the discrete state/frame carried from the sample at or
/// before each grid point) so replay draws smoothly.
const _resampleMs = 100;

double _lerp(double a, double b, double f) => a + (b - a) * f;

List<ShotSnapshot> _resampleTo10Hz(List<ShotSnapshot> src) {
  if (src.length < 2) return src;
  final origin = src.first.machine.timestamp;
  final elapsed = src
      .map((s) => s.machine.timestamp.difference(origin).inMicroseconds / 1e6)
      .toList();
  final lastElapsed = elapsed.last;

  final out = <ShotSnapshot>[];
  var lo = 0;
  for (var k = 0; ; k++) {
    final t = k * _resampleMs / 1000.0;
    if (t > lastElapsed + 1e-9) break;
    while (lo < elapsed.length - 2 && elapsed[lo + 1] < t) {
      lo++;
    }
    final hi = (lo + 1).clamp(0, src.length - 1);
    final span = elapsed[hi] - elapsed[lo];
    final f = span <= 0 ? 0.0 : ((t - elapsed[lo]) / span).clamp(0.0, 1.0);
    final a = src[lo];
    final b = src[hi];
    final ts = origin.add(Duration(microseconds: (t * 1e6).round()));

    final machine = a.machine.copyWith(
      timestamp: ts,
      flow: _lerp(a.machine.flow, b.machine.flow, f),
      pressure: _lerp(a.machine.pressure, b.machine.pressure, f),
      targetFlow: _lerp(a.machine.targetFlow, b.machine.targetFlow, f),
      targetPressure: _lerp(
        a.machine.targetPressure,
        b.machine.targetPressure,
        f,
      ),
      mixTemperature: _lerp(
        a.machine.mixTemperature,
        b.machine.mixTemperature,
        f,
      ),
      groupTemperature: _lerp(
        a.machine.groupTemperature,
        b.machine.groupTemperature,
        f,
      ),
      targetMixTemperature: _lerp(
        a.machine.targetMixTemperature,
        b.machine.targetMixTemperature,
        f,
      ),
      targetGroupTemperature: _lerp(
        a.machine.targetGroupTemperature,
        b.machine.targetGroupTemperature,
        f,
      ),
      steamTemperature: _lerp(
        a.machine.steamTemperature.toDouble(),
        b.machine.steamTemperature.toDouble(),
        f,
      ).round(),
    );

    WeightSnapshot? scale;
    if (a.scale != null && b.scale != null) {
      scale = WeightSnapshot(
        timestamp: ts,
        weight: _lerp(a.scale!.weight, b.scale!.weight, f),
        weightFlow: _lerp(a.scale!.weightFlow, b.scale!.weightFlow, f),
      );
    } else {
      scale = a.scale;
    }

    out.add(ShotSnapshot(machine: machine, scale: scale, volume: a.volume));
  }
  return out;
}

/// Guards — and, on demand, regenerates — the bundled simulator replay corpus.
///
/// Source of truth: de1app's `simulations/simulated_{1,2,3}.shot`, copied into
/// `tool/simulation_sources/`. Each is converted through decaid's own
/// [TclShotParser] into native historical-shot JSON under `assets/simulations/`.
///
/// By default this only asserts the committed assets still parse (safe in CI).
/// To rebuild the assets after changing the sources, run:
///   REGEN_SIM_ASSETS=1 flutter test test/tools/generate_simulation_assets_test.dart
void main() {
  const sourceDir = 'tool/simulation_sources';
  const outputDir = 'assets/simulations';
  final regenerate = Platform.environment['REGEN_SIM_ASSETS'] == '1';

  test('bundled simulation assets parse into ShotRecords', () {
    final manifest =
        jsonDecode(File('$outputDir/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final files = (manifest['shots'] as List).cast<String>();
    expect(files, isNotEmpty);
    for (final file in files) {
      final shot = ShotRecord.fromJson(
        jsonDecode(File('$outputDir/$file').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(
        shot.measurements,
        isNotEmpty,
        reason: '$file has no measurements',
      );
    }
  });

  test(
    'regenerate bundled simulation shots',
    () {
      final sources =
          Directory(sourceDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.shot'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      expect(sources, isNotEmpty, reason: 'no source .shot files found');

      Directory(outputDir).createSync(recursive: true);
      final manifest = <String>[];

      for (final source in sources) {
        final stem = source.uri.pathSegments.last.replaceAll('.shot', '');
        final parsed = TclShotParser.parse(source.readAsStringSync());
        final shot = parsed.shot.copyWith(
          measurements: _resampleTo10Hz(parsed.shot.measurements),
        );

        final json = shot.toJson();
        json['id'] = 'sim-$stem';
        final workflow = json['workflow'];
        if (workflow is Map) {
          workflow['id'] = 'sim-$stem-workflow';
          // TclShotParser leaves the profile step list empty (it does not
          // reconstruct the de1app advanced_shot frames). Replay drives telemetry
          // from the recorded samples, not the profile, but ShotRecord.fromJson
          // requires a non-empty step list. Inject one representative step built
          // from the recorded frame-0 targets so the asset round-trips.
          final measurements = shot.measurements;
          final first = measurements.first.machine;
          final durationSeconds =
              measurements.last.machine.timestamp
                  .difference(first.timestamp)
                  .inMilliseconds /
              1000.0;
          final replayStep = ProfileStepPressure(
            name: 'Replay',
            transition: TransitionType.fast,
            volume: 0,
            seconds: durationSeconds,
            temperature: first.targetGroupTemperature > 0
                ? first.targetGroupTemperature
                : 90,
            sensor: TemperatureSensor.coffee,
            pressure: first.targetPressure > 0 ? first.targetPressure : 9,
          );
          final profile = workflow['profile'];
          if (profile is Map) {
            profile['steps'] = [replayStep.toJson()];
          }
        }

        final roundTripped = ShotRecord.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        );
        expect(roundTripped.measurements, isNotEmpty);

        final fileName = '$stem.json';
        File(
          '$outputDir/$fileName',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
        manifest.add(fileName);
      }

      File('$outputDir/manifest.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'shots': manifest}),
      );
    },
    skip: regenerate ? false : 'set REGEN_SIM_ASSETS=1 to rebuild assets',
  );
}
