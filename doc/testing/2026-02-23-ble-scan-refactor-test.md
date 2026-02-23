# BLE Scan Refactor Testing Results

**Date:** 2026-02-23
**Tester:** [Name]
**Branch:** fix/ble-uuids

## Test Environment

- Device: [Android/iOS/Linux/macOS/Windows]
- OS Version: [e.g., Android 12]
- App Version: [git commit hash]

## Test Cases

### Discovery Tests

#### Test 1: Decent Scale Discovery
- [ ] Turn on Decent Scale
- [ ] Tap scan in app
- [ ] Scale appears in device list
- [ ] Logs show: "Matched device ... Decent Scale"
- [ ] Scale connects successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 2: Skale2 Discovery
- [ ] Turn on Skale2
- [ ] Tap scan in app
- [ ] Scale appears in device list
- [ ] Scale connects successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 3: Multiple Devices
- [ ] Turn on DE1 machine + scale
- [ ] Tap scan
- [ ] Both devices appear
- [ ] Both connect successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 4: Unknown Device
- [ ] Scan with non-coffee BLE device nearby
- [ ] Unknown device does NOT appear in list
- [ ] No errors in logs

**Result:** PASS / FAIL
**Notes:**

### Service Verification Tests

#### Test 5: Wrong Device Name
- [ ] If possible, test device with mismatched name/service UUID
- [ ] Device should fail service verification
- [ ] Error logged: "Expected service X not found"
- [ ] Device removed from list

**Result:** PASS / FAIL
**Notes:**

### Regression Tests

#### Test 6: Existing Devices Still Work
- [ ] Test Felicita Arc
- [ ] Test Acaia scale
- [ ] Test Hiroia Jimmy
- [ ] All connect as before

**Result:** PASS / FAIL
**Notes:**

## Issues Found

[List any issues discovered during testing]

## Logs

[Paste relevant log excerpts here]
