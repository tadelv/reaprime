part of 'de1_controller.dart';

extension Defaults on De1Controller {
  Future<void> _setDe1Defaults() async {
    await _de1?.setFanThreshhold(55);

    // TODO: set flush, steam and hotwater defaults
    // TODO: set heater defaults

    if (defaultWorkflow == null) {
      return;
    }
    final defaultProfile = defaultWorkflow?.profile;
    if (defaultProfile == null) {
      return;
    }
    await _de1?.setProfile(defaultProfile);
  }
}
