/// USB VID:PID dispatch for DE1-family devices.
///
/// The desktop and Android serial services consult [usbDeviceTable] as a
/// fast path before falling through to protocol probing. Currently both
/// tables are empty until concrete pairs are captured from hardware
/// (procedure documented in `doc/plans/...bengle-mock-and-usb.md`).
///
/// Note on DE1: the original DE1 uses a generic USB-serial adapter
/// (FTDI / similar), so VID:PID matching may false-match on unrelated
/// devices. The `productName == "DE1"` shortcut is more specific and
/// stays in place. Only add a DE1 VID:PID pair here if a specific DE1
/// model is verified to expose a custom descriptor distinct from the
/// generic adapter.
enum UsbDeviceModel { de1, bengle }

/// `(vendorId, productId)` pairs.
typedef UsbIdPair = (int vid, int pid);

/// DE1 USB ID pairs. See doc on [UsbDeviceModel] for caveats.
const List<UsbIdPair> de1UsbIds = [];

/// Bengle USB ID pairs. Deliberately EMPTY: the Bengle's TinyUSB stack
/// currently enumerates with the pico-sdk DEFAULT ids (`0x2E8A:0x000A`,
/// product string "TinyUSB Device" — captured from hardware),
/// which any default pico-sdk CDC device also uses. Too generic for the
/// direct-instantiation shortcut; see [bengleProbeCandidateIds] instead.
const List<UsbIdPair> bengleUsbIds = [];

/// VID:PID pairs that qualify a port for the identification PROBE (the
/// v13Model read stays the authority on what the device is), without
/// requiring the product-name gate to pass. This is how a Bengle whose
/// firmware still ships the TinyUSB default descriptors ("TinyUSB
/// Device") gets probed at all on Android.
const List<UsbIdPair> bengleProbeCandidateIds = [(0x2E8A, 0x000A)];

/// True when `(vid, pid)` is worth a DE1-protocol probe even though the
/// product name says nothing useful. Null inputs yield false.
bool isBengleProbeCandidate({required int? vid, required int? pid}) {
  if (vid == null || pid == null) return false;
  return bengleProbeCandidateIds.contains((vid, pid));
}

/// Default table consulted by serial services.
const Map<UsbDeviceModel, List<UsbIdPair>> usbDeviceTable = {
  UsbDeviceModel.de1: de1UsbIds,
  UsbDeviceModel.bengle: bengleUsbIds,
};

/// Returns the [UsbDeviceModel] for a `(vid, pid)` pair found in [table],
/// or null if neither is present in any list. Null inputs yield null.
UsbDeviceModel? matchUsbDevice(
  Map<UsbDeviceModel, List<UsbIdPair>> table, {
  required int? vid,
  required int? pid,
}) {
  if (vid == null || pid == null) return null;
  for (final entry in table.entries) {
    for (final pair in entry.value) {
      if (pair.$1 == vid && pair.$2 == pid) {
        return entry.key;
      }
    }
  }
  return null;
}
