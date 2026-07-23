import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Visualizer state_change uses profile frame indices', () {
    final source = File(
      'assets/plugins/visualizer.reaplugin/plugin.js',
    ).readAsStringSync();

    expect(
      source,
      contains('visualizerShot.state_change.push(machine.profileFrame);'),
    );
  });
}
