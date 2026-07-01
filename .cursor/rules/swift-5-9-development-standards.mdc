---
description: "Swift 5.9 development standards - SwiftUI, layers, concurrency, testing; platform minimum from project deployment target"
globs: ["**/*.swift"]
alwaysApply: false
---
## Persona: Senior iOS Craftsman
- **Role:** Apple Ecosystem expert (SwiftUI/Combine/ARC). **Philosophy:** SwiftUI purist, strict layer separation
- **Bias:** User-first (60fps, non-blocking main), Memory-safe (paranoid retain cycles, [weak self]), Modern (async/await > GCD), Architecture (MVVM, value types), Platform (deployment target from project, Swift 5.9 language mode)

---

# iOS Development Standards

You are an expert iOS developer using Swift and SwiftUI. Follow these guidelines:

## Scope

- **Swift (filename contract):** This file targets **Swift 5.9** (see `swift-5-9-*.mdc` filename). Do not use Swift 6-only language features listed under "Swift 5.9 Compatibility" unless the project explicitly adopts Swift 6.
- **For Swift 6 language mode:** See `swift-6-development-standards.mdc` and `swift-6-brutal-audit.mdc`.
- **Platform:** Minimum OS version is defined by the **Xcode target** (`IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` / etc.), **SwiftPM `platforms`**, or extension targets—not by this rule. Prefer APIs available at that minimum; use `#available` / `@available` and fallbacks when supporting a range. Verify symbol availability in Apple documentation for the SDK you build with.

## Code Structure

- Use Swift and SwiftUI features allowed by **Swift 5.9** and the project's deployment target; protocol-oriented programming
- Prefer value types (structs) over classes
- Use MVVM architecture with SwiftUI
- Structure: Features/, Core/, UI/, Resources/
- Follow Apple's Human Interface Guidelines

### Source File Naming (Guidance)

PascalCase matching primary type (`UserProfileViewModel.swift`). Extensions: `Type+ExtensionPurpose.swift`. 📍 See: `general-llm-anti-patterns.mdc` Category 12.

## Architectural Layers (CRITICAL)

To prevent "God Objects" and "Smart UI", strict layer separation is enforced:

### 1. Presentation Layer (Views & ViewModels)

- **Role:** Transforming user intent into actions and State into UI.
- ❌ **FORBIDDEN:** Importing `SwiftData` or `MusicKit` directly.
- ❌ **FORBIDDEN:** Direct database fetches or API calls.
- ✅ **ALLOWED:** Calling methods on injected Use Cases or Repositories.

### 2. Domain Layer (Models, Use Cases, Interfaces)

- **Role:** Pure business logic and rules.
- ❌ **FORBIDDEN:** Importing `SwiftUI`, `SwiftData`, or UI libraries.
- ✅ **MUST:** Be Pure Swift.
- ✅ **MUST:** Define `protocol` interfaces for data access (e.g., `MusicRepositoryProtocol`).

### 3. Data Layer (Repositories, Services, DataSources)

- **Role:** The "How". Implementation of Domain interfaces.
- ✅ **ONLY LAYER** allowed to import `SwiftData`, `CoreData`, or low-level Networking.
- **Rule:** ViewModels must NEVER know if data comes from Cloud or Disk.

## Architectural Patterns (Refined)

### Use Cases as Actors

- ✅ **MANDATORY:** All Use Cases MUST be implemented as `actor` types.
- **Reason:** Actor isolation provides thread-safe execution and prevents data races.

### Explicit Sendability Requirements

- ✅ **MANDATORY:** Every new Protocol defined in `Core/Domain/Interfaces/` MUST inherit from `Sendable`.
- **Reason:** Ensures type safety across concurrency boundaries and enables safe data passing between actors.
- **Enforcement:** All domain interface protocols must explicitly conform to `Sendable`.
- **Example:**

  ```swift
  protocol MusicRepositoryProtocol: Sendable {
      func fetchSongs() async throws -> [MediaItem]
  }
  ```

### DTO Pattern (Data Transfer Objects)

- ✅ **MANDATORY:** SwiftData `@Model` objects MUST NEVER be passed to Use Cases.
- **Rule:** All SwiftData models must be converted to Sendable structs (like `MediaItem`) inside the Repository before being returned to Use Cases.
- **Reason:** Keeps Domain Layer pure and free from framework dependencies. Enables safe concurrent access.

