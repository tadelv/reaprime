// Firmware <-> app MMR contract checker (CI drift gate).
//
// Validates every app-declared MMR register against the machine-readable
// firmware contract `assets/api/bengle_hw_v1.yml` (contract_version 1,
// distilled from firmware the firmware register table @ a firmware development branch
// The MMR layout is hand-declared twice (firmware C, app Dart); this test is
// the machine check that the two copies cannot silently drift apart.
//
// Run: flutter test test/unit/models/device/impl/bengle/mmr_contract_test.dart
// (rides the normal `flutter test` CI job; reads the contract with plain File
// IO relative to the package root, which is where `flutter test` runs).
//
// WHAT IS ASSERTED (v1 semantics):
//   * address -- exact match.
//   * length  -- exact match.
//   * scale   -- app writeScale == contract mult AND app readScale == 1/mult.
//               Non-scaled registers carry the default 1.0/1.0 and contract
//               mult 1, so the same rule covers every kind.
//   * range   -- app SUBSET of contract: a min/max bound the app declares must
//               sit inside the contract's bound. The app declaring NO bound is
//               legal (contract bounds are documentation -- the firmware never
//               range-checks Bengle macro-path writes; the app is the guard),
//               and the app being strictly narrower is legal (e.g. CalFlowEst
//               app raw min 130 vs contract 125).
//   * perms are NOT asserted in v1: the app enums carry no perms field (a
//     `perms` getter on MmrAddress is proposed via the Phase-0 issue).
//   * Direction: every app-declared register must exist in the contract and
//     match; contract rows with no app entry are legal -- the app grows into
//     the contract branch by branch (unconsumed rows are printed
//     informationally below).
//
// EXTENSION PROTOCOL (how capability branches extend this test):
//   The single registration table is `entriesUnderTest` below, grouped into
//   clearly-marked sections, one per capability branch. On the foundation
//   branch only the MMRItem section (and its import) is active; each later
//   capability branch that introduces an MMR enum:
//     1. uncomments (or appends) its section's `ContractEntry` lines -- one
//        line per register, mapping the enum entry to its contract row by the
//        FIRMWARE register name;
//     2. uncomments the import its section needs (marked alongside);
//     3. never edits the assertions -- if the checker fails, the enum or the
//        contract (with a contract_version bump) is wrong, not the test.
//   An app desc string that deliberately differs from the firmware name is
//   recorded in the contract as `app_alias` (today: TargetMilkTemp vs the
//   app's 'StopAtTemperatureTarget').
//
// CONTRACT CHANGE PROTOCOL: firmware changes a register -> regenerate
// bengle_hw_v1.yml from the new the firmware register table (never from a stale working tree) ->
// bump contract_version -> update the app enums -> update
// `_expectedContractVersion` here. Firmware and app PRs both cite the version.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart'
    show MMRItem;
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart'
    show MmrAddress;
// Thermal branch (spec 08) uncomments this import with its section below:
// import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart'
//     show BengleMmr, BengleSteamMmr;
// The cal (spec 06) / LED (spec 07) branches extend this `show` list with
// BengleCalMmr / BengleLedMmr as they land (the enums are parts of the
// unified_de1 library):
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart'
    show BengleScaleMmr;

const String _contractPath = 'assets/api/bengle_hw_v1.yml';

/// The contract_version this registration table was written against.
/// Bump deliberately, together with the enum updates the new contract needs.
const int _expectedContractVersion = 1;

/// One app-declared register under test: the app enum entry and the FIRMWARE
/// register name of its row in bengle_hw_v1.yml.
class ContractEntry {
  const ContractEntry(this.register, this.contractName);

  final MmrAddress register;

  /// Firmware register name (the `name:` field of the contract row).
  final String contractName;

  String get label => '${register.runtimeType}.${register.name}';
}

