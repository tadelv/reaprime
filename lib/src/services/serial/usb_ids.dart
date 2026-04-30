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

/// Bengle USB ID pairs. Populated once captured from hardware.
const List<UsbIdPair> bengleUsbIds = [];

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