### State Snapshotting Before Async
**CRITICAL:** Snapshot state before async network calls to prevent view inconsistencies.
❌ Bad: `@State var user: User?; Task { user = await fetchUser() }` (state may change during await)
✅ Good: `Task { let fetched = await fetchUser(); await MainActor.run { user = fetched } }` (snapshot then update)
⚠️ Why: State may change during await, causing view inconsistencies, race conditions
🔧 Fix: Always snapshot mutable state before await, update on MainActor
📍 See: `general-llm-anti-patterns.mdc` section 1.2
**Detect:** @State modified directly in async Task, no snapshot before await, state changes during network calls

### Swift 5.9 Compatibility

- ✅ **MANDATORY:** Code must target Swift 5.9 and remain compatible with Swift 5.9.
- ❌ **FORBIDDEN:** Do NOT use Swift 6-exclusive keywords:
  - ❌ `sending` (Swift 6 concurrency feature)
  - ❌ `consume` (Swift 6 ownership feature)
- ✅ **ALLOWED:** Use Swift 5.9-compatible concurrency features:
  - ✅ `nonisolated` (for actor isolation control)
  - ✅ `await` (for async operations)
  - ✅ `actor` (for actor types)
  - ✅ `Sendable` (for concurrency-safe types)
- **Reason:** Ensures compatibility with the project's Swift 5.9 target while maintaining modern concurrency patterns.

## Critical Swift Anti-Patterns (Quick Reference)

**CRITICAL:** These are the most common Swift/iOS-specific anti-patterns that cause architectural violations and performance issues.

### Fake Actor Pattern (SwiftData)

❌ Bad: `actor Repo { nonisolated(unsafe) let ctx; func add() { await MainActor.run { } } }`
✅ Good: `@ModelActor actor Repo { func add() async { /* background */ } }` OR `@MainActor class Repo`
⚠️ Why: Defeats concurrency benefits, causes UI freezes at scale

### SwiftData Models in Domain

❌ Bad: Passing `@Model` SwiftData objects to Use Cases or Domain layer
✅ Good: Convert to Sendable DTOs (e.g., `MediaItem`) in Repository before returning
⚠️ Why: Framework dependencies in Domain, breaks isolation, violates DTO pattern

### MainActor on Domain Types

❌ Bad: `@MainActor struct MediaID: Hashable { }` in `Core/Domain/`
✅ Good: `struct MediaID: Hashable, Sendable { }` (no actor isolation)
⚠️ Why: Domain types must be usable from any isolation context, breaks background actors

### Actor Isolation in Tests

❌ Bad: `@Test func test() { let repo = MainActorRepo() }` (no isolation match)
✅ Good: `@Test @MainActor func test() { let repo = MainActorRepo() }`
⚠️ Why: Swift 6 error - test isolation must match type isolation

## Anti-Patterns to Avoid

**CRITICAL: These patterns violate architectural principles and must be avoided**

### Pass SwiftData Models to Domain Layer (CRIT)

❌ Bad: `func fetchSongs() async throws -> [SongModel] { return models }` (SwiftData @Model returned)
✅ Good: `return models.map { MediaItem(from: $0) }` (convert to Sendable DTO in Repository)
⚠️ Why: SwiftData @Model is MainActor-isolated; Domain must remain pure Swift
🔧 Fix: Convert to Sendable DTO in Repository before returning to Use Cases
📍 See: DTO Pattern above, `general-llm-anti-patterns.mdc` section 1.4

**Detect:** SwiftData @Model returned from Repository, @Model in Use Case signatures

---

### Import SwiftData in Domain Layer (CRIT)

❌ Bad: `import SwiftData` in Core/Domain/
✅ Good: `import Foundation` only in Domain layer
⚠️ Why: Domain must have zero framework dependencies
🔧 Fix: SwiftData only in Data layer; Domain uses Pure Swift
📍 See: Architectural Layers above

**Detect:** SwiftData import in Domain, MusicKit import in Domain

---

### Use Task.sleep for Synchronization (CRIT)

❌ Bad: `try await Task.sleep(...); let data = await someAsyncValue` (may still not be ready)
✅ Good: Wait for actual condition or use proper async/await
⚠️ Why: Task.sleep creates race conditions, unreliable timing
🔧 Fix: Use async streams, asyncPublisher.values, or proper async/await
📍 See: `general-llm-anti-patterns.mdc` section 6.4

**Detect:** Task.sleep for synchronization, sleep instead of proper async wait

---

### Pass Entire Container to ViewModels (CRIT)

