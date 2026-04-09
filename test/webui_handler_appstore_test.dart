import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// A fake WebUIStorage that tracks install calls without touching the filesystem.
class FakeWebUIStorage extends Fake implements WebUIStorage {
  bool installFromGitHubReleaseCalled = false;
  bool installFromGitHubCalled = false;
  bool installFromUrlCalled = false;

  @override
  Future<void> installFromGitHubRelease(
    String repo, {
    String? assetName,
    bool includePrerelease = false,
  }) async {
    installFromGitHubReleaseCalled = true;
  }

  @override
  Future<void> installFromGitHub(String repo,
      {String branch = 'main'}) async {
    installFromGitHubCalled = true;
  }

  @override
  Future<void> installFromUrl(String url) async {
    installFromUrlCalled = true;
  }
}

void main() {
  late FakeWebUIStorage fakeStorage;

  setUp(() {
    fakeStorage = FakeWebUIStorage();
  });

  Handler buildHandler({required bool appStoreMode}) {
    final webUIHandler = WebUIHandler(
      storage: fakeStorage,
      service: WebUIService(),
      appStoreMode: appStoreMode,
    );
    final app = Router().plus;
    webUIHandler.addRoutes(app);
    return app.call;
  }

  Future<Response> sendPost(
      Handler handler, String path, Map<String, dynamic> body) async {
    return await handler(
      Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  group('WebUIHandler App Store mode', () {
    group('when appStoreMode is true', () {
      late Handler handler;

      setUp(() {
        handler = buildHandler(appStoreMode: true);
      });

      test('POST /api/v1/webui/skins/install/github-release returns 403',
          () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/github-release',
          {'repo': 'user/repo'},
        );
        expect(response.statusCode, 403);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], contains('not available'));
        expect(fakeStorage.installFromGitHubReleaseCalled, isFalse);
      });

      test('POST /api/v1/webui/skins/install/github-branch returns 403',
          () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/github-branch',
          {'repo': 'user/repo'},
        );
        expect(response.statusCode, 403);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], contains('not available'));
        expect(fakeStorage.installFromGitHubCalled, isFalse);
      });

      test('POST /api/v1/webui/skins/install/url returns 403', () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/url',
          {'url': 'https://example.com/skin.zip'},
        );
        expect(response.statusCode, 403);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], contains('not available'));
        expect(fakeStorage.installFromUrlCalled, isFalse);
      });
    });

    group('when appStoreMode is false', () {
      late Handler handler;

      setUp(() {
        handler = buildHandler(appStoreMode: false);
      });

      test(
          'POST /api/v1/webui/skins/install/github-release calls storage method',
          () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/github-release',
          {'repo': 'user/repo'},
        );
        expect(response.statusCode, isNot(403));
        expect(fakeStorage.installFromGitHubReleaseCalled, isTrue);
      });

      test(
          'POST /api/v1/webui/skins/install/github-branch calls storage method',
          () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/github-branch',
          {'repo': 'user/repo'},
        );
        expect(response.statusCode, isNot(403));
        expect(fakeStorage.installFromGitHubCalled, isTrue);
      });

      test('POST /api/v1/webui/skins/install/url calls storage method',
          () async {
        final response = await sendPost(
          handler,
          '/api/v1/webui/skins/install/url',
          {'url': 'https://example.com/skin.zip'},
        );
        expect(response.statusCode, isNot(403));
        expect(fakeStorage.installFromUrlCalled, isTrue);
      });
    });
  });
}
