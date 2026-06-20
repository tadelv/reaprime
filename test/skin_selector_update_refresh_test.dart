import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/skin_selector/skin_selector_page.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'helpers/mock_settings_service.dart';

/// Minimal stand-in: never serving, so the page renders the "Check for Skin
/// Updates" control.
class _FakeWebUIService extends Fake implements WebUIService {
  @override
  bool get isServing => false;
}

/// Stand-in storage whose single installed skin reports a newer version after
/// [downloadRemoteSkins] runs — mirroring a real update check that bumps the
/// on-disk skin from 0.2.2 to 0.2.3 and re-scans the registry.
class _FakeWebUIStorage extends Fake implements WebUIStorage {
  _FakeWebUIStorage(this._version);

  String _version;
  int downloadCount = 0;

  WebUISkin get _skin => WebUISkin(
        id: 'streamline.js',
        name: 'Streamline',
        path: '/tmp/streamline.js',
        version: _version,
        isBundled: true,
      );

  @override
  List<WebUISkin> get installedSkins => [_skin];

  @override
  WebUISkin? get defaultSkin => _skin;

  @override
  WebUISkin? getSkin(String id) => id == _skin.id ? _skin : null;

  @override
  Future<void> downloadRemoteSkins() async {
    downloadCount++;
    _version = '0.2.3';
  }
}

void main() {
  testWidgets(
    'skins list refreshes to the new version after "Check for Skin Updates" '
    '(issue #370)',
    (tester) async {
      final storage = _FakeWebUIStorage('0.2.2');

      await tester.pumpWidget(
        ShadApp(
          // The production app provides a ScaffoldMessenger above the page
          // (app.dart); the page's update-check snackbars require one.
          home: ScaffoldMessenger(
            child: SkinSelectorPage(
              settingsController: SettingsController(MockSettingsService()),
              webUIService: _FakeWebUIService(),
              webUIStorage: storage,
            ),
          ),
        ),
      );
      await tester.pump();

      // The dropdown shows the currently-installed version up front.
      expect(find.textContaining('0.2.2'), findsOneWidget);
      expect(find.textContaining('0.2.3'), findsNothing);

      final updateButton = find.text('Check for Skin Updates');
      await tester.ensureVisible(updateButton);
      await tester.tap(updateButton);
      await tester.pump(); // run the async handler + its setState
      await tester.pump(const Duration(milliseconds: 300)); // settle snackbar

      // Storage actually ran the update...
      expect(storage.downloadCount, 1);
      // ...and the list now reflects the new version without leaving the page.
      expect(find.textContaining('0.2.3'), findsOneWidget);
      expect(find.textContaining('0.2.2'), findsNothing);
    },
  );
}