❌ Bad: `init(container: AppContainer)` (ViewModel has access to everything)
✅ Good: `init(playMusicUseCase: PlayMusicUseCaseProtocol)` (only what it needs)
⚠️ Why: Violates Interface Segregation Principle; creates God object dependency
🔧 Fix: Inject only required Use Cases/protocols
📍 See: `general-llm-anti-patterns.mdc` section 1.6

**Detect:** Container/Environment passed to ViewModel, ViewModel with access to all services

---

### Access SwiftData Directly from ViewModels (CRIT)

❌ Bad: `@Query var playlists: [Playlist]` (SwiftData in ViewModel)
✅ Good: `@Published var playlists: [MediaItem]`; load via Use Case
⚠️ Why: Presentation must not import SwiftData; violates layer separation
🔧 Fix: Use Cases/Repositories handle data; ViewModel uses DTOs
📍 See: Architectural Layers above

**Detect:** @Query in ViewModel, SwiftData import in Presentation

---

### Create Custom UI Components That Duplicate System (CRIT)

❌ Bad: Custom sheet overlay in ZStack (breaks keyboard, accessibility)
✅ Good: `.sheet(item: $sheetItem)`, `.presentationDetents([.medium, .large])`
⚠️ Why: System components handle keyboard, accessibility, platform conventions
🔧 Fix: Use native SwiftUI presentation APIs; avoid custom overlays
📍 See: `general-llm-anti-patterns.mdc` section 4.3

**Detect:** Custom overlay when .sheet exists, custom modal instead of native

---

### Use MainActor for Actor-Isolated Services (CRIT)

❌ Bad: `@MainActor actor MusicService` (conflicting isolation)
✅ Good: `actor MusicService` (no MainActor for background services)
⚠️ Why: MainActor for UI/SwiftData; actor for services; mixing defeats isolation
🔧 Fix: Use actor for services; MainActor only for UI/SwiftData types
📍 See: `general-llm-anti-patterns.mdc` section 1.2

**Detect:** @MainActor on actor for non-UI service, conflicting isolation

---

### Skip DTO Conversion in Repositories (CRIT)

❌ Bad: `func fetchSongs() async throws -> [MusicItem] { return try context.fetch(...) }`
✅ Good: `return models.map { MediaItem(from: $0) }` in Repository
⚠️ Why: Domain must be framework-agnostic; DTOs enable safe concurrent access
🔧 Fix: Always convert @Model to Sendable DTO in Repository before return
📍 See: DTO Pattern above, SwiftData Models in Domain above

**Detect:** @Model return type from Repository, no DTO conversion in fetch methods

---

### Create God Objects (Services That Do Everything) (CRIT)

❌ Bad: `class AppService` with playMusic, fetchPodcasts, managePlaylists, handleSearch (50+ methods)
✅ Good: Separate actors — MusicService, PodcastService, PlaylistService, SearchService
⚠️ Why: Violates SRP; harder to test, maintain, and understand
🔧 Fix: One actor per domain concern; split God Objects into focused services
📍 See: `general-llm-anti-patterns.mdc` section 1.6

**Detect:** Single class/actor with 50+ methods, unrelated responsibilities in one service

---

### Use String-Based Logic Instead of Type Safety (CRIT)

❌ Bad: `if item.source == "appleMusic"` (string comparison)
✅ Good: `switch item.id.source { case .appleMusic: ... case .localLibrary: ... }`
⚠️ Why: Strings allow typos and runtime errors; enums give compile-time safety
🔧 Fix: Use enums for source/type discriminations; avoid string literals
📍 See: `engineering-philosophy.mdc` section 2.1

**Detect:** String comparisons for type/source, magic string literals instead of enums

---

## Common LLM Mistakes to Avoid

### Mistake 1: Generating Code Without Understanding Architecture

**Symptom:** Code that technically compiles but violates layer separation

**Solution:** Always verify code follows architectural constraints before accepting

### Mistake 2: Creating Mocks That Don't Match Real Implementation

**Symptom:** Tests pass but real implementation fails

**Solution:** Ensure mocks accurately reflect real service behavior

### Mistake 3: Adding Framework Dependencies to Domain Layer

**Symptom:** Domain layer imports SwiftUI, SwiftData, or MusicKit

**Solution:** Check imports in Domain layer files - should only be Foundation

### Mistake 4: Forgetting DTO Conversion

**Symptom:** SwiftData models passed to Use Cases

