# WebUI Skin Deployment Guide

## Overview

Streamline-Bridge now supports multiple methods for deploying and distributing WebUI skins, with enhanced support for **GitHub Releases** as the recommended production deployment method.

## Deployment Methods

### 1. GitHub Releases (Recommended for Production)

GitHub Releases provide the cleanest and most professional distribution method:

**Benefits:**
- Semantic versioning via Git tags (v1.0.0, v1.2.3, etc.)
- Automatic update detection based on release tags
- Clean separation of source code vs. distribution files
- Release notes and changelog support
- Proper asset management with download counts
- Professional software distribution workflow

**Setup:**

Create `.github/workflows/release.yml` in your skin repository:

```yaml
name: Build and Release WebUI Skin

on:
  push:
    tags:
      - 'v*'  # Trigger on version tags
  workflow_dispatch:

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'
          
      - name: Install dependencies
        run: npm ci
        
      - name: Build Next.js app
        run: npm run build
        
      - name: Create manifest.json
        run: |
          cat > out/manifest.json << EOF
          {
            "id": "my-skin-id",
            "name": "My Skin Name",
            "description": "Skin description",
            "version": "${{ github.ref_name }}",
            "author": "Your Name",
            "repository": "${{ github.repository }}"
          }
          EOF
      
      - name: Create release archive
        run: |
          cd out
          zip -r ../my-skin-${{ github.ref_name }}.zip .
          cd ..
          
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: my-skin-${{ github.ref_name }}.zip
          tag_name: ${{ github.ref_name }}
          name: Release ${{ github.ref_name }}
          draft: false
          prerelease: false
          generate_release_notes: true
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Usage:**

```bash
# Create and push a version tag
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions automatically:
# 1. Builds your skin
# 2. Creates manifest.json
# 3. Packages as ZIP
# 4. Creates GitHub Release
```

### 2. Distribution Branch

Alternative to releases, use a separate `dist` branch:

```yaml
name: Build to Dist Branch

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          
      - name: Build
        run: |
          npm ci
          npm run build
          
      - name: Deploy to dist branch
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./out
          publish_branch: dist
          force_orphan: true
```

### 3. Direct URL

Any publicly accessible ZIP file can be used.

## Configuring Streamline-Bridge

### Auto-Download Bundled Skins

Edit `lib/src/webui_support/webui_storage.dart`:

```dart
static const List<Map<String, dynamic>> _remoteWebUISources = [
  // GitHub Release (recommended)
  {
    'type': 'github_release',
    'repo': 'username/my-skin-repo',
    'asset': 'my-skin.zip',  // Optional: specific asset name
    'prerelease': false,      // Optional: include pre-releases
  },
  
  // GitHub Branch Archive
  {
    'type': 'github_branch',
    'repo': 'username/my-skin-repo',
    'branch': 'dist',
  },
  
  // Direct URL
  {
    'type': 'url',
    'url': 'https://example.com/skin.zip',
  },
];
```

**What happens:**
- Skins are downloaded on first app startup
- Updates are checked on subsequent startups
- For GitHub releases: checks for new release tags
- For URLs: uses HTTP ETag/Last-Modified headers
- Only downloads if remote version has changed
- These skins are marked as "bundled" (cannot be removed by users)

### User-Installable Skins

Skins can also be installed dynamically:

```dart
// From GitHub Release
await webUIStorage.installFromGitHubRelease(
  'username/my-skin-repo',
  assetName: 'my-skin.zip',  // Optional
  includePrerelease: false,   // Optional
);

// From GitHub Branch
await webUIStorage.installFromGitHub('username/repo', branch: 'main');

// From URL
await webUIStorage.installFromUrl('https://example.com/skin.zip');

