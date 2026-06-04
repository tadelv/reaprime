import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';

void main() {
  group('De1HeaterVoltage.fromInt', () {
    test('normalizes measured regional voltages to canonical settings', () {
      expect(De1HeaterVoltage.fromInt(110), De1HeaterVoltage.v110);
      expect(De1HeaterVoltage.fromInt(120), De1HeaterVoltage.v110);
      expect(De1HeaterVoltage.fromInt(220), De1HeaterVoltage.v220);
      expect(De1HeaterVoltage.fromInt(230), De1HeaterVoltage.v220);
    });

    test('normalizes committed voltage markers before classifying', () {
      expect(De1HeaterVoltage.fromInt(1110), De1HeaterVoltage.v110);
      expect(De1HeaterVoltage.fromInt(1120), De1HeaterVoltage.v110);
      expect(De1HeaterVoltage.fromInt(1220), De1HeaterVoltage.v220);
      expect(De1HeaterVoltage.fromInt(1230), De1HeaterVoltage.v220);
    });

    test('leaves unknown values unset', () {
      expect(De1HeaterVoltage.fromInt(0), De1HeaterVoltage.unset);
      expect(De1HeaterVoltage.fromInt(170), De1HeaterVoltage.unset);
    });
  });
}
