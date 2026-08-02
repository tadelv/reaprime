import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/webserver/data_export/data_transfer_result.dart';

void main() {
  test('classifies errors with progress as partial', () {
    final phase = DataTransferPhaseOutcome.fromSections(
      rawSections: {
        'profiles': {
          'imported': 2,
          'errors': ['bad row'],
        },
      },
      expectedSections: ['profiles'],
    );

    expect(phase.status, DataTransferStatus.partial);
    expect(phase.sections['profiles']!.status, DataSectionStatus.partial);
  });

  test('does not trust declared complete status over missing sections', () {
    final phase = DataTransferPhaseOutcome.fromRemote(
      {
        'status': 'complete',
        'complete': true,
        'sections': {
          'profiles': {'imported': 1},
        },
      },
      ['profiles', 'shots'],
    );

    expect(phase.status, DataTransferStatus.partial);
    expect(phase.sections['shots']!.status, DataSectionStatus.failed);
  });
}