**Solution:** Always convert in Repository layer before returning

### Mistake 5: Using MainActor Where Actor Is Needed

**Symptom:** Concurrency warnings or data races

**Solution:** Use `actor` for services, `@MainActor` only for UI/SwiftData

### Mistake 6: Jumping Ahead to Future Phases

**Symptom:** Implementing features from Phase 5+ when still in Phase 4

**Solution:** Follow phase-based implementation plan strictly. Complete current phase before moving to next.

## Apple Framework and API Usage

### CRITICAL: Always prefer built-in Apple frameworks and APIs over custom implementations

### Framework Priority Rules

1. **Before implementing custom functionality, check if Apple provides it:**
   - ✅ **SwiftData**: Use Model, Query, and ModelContext for data persistence instead of custom solutions
   - ✅ **MusicKit**: Use ApplicationMusicPlayer, MusicSubscription, and MusicItem for Apple Music integration
   - ✅ **Apple Music API**: Use official API endpoints and data structures before custom implementations
   - ✅ **Foundation**: Use standard types, collections, and utilities
   - ✅ **Combine**: Use publishers, subscribers, and operators for reactive programming
   - ✅ **AVFoundation**: Use AVPlayer, AVAudioSession for audio playback
   - ✅ **MediaPlayer**: Use MPNowPlayingInfoCenter, MPRemoteCommandCenter for system integration

2. **When to Use Built-in Features**

   - Always check Apple documentation first (locally indexed for fast access)
   - Use system components that match platform conventions
   - Leverage framework-provided functionality for better integration
   - Take advantage of automatic updates and improvements from Apple
   - Ensure compatibility with system features (Siri, Control Center, etc.)

3. **When Custom Implementation is Acceptable:**
   - ✅ Apple framework doesn't provide the specific functionality needed
   - ✅ Custom implementation is required for unique business logic
   - ✅ Framework limitations prevent desired behavior
   - ✅ Performance requirements cannot be met with built-in solutions
   - ❌ **NOT acceptable**: Reimplementing functionality that Apple already provides
   - ❌ **NOT acceptable**: Creating custom components that duplicate system functionality

4. **Framework-Specific Guidelines**

   **SwiftData**
   - Use `@Model` macro for model definitions
   - Use `@Attribute` and `@Relationship` macros for property configuration
   - Use `ModelContext` for data operations (insert, delete, fetch, save)
   - Use `@Query` in SwiftUI views for automatic data fetching
   - Use `FetchDescriptor` for complex queries
   - Use `ModelContainer` for data storage configuration

   **MusicKit**
   - Use `ApplicationMusicPlayer` for playback control
   - Use `MusicSubscription` for subscription status
   - Use `MusicItem` types (Song, Album, Artist, etc.) for content representation
   - Use `MusicItemCollection` for collections
   - Use `MusicCatalogSearchRequest` for search functionality
   - Use `MusicLibrary` for user's library access
   - Use `MusicVideo` and other specialized types as appropriate

   **Apple Music API**
   - Use official API endpoints and request structures
   - Use provided data models and response types
   - Follow API authentication and authorization patterns
   - Use API rate limiting and error handling as specified
   - Leverage API features like recommendations, charts, and playlists

5. **Benefits of Using Built-in Features**

   - ✅ Automatic system integration (Siri, Control Center, Lock Screen, etc.)
   - ✅ Consistent user experience with platform conventions
   - ✅ Automatic updates and improvements from Apple
   - ✅ Better performance and optimization
   - ✅ Reduced maintenance burden
   - ✅ Accessibility support built-in
   - ✅ Internationalization support
   - ✅ Security and privacy compliance

6. **Before Creating Custom Implementation**
   - Search Apple documentation (locally indexed) for existing solutions
   - Check WWDC sessions and sample code for patterns
   - Review framework release notes for new features
   - Consider if a combination of built-in features can achieve the goal
   - Document why custom implementation is necessary

## Naming

- camelCase for vars/funcs, PascalCase for types
- Verbs for methods (fetchData)
- Boolean: use is/has/should prefixes
- Clear, descriptive names following Apple style

## Swift Best Practices

- Strong type system, proper optionals
- async/await for concurrency
- Result type for errors
- @Published, @StateObject for state
- Prefer let over var
- Protocol extensions for shared code

## Dependency Injection Rules

