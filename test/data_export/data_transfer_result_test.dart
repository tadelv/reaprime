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

  test('derives section statuses from their contents', () {
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
    final declaredFailedWithProgress = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {'status': 'failed', 'imported': 4},
        },
      },
      ['profiles'],
    );
    final flatFailedWithProgress = DataTransferPhaseOutcome.fromRemote(
      {
        'profiles': {'status': 'failed', 'imported': 4},
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
    expect(declaredFailedWithProgress.status, DataTransferStatus.partial);
    expect(
      declaredFailedWithProgress.sections['profiles']!.status,
      DataSectionStatus.failed,
    );
    expect(flatFailedWithProgress.status, DataTransferStatus.partial);
    expect(
      flatFailedWithProgress.sections['profiles']!.status,
      DataSectionStatus.failed,
    );
  });

  test('rejects hybrid flat and structured section representations', () {
    final outcome = DataTransferPhaseOutcome.fromRemote(
      {
        'sections': {
          'profiles': {'imported': 1},
        },
        'profiles': {
          'errors': ['conflicting flat result'],
        },
      },
      ['profiles'],
    );

    expect(outcome.status, DataTransferStatus.failed);
  });

  test('rejects invalid errors, warnings, and contradictory phase flags', () {
    for (final value in [
      {
        'sections': {
          'profiles': {'imported': 1, 'errors': 'bad'},
        },
      },
      {
        'sections': {
          'profiles': {
            'imported': 1,
            'warnings': ['ok', 2],
          },
        },
      },
      {
        'status': 'complete',
        'complete': true,
        'partial': true,
        'sections': {
          'profiles': {'imported': 1},
        },
      },
    ]) {
      final outcome = DataTransferPhaseOutcome.fromRemote(value, ['profiles']);
      expect(outcome.status, DataTransferStatus.failed);
    }
  });

  test('preserves conservative remote phase declarations and metadata', () {
    final failed = DataTransferPhaseOutcome.fromRemote(
      {
        'status': 'failed',
        'complete': false,
        'error': 'Import commit failed',
        'message': 'The target rejected the import.',
        'sections': {
          'profiles': {'status': 'complete', 'imported': 2},
        },
      },
      ['profiles'],
    );
    final partial = DataTransferPhaseOutcome.fromRemote(
      {
        'status': 'partial',
        'complete': false,
        'partial': true,
        'sections': {
          'profiles': {'status': 'complete', 'imported': 2},
        },
      },
      ['profiles'],
    );

    expect(failed.status, DataTransferStatus.failed);
    expect(failed.error, 'Import commit failed');
    expect(failed.message, 'The target rejected the import.');
    expect(failed.sections['profiles']!.status, DataSectionStatus.complete);
    expect(partial.status, DataTransferStatus.partial);
    expect(partial.sections['profiles']!.status, DataSectionStatus.complete);
  });
}
