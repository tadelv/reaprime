import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';

MachineState mapDe1ToMachineState(De1StateEnum de1State) {
  switch (de1State) {
    case De1StateEnum.sleep:
    case De1StateEnum.goingToSleep:
    case De1StateEnum.schedIdle:
      return MachineState.sleeping;

    case De1StateEnum.idle:
    case De1StateEnum.noRequest:
      return MachineState.idle;

    case De1StateEnum.init:
    case De1StateEnum.inBootLoader:
      return MachineState.booting;

    case De1StateEnum.busy:
    case De1StateEnum.longCal:
    case De1StateEnum.shortCal:
    case De1StateEnum.selfTest:
      return MachineState.preheating;

    case De1StateEnum.espresso:
      return MachineState.espresso;

    case De1StateEnum.hotWater:
    case De1StateEnum.hotWaterRinse:
      return MachineState.hotWater;

    case De1StateEnum.steam:
    case De1StateEnum.steamRinse:
    case De1StateEnum.airPurge:
      return MachineState.steam;

    case De1StateEnum.clean:
      return MachineState.cleaning;

    case De1StateEnum.descale:
      return MachineState.descaling;

    case De1StateEnum.skipToNext: 
      return MachineState.skipStep;

    case De1StateEnum.refill:
      return MachineState.needsWater;

    case De1StateEnum.fatalError:
      return MachineState.error;

    default:
      return MachineState.error; // Fallback for unknown or unexpected states
  }
}


MachineSubstate mapDe1SubToMachineSubstate(De1SubState de1SubState) {
  switch (de1SubState) {
    case De1SubState.noState:
    case De1SubState.userNotPresent:
    case De1SubState.refill:
    case De1SubState.pausedSteam:
    case De1SubState.puffing:
      return MachineSubstate.idle;

    case De1SubState.heatWaterTank:
    case De1SubState.heatWaterHeater:
    case De1SubState.stabilizeMixTemp:
      return MachineSubstate.preparingForShot;

    case De1SubState.preInfuse:
      return MachineSubstate.preinfusion;

    case De1SubState.pour:
    case De1SubState.steaming:
      return MachineSubstate.pouring;

    case De1SubState.end:
      return MachineSubstate.pouringDone;

    case De1SubState.cleanInit:
    case De1SubState.descaleInt:
      return MachineSubstate.cleaningStart;

    case De1SubState.cleanFillGroup:
    case De1SubState.cleanGroup:
    case De1SubState.descaleFillGroup:
    case De1SubState.descaleGroup:
    case De1SubState.descaleReturn:
      return MachineSubstate.cleaingGroup;

    case De1SubState.cleanSoak:
      return MachineSubstate.cleanSoaking;

    case De1SubState.descaleSteam:
      return MachineSubstate.cleaningSteam;

    default: // Any errors map to idle
      return MachineSubstate.idle;
  }
}

