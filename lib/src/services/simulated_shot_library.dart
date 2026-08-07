import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';

/// Bundled corpus of real recorded shots the simulator replays, converted from
/// de1app's `simulations/*.shot` into native historical-shot JSON. Loaded once
/// from `assets/simulations/` and handed to [MockDe1] so each simulated shot
/// replays a genuine pull instead of synthesizing telemetry.
class SimulatedShotLibrary {
  SimulatedShotLibrary({
    AssetBundle? bundle,
    this.manifestPath = 'assets/simulations/manifest.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String manifestPath;
  final _log = Logger('SimulatedShotLibrary');

  final List<ShotRecord> _shots = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isEmpty => _shots.isEmpty;
  int get length => _shots.length;
  List<ShotRecord> get shots => List.unmodifiable(_shots);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final manifest =
          jsonDecode(await _bundle.loadString(manifestPath))
              as Map<String, dynamic>;
      final directory = manifestPath.substring(
        0,
        manifestPath.lastIndexOf('/') + 1,
      );
      for (final entry in (manifest['shots'] as List).cast<String>()) {
        try {
          final raw = await _bundle.loadString('$directory$entry');
          _shots.add(
            ShotRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        } catch (e) {
          _log.warning('failed to load simulation shot $entry: $e');
        }
      }
    } catch (e) {
      _log.warning('no simulation manifest at $manifestPath: $e');
    }
    _loaded = true;
  }

  ShotRecord? pickRandom([Random? random]) {
    if (_shots.isEmpty) return null;
    return _shots[(random ?? Random()).nextInt(_shots.length)];
  }
}
