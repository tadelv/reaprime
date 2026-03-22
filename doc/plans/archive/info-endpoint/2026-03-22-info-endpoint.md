# Plan: Add `/api/v1/info` endpoint

**Date:** 2026-03-22  
**Branch:** `feature/info-endpoint`  
**Status:** Implemented, needs verification

## Overview

Add a new REST endpoint to expose compile-time build information from `BuildInfo` class.

## Decisions

- **Endpoint path:** `/api/v1/info`
- **HTTP method:** GET
- **Response fields:** All static fields from `BuildInfo`:
  - `commit` (full SHA)
  - `commitShort` (short SHA)
  - `branch`
  - `buildTime` (ISO8601)
  - `version` (semver)
  - `buildNumber` (string)
  - `appStore` (boolean)
  - `fullVersion` (computed: `$version+$buildNumber`)
- **No runtime/platform info** (keep compile‑time only)

## Test Tiers

1. **Unit:** `InfoHandler` unit test (in `test/info_handler_test.dart`)
2. **Integration:** Not needed (single‑handler endpoint)
3. **MCP verification:** Scenario `test/mcp_scenarios/build-info.yaml`

## Implementation Steps

1. Create `InfoHandler` class in `lib/src/services/webserver/info_handler.dart`
2. Register handler in `webserver_service.dart`
   - Add import
   - Instantiate in `startWebServer`
   - Add parameter to `_init` signature
   - Call `infoHandler.addRoutes(app)`
3. Write unit test (`test/info_handler_test.dart`)
4. Update OpenAPI spec (`assets/api/rest_v1.yml`)
5. Create MCP verification scenario (`test/mcp_scenarios/build-info.yaml`)
6. Run tests, analyze, verify

## Files Changed

- `lib/src/services/webserver/info_handler.dart` (new)
- `lib/src/services/webserver_service.dart` (modified)
- `test/info_handler_test.dart` (new)
- `assets/api/rest_v1.yml` (modified)
- `test/mcp_scenarios/build-info.yaml` (new)

## Verification Checklist

- [x] Unit test passes (`flutter test test/info_handler_test.dart`)
- [x] Static analysis passes (`flutter analyze`)
- [x] All existing webserver tests pass (`flutter test test/webserver/`)
- [ ] MCP scenario passes (requires running app with `--dart-define=simulate=1`)
- [x] OpenAPI spec updated and valid