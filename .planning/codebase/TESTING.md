# Testing Patterns

**Analysis Date:** 2025-02-15

## Test Framework

**Runner:**
- `flutter_test` (part of Flutter SDK)
- Config: No separate config file; uses Flutter defaults
- Dart 3.7.0+ required (from `pubspec.yaml`)

**Assertion Library:**
- `flutter_test` provides `expect()` and matchers
- No additional assertion library needed

**Run Commands:**
```bash
flutter test                    # Run all tests
flutter test test/profile_test.dart   # Run specific test file
flutter test --watch          # Watch mode (re-run on changes)
flutter test --coverage       # Generate coverage report
```

## Test File Organization

**Location:**
- Co-located in `test/` directory at project root
- Mirror source structure conceptually but not required (flat organization used here)
- Current test files: `test/unit_test.dart`, `test/profile_test.dart`, `test/widget_test.dart`, `test/shot_importer_test.dart`

**Naming:**
- Test files end with `_test.dart` suffix
- Test class: `void main() { }` (not a class, uses function-based structure)
- Group-based organization with `group()` and `test()` functions

**Structure:**
```
test/
├── profile_test.dart          # Tests for Profile, ProfileHash, ProfileRecord
├── shot_importer_test.dart    # Tests for ShotImporter utility
├── unit_test.dart             # Basic example tests
└── widget_test.dart           # Flutter widget tests
```

## Test Structure

**Suite Organization:**
```dart
void main() {
  // 1. Setup (one-time)
  setUpAll(() async {
    Hive.init(null);  // Initialize resources
  });

  // 2. Test group
  group('ProfileHash', () {
    // 3. Individual test
    test('calculates consistent profile hash from execution fields', () {
      // Arrange
      final profile1 = Profile(...);
      final profile2 = Profile(...);

      // Act
      final hash1 = ProfileHash.calculateProfileHash(profile1);
      final hash2 = ProfileHash.calculateProfileHash(profile2);

      // Assert
      expect(hash1, equals(hash2));
      expect(hash1.startsWith('profile:'), isTrue);
    });

    test('different execution fields produce different hashes', () {
      // Arrange, Act, Assert pattern
    });
  });
}
```

**Patterns:**
- Use `setUpAll()` for one-time initialization (e.g., Hive setup in `profile_test.dart`)
- Use `setUp()` for per-test setup (e.g., creating fresh mock instances in `shot_importer_test.dart`)
- Use `tearDown()` for per-test cleanup (not heavily used in codebase)
- Organize with `group()` to logically structure related tests
- Follow AAA pattern: Arrange → Act → Assert with clear section comments

**Example from shot_importer_test.dart:**
```dart
void main() {
  late MockStorageService mockStorage;
  late ShotImporter importer;

  setUp(() {
    mockStorage = MockStorageService();
    importer = ShotImporter(storage: mockStorage);
  });

  group('ShotImporter - Single Shot Import', () {
    test('should import a valid single shot JSON object', () async {
      const validShotJson = '{ ... }';

      await importer.importShotJson(validShotJson);

      expect(mockStorage.storedShots.length, 1);
      expect(mockStorage.storedShots[0].id, 'shot-123');
    });

    test('should throw FormatException when JSON is not an object', () async {
      const invalidJson = '["not", "an", "object"]';

      expect(
        () => importer.importShotJson(invalidJson),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

## Mocking

**Framework:** Manual mocking (no package like `mockito` or `mocktail` used)

**Patterns:**
- Implement `interface` by creating a class that implements the interface
- Use `@override` for all interface methods
- Return sensible defaults or store state in mocks
- Add helper methods like `reset()` for test cleanup

**Example mock from profile_test.dart:**
```dart
class MockProfileStorage implements ProfileStorageService {
  final Map<String, ProfileRecord> _storage = {};

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

  @override
  Future<void> store(ProfileRecord record) async {
    _storage[record.id] = record;
  }

  @override
  Future<ProfileRecord?> get(String id) async {
    return _storage[id];
  }

  @override
  Future<List<ProfileRecord>> getAll({Visibility? visibility}) async {
    if (visibility == null) {
      return _storage.values.toList();
    }
    return _storage.values
        .where((record) => record.visibility == visibility)
        .toList();
  }

  // Test helper to reset state
  void reset() {
    _storage.clear();
  }
}
```

**Example mock from shot_importer_test.dart:**
```dart
class MockStorageService implements StorageService {
  final List<ShotRecord> storedShots = [];

  @override
  Future<void> storeShot(ShotRecord record) async {
    storedShots.add(record);
  }

  @override
  Future<List<ShotRecord>> getAllShots() async {
    return storedShots;
  }

  // Unimplemented methods for this test context
  @override
  Future<void> deleteShot(String id) {
    throw UnimplementedError();
  }
}
```

**What to Mock:**
- External service interfaces (storage, discovery services)
- Device interfaces for controller tests
- Any dependency that would slow tests or require hardware

**What NOT to Mock:**
- Pure data classes (`Profile`, `ProfileRecord`)
- Utility functions that are simple and fast
- System-wide behavior (unless hardware-dependent)

## Fixtures and Factories

**Test Data:**
- Create helper functions or factory constructors to build test objects
- Use real data model constructors with minimal required fields
- Construct test data inline or in helper functions

**Pattern from profile_test.dart:**
```dart
final profile1 = Profile(
  version: '2',
  title: 'Test Profile',
  author: 'Author 1',
  notes: 'Some notes',
  beverageType: BeverageType.espresso,
  steps: [],
  tankTemperature: 93.0,
  targetWeight: 36.0,
  targetVolumeCountStart: 0,
);

