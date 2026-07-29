import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/android_updater.dart';
import 'package:reaprime/src/settings/update_dialog.dart';

void main() {
  final updateInfo = UpdateInfo(
    version: '1.2.3',
    downloadUrl: 'https://example.com/decent.apk',
    releaseNotes: '',
    isPrerelease: false,
    tagName: 'v1.2.3',
  );

  Widget dialog({
    required Future<String> Function(UpdateInfo, void Function(double))
    onDownload,
    Future<bool> Function(String)? onInstall,
  }) => MaterialApp(
    home: AndroidQuickUpdateDialog(
      updateInfo: updateInfo,
      onDownload: onDownload,
      onInstall: onInstall ?? (_) async => true,
    ),
  );

  testWidgets('shows determinate download progress and percentage', (
    tester,
  ) async {
    final download = Completer<String>();
    late void Function(double) reportProgress;

    await tester.pumpWidget(
      dialog(
        onDownload: (_, onProgress) {
          reportProgress = onProgress;
          return download.future;
        },
      ),
    );

    reportProgress(0.42);
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.42);
    expect(find.text('Downloading update… 42%'), findsOneWidget);
  });

  testWidgets('stays indeterminate when download progress is unavailable', (
    tester,
  ) async {
    final download = Completer<String>();

    await tester.pumpWidget(dialog(onDownload: (_, _) => download.future));

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNull);
    expect(find.text('Downloading update…'), findsOneWidget);
  });

  testWidgets('retry resets stale download progress', (tester) async {
    final retryDownload = Completer<String>();
    var attempts = 0;

    await tester.pumpWidget(
      dialog(
        onDownload: (_, onProgress) async {
          attempts++;
          if (attempts == 1) {
            onProgress(0.64);
            throw Exception('network failed');
          }
          return retryDownload.future;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, isNull);
    expect(find.text('Downloading update…'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('transitions from downloading to installing', (tester) async {
    final download = Completer<String>();
    final install = Completer<bool>();
    String? installedPath;

    await tester.pumpWidget(
      dialog(
        onDownload: (_, _) => download.future,
        onInstall: (path) {
          installedPath = path;
          return install.future;
        },
      ),
    );

    download.complete('/tmp/decent.apk');
    await tester.pump();

    expect(find.text('Downloading update…'), findsNothing);
    expect(find.text('Installing update…'), findsOneWidget);
    expect(installedPath, '/tmp/decent.apk');
  });
}
