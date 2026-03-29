# TestFlight Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable iOS builds to be submitted to TestFlight, both locally and via automated CI/CD on tag push.

**Architecture:** One Info.plist change for export compliance, one new CI job (`build-ios`) in `release.yml` that builds an IPA with manual signing and uploads to TestFlight via App Store Connect API. The job runs independently from the existing `create-release` job.

**Tech Stack:** Flutter (iOS), GitHub Actions, Xcode CLI tools (`xcodebuild`, `xcrun altool`), App Store Connect API

---

### Task 1: Add Export Compliance Key to Info.plist

**Files:**
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Add ITSAppUsesNonExemptEncryption key**

In `ios/Runner/Info.plist`, add the following key-value pair inside the top-level `<dict>`, after the `UIBackgroundModes` entry (line 71):

```xml
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```

This tells Apple the app uses no encryption beyond standard HTTPS/TLS, preventing the export compliance prompt on every TestFlight upload.

- [ ] **Step 2: Verify the change**

Run:
```bash
flutter analyze
```

Expected: No new issues. The Info.plist key doesn't affect analysis, but this confirms nothing was broken by the edit.

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/Info.plist
git commit -m "feat(ios): add export compliance key to Info.plist

Adds ITSAppUsesNonExemptEncryption=NO so Apple doesn't prompt
about encryption on every TestFlight upload."
```

---

### Task 2: Add `build-ios` Job to CI/CD Release Workflow

**Files:**
- Modify: `.github/workflows/release.yml`

This is the main task. The new `build-ios` job follows the same structure as the existing `build-macos` job but builds an IPA with manual signing and uploads it to TestFlight.

- [ ] **Step 1: Add the `build-ios` job**

In `.github/workflows/release.yml`, add the following job after the `build-windows` job (before `create-release`). Insert it at the same indentation level as the other `build-*` jobs:

```yaml
  build-ios:
    runs-on: macos-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Install dependencies
        run: flutter pub get

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Build DYE2 plugin
        run: |
          cd packages/dye2-plugin
          npm ci
          npm run build

      - name: Import distribution certificate
        env:
          CERTIFICATE_P12: ${{ secrets.APPLE_DISTRIBUTION_CERTIFICATE_P12 }}
          CERTIFICATE_PASSWORD: ${{ secrets.APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Decode and import certificate
          echo "$CERTIFICATE_P12" | base64 --decode > certificate.p12
          security import certificate.p12 \
            -k "$KEYCHAIN_PATH" \
            -P "$CERTIFICATE_PASSWORD" \
            -T /usr/bin/codesign

          # Allow codesign to access keychain
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Make this keychain the default
          security list-keychain -d user -s "$KEYCHAIN_PATH"

          # Clean up
          rm certificate.p12

      - name: Install provisioning profile
        env:
          PROVISIONING_PROFILE: ${{ secrets.IOS_PROVISIONING_PROFILE_B64 }}
        run: |
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision

          echo "$PROVISIONING_PROFILE" | base64 --decode > "$PP_PATH"

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp "$PP_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/

      - name: Create ExportOptions.plist
        env:
          TEAM_ID: ${{ secrets.TEAM_ID }}
          PROVISIONING_PROFILE_NAME: ${{ secrets.IOS_PROVISIONING_PROFILE_NAME }}
        run: |
          cat > ExportOptions.plist <<EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>method</key>
            <string>app-store</string>
            <key>teamID</key>
            <string>${TEAM_ID}</string>
            <key>signingStyle</key>
            <string>manual</string>
            <key>signingCertificate</key>
            <string>Apple Distribution</string>
            <key>provisioningProfiles</key>
            <dict>
              <key>net.tadel.reaprime</key>
              <string>${PROVISIONING_PROFILE_NAME}</string>
            </dict>
            <key>uploadSymbols</key>
            <true/>
          </dict>
          </plist>
          EOF

      - name: Build IPA
        run: ./flutter_with_commit.sh build ipa --release --export-options-plist=ExportOptions.plist
        env:
          FEEDBACK_TOKEN: ${{ secrets.FEEDBACK_TOKEN }}

      - name: Upload to TestFlight
        env:
          API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          API_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
          API_KEY_P8: ${{ secrets.APP_STORE_CONNECT_API_KEY_P8 }}
        run: |
          # Write the API key to the expected location
          mkdir -p ~/.private_keys
          echo "$API_KEY_P8" | base64 --decode > ~/.private_keys/AuthKey_${API_KEY_ID}.p8

          # Find the built IPA
          IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -1)

          if [ -z "$IPA_PATH" ]; then
            echo "Error: No IPA found in build/ios/ipa/"
            exit 1
          fi

          echo "Uploading $IPA_PATH to TestFlight..."

          xcrun altool --upload-app \
            --type ios \
            --file "$IPA_PATH" \
            --apiKey "$API_KEY_ID" \
            --apiIssuer "$API_ISSUER_ID"
```

- [ ] **Step 2: Add `IOS_PROVISIONING_PROFILE_NAME` to the secrets table in the spec**

Note: The `ExportOptions.plist` generation requires one additional secret not in the original spec: `IOS_PROVISIONING_PROFILE_NAME` — the human-readable name of the provisioning profile (e.g., "Streamline Bridge App Store"). This is set when creating the profile in Apple Developer Portal.

- [ ] **Step 3: Update the release body to mention iOS/TestFlight**

In the `create-release` job's release body, add an iOS section after the Windows entry. Find this line in the `body:` field:

```yaml
            > **Windows users**: Streamline-Bridge requires the [Microsoft Visual C++ Redistributable]...
```

Add after it:

```yaml

            **iOS**: Available via TestFlight. [Join the beta](https://testflight.apple.com/join/<your-link>)
```

Note: The TestFlight public link will be available after the first build is uploaded and external testing is configured. Use a placeholder for now and update it after the first successful upload.

- [ ] **Step 4: Verify YAML syntax**

Run:
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

If python3 yaml module isn't available, use:
```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')" && echo "YAML OK"
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add iOS build and TestFlight upload to release workflow

Adds build-ios job that runs on tag push, builds an IPA with
manual signing, and uploads to TestFlight via App Store Connect API.
Runs independently from the create-release job."
```

---

### Task 3: Apple Developer Portal and GitHub Secrets Setup

This task is a manual walkthrough — no code changes, but required before the CI job can run.

- [ ] **Step 1: Create Apple Distribution certificate**

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click "+" to create a new certificate
3. Select "Apple Distribution" (covers both App Store and TestFlight)
4. Follow the CSR (Certificate Signing Request) flow:
   - Open Keychain Access on your Mac
   - Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority
   - Enter your email, leave CA Email blank, select "Saved to disk"
   - Upload the `.certSigningRequest` file
5. Download the `.cer` file and double-click to install in Keychain Access
6. In Keychain Access, find the certificate under "My Certificates"
7. Right-click → Export → save as `.p12` with a strong password
8. Base64-encode it:
   ```bash
   base64 -i Certificates.p12 | pbcopy
   ```
9. Add to GitHub: Settings → Secrets and variables → Actions → New repository secret:
   - Name: `APPLE_DISTRIBUTION_CERTIFICATE_P12`
   - Value: paste the base64 string
   - Name: `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`
   - Value: the password you chose for the .p12

- [ ] **Step 2: Create App Store provisioning profile**

1. Go to https://developer.apple.com/account/resources/profiles/list
2. Click "+" to create a new profile
3. Select "App Store Connect" under Distribution
4. Select app ID `net.tadel.reaprime`
5. Select the Apple Distribution certificate you just created
6. Name it (e.g., "Streamline Bridge App Store") — **remember this name exactly**
7. Download the `.mobileprovision` file
8. Base64-encode it:
   ```bash
   base64 -i StreamlineBridge_AppStore.mobileprovision | pbcopy
   ```
9. Add to GitHub secrets:
   - Name: `IOS_PROVISIONING_PROFILE_B64`
   - Value: paste the base64 string
   - Name: `IOS_PROVISIONING_PROFILE_NAME`
   - Value: the exact name you gave the profile (e.g., "Streamline Bridge App Store")

- [ ] **Step 3: Create App Store Connect API key**

1. Go to https://appstoreconnect.apple.com/access/integrations/api
2. Click "+" to generate a new key
3. Name: "CI TestFlight Upload" (or similar)
4. Role: "App Manager"
5. Click "Generate"
6. **Download the .p8 file immediately** — Apple only lets you download it once
7. Note the Key ID (shown in the table) and Issuer ID (shown at the top of the page)
8. Base64-encode the .p8 key:
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```
9. Add to GitHub secrets:
   - Name: `APP_STORE_CONNECT_API_KEY_ID`
   - Value: the Key ID
   - Name: `APP_STORE_CONNECT_API_ISSUER_ID`
   - Value: the Issuer ID
   - Name: `APP_STORE_CONNECT_API_KEY_P8`
   - Value: paste the base64 string

- [ ] **Step 4: Verify TEAM_ID secret exists**

The `ExportOptions.plist` uses `${{ secrets.TEAM_ID }}` which is already used by the macOS notarization step. Verify it exists in your GitHub secrets. If not, add it:
- Name: `TEAM_ID`
- Value: `XLS3XF57J8`

---

### Task 4: Local Build Test

This task validates the local build workflow before relying on CI.

- [ ] **Step 1: Build the IPA locally**

```bash
./flutter_with_commit.sh build ipa --release
```

Expected: Build succeeds, output shows path to the `.xcarchive` and IPA in `build/ios/archive/` and `build/ios/ipa/`.

Note: This uses automatic signing (your local Xcode configuration). If you get a signing error, open `ios/Runner.xcworkspace` in Xcode, go to Signing & Capabilities, and verify the team is set to `XLS3XF57J8` with automatic signing enabled.

- [ ] **Step 2: Upload to TestFlight via Xcode**

1. Open Xcode
2. Window → Organizer (or the archive should open automatically)
3. Select the latest archive
4. Click "Distribute App"
5. Select "TestFlight & App Store" → Next
6. Select "Upload" → Next
7. Xcode will handle signing automatically
8. Wait for upload to complete

- [ ] **Step 3: Verify in App Store Connect**

1. Go to https://appstoreconnect.apple.com → Your App → TestFlight
2. The build should appear within 10-30 minutes (Apple processes it)
3. Status should transition: "Processing" → "Ready to Test"

- [ ] **Step 4: Add internal testers**

1. In App Store Connect → TestFlight → Internal Testing
2. Create a new group or use the default
3. Add testers (they must be App Store Connect users with appropriate roles)
4. Testers receive a TestFlight invitation email

---

### Task 5: Update Release Documentation

**Files:**
- Modify: `doc/RELEASE.md`

- [ ] **Step 1: Add iOS/TestFlight section to RELEASE.md**

In `doc/RELEASE.md`, add the following section after the existing content about release workflow:

```markdown
## iOS / TestFlight

iOS builds are uploaded to TestFlight automatically on tag push, running as an independent CI job (`build-ios`) alongside the other platform builds.

### Local TestFlight Upload

To build and upload an IPA locally:

```bash
./flutter_with_commit.sh build ipa --release
```

Then upload via Xcode Organizer (Window → Organizer → Distribute App → TestFlight & App Store).

### CI/CD

The `build-ios` job in `.github/workflows/release.yml`:
1. Builds the IPA with manual signing (Apple Distribution certificate + App Store provisioning profile)
2. Uploads to TestFlight via App Store Connect API

Required secrets: `APPLE_DISTRIBUTION_CERTIFICATE_P12`, `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_B64`, `IOS_PROVISIONING_PROFILE_NAME`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`, `TEAM_ID`.

### TestFlight Distribution

- **Internal testing**: Available immediately after processing (~10-30 min). Up to 100 testers (App Store Connect users).
- **External testing**: Requires App Review for first build per version. Up to 10,000 testers. Can use a public link.
```

- [ ] **Step 2: Commit**

```bash
git add doc/RELEASE.md
git commit -m "docs: add iOS/TestFlight section to release documentation"
```
