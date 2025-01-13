// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/machine.dart';

final String de1ServiceUUID = '0000A000-0000-1000-8000-00805F9B34FB';

enum Endpoint {
  versions('0000A001-0000-1000-8000-00805F9B34FB'),
  requestedState('0000A002-0000-1000-8000-00805F9B34FB'),
  setTime('0000A003-0000-1000-8000-00805F9B34FB'),
  shotDirectory('0000A004-0000-1000-8000-00805F9B34FB'),
  readFromMMR('0000A005-0000-1000-8000-00805F9B34FB'),
  writeToMMR('0000A006-0000-1000-8000-00805F9B34FB'),
  shotMapRequest('0000A007-0000-1000-8000-00805F9B34FB'),
  deleteShotRange('0000A008-0000-1000-8000-00805F9B34FB'),
  fwMapRequest('0000A009-0000-1000-8000-00805F9B34FB'),
  temperatures('0000A00A-0000-1000-8000-00805F9B34FB'),
  shotSettings('0000A00B-0000-1000-8000-00805F9B34FB'),
  deprecatedShotDesc('0000A00C-0000-1000-8000-00805F9B34FB'),
  shotSample('0000A00D-0000-1000-8000-00805F9B34FB'),
  stateInfo('0000A00E-0000-1000-8000-00805F9B34FB'),
  headerWrite('0000A00F-0000-1000-8000-00805F9B34FB'),
  frameWrite('0000A010-0000-1000-8000-00805F9B34FB'),
  waterLevels('0000A011-0000-1000-8000-00805F9B34FB'),
  calibration('0000A012-0000-1000-8000-00805F9B34FB');

  final String uuid;

  const Endpoint(this.uuid);

  // Helper method to find an Endpoint by its UUID
  static Endpoint? fromUuid(String uuid) {
    return Endpoint.values.where((e) => e.uuid == uuid).firstOrNull;
  }
}

enum De1StateEnum {
  sleep(0x0), // Everything is off
  goingToSleep(0x1),
  idle(0x2), // Heaters are controlled, tank water will be heated if required.
  busy(0x3), // Firmware is doing something you can't interrupt.
  espresso(0x4), // Making espresso
  steam(0x5), // Making steam
  hotWater(0x6), // Making hot water
  shortCal(0x7), // Running a short calibration
  selfTest(0x8), // Checking as much as possible within the firmware.
  longCal(
    0x9,
  ), // Long and involved calibration, possibly with user interaction.
  descale(0xA), // Descale the whole machine
  fatalError(0xB), // Something has gone horribly wrong
  init(0xC), // Machine has not been run yet
  noRequest(
    0xD,
  ), // State for T_RequestedState, means nothing is specifically requested
  skipToNext(0xE), // Skip to next frame or go to Idle if possible
  hotWaterRinse(0xF), // Produce hot water at available temperature
  steamRinse(0x10), // Produce a blast of steam
  refill(0x11), // Attempting or needs a refill
  clean(0x12), // Clean group head
  inBootLoader(0x13), // Bootloader is active, firmware has not run
  airPurge(0x14), // Air purge
  schedIdle(0x15), // Scheduled wake-up idle state
  unknown(-1); // Default or unknown state

  final int hexValue;

  const De1StateEnum(this.hexValue);

  // Helper method to find a state by its hex value
  static De1StateEnum fromHexValue(int hex) {
    return De1StateEnum.values.firstWhere(
      (e) => e.hexValue == hex,
      orElse: () => De1StateEnum.unknown,
    );
  }

  static De1StateEnum fromMachineState(MachineState state) {
    switch (state) {
      case MachineState.idle:
        return De1StateEnum.idle;
      case MachineState.booting:
        throw UnimplementedError();
      case MachineState.sleeping:
        return De1StateEnum.sleep;
      case MachineState.heating:
        throw UnimplementedError();
      case MachineState.preheating:
        throw UnimplementedError();
      case MachineState.espresso:
        return De1StateEnum.espresso;
      case MachineState.hotWater:
        return De1StateEnum.hotWater;
      case MachineState.flush:
        return De1StateEnum.hotWaterRinse;
      case MachineState.steam:
        return De1StateEnum.steam;
      case MachineState.cleaning:
        // TODO: Handle this case.
        throw UnimplementedError();
      case MachineState.descaling:
        // TODO: Handle this case.
        throw UnimplementedError();
      case MachineState.transportMode:
        // TODO: Handle this case.
        throw UnimplementedError();
      case MachineState.needsWater:
        throw UnimplementedError();
      case MachineState.error:
        throw UnimplementedError();
    }
  }
}

enum De1SubState {
  noState(0x00, 'No state is relevant'),
  heatWaterTank(0x01, 'Cold water is not hot enough. Heating hot water tank.'),
  heatWaterHeater(0x02, 'Warm up hot water heater for shot.'),
  stabilizeMixTemp(
    0x03,
    'Stabilize mix temp and get entire water path up to temperature.',
  ),
  preInfuse(0x04, 'Espresso only. Hot Water and Steam will skip this state.'),
  pour(0x05, 'Not used in Steam.'),
  end(0x06, 'Espresso only, atm.'),
  steaming(0x07, 'Steam only.'),
  descaleInt(0x08, 'Starting descale.'),
  descaleFillGroup(
    0x09,
    'Get some descaling solution into the group and let it sit.',
  ),
  descaleReturn(0x0A, 'Descaling internals.'),
  descaleGroup(0x0B, 'Descaling group.'),
  descaleSteam(0x0C, 'Descaling steam.'),
  cleanInit(0x0D, 'Starting clean.'),
  cleanFillGroup(0x0E, 'Fill the group.'),
  cleanSoak(0x0F, 'Wait for 60 seconds to soak the group head.'),
  cleanGroup(0x10, 'Flush through group.'),
  refill(0x11, 'Have we given up on a refill?'),
  pausedSteam(0x12, 'Are we paused in steam?'),
  userNotPresent(0x13, 'User is not present.'),
  puffing(0x14, 'Puffing.'),

