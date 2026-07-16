import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/firmware/bundled_firmware_catalog.dart';
import 'package:reaprime/src/services/firmware/firmware_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production bundle contains valid build 1352 firmware', () async {
    final catalog = BundledFirmwareCatalog(bundle: rootBundle);
    final manifest = await catalog.loadManifest();

    expect(manifest.entries, hasLength(1));
    final entry = manifest.entries.single;
    expect(entry.artifact.id, 'de1-1352');
    expect(entry.artifact.build, 1352);
    expect(
      entry.artifact.supportedModels,
      {'DE1Pro', 'DE1XL', 'DE1XXL', 'DE1XXXL'},
    );

    final image = await catalog.loadImage(entry.artifact.id);
    const FirmwareValidator().validate(entry, image);
    await catalog.verifyAllArtifacts();
  });
}
