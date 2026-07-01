---
description: "Build automation rules for SweetPad/xcodebuild integration and automated verification workflows"
globs: ["**/*.swift"]
alwaysApply: false
---
# Build Automation & SweetPad Integration

**CRITICAL:** This file defines how the LLM should use build automation tools (SweetPad/xcodebuild) to verify code changes automatically in agent mode.

## Purpose

When in agent mode, the LLM must automatically verify builds and tests after code changes. This ensures:

- Zero-warning policy enforcement
- Test verification before marking work complete
- Immediate error detection and fixing
- No manual build verification required

---

## SweetPad Build Commands

### Physical Device Build Command

**Current Configuration:**

- **Device ID:** `{{DEVICE_ID}}` (physical iOS device)
- **Workspace:** `{{WORKSPACE_PATH}}`
- **Scheme:** `{{SCHEME}}`
- **Configuration:** `Debug`

Set these via a project-specific rule, env vars, or `.xcode.env`. Example: `export DEVICE_ID=... WORKSPACE_PATH=... SCHEME=... RESULT_BUNDLE_PATH=...` and use `$DEVICE_ID`, `$WORKSPACE_PATH`, etc. in the commands below.

**Build Command:**

```bash
xcodebuild \
  -scheme {{SCHEME}} \
  -configuration Debug \
  -workspace {{WORKSPACE_PATH}} \
  -destination 'platform=iOS,id={{DEVICE_ID}}' \
  -resultBundlePath '{{RESULT_BUNDLE_PATH}}' \
  -allowProvisioningUpdates \
  build
```

**Test Command:**

```bash
xcodebuild \
  -scheme {{SCHEME}} \
  -configuration Debug \
  -workspace {{WORKSPACE_PATH}} \
  -destination 'platform=iOS,id={{DEVICE_ID}}' \
  -resultBundlePath '{{RESULT_BUNDLE_PATH}}' \
  -allowProvisioningUpdates \
  test
```

**Notes:**

- `-allowProvisioningUpdates` enables automatic code signing/provisioning
- Result bundle path is SweetPad-specific and may change with workspace storage
- Device ID can be obtained via: `xcrun xctrace list devices`
- Update device ID if physical device changes

---

## Alternative: Simulator Build (Fallback)

If physical device is unavailable or for faster iteration, use iOS Simulator:

**Simulator Build Command:**

```bash
xcodebuild \
  -scheme {{SCHEME}} \
  -configuration Debug \
  -workspace {{WORKSPACE_PATH}} \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

**Simulator Test Command:**

```bash
xcodebuild test \
  -scheme {{SCHEME}} \
  -configuration Debug \
  -workspace {{WORKSPACE_PATH}} \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan {{SCHEME}}
