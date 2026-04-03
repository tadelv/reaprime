import 'package:reaprime/src/import/parsers/tcl_parser.dart';
import 'package:reaprime/src/models/data/grinder.dart';

/// Parses DYE's grinders.tdb file into a list of [Grinder] entities.
///
/// The TDB format has one entry per line:
///   ModelName {setting_type TYPE small_step N big_step N burrs {DESC}}
///
/// Top-level keys are grinder model names; values are maps with:
///   - setting_type (numeric | preset)
///   - small_step
///   - big_step
///   - burrs
class GrinderTdbParser {
  static List<Grinder> parse(String content) {
    final data = TclParser.parse(content);
    final grinders = <Grinder>[];

    for (final entry in data.entries) {
      final model = entry.key;
      final specs = entry.value;
      if (specs is! Map<String, dynamic>) continue;

      grinders.add(
        Grinder.create(
          model: model,
          burrs: specs['burrs']?.toString(),
          settingType: specs['setting_type']?.toString() == 'numeric'
              ? GrinderSettingType.numeric
              : GrinderSettingType.preset,
          settingSmallStep: double.tryParse(
            specs['small_step']?.toString() ?? '',
          ),
          settingBigStep: double.tryParse(
            specs['big_step']?.toString() ?? '',
          ),
        ),
      );
    }

    return grinders;
  }
}
