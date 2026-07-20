const int kMinSleepTimeoutPreferenceMinutes = 0;
const int kMaxSleepTimeoutPreferenceMinutes = 240;

int normalizeSleepTimeoutPreferenceMinutes(int value) => value.clamp(
  kMinSleepTimeoutPreferenceMinutes,
  kMaxSleepTimeoutPreferenceMinutes,
);