// =============================================================================
// REGISTRATION TABLE -- one line per app-declared MMR register.
// Capability branches extend this list (see EXTENSION PROTOCOL above).
// =============================================================================
const List<ContractEntry> entriesUnderTest = <ContractEntry>[
  // ---------------------------------------------------------------------------
  // Foundation branch (spec 01): shared-DE1 `MMRItem` baseline.
  // ---------------------------------------------------------------------------
  ContractEntry(MMRItem.externalFlash, 'ExternalFlash'),
  ContractEntry(MMRItem.hwConfig, 'HWConfig'),
  ContractEntry(MMRItem.model, 'Model'),
  ContractEntry(MMRItem.cpuBoardModel, 'CPUBoardModel'),
  ContractEntry(MMRItem.v13Model, 'v13Model'),
  ContractEntry(MMRItem.cpuFirmwareBuild, 'CPUFirmwareBuild'),
  ContractEntry(MMRItem.debugLen, 'DebugLen'),
  ContractEntry(MMRItem.debugBuffer, 'DebugBuffer'),
  ContractEntry(MMRItem.debugConfig, 'DebugConfig'),
  ContractEntry(MMRItem.fanThreshold, 'FanThreshold'),
  ContractEntry(MMRItem.tankTemp, 'TankTemp'),
  ContractEntry(MMRItem.heaterUp1Flow, 'HeaterUp1Flow'),
  ContractEntry(MMRItem.heaterUp2Flow, 'HeaterUp2Flow'),
  ContractEntry(MMRItem.waterHeaterIdleTemp, 'WaterHeaterIdleTemp'),
  ContractEntry(MMRItem.ghcInfo, 'GHCInfo'),
  ContractEntry(MMRItem.targetSteamFlow, 'TargetSteamFlow'),
  // The expected SteamStartSecs scales are readScale 0.01 / writeScale 100.0
  // (== fw mult 100). The entry historically carried the latent default-1.0
  // scales (known drift, the contract change protocol) and MUST fail here if that ever
  // regresses.
  ContractEntry(MMRItem.steamStartSecs, 'SteamStartSecs'),
  ContractEntry(MMRItem.serialN, 'SerialN'),
  ContractEntry(MMRItem.heaterV, 'HeaterV'),
  ContractEntry(MMRItem.heaterUp2Timeout, 'HeaterUp2Timeout'),
  ContractEntry(MMRItem.calFlowEst, 'CalFlowEst'),
  ContractEntry(MMRItem.flushFlowRate, 'FlushFlowRate'),
  ContractEntry(MMRItem.flushTemp, 'FlushTemp'),
  ContractEntry(MMRItem.flushTimeout, 'FlushTimeout'),
  ContractEntry(MMRItem.hotWaterFlowRate, 'HotWaterFlowRate'),
  ContractEntry(MMRItem.steamPurgeMode, 'SteamPurgeMode'),
  ContractEntry(MMRItem.allowUSBCharging, 'AllowUSBCharging'),
  ContractEntry(MMRItem.appFeatureFlags, 'AppFeatureFlags'),
  ContractEntry(MMRItem.refillKitPresent, 'RefillKitPresent'),
  ContractEntry(MMRItem.userPresent, 'UserPresent'),

  // ---------------------------------------------------------------------------
  // SAW/tare branch (spec 05): `BengleScaleMmr`
  // (in integrated_scale_capability.dart, part of unified_de1).
  // ---------------------------------------------------------------------------
  ContractEntry(BengleScaleMmr.stopAtWeightTarget, 'EndOfShotWeight'),
  // ContractEntry(BengleScaleMmr.scaleTare, 'ScaleTare'), // commit

  // ---------------------------------------------------------------------------
  // Calibration-wizard branch (spec 06): `BengleCalMmr`
  // (in scale_calibration_capability.dart, part of unified_de1).
  // UNCOMMENT these lines (and the unified_de1 import) when the branch lands:
  // ---------------------------------------------------------------------------
  // ContractEntry(BengleCalMmr.cmd, 'ScaleCalCmd'),
  // ContractEntry(BengleCalMmr.state, 'ScaleCalState'),
  // ContractEntry(BengleCalMmr.weight, 'ScaleCalWeight'),

  // ---------------------------------------------------------------------------
  // LED-strip branch (spec 07): `BengleLedMmr`
  // (in led_strip_capability.dart, part of unified_de1).
  // UNCOMMENT these lines (and the unified_de1 import) when the branch lands:
  // ---------------------------------------------------------------------------
  // ContractEntry(BengleLedMmr.frontLive, 'FrontLEDColor'),
  // ContractEntry(BengleLedMmr.rearLive, 'RearLEDColor'),
  // ContractEntry(BengleLedMmr.frontAwake, 'FrontLEDAwake'),
  // ContractEntry(BengleLedMmr.rearAwake, 'RearLEDAwake'),
  // ContractEntry(BengleLedMmr.frontSleep, 'FrontLEDSleep'),
  // ContractEntry(BengleLedMmr.rearSleep, 'RearLEDSleep'),

  // ---------------------------------------------------------------------------
  // Thermal branch (spec 08: cup-warmer mode + milk temp + mat-temp read):
  // `BengleMmr` + `BengleSteamMmr` (bengle_mmr.dart). The app desc string
  // 'StopAtTemperatureTarget' is the contract row's `app_alias`.
  // UNCOMMENT these lines (and the bengle_mmr import) when the branch lands:
  // ---------------------------------------------------------------------------
  // ContractEntry(BengleMmr.matSetPoint, 'MatSetPoint'),
  // ContractEntry(BengleMmr.cupWarmerMode, 'CupWarmerMode'),
  // ContractEntry(BengleSteamMmr.stopAtTemperatureTarget, 'TargetMilkTemp'),
];

