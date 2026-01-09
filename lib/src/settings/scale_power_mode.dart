/// Scale power management mode for automatic power control
/// tied to machine state transitions
enum ScalePowerMode {
  /// Disable automatic scale power management (manual control only)
  disabled,

  /// Put scale display to sleep when machine sleeps
  displayOff,

  /// Power down / disconnect scale completely when machine sleeps
  powerOff,
}

extension ScalePowerModeExtension on ScalePowerMode {
  String get displayName {
    switch (this) {
      case ScalePowerMode.disabled:
        return 'Disabled';
      case ScalePowerMode.displayOff:
        return 'Display Off';
      case ScalePowerMode.powerOff:
        return 'Power Off';
    }
  }

  String get description {
    switch (this) {
      case ScalePowerMode.disabled:
        return 'Manual control only, no automatic power management';
      case ScalePowerMode.displayOff:
        return 'Turn off scale display when machine sleeps';
      case ScalePowerMode.powerOff:
        return 'Power down scale completely when machine sleeps';
    }
  }
}

extension ScalePowerModeFromString on ScalePowerMode {
  static ScalePowerMode? fromString(String value) {
    switch (value.toLowerCase()) {
      case 'disabled':
        return ScalePowerMode.disabled;
      case 'displayoff':
      case 'display_off':
        return ScalePowerMode.displayOff;
      case 'poweroff':
      case 'power_off':
        return ScalePowerMode.powerOff;
      default:
        return null;
    }
  }
}
