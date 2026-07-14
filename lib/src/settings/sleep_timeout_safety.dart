/// Bounds for the *stored* sleep-timeout preference.
///
/// `sleepTimeoutMinutes` does not only arrive from the settings dropdown. It
/// also arrives from `POST /api/v1/presence/settings` and from an imported
/// settings blob, and both of those are untrusted input. The handler used to
/// hard-cast the raw JSON (`json['sleepTimeoutMinutes'] as int`), so a string, a
/// double, a bool or a wildly out-of-range number either sailed straight into
/// the setting or threw a `TypeError` that surfaced as a 500.
///
/// This file is the single place that says what a storable value may be, so the
/// REST handler, the settings import and the controller all agree.
library;

/// The largest sleep timeout the app will store, in minutes (4 hours).
///
/// This is the maximum the machine's inactivity-sleep register accepts, so the
/// app can never store a preference the machine would refuse.
const int kMaxSleepTimeoutMinutes = 240;

/// The widest range the stored user preference may take.
///
/// `0` is legal and means "Disabled" — the app will not sleep the machine on its
/// own idle timer. It is a statement about *the app's* behaviour only.
const int kMinSleepTimeoutSetting = 0;
const int kMaxSleepTimeoutSetting = kMaxSleepTimeoutMinutes;

/// True if [minutes] is a storable sleep-timeout preference (`0..240`).
bool isValidSleepTimeoutSetting(int minutes) =>
    minutes >= kMinSleepTimeoutSetting && minutes <= kMaxSleepTimeoutSetting;

/// Coerces an untrusted value (REST JSON, an imported settings blob) into a
/// storable sleep-timeout preference, or `null` if it is not a usable number at
/// all — so the caller can reject it rather than store garbage.
///
/// Note `0` survives this: it is a legal *preference*, not a rejection.
int? sanitizeSleepTimeoutSetting(Object? raw) {
  final int value;
  switch (raw) {
    case final int i:
      value = i;
    case final double d:
      value = d.round();
    case final String s:
      final parsed = int.tryParse(s.trim());
      if (parsed == null) return null;
      value = parsed;
    default:
      return null; // null, bool, list, … — not a timeout.
  }
  return value.clamp(kMinSleepTimeoutSetting, kMaxSleepTimeoutSetting);
}
