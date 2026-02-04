# Streamline Bridge

> **Streamline Bridge** is a gateway application for Decent Espresso machines, providing an API-first approach to building modern and sleek user interfaces. It enables developers to focus on creating delightful experiences while handling all the complexity of machine communication, state management, and device connectivity.

## Table of Contents

- [Features](#features)
- [API Documentation](#api-documentation)
- [Supported Platforms](#supported-platforms)
- [WebUI / Skins](#webui--skins)
- [Supported Operations](#supported-operations)
- [Plugins](#plugins)
- [Building](#building)
- [System Requirements](#system-requirements)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

## Features

- **REST API** for machine control, settings, and shot management
- **WebSocket streams** for real-time updates (shot progress, weight, temperature)
- **Profile management** with content-based hashing and automatic deduplication
- **Auto-connect** to preferred devices on startup
- **Gateway modes** for flexible control delegation
- **Plugin system** for extensibility
- **WebUI support** with multiple skins
- **Cross-platform** support (Android, macOS, Linux, Windows, iOS)

## API Documentation

To browse the complete API documentation:

1. Start Streamline Bridge
2. Navigate to [http://localhost:4001](http://localhost:4001)

The API provides:
- **REST endpoints** on port `8080`
- **WebSocket streams** for real-time data
- **Plugin HTTP endpoints** for custom integrations

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| **Android** | ✅ Primary | Runs on Decent Espresso tablets |
| **macOS** | ✅ Full support | Desktop development and testing |
| **Linux** | ✅ Full support | ARM64 and x86_64 |
| **Windows** | ✅ Full support | Desktop operation |
| **iOS** | ⚠️ Experimental | Limited testing |

### Background Operation

On Android, Streamline Bridge can run as a foreground service, maintaining stable connections to your machine and scale while tucked away in the background.

## WebUI / Skins

Similar to the original DE1 app, Streamline Bridge supports loading and displaying different "skins" (web-based UIs).

### Accessing Skins

- **Network access**: From any device on your local network at `http://<device-ip>:3000`
- **In-app WebView**: On supported platforms, use the embedded browser to access skins directly

### Android WebView Compatibility

**Note for Teclast tablets**: Some older Android System WebView versions may cause display issues with the in-app skin view.

**Solutions:**
1. Update Android System WebView from [APKMirror](https://www.apkmirror.com/apk/google-inc/android-system-webview/)
2. Restart your device after updating
3. Use an external browser if issues persist (the app will automatically detect incompatible WebViews)

## Supported Operations

### Machine Operations

- ✅ Query and control machine state (power on/off, start/stop espresso)
- ✅ Configure machine settings (temperatures, flow rates, timeouts)
- ✅ Upload v2 JSON profiles (compatible with DE1 app `profiles_v2` format)
- ✅ Real-time shot telemetry via WebSocket
- ✅ Advanced settings management

### Scale Operations

- ✅ Tare scale
- ✅ Real-time weight updates via WebSocket
- ✅ Auto-stop shots at target weight
- ✅ Power management (auto-disconnect/display-off when machine sleeps)

#### Supported Scales

- **Felicita Arc**
- **Decent Scale**
- **Bookoo Mini Scale**

### Workflow Management

- ✅ Create and save multi-step workflows
- ✅ Set target weight for automatic shot stopping
- ✅ Profile selection per workflow

### Additional Features

- ✅ **Auto-connect**: Set preferred devices for automatic connection on startup
- ✅ **Gateway modes**: 
  - **Disabled**: Full local control
  - **Tracking**: Monitor and stop at target weight
  - **Full**: Complete remote control
- ✅ **Shot history**: Save and export shot data
- ✅ **Device simulation**: Test without physical hardware

## Plugins

Streamline Bridge features a JavaScript plugin system for dynamic functionality expansion.

**Capabilities:**
- React to machine state changes
- Make HTTP requests
- Store persistent data
- Emit custom events
- Serve custom HTTP endpoints

**Bundled Plugins:**
- `settings.reaplugin`: Web-based settings dashboard
- `time-to-ready.reaplugin`: Machine warm-up notifications
- `visualizer.reaplugin`: Real-time shot visualization

📖 **[Read the Plugin Development Guide →](/Plugins.md)**

## Building

### Prerequisites

- **Flutter SDK**: Version 3.7.0 or later
- **Platform-specific tools**:
  - Android: Android Studio / SDK
  - macOS: Xcode
  - Linux: Standard build tools
  - Windows: Visual Studio

### Development Build

The project includes a build script that injects version information from Git:

```bash
./flutter_with_commit.sh run
```

For standard Flutter builds:

```bash
flutter run
```

### Linux ARM64 (Docker/Colima)

Build for ARM64 tablets using containers:

```bash
# Start Colima with ARM64 profile
make colima-arm

# Build
make build-arm
```

For x86_64:

```bash
make colima-amd
make build-amd
```

Build both architectures:

```bash
make dual-build
```

## System Requirements

### Minimum Requirements

- **Android**: 8.0 (API 26) or later
- **macOS**: 10.14 or later
- **Linux**: Modern distribution with GTK 3.0+
- **Windows**: Windows 10 or later

### Recommended

- **RAM**: 2GB+ available
- **Storage**: 500MB for app + skins
- **Network**: Local WiFi network for skin access
- **Bluetooth**: Bluetooth 4.0+ for device connectivity

## Troubleshooting

### WebView Issues (Android)

**Problem**: Blank screen or rendering artifacts in skin view

**Solutions**:
1. Update Android System WebView
2. Clear app data and restart
3. Use external browser option (Settings → Auto-detected)

### Connection Issues

**Problem**: Cannot connect to machine or scale

**Solutions**:
1. Verify Bluetooth is enabled
2. Check device permissions (Location, Bluetooth)
3. Try "Scan Again" in device selection
4. Check if device is already connected to another app

### Auto-Connect Not Working

**Problem**: Preferred device doesn't auto-connect

**Solutions**:
1. Verify device ID is correct (Settings → Auto-Connect Device)
2. Ensure device is powered on during scan
3. Clear and re-set preferred device
4. Check logs for connection errors

### API Not Accessible

**Problem**: Cannot reach API at localhost:8080

**Solutions**:
1. Verify app is running
2. Check firewall settings
3. On network access: use device's local IP instead of localhost
4. Check port 8080 is not in use by another application

## Credits

**Streamline Bridge** (formerly REA/ReaPrime) stands for "Reasonable Espresso App" - because with a Decent Espresso machine, you might just brew something reasonably decent.

### Acknowledgments

- **[@randomcoffeesnob](https://github.com/randomcoffeesnob)**: Original name inspiration and ongoing support
- **[@mimoja](https://github.com/mimoja)**: First Flutter app version
- **Decent Espresso community**: Testing, feedback, and feature requests

### License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0).

See the [LICENSE](LICENSE) file for details.

---

**Need help?** Check our [documentation](/) or open an [issue](https://github.com/tadelv/reaprime/issues).


