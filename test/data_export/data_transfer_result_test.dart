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

  test('fails closed for empty and explicitly failed sections', () {
    final empty = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {'profiles': {}},
      },
      ['profiles'],
    );
    final failed = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {'status': 'failed'},
        },
      },
      ['profiles'],
    );

    expect(empty.status, DataTransferStatus.failed);
    expect(empty.sections['profiles']!.status, DataSectionStatus.failed);
    expect(failed.status, DataTransferStatus.failed);
    expect(failed.sections['profiles']!.status, DataSectionStatus.failed);
  });

  test('rejects invalid and contradictory section statuses', () {
    final invalid = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {'status': 'unknown', 'imported': 1},
        },
      },
      ['profiles'],
    );
    final contradictory = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {
            'status': 'complete',
            'imported': 1,
            'errors': ['bad row'],
          },
        },
      },
      ['profiles'],
    );
    final declaredPartial = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {'status': 'partial'},
        },
      },
      ['profiles'],
    );

    expect(invalid.status, DataTransferStatus.failed);
    expect(invalid.sections['profiles']!.status, DataSectionStatus.failed);
    expect(contradictory.status, DataTransferStatus.partial);
    expect(
      contradictory.sections['profiles']!.status,
      DataSectionStatus.partial,
    );
    expect(declaredPartial.status, DataTransferStatus.partial);
    expect(
      declaredPartial.sections['profiles']!.status,
      DataSectionStatus.partial,
    );
  });
}