- ❌ **NEVER** pass the entire `ServiceContainer` or `Environment` object to ViewModels.
- ✅ **ALWAYS** inject only the specific protocols needed (Interface Segregation).
  - *Bad:* `init(container: AppContainer)`
  - *Good:* `init(playMusicUseCase: PlayMusicUseCaseProtocol)`

## Performance

- Profile with Instruments
- Optimize network requests
- Background task handling
- Proper state management
- Memory management

## Data & State

- SwiftData for data persistence (modern approach)
- CoreData for complex models (if needed)
- UserDefaults for preferences
- Combine for reactive code
- Clean data flow architecture
- Proper dependency injection
- Handle state restoration

## Security

- Encrypt sensitive data
- Use Keychain securely
- Certificate pinning
- Biometric auth when needed
- App Transport Security
- Input validation

## Testing & Quality

**CRITICAL: Follow Apple's official testing documentation and best practices** - Reference: <https://developer.apple.com/documentation/xcode/testing> and <https://developer.apple.com/documentation/Xcode/adding-tests-to-your-xcode-project>

### Testing Frameworks

- **Swift Testing Framework** (`@Test`) for new tests when supported by the project's **Xcode version, SDK, and deployment target**; otherwise use XCTest
- **XCTest** for unit tests (default when Swift Testing is unavailable or for legacy targets)
- **XCUITest** for UI tests and user interaction testing
- Test common user flows and critical paths
- Performance testing using `measure` blocks
- Error scenarios and negative test cases
- Accessibility testing (VoiceOver, Dynamic Type, etc.)

### Test Target Organization (Per Apple Documentation)

1. **Test Target Setup:**
   - Create separate test targets for different test types (unit tests, UI tests)
   - Use Xcode's Test Navigator (⌘6) to manage and organize tests
   - Configure test target membership in File Inspector for each test class
   - Ensure proper target dependencies and linking

2. **Adding Tests to Xcode Project**

   - Use Test Navigator's Add (+) button to create new test targets
   - Choose "New Unit Test Target" or "New UI Test Target" as appropriate
   - Use setup assistant to configure product name and settings
   - Add test classes via Test Navigator: "New Unit Test Class" or "New UI Test Class"
   - Associate test classes with appropriate test targets

3. **Test Class Organization**
   - Use clear, consistent naming: append "Tests" to class under test (e.g., `MyFeatureTests` for `MyFeature`)
   - Organize test files in folders mirroring main codebase structure
   - Group related test methods within each test class
   - Use descriptive test method names indicating what aspect is being tested

### Unit Testing Best Practices (Per Apple Guidelines)

1. **Define Clear API Requirements:**
   - Clearly specify expected behavior and outcomes for each method/function
   - Write precise tests that validate intended functionality
   - Document assumptions and expected inputs/outputs

2. **Implement Negative Tests:**
   - Test invalid or unexpected inputs to ensure proper error handling
   - Test boundary conditions (e.g., if function accepts 0-100, test -1 and 101)
   - Verify error responses and edge cases

3. **Write Comprehensive Test Cases:**
   - Cover various code modules and their interactions
   - Mimic real-world usage scenarios
   - Identify issues that might not surface in isolated tests
   - Test code paths and branches comprehensively

4. **Cover Bug Fixes with Tests:**
   - Create test cases that verify bug fixes
   - Prevent regressions by maintaining tests for fixed bugs
   - Document the bug scenario in test comments

### UI Testing Best Practices (Per Apple Guidelines)

1. **Utilize UI Recording:**
   - Leverage Xcode's UI recording feature to generate test code
   - Capture user interactions and translate them into test code
   - Quickly set up UI tests using recorded interactions

2. **Structure UI Tests Effectively:**
   - Create separate test classes for different functionalities
   - Organize tests to make them manageable and maintainable
   - Group related UI test scenarios together

3. **Use Assertions to Validate UI Elements:**
   - Employ XCTest assertions to verify UI element behavior and state
   - Ensure UI responds correctly to user interactions
   - Validate expected UI states after actions

4. **Automate Testing Processes:**
   - Incorporate continuous integration tools to automate test execution
   - Enable early detection of issues
   - Maintain code quality as project evolves

### Test Execution & Analysis

1. **Test Navigator Usage:**
   - Use Test Navigator (⌘6) to view all test bundles, classes, and methods
   - Run individual tests or entire test suites from Test Navigator
   - Monitor real-time pass/fail indicators during test execution
   - Quickly identify and address test failures

