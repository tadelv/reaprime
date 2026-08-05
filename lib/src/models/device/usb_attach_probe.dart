import 'de1_interface.dart';
import 'device_attach_notifier.dart';

/// Outcome of probing a specifically attached USB device for a supported
/// machine.
sealed class AttachProbeResult {
  const AttachProbeResult();
}

/// A supported machine was positively identified, connected, and its
/// identity initialization completed.
class AttachProbeConnected extends AttachProbeResult {
  const AttachProbeConnected(this.machine);

  final De1Interface machine;
}

/// No supported machine corresponds to the attachment: uncorrelated,
/// unsupported, or already known. Nothing was changed.
class AttachProbeUnsupported extends AttachProbeResult {
  const AttachProbeUnsupported();
}

/// A supported machine was detected but connection or identity
/// initialization failed. All resources were cleaned up.
class AttachProbeFailed extends AttachProbeResult {
  const AttachProbeFailed({this.deviceId, this.deviceName});

  final String? deviceId;
  final String? deviceName;
}

/// Optional capability for the discovery service that originated a
/// [DeviceAttachedEvent]: positively identify and connect the machine on the
/// specifically attached USB device, bypassing preferred-machine policy.
abstract class UsbAttachProbe {
  Future<AttachProbeResult> connectAttachedMachine(DeviceAttachedEvent event);
}
