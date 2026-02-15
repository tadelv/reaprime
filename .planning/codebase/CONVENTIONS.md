# Coding Conventions

**Analysis Date:** 2025-02-15

## Naming Patterns

**Files:**
- Classes: PascalCase (e.g., `de1_controller.dart`, `profile_record.dart`)
- Directories: snake_case (e.g., `lib/src/models/device/impl/acaia/`, `lib/src/services/webserver/`)
- Implementation classes use descriptive names (e.g., `HiveProfileStorageService`, `BluePlusDiscoveryService`, `UnifiedDe1Transport`)

**Functions:**
- Camel case for all functions and methods: `connectToDe1()`, `calculateProfileHash()`, `getAll()`
- Private functions prefixed with underscore: `_initialize()`, `_onDisconnect()`, `_processSnapshot()`
- Factory constructors named descriptively: `fromJson()`, `create()`
- Getter/setter names use camelCase: `get de1 =>`, `get box =>`

**Variables:**
- Camel case for local variables and parameters: `targetTemperature`, `shotController`, `metadataHash`
- Constants in camelCase (not UPPER_CASE): `static const String _boxName = 'profiles'`
- Private member variables prefixed with underscore: `_de1`, `_log`, `_subscriptions`, `_shotDataStream`
- Nullable types indicated with `?`: `De1Interface?`, `Timer?`
- Clear intent with descriptive names: `_dataInitialized`, `_bypassSAW`, `_snapshotSubscription`

**Types:**
- Enums in PascalCase: `ConnectionState`, `DeviceType`, `BeverageType`, `Visibility`
- Enum values in camelCase: `ConnectionState.connecting`, `Visibility.visible`, `BeverageType.espresso`
- Abstract classes prefix with interface-like names or use `Interface` suffix: `De1Interface`, `Device`, `Scale`, `DeviceDiscoveryService`
- Implementation classes name after concrete type: `HiveProfileStorageService`, `FilePersistenceService`, `BluePlusDiscoveryService`

## Code Style

**Formatting:**
- No explicit formatter configured (relies on Dart defaults)
- Uses standard Dart formatting conventions
- Consistent 2-space indentation throughout
- Line breaks before type parameters for readability in complex generics

**Linting:**
- Uses `flutter_lints` package (extends `package:flutter_lints/flutter.yaml`)
- Configuration in `analysis_options.yaml` at project root
- No custom lint rules overrides; uses standard Flutter lint set
- Common ignored lints: `avoid_print` (not globally disabled but sometimes used for logging)

**Code Organization:**
- Proper null-safety throughout: use `?` for nullable types, `!` for non-null assertions (sparingly)
- Use `@immutable` annotation on value objects (e.g., `Profile`, `ProfileRecord`)
- Use `@override` annotation when overriding methods
- Use `/// ` for documentation comments (doc strings), not `//`

## Import Organization

**Order:**
1. Dart imports: `import 'dart:async'`, `import 'dart:io'`, `import 'dart:typed_data'`
2. Flutter imports: `import 'package:flutter/material.dart'`
3. Third-party package imports: `import 'package:logging/logging.dart'`, `import 'package:rxdart/subjects.dart'`
4. Project imports: `import 'package:reaprime/src/...`
5. Relative imports (if used): `import '../sibling.dart'`, `part '...'`

**Path Aliases:**
- None configured; all imports use full `package:reaprime/src/...` paths
- Relative imports and `part` directives used for file partitioning within handlers

**Examples from codebase:**
- `lib/src/services/webserver_service.dart` shows all imports grouped by type
- `lib/src/controllers/de1_controller.dart` follows import order precisely
- Handlers use `part` directives for organization (e.g., `part 'webserver/de1handler.dart'`)

## Error Handling

**Patterns:**
- Use `try-catch` for operations that can fail: database access, file I/O, device communication
- Log errors with `_log.warning()` or `_log.severe()` with stacktrace: `_log.severe('Failed to...', e, st)`
- `ArgumentError` for invalid arguments to functions: `throw ArgumentError('Profile not found: $id')`
- `Exception` for general runtime errors: `throw Exception("Scale not connected")`
- `StateError` for invalid object state: `throw StateError('HiveProfileStorageService not initialized')`
- Chain exceptions with `rethrow` to preserve stack trace: `catch(e, st) { _log.severe(...); rethrow; }`
- Use explicit error messages that aid debugging: `'Failed to store profile: ${record.id}'`

**Examples:**
```dart
// From shot_controller.dart - try/catch with fallback
try {
  final state = await scaleController.connectionState.first;
  if (state != device.ConnectionState.connected) {
    throw Exception("Scale not connected");
  }
  // Use combined stream
} catch (e) {
  _log.warning("Continuing without scale: $e");
  // Use fallback stream (DE1 only)
}

// From hive_profile_storage.dart - logging with stacktrace
catch (e, st) {
  _log.severe('Failed to initialize HiveProfileStorageService', e, st);
  rethrow;
}

// From profile_controller.dart - ArgumentError for validation
if (!_storage.containsKey(record.id)) {
  throw Exception('Profile not found');
}
```

## Logging

**Framework:** `package:logging` with `Logger` instances

**Patterns:**
- Create class-scoped logger: `final Logger _log = Logger("ClassName")`
- Use appropriate log levels:
  - `_log.info()` for lifecycle events: "device connected", "initialized"
  - `_log.fine()` for detailed information: "trying to connect to existing de1"
  - `_log.warning()` for recoverable issues: "Continuing without scale"
  - `_log.severe()` for errors with stacktrace: `_log.severe('Failed...', e, st)`
