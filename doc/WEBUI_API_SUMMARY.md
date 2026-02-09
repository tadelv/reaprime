# WebUI Skin Management API - Implementation Summary

## Overview

We've successfully implemented a complete REST API for managing WebUI skins in Streamline-Bridge, allowing users to install, list, and remove custom web-based user interfaces without recompiling the app.

## What Was Implemented

### 1. Enhanced WebUIStorage with GitHub Release Support

**File:** `lib/src/webui_support/webui_storage.dart`

**New Features:**
- Support for three source types: `github_release`, `github_branch`, and `url`
- GitHub Release API integration for semantic versioning
- Automatic version detection and update checking
- Content-based deduplication via metadata tracking

**New Methods:**
- `installFromGitHubRelease()` - Public API for installing from releases
- `_installFromGitHubRelease()` - Internal method with full GitHub API integration
- Enhanced `downloadRemoteSkins()` to support all three source types

**Configuration Example:**
```dart
static const List<Map<String, dynamic>> _remoteWebUISources = [
  {
    'type': 'github_branch',
    'repo': 'allofmeng/streamline_project',
    'branch': 'main',
  },
];
```

### 2. REST API Handler for WebUI Management

**File:** `lib/src/services/webserver/webui_handler.dart`

**Endpoints Implemented:**

#### GET /api/v1/webui/skins
List all installed WebUI skins with metadata.

**Response:**
```json
[
  {
    "id": "my-skin-id",
    "name": "My Skin",
    "path": "/path/to/skin",
    "description": "Skin description",
    "version": "1.0.0",
    "isBundled": false,
    "reaMetadata": {
      "skinId": "my-skin-id",
      "sourceUrl": "github_release:username/repo@v1.0.0",
      "commitHash": "v1.0.0",
      "installedAt": "2026-02-09T10:00:00Z"
    }
  }
]
```

#### GET /api/v1/webui/skins/{id}
Get details for a specific skin.

#### GET /api/v1/webui/skins/default
Get the default skin.

#### POST /api/v1/webui/skins/install/github-release
Install from GitHub Release.

**Request Body:**
```json
{
  "repo": "username/my-skin-repo",
  "asset": "my-skin.zip",
  "prerelease": false
}
```

#### POST /api/v1/webui/skins/install/github-branch
Install from GitHub branch.

**Request Body:**
```json
{
  "repo": "username/my-skin-repo",
  "branch": "main"
}
```

#### POST /api/v1/webui/skins/install/url
Install from direct URL.

**Request Body:**
```json
{
  "url": "https://example.com/skin.zip"
}
```

#### DELETE /api/v1/webui/skins/{id}
Remove user-installed skin (bundled skins cannot be removed).

### 3. Webserver Integration

**File:** `lib/src/services/webserver_service.dart`

- Added `WebUIStorage` parameter to `startWebServer()`
- Created and registered `WebUIHandler`
- Added routes to the API router

**File:** `lib/main.dart`

- Updated `startWebServer()` call to pass `webUIStorage` instance

### 4. API Documentation

**File:** `assets/api/rest_v1.yml`

Added complete OpenAPI 3.0 documentation for all WebUI endpoints:
- Path definitions with request/response schemas
- Schema definitions for `WebUISkin` and `WebUIReaMetadata`
- Tagged under `[WebUI]` for organization

### 5. Comprehensive Documentation

**File:** `Skins.md`

Added extensive "Skin Development & Deployment" section covering:
- Understanding skin distribution methods
- Local development workflow (Next.js, React, Vue, Svelte examples)
- Production deployment via GitHub Releases
- Alternative distribution branch approach
- Version management and update detection
- Best practices for skin development
- Framework-specific configurations
- Complete troubleshooting guide
- Full Next.js project example with GitHub Actions

**File:** `.github/SKIN_DEPLOYMENT_GUIDE.md`

Created quick-start guide with:
- Complete GitHub Actions workflow templates
- Configuration instructions for all deployment methods
- Best practices and testing procedures
- API reference for WebUIStorage methods

