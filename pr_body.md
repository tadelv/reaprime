### Description
This PR introduces the logic and UI for integrating the Combustion Inc. BLE temperature probe. 

**Resolves / Addresses:** #403

### ⚠️ Hardware Testing Needed ⚠️
**Please note: This is currently a Work In Progress (WIP).** 
While this feature appears to be fully functional in the local development environment/simulator, **I do not currently have the physical machinery (Decent Espresso machine, Combustion probe, and Android tablet setup) to test this in the real world.**

I am opening this PR to request two things from the community/maintainers:
1. **Code Review:** Feedback on the implementation, architecture, and whether it aligns with project standards.
2. **Hardware Testing:** I would greatly appreciate it if someone with a physical Decent setup and a Combustion probe could pull this branch, run it (or download the APK from the CI pipeline), and verify that it behaves as expected during an actual pull or steaming session.

### Changes Made
* Added a new `SensorController` and integrated it into `AppRoot` / `MyApp`.
* Modified `UniversalBleDiscoveryService` and `UniversalBleTransport` to handle `CombustionAdvertisingTransport` (extracting temperature data directly from BLE manufacturer advertising data).
* Plumbed the sensor state into `De1StateManager` and `ShotSequencer`.
* Added a new "Steam" workflow settings page in the launcher.

### How to Test (For Reviewers with Hardware)
1. Connect the app to a physical Decent espresso machine and have a Combustion Inc. probe active.
2. Navigate to the new Steam/Sensor settings to verify the probe is discovered.
3. Start a standard profile shot or steaming session.
4. Verify that the temperature readings from the Combustion probe appear correctly and update smoothly without crashing the app.

### Notes for CI
*Once the GitHub Actions CI builds the Android APK for this branch, I plan to download it from the artifacts to sideload onto a tablet for further UI testing.*