- Include context in messages: `_log.info("device $_de1 connecting")`
- Use string interpolation for variable inclusion: `"ShotController initialized"`
- Avoid excessive logging in tight loops; use `fine()` level for verbose output

**Configuration:**
- Initialized in `main.dart`: `Logger.root.level = Level.FINE`
- Appended to file on Android: `~/Download/REA1/log.txt`
- Uses `PrintAppender` with `ColorFormatter()` for console output

## Comments

**When to Comment:**
- Comment complex algorithms or non-obvious logic
- Comment workarounds or hacks (use TODO/FIXME for future improvement)
- Document public API with doc comments (`///`)
- Do NOT comment obvious code ("increment counter", "parse JSON")

**JSDoc/TSDoc:**
- Use Dart doc comments (`/// `) for:
  - Class descriptions: `/// Envelope around Profile with metadata...`
  - Parameter descriptions: `/// The actual profile data`
  - Return value descriptions: `/// The unique identifier based on content hash`
  - Enum value documentation
  - Important notes: `/// Content-based hashing for deduplication`
- Include code examples in doc comments for complex classes
- Example from `profile_record.dart`:
```dart
/// Envelope around Profile with metadata for storage and versioning
///
/// Uses content-based hashing for profile identification:
/// - `id`: Hash of execution-relevant fields (profile hash)
/// - `metadataHash`: Hash of presentation fields
/// - `compoundHash`: Combined hash of both
@immutable
class ProfileRecord extends Equatable { ... }
```

## Function Design

**Size:**
- Keep functions under 50 lines when possible
- Extract complex logic into separate private functions (e.g., `_initialize()`, `_processSnapshot()`)
- Larger files use multiple private helper functions for readability

**Parameters:**
- Use named parameters for optional arguments: `future.then((_) { ... })`
- Group related parameters (avoid long parameter lists)
- Use required keyword explicitly: `required DeviceController controller`
- Constructor injection pattern (see controllers): `De1Controller({required DeviceController controller})`

**Return Values:**
- Async methods return `Future<T>` (e.g., `Future<void>`, `Future<ProfileRecord?>`)
- Stream-based methods return `Stream<T>` for continuous data
- Nullable returns explicit with `?`: `Future<ProfileRecord?>`, not just `Future`
- Use early returns to reduce nesting

## Module Design

**Exports:**
- No barrel files or `export` statements at package level
- Each module imports directly from implementation files
- Concrete implementations exported implicitly through class definitions

**Barrel Files:**
- Not used; prefer explicit imports to clarify dependencies
- Handlers within `webserver_service.dart` use `part` directives for organization

**File Organization:**
- One public class per file (main class)
- Private helper classes in same file if tightly coupled
- Extensions and enums typically in same file as related class
- Use `part` for splitting large handlers into logical sections

## Data Classes and Models

**Immutability:**
- Mark value objects with `@immutable`: `Profile`, `ProfileRecord`, `ShotRecord`
- Use `const` constructors for value classes
- Use `copyWith()` for creating modified copies (e.g., `profile.copyWith(steps: newSteps)`)

**Serialization:**
- Implement `fromJson()` factory and `toJson()` method for JSON-able models
- Use `Equatable` mixin for value equality: `class Profile extends Equatable { ... }`
- Override `props` getter for `Equatable`: `List<Object?> get props => [field1, field2, ...]`

**Example from codebase:**
```dart
@immutable
class Profile extends Equatable {
  // Fields declared final
  final String title;
  final List<ProfileStep> steps;
  // ...

  const Profile({ ... });

  @override
  List<Object?> get props => [version, title, steps, ...];

  factory Profile.fromJson(Map<String, dynamic> json) { ... }

  Map<String, dynamic> toJson() { ... }

  Profile copyWith({ ... }) { ... }
}
```

## Dependency Injection

**Pattern:**
- Constructor-based injection used throughout
- Controllers receive dependencies through constructor parameters
- Services registered in `main.dart` and passed to controllers
- No service locators or global singletons

**Example from controllers:**
```dart
class ShotController {
  final De1Controller de1controller;
  final ScaleController scaleController;
  final PersistenceController persistenceController;

  ShotController({
    required this.scaleController,
    required this.de1controller,
    required this.persistenceController,
    required this.targetProfile,
  }) {
    Future.value(_initialize()).then((_) {
      _log.info("ShotController initialized");
    });
  }
}
```

## Stream Management (RxDart)

**Patterns:**
- Use `BehaviorSubject<T>` for stateful streams with initial values
- Create public `Stream<T> get` accessors to expose subjects
- Private subject naming: `final BehaviorSubject<T> _subjectController`
- Combine streams with `Rx.combineLatest3()`, `withLatestFrom()` for multi-source data
- Subscribe in widget `build()` using `StreamBuilder`
- Always cancel subscriptions in `dispose()` to prevent memory leaks

**Example from de1_controller.dart:**
```dart
final BehaviorSubject<De1Interface?> _de1Controller =
    BehaviorSubject.seeded(null);

Stream<De1Interface?> get de1 => _de1Controller.stream;

// In cleanup
_subscriptions.add(
  _de1!.ready.listen(
    (ready) { /* handle */ },
  ),
);

// In dispose
void dispose() {
  for (var sub in _subscriptions) {
    sub.cancel();
  }
}
```

---

*Convention analysis: 2025-02-15*