## Usage Examples

### For Developers (Local Development)

```bash
# Develop your skin
npm run dev

# Build for testing
npm run build

# Install via API
curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-branch \
  -H "Content-Type: application/json" \
  -d '{"repo": "username/my-skin-repo", "branch": "dev"}'
```

### For Production (GitHub Releases)

1. **Create GitHub Actions workflow** (`.github/workflows/release.yml`)
2. **Tag and push release:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. **Install via API:**
   ```bash
   curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-release \
     -H "Content-Type: application/json" \
     -d '{"repo": "username/my-skin-repo"}'
   ```

### For Users (Testing Skins)

```bash
# List installed skins
curl http://localhost:8080/api/v1/webui/skins

# Install a skin from GitHub
curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-release \
  -H "Content-Type: application/json" \
  -d '{"repo": "somedev/cool-skin"}'

# Remove a skin
curl -X DELETE http://localhost:8080/api/v1/webui/skins/cool-skin
```

## Benefits

1. **No Recompilation Required**: Users can install and test skins via REST API
2. **Professional Distribution**: GitHub Releases provide semantic versioning and proper software distribution
3. **Automatic Updates**: Remote bundled skins check for updates on app startup
4. **Version Tracking**: Full metadata tracking for all installed skins
5. **Flexible Sources**: Support for releases, branches, and direct URLs
6. **Developer-Friendly**: Clear documentation and examples for all frameworks

## Architecture

### Skin Storage Flow

```
User/API Request
    ↓
WebUIHandler (REST endpoint)
    ↓
WebUIStorage (download & install)
    ↓
GitHub API or HTTP GET
    ↓
Extract ZIP to web-ui/{id}/
    ↓
Update .rea_metadata.json
    ↓
Mark as bundled/user-installed
```

### Version Detection Flow

```
App Startup
    ↓
WebUIStorage.downloadRemoteSkins()
    ↓
For each source in _remoteWebUISources:
    ├─ github_release: Check GitHub API for latest tag
    ├─ github_branch: Check HTTP headers (ETag/Last-Modified)
    └─ url: Check HTTP headers (ETag/Last-Modified)
    ↓
Compare with installed version
    ↓
Download if different
    ↓
Update .rea_metadata.json
```

## Configuration

### Hardcoded Bundled Skins

Edit `lib/src/webui_support/webui_storage.dart`:

```dart
static const List<Map<String, dynamic>> _remoteWebUISources = [
  {
    'type': 'github_branch',
    'repo': 'allofmeng/streamline_project',
    'branch': 'main',
  },
  // Add more skins here
];
```

These skins:
- Auto-download on first startup
- Check for updates on subsequent startups
- Cannot be removed by users
- Are marked as "bundled" in metadata

## Testing

### Test the API

```bash
# Start Streamline-Bridge
./flutter_with_commit.sh run

# Test listing skins
curl http://localhost:8080/api/v1/webui/skins

# Test installing from GitHub branch (for development)
curl -X POST http://localhost:8080/api/v1/webui/skins/install/github-branch \
  -H "Content-Type: application/json" \
  -d '{"repo": "yourusername/test-skin", "branch": "main"}'

# Verify installation
curl http://localhost:8080/api/v1/webui/skins
```

## Future Enhancements

Possible improvements:
- WebSocket notifications for skin installation progress
- Skin update notifications
- Skin marketplace/registry
- Automatic rollback on installation failure
- Skin compatibility checking (API version requirements)
- Multi-skin selection in UI

## Summary

This implementation provides a complete, production-ready system for managing WebUI skins in Streamline-Bridge. Users can now:

1. **Install skins via REST API** without recompiling
2. **Use GitHub Releases** for professional version management
3. **Develop locally** and test via API
4. **Automatic updates** for bundled skins
5. **Full version tracking** with metadata

The system is flexible, well-documented, and follows best practices for software distribution.
