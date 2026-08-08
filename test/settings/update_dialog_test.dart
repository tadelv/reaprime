import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/settings/update_dialog.dart';

void main() {
  final updateInfo = UpdateInfo(
    version: '1.2.3',
    downloadUrl: 'https://example.com/decent.apk',
    releaseNotes: '## Internal Markdown\n- implementation detail',
    isPrerelease: false,
    tagName: 'v1.2.3',
  );

  testWidgets('shows determinate download progress and percentage', (
    tester,
  ) async {
    final download = Completer<String>();

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateDialog(
          updateInfo: updateInfo,
          currentVersion: '1.2.2',
          onViewReleaseNotes: () {},
          onDownload: (info, onProgress) {
            onProgress(0.42);
            return download.future;
          },
          onInstall: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.text('Download'));
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.42);
    expect(find.text('Downloading update… 42%'), findsOneWidget);
  });

  testWidgets('opens GitHub release notes instead of rendering raw Markdown', (
    tester,
  ) async {
    var viewReleaseNotesCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateDialog(
          updateInfo: updateInfo,
          currentVersion: '1.2.2',
          onViewReleaseNotes: () => viewReleaseNotesCalls++,
          onDownload: (_, _) async => '/tmp/decent.apk',
          onInstall: (_) async => true,
        ),
      ),
    );

    expect(find.textContaining('Internal Markdown'), findsNothing);

    await tester.tap(find.text("What's new"));
    await tester.pump();

    expect(viewReleaseNotesCalls, 1);
  });
}