// =============================================================================
// Minimal contract parser.
//
// Deliberately hand-rolled: `package:yaml` is only a TRANSITIVE dependency of
// this package, and depending on it directly would need a pubspec change.
// The parser supports exactly the subset bengle_hw_v1.yml is written in --
// top-level scalar keys, the two-space-indented `firmware:` block map, and
// the `registers:` list of `- key: value` block maps with `#` comments
// (whole-line or trailing, quote-aware). The packet_0xA013 / serial_verbs
// sections are documentation for humans and are intentionally skipped.
// =============================================================================

class ContractRegister {
  const ContractRegister({
    required this.name,
    required this.fwRow,
    required this.address,
    required this.length,
    required this.perms,
    required this.mult,
    required this.valueKind,
    required this.min,
    required this.max,
    required this.appAlias,
  });

  final String name;
  final int? fwRow;
  final int address;
  final int length;
  final String perms;
  final int mult;
  final String valueKind;
  final int? min;
  final int? max;
  final String? appAlias;
}

class HwContract {
  const HwContract({
    required this.contractVersion,
    required this.firmwareCommit,
    required this.registers,
  });

  final int contractVersion;
  final String firmwareCommit;

  /// Keyed by firmware register name.
  final Map<String, ContractRegister> registers;
}

/// Drops a `#` comment (whole-line or trailing) unless the `#` sits inside a
/// double-quoted scalar. Trailing comments in the contract are always
/// whitespace-separated from the value.
String _stripComment(String line) {
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') inQuotes = !inQuotes;
    if (ch == '#' &&
        !inQuotes &&
        (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
      return line.substring(0, i);
    }
  }
  return line;
}