2. **Code Coverage Analysis:**
   - Enable code coverage in scheme settings: Test action → "Gather coverage data"
   - Review coverage reports after test execution
   - Identify untested code paths and increase coverage
   - Aim for 80%+ coverage on business logic (per project standards)

3. **Performance Testing**

   - Use `measure` method in XCTest to establish performance baselines
   - Test execution time of critical code blocks
   - Identify potential bottlenecks and regressions
   - Review performance test results in report navigator, issues navigator, and source editor

4. **Test Schemes and Configurations**

   - Configure test schemes for different environments (Debug, Release, etc.)
   - Set up test plans for different device configurations
   - Use test execution options (parallel execution, random order, etc.)
   - Configure test timeouts and retry options as needed

### Testing Documentation References

- **Apple Testing Documentation**: <https://developer.apple.com/documentation/xcode/testing>
- **Adding Tests to Xcode Project**: <https://developer.apple.com/documentation/Xcode/adding-tests-to-your-xcode-project>
- Always consult Apple's official documentation for latest testing features and best practices
- Review WWDC sessions on testing for advanced techniques and workflows

## Test-Driven Development (TDD) Requirements

### CRITICAL: Tests must be created alongside all new code

**Reference:** Follow Apple's testing documentation: <https://developer.apple.com/documentation/xcode/testing>

### Mandatory Test Creation Rules

1. **When adding new functionality:**
   - Create corresponding test files BEFORE or IMMEDIATELY AFTER implementing the feature
   - Test files should be in the same directory structure as source files (e.g., `MyApp/Services/MyService.swift` → `MyAppTests/Services/MyServiceTests.swift`)
   - Use Swift Testing Framework (`@Test`) for new tests when the project's Xcode/SDK and deployment target support it; otherwise XCTest
   - Use XCTest when Swift Testing is unavailable or for legacy compatibility
   - Add test classes via Test Navigator: "New Unit Test Class" or "New UI Test Class"
   - Ensure proper target membership for test files

2. **When fixing bugs:**
   - ALWAYS create a test that reproduces the bug first (if possible)
   - Write test that demonstrates the bug scenario
   - Then fix the bug
   - Ensure the test passes after the fix
   - Add additional tests to prevent regression
   - Document the bug scenario in test comments

3. **When modifying existing code:**
   - Update existing tests if behavior changes
   - Add new tests for new behavior
   - Ensure all existing tests still pass
   - Review and update test coverage as needed

4. **Test Coverage Requirements:**
   - **Services**: 100% of public methods must have tests
   - **ViewModels**: All public methods and state changes must be tested
   - **Models**: Test validation, transformations, and business logic
   - **UI Components**: Test behavior, not implementation details
   - **Error Handling**: All error paths must be tested
   - **Edge Cases**: Test boundary conditions, nil values, empty states
   - Enable code coverage in scheme settings to track coverage metrics
   - Aim for 80%+ coverage on business logic

5. **Test Structure:**
   - Use descriptive test names: `testFunctionName_Scenario_ExpectedResult()`
   - Group related tests in the same test struct/class
   - Use `@Test` attribute with descriptive names: `@Test("Description of what is being tested")`
   - Use `#expect()` for assertions in Swift Testing Framework
   - Use `XCTAssert*` for XCTest
   - Follow Arrange-Act-Assert (AAA) pattern for clarity
   - **CRITICAL: Actor Isolation in Tests:** Ensure proper actor isolation in test code to prevent data races and maintain thread safety.

6. **Test Organization (Per Apple Guidelines):**
   - Mirror source directory structure in test directory
   - One test file per source file (or logical grouping)
   - Use clear naming convention: append "Tests" to class under test
   - Organize test files in folders mirroring main codebase structure
   - Use `@testable import` to access internal members when needed
   - Create mock objects for dependencies (organize in a `Mocks/` directory within your test target)
   - Group related test methods within test classes

7. **What to Test (Per Apple Guidelines)**

   - ✅ Public API methods and their return values
   - ✅ State changes and side effects
   - ✅ Error conditions and edge cases (negative tests)
   - ✅ Business logic and calculations
   - ✅ Integration between components
   - ✅ Boundary conditions and invalid inputs
   - ✅ Real-world usage scenarios
   - ❌ Private implementation details
   - ❌ Framework behavior (e.g., SwiftUI rendering)

