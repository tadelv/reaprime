# Implementation: `/api/v1/info` endpoint

**Date:** 2026-03-22  
**Branch:** `feature/info-endpoint`

## Implementation Details

### 1. InfoHandler Class (`lib/src/services/webserver/info_handler.dart`)

Simple handler that returns a JSON map of all `BuildInfo` static fields.

```dart
class InfoHandler {
  final Logger _log = Logger('InfoHandler');

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/info', _infoHandler);
  }

  Future<Response> _infoHandler(Request request) async {
    _log.fine('Handling info request');
    final info = {
      'commit': BuildInfo.commit,
      'commitShort': BuildInfo.commitShort,
      'branch': BuildInfo.branch,
      'buildTime': BuildInfo.buildTime,
      'version': BuildInfo.version,
      'buildNumber': BuildInfo.buildNumber,
      'appStore': BuildInfo.appStore,
      'fullVersion': BuildInfo.fullVersion,
    };
    return jsonOk(info);
  }
}
```

### 2. WebServer Integration (`lib/src/services/webserver_service.dart`)

- Added import: `import 'package:reaprime/src/services/webserver/info_handler.dart';`
- Instantiated in `startWebServer()`: `final infoHandler = InfoHandler();`
- Added `InfoHandler infoHandler` parameter to `_init()` signature
- Added call `infoHandler.addRoutes(app)` after other handler registrations
- Updated `_init()` call site to pass `infoHandler`

### 3. Unit Test (`test/info_handler_test.dart`)

Validates that the endpoint returns all expected fields with correct values (matching `BuildInfo` constants).

### 4. OpenAPI Spec (`assets/api/rest_v1.yml`)

Added path definition before `components:` section:

```yaml
  /api/v1/info:
    get:
      summary: Get build information
      description: Returns compile-time build information (version, commit, branch, build time, etc.)
      tags: [System]
      responses:
        "200":
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  commit:
                    type: string
                  commitShort:
                    type: string
                  branch:
                    type: string
                  buildTime:
                    type: string
                  version:
                    type: string
                  buildNumber:
                    type: string
                  appStore:
                    type: boolean
                  fullVersion:
                    type: string
```

### 5. MCP Verification Scenario (`test/mcp_scenarios/build-info.yaml`)

Scenario that starts the app with simulated devices and verifies the endpoint returns the expected fields.

## Verification Results

- ✅ Unit test passes (`flutter test test/info_handler_test.dart`)
- ✅ Static analysis passes (`flutter analyze` — only existing warnings)
- ✅ All existing webserver tests pass (`flutter test test/webserver/`)
- ⏳ MCP scenario not yet executed (requires MCP client)
- ✅ OpenAPI spec updated

## Notes

- The endpoint does not require any controllers or dependencies — it's purely static data.
- Fields match exactly the `BuildInfo` class, making it trivial to maintain.
- The `fullVersion` field is computed as `$version+$buildNumber` (same as `BuildInfo.fullVersion` getter).