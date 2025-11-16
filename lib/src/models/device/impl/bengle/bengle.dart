import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.dart';

class Bengle extends De1 implements BengleInterface {
  Bengle({required super.deviceId});

  Bengle.withDevice({required super.device}): super.withDevice();

  @override
  String get name => "Bengle";
}