8. **Test Quality Standards (Per Apple Guidelines)**

   - **Independence**: Tests must be independent (no shared state)
   - **Repeatability**: Tests must be repeatable (same results every run)
   - **Speed**: Tests must be fast (avoid network calls, use mocks)
   - **Clarity**: Tests must be clear (readable test names and assertions)
   - **Comprehensiveness**: Cover various code modules and their interactions
   - **Real-world scenarios**: Mimic actual usage patterns
   - Use async/await properly in tests with appropriate delays
   - Define clear API requirements before writing tests

9. **When Tests Are NOT Required (Exceptions):**
   - Simple data models with no logic (SwiftData models with only properties)
   - View-only SwiftUI components with no business logic
   - Protocol definitions
   - Type aliases and simple extensions with no logic
   - However, even these should have tests if they contain any logic or transformations

10. **Test Execution (Per Apple Guidelines):**
    - Use Test Navigator (⌘6) to view and run tests
    - Run tests after every code change
    - Run individual tests or entire test suites from Test Navigator
    - Monitor real-time pass/fail indicators
    - Ensure all tests pass before committing
    - Fix or update failing tests immediately
    - Do not skip or disable tests without good reason
    - Review test results in report navigator and source editor
    - Use continuous integration for automated test execution

### Xcode Testing Workflow & Tools

1. **Test Navigator Usage:**
   - Access Test Navigator with ⌘6 (Command+6)
   - View hierarchical structure: test bundles → test classes → test methods
   - Run individual tests by clicking the diamond icon next to test method
   - Run all tests in a class or bundle from Test Navigator
   - Monitor real-time execution status with pass/fail indicators
   - Quick access to test failures and error details

2. **Adding Tests via Xcode:**
   - Use Test Navigator's Add (+) button to create:
     - New Unit Test Target
     - New UI Test Target
     - New Unit Test Class
     - New UI Test Class
   - Use setup assistant to configure test targets
   - Set target membership in File Inspector for test classes

3. **Test Execution Options:**
   - Run single test: Click diamond icon next to test method
   - Run test class: Click diamond icon next to test class
   - Run all tests: Cmd+U or Product → Test
   - Run tests in parallel: Enable in scheme settings
   - Run tests in random order: Enable in scheme settings for better reliability
   - Stop test execution: Click stop button in toolbar

4. **Code Coverage Integration:**
   - Enable in scheme: Edit Scheme → Test → Options → "Gather coverage data"
   - View coverage after test runs in report navigator
   - See inline coverage indicators in source editor (green/red highlighting)
   - Review coverage percentages per file and function
   - Identify untested code paths for improvement

5. **Performance Testing with XCTest**

   - Use `measure` block to establish performance baselines:

   ```swift
   func testPerformanceExample() {
       measure {
           // Code to measure performance
           expensiveOperation()
       }
   }
   ```

   - Xcode runs the block multiple times to establish baseline
   - View performance metrics in report navigator
   - Set performance thresholds to catch regressions
   - Compare performance across different test runs

6. **Test Reports & Analysis:**
   - View test results in Report Navigator (⌘9)
   - See detailed test execution logs and errors
   - Review performance test metrics and comparisons
   - Export test results for analysis or CI/CD integration
   - Track test history and trends over time

### Example Test Patterns

#### Service Test

```swift
@Test("ServiceName methodName() returns expected result")
func testMethodName() async throws {
    // Arrange
    let service = ServiceName(...)
    
    // Act
    let result = try await service.methodName()
    
    // Assert
    #expect(result == expectedValue)
}
```

#### ViewModel Test

```swift
@Test("ViewModelName action() updates state correctly")
func testAction() async throws {
    let viewModel = ViewModelName(...)
    
    viewModel.action()
    // Wait for async state update to complete
    // For @Published properties, use: await viewModel.$state.values.first { $0 == expectedState }
    // For other async patterns, await the actual completion mechanism
    
    #expect(viewModel.state == expectedState)
}
```

#### Negative Test (Per Apple Guidelines)

```swift
@Test("ServiceName methodName() handles invalid input correctly")
func testMethodName_InvalidInput_ThrowsError() async throws {
    // Arrange
    let service = ServiceName(...)
    let invalidInput = -1 // Boundary violation
    
    // Act & Assert
    await #expect(throws: ServiceError.invalidInput) {
        try await service.methodName(invalidInput)
    }
}
```

#### Performance Test

```swift
func testPerformanceExpensiveOperation() {
    let service = ServiceName(...)
    
    measure {
        service.performExpensiveOperation()
    }
}
```

#### Bug Fix Test

```swift
@Test("Fixed bug: issue description")
func testBugFix() async throws {
    // Test that reproduces the bug scenario
    // Should pass after fix is applied
}
```

