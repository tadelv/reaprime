# Technology Stack

**Analysis Date:** 2026-02-15

## Languages

**Primary:**
- Dart 3.7+ - Core application logic, Flutter widgets, backend services
- HTML/CSS/JavaScript - WebUI skins (served via REST API), plugins executed in JS runtime

**Secondary:**
- Kotlin - Android platform channel implementations
- Swift - iOS/macOS platform channel implementations
- C++ - Linux platform integrations (Bluetooth stack via libglib, serial communications)

## Runtime

**Environment:**
- Flutter (stable channel) - Cross-platform UI framework
- Dart VM - Executes Dart code on all platforms

**Package Manager:**
- Pub.dev - Flutter/Dart package manager
- Lockfile: `pubspec.lock` (present)

## Frameworks

**Core:**
- Flutter 3.x - UI framework for Android, iOS, macOS, Linux, Windows
- Shelf 1.0.0 - HTTP server library for REST API and WebSocket support
- RxDart 0.28.0 - Reactive programming for state management via `BehaviorSubject`

**Network & Communication:**
- Shelf Router 1.1.4 - Request routing for REST API endpoints
- Shelf Web Socket 3.0.0 - WebSocket support for real-time bidirectional communication
- Shelf CORS Headers 0.1.5 - CORS header middleware
- Shelf Static 1.1.3 - Static file serving (API docs, web assets)
- Universal BLE 1.1.0 - Cross-platform Bluetooth Low Energy abstraction
- Flutter Blue Plus 2.0.2 - Native Bluetooth integration (iOS, macOS, Android)
- Flutter Libserialport (git master) - Serial port communication for desktop platforms

**Data & Storage:**
- Hive CE (Community Edition) 2.15.1 - Local key-value store with Flutter support
- Hive CE Flutter 2.3.3 - Hive integration for Flutter
- Hive CE Generator 1.10.0 - Code generation for Hive adapters

**Plugin System:**
- flutter_js (git master, tadelv fork) - JavaScript runtime for plugin execution

**Firebase (Mobile/Desktop Analytics & Error Reporting):**
- firebase_core 4.3.0 - Core Firebase SDK
- firebase_crashlytics 5.0.6 - Crash reporting (Android, iOS, macOS, Windows)
- firebase_performance 0.11.1+3 - Performance monitoring
- firebase_analytics 12.1.0 - Event analytics (Android, iOS, macOS, Windows)

**UI Components:**
- shadcn_ui 0.46.0 - Shadcn design system components for Flutter
- fl_chart 1.0.0 - Charting library (used in shot visualization)
- flutter_launcher_icons 0.14.3 - App icon generation

**Utilities & Helpers:**
- logging 1.3.0 - Structured logging framework
- logging_appenders 2.0.0 - Log appenders (file, console with colors)
- rxdart 0.28.0 - Reactive extensions
- uuid 4.5.1 - UUID generation
- path_provider 2.1.5 - Platform-aware application directories
- archive 4.0.7 - ZIP/archive support (profile imports, WebUI skin downloads)
- equatable 2.0.7 - Value equality for data models
- collection 1.19.0 - Collections utilities
- url_launcher 6.3.2 - Open URLs in system browser
- http 1.2.2 - HTTP client for external API calls (GitHub feedback, WebUI downloads)
- network_info_plus 7.0.0 - Network information (IP addresses)
- device_info_plus 12.3.0 - Device information
- battery_plus 7.0.0 - Battery status monitoring
- permission_handler 12.0.0+1 - Android/iOS runtime permissions
- flutter_foreground_task 9.2.0 - Background service for Bluetooth maintenance
- flutter_inappwebview 6.1.5 - Web view for embedded web content
- window_manager 0.5.1 - Desktop window control
- file_picker 10.3.8 - File picker UI
- shared_preferences 2.5.3 - Simple key-value preferences storage
- ansi_escape_codes 2.1.0 - ANSI color codes for terminal output

## Configuration

**Environment:**
- Compile-time variables: `simulate=1` for device simulation, `GITHUB_FEEDBACK_TOKEN` for feedback service
- `.env.dev` file (present, not read) - Local development environment
- Firebase configuration: Generated via FlutterFire CLI (`firebase_options.dart`)
- Platform-specific configs:
  - Android: `android/` directory with Gradle, native Kotlin integration
  - iOS: `ios/` directory with Xcode project, Swift integration
  - macOS: `macos/` directory
  - Linux: `linux/` directory with CMake build system, D-Bus for Bluetooth
  - Windows: `windows/` directory with MSVC build system

**Build:**
- `analysis_options.yaml` - Dart linter configuration (inherits `flutter_lints`)
- `flutter_launcher_icons.yaml` - Icon generation configuration
- `l10n.yaml` - Localization configuration
- `pubspec.yaml` - Package manifest with asset declarations
- `Makefile` - Multi-architecture Linux builds with Docker/Colima
- `Dockerfile` - Ubuntu 22.04 base, Flutter Linux tools, libserialport dev dependencies
- `docker-compose.yml` - Multi-arch build orchestration with volume caching

## Platform Requirements

**Development:**
- Dart SDK 3.7+
- Flutter SDK (stable)
- For Linux builds: libserialport development libraries
- For Docker builds: Docker Desktop or Colima with ARM64/x86_64 profiles
- For macOS/iOS: Xcode 14+
- For Android: Android SDK 24+, NDK, Gradle

**Production:**
- **Android:** Target SDK 34 (Android 14), minimum SDK 24 (Android 7.0)
- **iOS:** iOS 11.0+
- **macOS:** macOS 10.11+
- **Linux:** glibc 2.31+ (Ubuntu 20.04 LTS or equivalent), libglib2.0-0, libserialport0
- **Windows:** Windows 10 1909+

## API Versioning

**REST API:** v1 on port 8080 (`/api/v1/*`)
**WebSocket:** v1 on port 8080 (`/ws/v1/*`)
**API Documentation Server:** port 4001 (OpenAPI/Swagger specs from `assets/api/`)

---

*Stack analysis: 2026-02-15*
