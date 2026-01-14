import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

class Bengle extends UnifiedDe1 implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";
}