#### UI Test with Recording

```swift
func testUserLoginFlow() {
    let app = XCUIApplication()
    app.launch()
    
    // Record interactions using UI Recording feature
    app.buttons["Login"].tap()
    app.textFields["Email"].tap()
    app.textFields["Email"].typeText("test@example.com")
    
    // Assert expected UI state
    XCTAssertTrue(app.buttons["Logout"].exists)
}
```

## Essential Features

- Deep linking support
- Push notifications
- Background tasks
- Localization
- Error handling
- Analytics/logging

## Development Process

- **CRITICAL: Compile and test code between every phase of development** - Never proceed to the next development phase without verifying the code compiles successfully and all relevant tests pass
- **CRITICAL: Zero-Warning Policy** - Code is not considered complete until the build succeeds with zero warnings. Treat all compiler warnings as errors. Warnings often indicate:
  - Potential runtime issues (data races, concurrency problems, deprecations)
  - Swift version compatibility issues (warnings today become errors in future Swift versions)
  - Code quality issues (unused variables, force unwraps, etc.)
  - Architectural violations (isolation mismatches, Sendable conformance issues)
  
  **Enforcement:**
  - Before marking work as complete, verify build output shows no warnings (filter out informational messages like destination selection)
  - Fix warnings immediately rather than deferring them
  - If a warning cannot be resolved, document the technical reason and create a tracking issue
  - Use clean builds (`xcodebuild clean build`) to verify no stale warnings exist
  - Do not suppress warnings with compiler directives unless absolutely necessary and documented
  
  **Rationale:** Warnings ignored today become production bugs and migration blockers tomorrow. Swift 6 strict concurrency warnings are forward-compatibility notices that will become errors in future Swift versions.
- **CRITICAL: Code Completion Requires Passing Tests** - Code is not considered complete until:
  - The project compiles successfully with zero warnings
  - All existing tests pass
  - All new tests pass (if new functionality was added)
  - Test coverage requirements are met (80%+ for business logic)
  
  **Enforcement:**
  - Before marking work as complete, run all tests via Test Navigator (⌘6) or `xcodebuild test`
  - Verify test results show 100% pass rate (excluding known flaky tests)
  - Fix failing tests immediately - do not proceed with incomplete work
  - If tests cannot be fixed, document the technical reason and create a tracking issue
  - Use clean test runs (`xcodebuild clean test`) to verify no stale test failures exist
  - Do not skip or disable tests without good reason and documentation
  
  **Rationale:** Code that compiles but fails tests indicates broken functionality or regressions. Tests are the contract that code must fulfill. Passing tests are non-negotiable for code completion. Just as zero warnings is required, zero test failures is required.
- **CRITICAL: Create tests alongside code** - Every new feature, bug fix, or significant change must include corresponding tests
- **CRITICAL: Use Xcode Test Navigator** - Leverage Test Navigator (⌘6) for test management, execution, and monitoring
- Enable code coverage in test schemes to track test effectiveness
- Run tests frequently during development (not just before committing)
- Use continuous integration for automated test execution
- Git branching strategy
- Code review process (include test review in code reviews)
- CI/CD pipeline with automated testing
- Documentation
- Unit test coverage (aim for 80%+ coverage on business logic)
- Reference Apple's testing documentation: <https://developer.apple.com/documentation/xcode/testing>

## App Store Guidelines

- Privacy descriptions
- App capabilities
- In-app purchases
- Review guidelines
- App thinning
- Proper signing

## Additional Best Practices

- Use os.log or unified logging for production logging
- Never log sensitive information
- Keep functions small and focused (ideally under 50 lines)
- Use guard statements for early returns
- Write self-documenting code with clear naming
- Add documentation comments for public APIs using ///
- **Remember: No code is complete without tests** - If you write code, write tests for it
- **Remember: Always use Apple frameworks first** - Check SwiftUI, SwiftData, MusicKit, Apple Music API before implementing custom solutions
- **Remember: Match the project's deployment target** - Use APIs available at that minimum; consult Apple docs for the active SDK when unsure

## Final Phase Verification

Before closing a task or phase, the agent must perform a self-audit using the instructions in `swift-5-9-brutal-audit.mdc`. This is a non-negotiable step for production-ready code.

**See also:** `swift-5-9-brutal-audit.mdc` for comprehensive phase review checklist

Follow Apple's documentation for detailed implementation guidance.
