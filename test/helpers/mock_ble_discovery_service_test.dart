import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/adapter_state.dart';

import '../helpers/mock_device_discovery_service.dart';

void main() {
  test('MockBleDiscoveryService emits adapter state changes', () async {
    final service = MockBleDiscoveryService();
    expect(await service.adapterStateStream.first, AdapterState.unknown);
    service.setAdapterState(AdapterState.poweredOn);
    expect(await service.adapterStateStream.first, AdapterState.poweredOn);
    service.setAdapterState(AdapterState.poweredOff);
    expect(await service.adapterStateStream.first, AdapterState.poweredOff);
    service.dispose();
  });
}
