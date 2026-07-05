### Is your feature request related to a problem? Please describe.
Currently, Reaprime does not have native support for external temperature probes, specifically the Combustion Inc. thermometer. Users who want to monitor milk temperature during steaming or track external temperatures alongside their espresso shot cannot easily do so within the app.

### Describe the solution you'd like
I propose integrating support for the Combustion Inc. BLE temperature probe. The implementation adds a new `SensorController`, updates the BLE discovery service to recognize the Combustion probe via its manufacturer advertising data (even without connecting), and pipes this real-time temperature data into the app state. It also adds a new "Steam" workflow settings page to manage this.

### Describe alternatives you've considered
Relying on a separate app to monitor the Combustion probe, but this breaks the unified dashboard experience that Reaprime aims to provide.

### Additional Context
I have been working on implementing this feature locally and it looks to be functioning correctly in the UI/simulator. I will be opening a Draft Pull Request shortly with the proposed code so the community can review the approach and help test it on physical Decent hardware.