String _unquote(String value) {
  final t = value.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

/// Parses `null`, decimal, or 0x-prefixed hex scalars (optionally quoted).
int? _intOrNull(String? value) {
  if (value == null) return null;
  final t = _unquote(value);
  if (t.isEmpty || t == 'null' || t == '~') return null;
  if (t.startsWith('0x') || t.startsWith('0X')) {
    return int.parse(t.substring(2), radix: 16);
  }
  return int.parse(t);
}

HwContract parseBengleHwContract(String text) {
  int? version;
  String? commit;
  final registers = <String, ContractRegister>{};

  var topKey = '';
  Map<String, String>? current;

  void flushCurrent() {
    final fields = current;
    current = null;
    if (fields == null) return;
    final name = _unquote(
      fields['name'] ?? (throw FormatException('register row without a name')),
    );
    registers[name] = ContractRegister(
      name: name,
      fwRow: _intOrNull(fields['fw_row']),
      address:
          _intOrNull(fields['address']) ??
          (throw FormatException('register $name has no address')),
      length:
          _intOrNull(fields['length']) ??
          (throw FormatException('register $name has no length')),
      perms: _unquote(fields['perms'] ?? ''),
      mult:
          _intOrNull(fields['mult']) ??
          (throw FormatException('register $name has no mult')),
      valueKind: _unquote(fields['value_kind'] ?? ''),
      min: _intOrNull(fields['min']),
      max: _intOrNull(fields['max']),
      appAlias: fields['app_alias'] == null
          ? null
          : _unquote(fields['app_alias']!),
    );
  }

  for (final raw in text.split('\n')) {
    final line = _stripComment(raw).trimRight();
    if (line.trim().isEmpty) continue;

    if (!line.startsWith(' ')) {
      // New top-level key ends any open register row.
      flushCurrent();
      final sep = line.indexOf(':');
      if (sep < 0) continue;
      topKey = line.substring(0, sep).trim();
      final value = line.substring(sep + 1).trim();
      if (topKey == 'contract_version' && value.isNotEmpty) {
        version = int.parse(value);
      }
      continue;
    }

    if (topKey == 'firmware') {
      final sep = line.indexOf(':');
      if (sep > 0 && line.substring(0, sep).trim() == 'commit') {
        commit = _unquote(line.substring(sep + 1));
      }
      continue;
    }

    if (topKey != 'registers') continue;

    var body = line.trimLeft();
    if (body.startsWith('- ')) {
      flushCurrent();
      current = <String, String>{};
      body = body.substring(2);
    }
    final fields = current;
    if (fields == null) continue;
    final sep = body.indexOf(':');
    if (sep <= 0) continue;
    fields[body.substring(0, sep).trim()] = body.substring(sep + 1).trim();
  }
  flushCurrent();

  if (version == null) {
    throw const FormatException('contract_version missing from contract');
  }
  if (commit == null) {
    throw const FormatException('firmware.commit missing from contract');
  }
  if (registers.isEmpty) {
    throw const FormatException('no registers parsed from contract');
  }
  return HwContract(
    contractVersion: version,
    firmwareCommit: commit,
    registers: registers,
  );
}

// =============================================================================
// Checker
// =============================================================================

HwContract? _cached;
HwContract _contract() =>
    _cached ??= parseBengleHwContract(File(_contractPath).readAsStringSync());

String _hex(int value) =>
    '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';

void main() {
  group('bengle_hw_v1.yml', () {
    test('parses, pins a firmware commit, and matches the checker version', () {
      final c = _contract();
      expect(
        c.contractVersion,
        _expectedContractVersion,
        reason:
            'contract_version drift: the contract file is '
            'v${c.contractVersion} but this registration table was written '
            'against v$_expectedContractVersion. Update the enums against the '
            'new contract, then bump _expectedContractVersion deliberately.',
      );
      expect(
        c.firmwareCommit,
        hasLength(40),
        reason: 'firmware.commit must pin a full 40-char firmware SHA',
      );
      stdout.writeln(
        '  contract v${c.contractVersion}, firmware pin ${c.firmwareCommit}, '
        '${c.registers.length} contract rows, '
        '${entriesUnderTest.length} app registers under test',
      );
    });

    test('every app register maps to a distinct contract row', () {
      final names = entriesUnderTest.map((e) => e.contractName).toList();
      expect(
        names.toSet().length,
        names.length,
        reason: 'two registration entries claim the same contract row',
      );
      final registers = entriesUnderTest.map((e) => e.register).toList();
      expect(
        registers.toSet().length,
        registers.length,
        reason: 'an app register is registered twice',
      );
    });
  });

  group('app register matches contract (address/length/scale/range)', () {
    for (final entry in entriesUnderTest) {
      test('${entry.label} <-> ${entry.contractName}', () {
        final row = _contract().registers[entry.contractName];
        expect(
          row,
          isNotNull,
          reason:
              'app register ${entry.label} is missing from the contract: '
              'no row named "${entry.contractName}" in $_contractPath. Every '
              'app-declared register must exist in the contract.',
        );
        final contract = row!;
        final app = entry.register;

        expect(
          _hex(app.address),
          _hex(contract.address),
          reason:
              'ADDRESS drift on ${entry.label}: app ${_hex(app.address)} '
              'vs contract ${_hex(contract.address)}',
        );
        expect(
          app.length,
          contract.length,
          reason:
              'LENGTH drift on ${entry.label}: app ${app.length} vs '
              'contract ${contract.length}',
        );

        // Scale: writeScale must equal the firmware mult; readScale must be
        // its inverse. Non-scaled registers have mult 1 and default 1.0
        // scales, so the same rule covers every value kind.
        expect(
          app.writeScale,
          contract.mult.toDouble(),
          reason:
              'SCALE drift on ${entry.label}: app writeScale '
              '${app.writeScale} vs contract mult ${contract.mult} '
              '(wire value = engineering value x mult)',
        );
        expect(
          app.readScale,
          closeTo(1.0 / contract.mult, 1e-9),
          reason:
              'SCALE drift on ${entry.label}: app readScale '
              '${app.readScale} vs contract 1/mult '
              '(${1.0 / contract.mult})',
        );

        // Range: app bounds (raw wire units) must be a SUBSET of the contract
        // bounds. Declaring no bound is legal; narrower is legal.
        final appMin = app.min;
        final appMax = app.max;
        if (appMin != null && contract.min != null) {
          expect(
            appMin >= contract.min!,
            isTrue,
            reason:
                'RANGE drift on ${entry.label}: app min $appMin lies '
                'below contract min ${contract.min} (app range must be a '
                'subset of the contract range)',
          );
        }
        if (appMax != null && contract.max != null) {
          expect(
            appMax <= contract.max!,
            isTrue,
            reason:
                'RANGE drift on ${entry.label}: app max $appMax lies '
                'above contract max ${contract.max} (app range must be a '
                'subset of the contract range)',
          );
        }
      });
    }
  });

  group('contract coverage (informational, never fails)', () {
    test('contract rows not yet consumed by the app', () {
      final covered = entriesUnderTest.map((e) => e.contractName).toSet();
      final unconsumed =
          _contract().registers.values
              .where((r) => !covered.contains(r.name))
              .toList()
            ..sort((a, b) => (a.fwRow ?? -1).compareTo(b.fwRow ?? -1));
      stdout.writeln(
        '  ${unconsumed.length} contract rows have no app entry '
        '(legal -- the app grows into the contract):',
      );
      for (final r in unconsumed) {
        stdout.writeln(
          '    row ${r.fwRow} ${r.name} @ ${_hex(r.address)} '
          '(${r.perms}, mult ${r.mult})',
        );
      }
    });

    test('contract rows carrying an app_alias (desc differs from FW name)', () {
      for (final r in _contract().registers.values) {
        if (r.appAlias != null) {
          stdout.writeln(
            '    ${r.name}: app declares desc "${r.appAlias}" (documented '
            'alias, not drift)',
          );
        }
      }
    });

    test('app ranges strictly narrower than the contract (legal)', () {
      for (final entry in entriesUnderTest) {
        final row = _contract().registers[entry.contractName];
        if (row == null) continue;
        final app = entry.register;
        final narrowerMin =
            app.min != null && row.min != null && app.min! > row.min!;
        final narrowerMax =
            app.max != null && row.max != null && app.max! < row.max!;
        if (narrowerMin || narrowerMax) {
          stdout.writeln(
            '    ${entry.label}: app [${app.min}..${app.max}] inside '
            'contract [${row.min}..${row.max}]',
          );
        }
      }
    });
  });
}