  errorNaN(200, 'Something died with a NaN.'),
  errorInf(201, 'Something died with an Inf.'),
  errorGeneric(202, 'An error for which we have no more specific description.'),
  errorAcc(203, 'ACC not responding, unlocked, or incorrectly programmed.'),
  errorTSensor(204, 'Probably a broken temperature sensor.'),
  errorPSensor(205, 'Pressure sensor error.'),
  errorWLevel(206, 'Water level sensor error.'),
  errorDip(207, 'DIP switches told us to wait in the error state.'),
  errorAssertion(208, 'Assertion failed.'),
  errorUnsafe(209, 'Unsafe value assigned to variable.'),
  errorInvalidParam(210, 'Invalid parameter passed to function.'),
  errorFlash(211, 'Error accessing external flash.'),
  errorOOM(212, 'Could not allocate memory.'),
  errorDeadline(213, 'Realtime deadline missed.'),
  errorHiCurrent(214, 'Measured a current that is out of bounds.'),
  errorLoCurrent(
    215,
    'Not enough current flowing, despite something being turned on.',
  ),
  errorBootFill(
    216,
    'Could not get up to pressure during boot pressure test, possibly no water.',
  ),
  errorNoAC(217, 'Front button off.');

  final int hexValue;
  final String description;

  const De1SubState(this.hexValue, this.description);

  // Helper method to find a substate by its hex value
  static De1SubState? fromHexValue(int hex) {
    return De1SubState.values.firstWhere(
      (e) => e.hexValue == hex,
      orElse: () => De1SubState.noState,
    );
  }
}

enum MMRItem {
  externalFlash(0x00000000, 0xFFFFF, "Flash RW"),
  hwConfig(0x00800000, 4, "HWConfig"),
  model(0x00800004, 4, "Model"),
  cpuBoardModel(0x00800008, 4, "CPU Board Model * 1000. eg: 1100 = 1.1"),
  v13Model(
    0x0080000C,
    4,
    "v1.3+ Firmware Model (Unset = 0, DE1 = 1, DE1Plus = 2, DE1Pro = 3, DE1XL = 4, DE1Cafe = 5)",
  ),
  cpuFirmwareBuild(
    0x00800010,
    4,
    "CPU Board Firmware build number. (Starts at 1000 for 1.3, increments by 1 for every build)",
  ),
  debugLen(
    0x00802800,
    4,
    "How many characters in debug buffer are valid. Accessing this pauses BLE debug logging.",
  ),
  debugBuffer(
    0x00802804,
    0x1000,
    "Last 4K of output. Zero terminated if buffer not full yet. Pauses BLE debug logging.",
  ),
  debugConfig(
    0x00803804,
    4,
    "BLEDebugConfig. (Reading restarts logging into the BLE log)",
  ),
  fanThreshold(0x00803808, 4, "Fan threshold temp"),
  tankTemp(0x0080380C, 4, "Tank water temp threshold."),
  heaterUp1Flow(0x00803810, 4, "HeaterUp Phase 1 Flow Rate"),
  heaterUp2Flow(0x00803814, 4, "HeaterUp Phase 2 Flow Rate"),
  waterHeaterIdleTemp(0x00803818, 4, "Water Heater Idle Temperature"),
  ghcInfo(
    0x0080381C,
    4,
    "GHC Info Bitmask, 0x1 = GHC LED Controller Present, 0x2 = GHC Touch Controller_Present, 0x4 GHC Active, 0x80000000 = Factory Mode",
  ),
  prefGHCMCI(0x00803820, 4, "TODO"),
  maxShotPres(0x00803824, 4, "TODO"),
  targetSteamFlow(0x00803828, 4, "Target steam flow rate"),
  steamStartSecs(
    0x0080382C,
    4,
    "Seconds of high steam flow * 100. Valid range 0.0 - 4.0. 0 may result in an overheated heater. Be careful.",
  ),
  serialN(0x00803830, 4, "Current serial number"),
  heaterV(
    0x00803834,
    4,
    "Nominal Heater Voltage (0, 120V or 230V). +1000 if it's a set value.",
  ),
  heaterUp2Timeout(0x00803838, 4, "HeaterUp Phase 2 Timeout"),
  calFlowEst(0x0080383C, 4, "Flow Estimation Calibration"),
  flushFlowRate(0x00803840, 4, "Flush Flow Rate"),
  flushTemp(0x00803844, 4, "Flush Temp"),
  flushTimeout(0x00803848, 4, "Flush Timeout"),
  hotWaterFlowRate(0x0080384C, 4, "Hot Water Flow Rate"),
  steamPurgeMode(0x00803850, 4, "Steam Purge Mode"),
  allowUSBCharging(0x00803854, 4, "Allow USB charging"),
  appFeatureFlags(0x00803858, 4, "App Feature Flags"),
  refillKitPresent(0x0080385C, 4, "Refill Kit Present");

  final int address;
  final int length;
  final String description;

  const MMRItem(this.address, this.length, this.description);
}