// For repeated use, create inline or in separate helper
final profile2 = Profile(
  version: '2',
  title: 'Different Title',
  author: 'Author 2',
  notes: 'Different notes',
  beverageType: BeverageType.espresso,
  steps: [],
  tankTemperature: 93.0,
  targetWeight: 36.0,
  targetVolumeCountStart: 0,
);
```

**Location:**
- Test fixtures defined at top of test file after imports
- Mock classes defined in same test file as they're used
- Reusable mocks (like `MockProfileStorage`, `MockStorageService`) placed before `void main()`
- Helper factory methods inline in test file

## Coverage

**Requirements:** No coverage targets enforced

**View Coverage:**
```bash
flutter test --coverage           # Generates coverage data to coverage/lcov.info
# Install lcov (macOS): brew install lcov
lcov --list coverage/lcov.info    # Human-readable coverage report
```

**Coverage Status:**
- Current test files focus on critical paths (Profile hashing, Shot importing)
- Widget tests exist but are minimal (example-only)
- Integration testing relies on manual/device testing or simulated devices

## Test Types

**Unit Tests:**
- Scope: Individual functions, classes, and algorithms
- Approach: Fast, deterministic, no I/O
- Examples:
  - `profile_test.dart`: Tests `ProfileHash.calculateProfileHash()`, profile equality, hashing
  - `shot_importer_test.dart`: Tests `ShotImporter` JSON parsing and validation
- Run: `flutter test test/profile_test.dart`

**Integration Tests:**
- Scope: Multiple components working together
- Approach: May use real storage (Hive), real models
- Examples:
  - Profile storage tests using `MockProfileStorage` to test controller with storage
  - Shot import tests using `MockStorageService` to test importer with storage
- Run: `flutter test test/shot_importer_test.dart`

**E2E Tests:**
- Framework: Not used in current codebase
- Alternative: Use simulated devices (`simulate=1` flag) for app-level testing
- Run: `flutter run --dart-define=simulate=1` for manual testing

**Widget Tests:**
- Scope: Individual widgets and simple interactions
- Approach: Use `WidgetTester` for tap, scroll, find operations
- Example from `widget_test.dart`:
```dart
testWidgets('should display a string of text', (WidgetTester tester) async {
  const myWidget = MaterialApp(
    home: Scaffold(
      body: Text('Hello'),
    ),
  );

  await tester.pumpWidget(myWidget);

  expect(find.byType(Text), findsOneWidget);
});
```

## Common Patterns

**Async Testing:**
```dart
test('should import a valid shot JSON', () async {
  // Mark test as async with () async
  const validShotJson = '{ ... }';

  // Await async operations
  await importer.importShotJson(validShotJson);

  expect(mockStorage.storedShots.length, 1);
});

// For widget tests with animations
testWidgets('widget interaction', (WidgetTester tester) async {
  await tester.pumpWidget(myWidget);
  await tester.tap(find.byType(Button));
  await tester.pumpAndSettle();  // Wait for animations
  expect(...);
});
```

**Error Testing:**
```dart
test('should throw FormatException when JSON is invalid', () async {
  const invalidJson = '["not", "an", "object"]';

  expect(
    () => importer.importShotJson(invalidJson),
    throwsA(isA<FormatException>()),
  );
});

test('should throw ArgumentError for missing fields', () {
  expect(
    () => ProfileRecord.create(profile: null),
    throwsA(isA<ArgumentError>()),
  );
});

// For async errors
test('should throw when storage fails', () async {
  mockStorage.throwOnStore = true;

  expect(
    () => importer.importShotJson(validJson),
    throwsException,
  );
});
```

**Matcher Reference:**
- `equals(value)` - exact equality
- `isA<Type>()` - type check
- `throwsA(matcher)` - exception matching
- `throwsException` - any exception
- `findsOneWidget`, `findsWidgets`, `findsNothing` - widget finding
- `isTrue`, `isFalse` - boolean checks
- `isNull`, `isNotNull` - null checks
- `startsWith()`, `endsWith()`, `contains()` - string operations
- `inRange()`, `greaterThan()`, `lessThan()` - numeric comparisons

## Test Organization Guidelines

**For New Features:**
1. Create `[feature]_test.dart` in `test/` directory
2. Define mocks for dependencies at top of file
3. Group tests by functionality with `group()`
4. Use descriptive test names: "should [expected behavior] when [condition]"
5. Keep tests focused on single behavior

**For Controllers:**
- Test with mock services
- Test state changes through streams
- Test error handling paths
- Example: Test `De1Controller` with mock device, storage, scale services

**For Models:**
- Test constructors and factories
- Test equality (`Equatable` checks)
- Test serialization (`fromJson()`, `toJson()`)
- Test immutability with `copyWith()`
- Example: Profile hash tests, ProfileRecord creation tests

**For Utilities:**
- Test pure functions with various inputs
- Test error cases
- Example: `ShotImporter` tests cover valid/invalid JSON, missing fields

---

*Testing analysis: 2025-02-15*