// From Local Path
await webUIStorage.installFromPath('/path/to/skin/directory');
```

## Version Management

### Metadata Tracking

Streamline-Bridge tracks skin metadata in `.rea_metadata.json`:

```json
{
  "my-skin-id": {
    "skinId": "my-skin-id",
    "sourceUrl": "github_release:username/repo@v1.2.0",
    "commitHash": "v1.2.0",
    "lastModified": "2026-02-09T10:00:00Z",
    "installedAt": "2026-02-09T10:00:00Z",
    "lastChecked": "2026-02-09T12:00:00Z"
  }
}
```

### Update Detection

**GitHub Releases:**
- Compares installed release tag with latest release tag
- Downloads new release if tags differ
- Provides clean semantic versioning

**GitHub Branches:**
- Uses HTTP ETag/Last-Modified headers
- Updates when branch changes

**Direct URLs:**
- Uses HTTP ETag/Last-Modified headers
- Updates when remote file changes

## Best Practices

### 1. Always Include manifest.json

```json
{
  "id": "my-skin-id",
  "name": "Beautiful Espresso UI",
  "description": "Modern skin with real-time visualization",
  "version": "1.2.0",
  "author": "Your Name",
  "repository": "https://github.com/username/repo"
}
```

### 2. Use Semantic Versioning

- `v1.0.0` - Initial release
- `v1.1.0` - New features, backward compatible
- `v1.1.1` - Bug fixes
- `v2.0.0` - Breaking changes

### 3. Test Before Release

```bash
# Build locally
npm run build

# Test build output
npx serve out

# Verify all assets load
# Test WebSocket connections
# Create manifest.json
# THEN create release tag
```

### 4. Configure for Static Export

**Next.js** (`next.config.js`):
```javascript
module.exports = {
  output: 'export',
  images: { unoptimized: true }
}
```

**Vite** (`vite.config.js`):
```javascript
export default {
  base: './',
  build: {
    outDir: 'dist',
    assetsDir: 'assets'
  }
}
```

## Local Development

During development, you don't need to create releases:

```bash
# Option 1: Serve locally and connect to gateway
npm run dev
# Access at http://localhost:3000
# Connect to gateway at http://<gateway-ip>:8080

# Option 2: Copy build to app documents
npm run build
cp -r ./out ~/Library/Containers/com.example.reaprime/Data/Documents/web-ui/my-skin-id/

# Option 3: Install via Dart code
await webUIStorage.installFromPath('/path/to/my-skin/out');
```

## Troubleshooting

### Release Not Found
- Ensure you've created at least one release with a .zip asset
- Check GitHub repository has releases enabled
- Verify asset is actually a .zip file

### Updates Not Detected
- For releases: New release tag must be created
- For branches: Commit changes and push
- Force re-download: delete skin directory and restart app

### Assets Not Loading
- Ensure static export is configured correctly
- Check browser console for 404 errors
- Verify `index.html` is at root of skin directory

## Complete Example

See `Skins.md` for a complete Next.js example with:
- Project structure
- GitHub Actions workflow
- Next.js configuration
- API client setup
- Deployment instructions

## API Reference

### WebUIStorage Methods

```dart
// Install from GitHub Release
Future<void> installFromGitHubRelease(
  String repo, {
  String? assetName,
  bool includePrerelease = false,
});

// Install from GitHub Branch
Future<void> installFromGitHub(
  String repo, {
  String branch = 'main',
});

// Install from URL
Future<void> installFromUrl(String url);

// Install from local path
Future<void> installFromPath(String sourcePath);

// Get installed skins
List<WebUISkin> get installedSkins;

// Get default skin
WebUISkin? get defaultSkin;

// Remove skin (only user-installed, not bundled)
Future<void> removeSkin(String skinId);
```

## Summary

**For Production:**
- Use GitHub Releases with semantic versioning
- Configure GitHub Actions for automated builds
- Include proper manifest.json with metadata

**For Development:**
- Use local dev server (`npm run dev`)
- Or copy build output to web-ui directory
- Connect to gateway API via environment variables

**For Auto-Updates:**
- Add skin to `_remoteWebUISources` array
- Choose type: `github_release`, `github_branch`, or `url`
- Streamline-Bridge handles download and update checking