```

**When to Use Simulator:**

- Physical device not connected
- Faster build iteration needed
- Testing simulator-specific features
- CI/CD environments

---

## Build Output Parsing

**CRITICAL:** In agent mode, the LLM must parse xcodebuild output to extract actionable information.

### Error Patterns

**Compilation Errors:**

```
/path/to/file.swift:42:15: error: 'SomeType' is unavailable
/path/to/file.swift:50:8: error: cannot find 'SomeFunction' in scope
```

**Extract:**

- File path: `/path/to/file.swift`
- Line number: `42`
- Column: `15` (optional, but useful)
- Error message: `'SomeType' is unavailable`
- Error type: `error`

### Warning Patterns

**Compilation Warnings:**

```
/path/to/file.swift:30:5: warning: result of call to 'someMethod()' is unused
/path/to/file.swift:45:12: warning: 'someVariable' was never mutated; consider changing to 'let'
```

**Extract:**

- File path: `/path/to/file.swift`
- Line number: `30`
- Warning message: `result of call to 'someMethod()' is unused`
- Warning type: `warning`

### Success Indicators

**Build Success:**

```
** BUILD SUCCEEDED **
```

**Build Failure:**

```
** BUILD FAILED **
```

### Test Result Patterns

**Test Success:**

```
Test Suite 'MyAppTests' passed.
Executed 45 tests, with 0 failures (0 unexpected) in 2.345 seconds
```

**Test Failure:**

```
Test Suite 'MyAppTests' failed.
Executed 45 tests, with 2 failures (2 unexpected) in 2.345 seconds
```

**Individual Test Failure:**

```
/path/to/TestFile.swift:123: error: testMethodName() : XCTAssertEqual failed: ("expected") is not equal to ("actual")
```

---

## Automation Workflow (CRITICAL)

**CRITICAL:** The LLM must follow this workflow after EVERY code change in agent mode.

### Step 1: Execute Build

1. Run build command (physical device or simulator)
2. Capture full output (stdout + stderr)
3. Parse output for errors and warnings

### Step 2: Handle Build Errors

**If errors exist:**

- ❌ **STOP** - Do not proceed until errors are fixed
- Extract all error details (file, line, message)
- Analyze each error
- Fix errors in code
- **Loop back to Step 1** until build succeeds

**Error Fixing Priority:**

1. Compilation errors (must fix immediately)
2. Linker errors (missing symbols, frameworks)
3. Code signing errors (provisioning issues)

### Step 3: Handle Build Warnings

**If warnings exist:**

- ⚠️ **FIX** - Per zero-warning/zero-error policy (see `swift-5-9-development-standards.mdc` or `swift-6-development-standards.mdc` per project language mode)
- Extract all warning details
- Fix warnings in code
- **Loop back to Step 1** until zero warnings

**Warning Types to Fix:**

- Unused variables/methods
- Deprecated API usage
- Concurrency warnings (Sendable, actor isolation)
- Force unwraps or unsafe patterns
- Any warning that indicates potential runtime issues

### Step 4: Execute Tests

**Only after build succeeds with zero warnings:**

1. **Determine which tests to run:**
   - For UI tests: Use targeted test execution when modifying specific features (e.g. `-only-testing:MyAppUITests/<TestClassName>`). For file-to-test mapping, maintain a project-specific rule or doc.
   - For unit tests: Run all unit tests (fast execution)
   - For UI infrastructure changes (UITestBase, UIHelpers, LiquidGlass): Run full UI test suite

2. Run test command (targeted or full suite)
3. Capture full output
4. Parse test results

**Targeted UI Test Execution:**
- Use `-only-testing:MyAppUITests/<TestClassName>` for feature-specific UI changes. Project-specific rules can define file-to-test mappings.
- **Exception:** Always run full UI suite for Liquid Glass changes or shared components

### Step 5: Handle Test Failures

**If test failures exist:**

- ❌ **STOP** - Do not mark work complete
- Extract failing test details
- Analyze test failures
- Fix tests or code (depending on failure reason)
- **Loop back to Step 4** until all tests pass

**Test Failure Analysis:**

- Is it a test bug? → Fix test
- Is it a code bug? → Fix code, then re-build (Step 1)
- Is it a flaky test? → Document, but still fix if possible

### Step 6: Mark Work Complete

**Only when ALL conditions met:**

- ✅ Build succeeded
- ✅ Zero warnings
- ✅ All tests passed
- ✅ Code changes are correct

**Report to user:**

```
✅ Build succeeded with 0 warnings
✅ All 45 tests passed
✅ Code changes complete
```

---

## Integration with Existing Rules

### Zero-Warning Policy

**Reference:** `swift-5-9-development-standards.mdc` or `swift-6-development-standards.mdc` - "Zero-Warning Policy" / "Development Process"

**Enforcement:**

- Build automation workflow enforces zero warnings automatically
- Warnings are treated as blocking issues
- Work is not complete until zero warnings achieved

### Test Requirements

**Reference:** `swift-5-9-development-standards.mdc` (Swift 5.9) or `swift-6-development-standards.mdc` (Swift 6) - "Code Completion Requires Passing Tests"

**Enforcement:**

- Tests must pass before marking work complete
- Test failures block completion
- All existing tests must pass (no regressions)
- New functionality must have tests

### Compile and Test Between Phases

**Reference:** Same Swift standards files - "Development Process"

**Enforcement:**

- Build verification happens after every code change
- Not just between phases, but continuously
- Immediate feedback loop prevents accumulation of issues

---

## Device Management

### Getting Device ID

**List available devices:**

```bash
xcrun xctrace list devices
```

**Output format:**

```
== Devices ==
My iPhone ({{DEVICE_ID}}) (Connected)
iPhone 16 Simulator (ABC12345-...) (Booted)
```

**Update device ID in commands if:**

- Physical device changes
- Different device needed for testing
- Device ID becomes invalid

### Device Selection Strategy

1. **Prefer physical device** for:
   - Real-world testing
   - Performance validation
   - Device-specific features
   - Final verification

2. **Use simulator** for:
   - Fast iteration
   - CI/CD environments
   - When device unavailable
   - Simulator-specific testing

---

## Error Handling in Automation

### Build Command Failures

**If xcodebuild command fails to execute:**

- Check Xcode installation: `xcodebuild -version`
- Check workspace path exists
- Check scheme name is correct
- Check device/simulator availability

### Provisioning Errors

**If code signing fails:**

- Verify `-allowProvisioningUpdates` is present
- Check Apple Developer account access
- Verify device is registered
- May need manual Xcode setup first time

### Timeout Handling

**If build takes too long:**

- Consider using simulator for faster builds
- Check for infinite loops or hanging operations
- Verify dependencies are available
- May need to cancel and investigate

---

## Best Practices

### Build Performance

- Use simulator for rapid iteration
- Use physical device for final verification
- Clean build if strange errors appear: `xcodebuild clean`
- Cache build artifacts when possible

### Output Management

- Capture full output (stdout + stderr) for parsing
- Log build output for debugging
- Parse errors/warnings programmatically
- Report clear, actionable error messages

### Workflow Efficiency

- Fix errors immediately (don't accumulate)
- Fix warnings as they appear (zero-warning policy)
- Run tests only after clean build
- Don't skip verification steps

---

## Example Automation Flow

```
User: "Fix the compilation error in PlaylistRepository"

LLM (Agent Mode):
1. Read PlaylistRepository.swift
2. Make code changes
3. Execute: xcodebuild -scheme {{SCHEME}} ... build
4. Parse output: "error: 'X' is unavailable at PlaylistRepository.swift:42"
5. Fix error in code
6. Re-execute build
7. Parse output: "BUILD SUCCEEDED" + 0 errors, 0 warnings ✅
8. Execute: xcodebuild test -scheme {{SCHEME}} ... test
9. Parse output: "Test Suite 'MyAppTests' passed. 45 tests, 0 failures" ✅
10. Report: "✅ Fixed. Build clean (0 warnings), all 45 tests passing."
```

---

## Summary

**CRITICAL Rules:**

1. ✅ Build after every code change
2. ✅ Fix errors immediately (loop until clean)
3. ✅ Fix warnings immediately (zero-warning policy)
4. ✅ Run tests after clean build
5. ✅ Fix test failures before completion
6. ✅ Only mark work complete when: Build ✅ + 0 Warnings ✅ + Tests ✅

**Commands:**

- Physical device: Use provided SweetPad commands
- Simulator: Use alternative commands with `platform=iOS Simulator`
- Device ID: Update if device changes (use `xcrun xctrace list devices`)

**Integration:**

- Enforces zero-warning policy automatically
- Enforces test requirements automatically
- Provides continuous feedback loop
- Eliminates manual verification steps
