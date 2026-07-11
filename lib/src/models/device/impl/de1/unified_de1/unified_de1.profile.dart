part of 'unified_de1.dart';

/// Bengle firmware (BLE protocol v2) supports flow rates up to 20 ml/s,
/// versus the DE1's 8 ml/s. de1plus raises `max_flowrate` to 20 when
/// `use_ble_v2` is negotiated (`de1_de1.tcl:778-782`). reaprime is headless
/// — there is no UI slider to bound a flow input — so the profile encoder
/// is the enforcement point for this ceiling.
const double _bengleMaxFlowMlPerSec = 20.0;

extension UnifiedDe1Profile on UnifiedDe1 {
  Future<void> _sendProfile(Profile profile) async {
    await _writeHeader(profile);
    await _writeSteps(profile);
    await _writeTail(profile);
    // The tank temperature threshold is a separate MMR (MMRItem.tankTemp), not
    // part of the profile frames — frames go via frameWrite, and there is no
    // MMR for steps. The DE1 expects the tank threshold to be written
    // alongside a profile load; mirror de1app's `de1_send_shot_frames`, which
    // writes the frames then `set_tank_temperature_threshold`
    // (de1_comms.tcl:1505-1514). Writing it on every profile load means the
    // next brew re-sets it from its own tankTemperature, so the cold-maintenance
    // workaround (which loads a tankTemperature:0 profile) needs no separate
    // set-to-0 or restore.
    await _writeMMRInt(MMRItem.tankTemp, profile.tankTemperature.round());
  }

  /// Encode a flow (ml/s) or pressure (bar) profile field to its wire byte,
  /// honouring the negotiated protocol version.
  ///
  /// A Bengle decodes these as **U8D1** (`byte × 0.1`, range 0..25.5); a DE1
  /// uses **U8P4** (`byte / 16`, range 0..15.9375). Encoding a v2 value with
  /// the v1 scale silently mis-commands the machine (`6 ml/s` written as the
  /// v1 `96` reads back as `9.6` on a Bengle). Only the Bengle U8D1 path clamps
  /// (to 0..25.5); the DE1 U8P4 path is unchanged from stock reaprime and wraps
  /// mod-256 above 15.9375 — harmless in practice, as DE1 flow/pressure stays
  /// well within range. Mirrors de1plus `convert_float_to_flow_pressure_byte`
  /// (`binary.tcl`).
  int _encodeFlowPressure(double value) => isBengle
      ? Helper.convert_float_to_U8D1(value)
      : (0.5 + value * 16.0).toInt();

  Future<void> _writeHeader(Profile profile) async {
    Uint8List data = Uint8List(5);

    int index = 0;
    // a Bengle rejects any header whose version != 2 — the firmware
    // memsets the header and returns, silently dropping the whole profile
    //. The DE1 stays on v1.
    data[index] = isBengle ? 2 : 1; // Header version
    index++;
    data[index] = profile.steps.length;
    index++;
    data[index] = profile.targetVolumeCountStart;
    index++;
    // min pressure (U8D1 on Bengle / U8P4 on DE1 — encodes to 0 either way)
    data[index] = 0;
    index++;
    // Global max flow. On a Bengle this advertises the raised 20 ml/s ceiling
    // (v1 machines cap at 8); every frame sets IgnoreLimit so it is a soft
    // bound, but it must still be encoded for the negotiated wire version —
    // the old hard-coded `12 * 16` was a raw v1 (U8P4) byte.
    data[index] = _encodeFlowPressure(isBengle ? _bengleMaxFlowMlPerSec : 12.0);

    await _transport.writeWithResponse(Endpoint.headerWrite, data);
  }

  Future<void> _writeSteps(Profile profile) async {
    // write frames
    for (var i = 0; i < profile.steps.length; i++) {
      var step = profile.steps[i];
      _log.fine("encoding step ${step.name}");
      _log.fine("limiter: ${step.limiter?.toJson()}");
      _log.fine("exit: ${step.exit?.toJson()}");
      Uint8List data = Uint8List(8);

      int index = 0;
      data[index] = i;
      index++;
      data[index] = Helper.convertProfileFlags(step);
      index++;
      // SetVal: the target flow (ml/s) or pressure (bar). U8D1 on a
      // Bengle, U8P4 on a DE1. A flow-priority target is clamped to the Bengle
      // 20 ml/s ceiling first (pressure targets ride the U8D1 0..25.5 clamp).
      double setVal = step.getTarget();
      if (isBengle &&
          step is ProfileStepFlow &&
          setVal > _bengleMaxFlowMlPerSec) {
        setVal = _bengleMaxFlowMlPerSec;
      }
      data[index] = _encodeFlowPressure(setVal);
      index++;
      data[index] = (0.5 + step.temperature * 2.0).toInt();
      index++;
      data[index] = Helper.convert_float_to_F8_1_7(step.seconds);
      index++;
      // TriggerVal: the exit-comparison threshold (flow or pressure) — same
      // U8D1/U8P4 split as SetVal.
      data[index] = _encodeFlowPressure(step.exit?.value ?? 0.0);
      index++;
      Helper.convert_float_to_U10P0(step.volume, data, index);

      await _transport.writeWithResponse(Endpoint.frameWrite, data);
    }

    // write available extension frames
    for (var i = 0; i < profile.steps.length; i++) {
      var step = profile.steps[i];
      int stepIndex = 32 + i;
      Uint8List data = Uint8List(8);

      data[0] = stepIndex;

      if (step.limiter == null || step.limiter?.value == 0) {
        // await _transport.writeWithResponse(Endpoint.frameWrite, data);
        continue;
      }
      double limiterValue = step.limiter!.value;
      double limiterRange = step.limiter!.range;

      // Extension-frame max flow-or-pressure limiter + its range — U8D1 on a
      // Bengle, U8P4 on a DE1.
      data[1] = _encodeFlowPressure(limiterValue);
      data[2] = _encodeFlowPressure(limiterRange);

      data[3] = 0;
      data[4] = 0;
      data[5] = 0;
      data[6] = 0;
      data[7] = 0;

      await _transport.writeWithResponse(Endpoint.frameWrite, data);
    }
  }

  Future<void> _writeTail(Profile profile) async {
    Uint8List data = Uint8List(8);

    data[0] = profile.steps.length;

    // Ignore writing shot vol limit, it's not compatible with active scale and breaks with high PI flows.
    // Helper.convert_float_to_U10P0_for_tail(profile.targetVolume ?? 0, data, 1);

    data[3] = 0;
    data[4] = 0;
    data[5] = 0;
    data[6] = 0;
    data[7] = 0;
    await _transport.writeWithResponse(Endpoint.frameWrite, data);
  }
}

class Helper {
  // ignore: non_constant_identifier_names
  static double convert_F8_1_7_to_float(int x) {
    if ((x & 128) == 0) {
      return x / 10.0;
    } else {
      return (x & 127).toDouble();
    }
  }

  /// U8D1: unsigned byte, scale ×0.1 (range 0..25.5, step 0.1) — the Bengle
  /// (BLE protocol v2) flow/pressure encoding. Clamps to the byte range so
  /// out-of-range values saturate instead of wrapping. Uses round-half-up (to
  /// match the `+ 0.5` truncation the v1 path uses). Mirrors de1plus
  /// `convert_float_to_U8D1` (`binary.tcl`).
  // ignore: non_constant_identifier_names
  static int convert_float_to_U8D1(double x) {
    final clamped = x < 0.0 ? 0.0 : (x > 25.5 ? 25.5 : x);
    return (clamped * 10).round();
  }

  // ignore: non_constant_identifier_names
  static int convert_float_to_F8_1_7(double x) {
    if (x == 0) {
      return 0;
    }
    var ret = 0;
    if (x >= 12.75) // need to set the high bit on (0x80);
    {
      if (x > 127) {
        ret = (127 | 0x80);
      } else {
        ret = (0x80 | (0.5 + x).toInt());
      }
    } else {
      ret = (0.5 + x * 10).toInt();
    }
    return ret;
  }

  // ignore: non_constant_identifier_names
  static void convert_float_to_U10P0_for_tail(
    double maxTotalVolume,
    Uint8List data,
    int index,
  ) {
    if (maxTotalVolume == 0) {
      return;
    }
    int ix = maxTotalVolume.toInt();

    if (ix > 1023) {
      // clamp to 1 liter, should be enough for a tasty brew
      ix = 1023;
    }
    // there is a mismatch between docs and actual implementation in the firmware
    // instead 0f 0x8000 for ignorePI, 0x400 sets PI counting to enabled.
    data[index] = ix >> 8; // Ignore preinfusion, only measure volume afterwards
    data[index + 1] = (ix & 0xff);
  }

  // ignore: non_constant_identifier_names
  static double convert_bottom_10_of_U10P0(int x) {
    return (x & 1023).toDouble();
  }

  // ignore: non_constant_identifier_names
  static void convert_float_to_U10P0(double x, Uint8List data, int index) {
    Uint8List d = Uint8List(2);

    int ix = x.toInt() | 1024;
    d.buffer.asByteData().setInt16(0, ix);

    // if (ix > 255) {
    //   ix = 255;
    // }

    data[index] = d.buffer.asByteData().getUint8(0);
    data[index + 1] = d.buffer.asByteData().getUint8(1);
  }

  static int ctrlF = 0x01; // Are we in Pressure or Flow priority mode?
  // ignore: constant_identifier_names
  static int doCompare =
      0x02; // Do a compare, early exit current frame if compare true
  // ignore: constant_identifier_names
  static int dcGT =
      0x04; // If we are doing a compare, then 0 = less than, 1 = greater than
  // ignore: constant_identifier_names
  static int dcCompF = 0x08; // Compare Pressure or Flow?
  // ignore: constant_identifier_names
  static int tMixTemp =
      0x10; // Disable shower head temperature compensation. Target Mix Temp instead.
  // ignore: constant_identifier_names
  static int interpolate = 0x20; // Hard jump to target value, or ramp?
  // ignore: constant_identifier_names
  static int ignoreLimit =
      0x40; // Ignore minimum pressure and max flow settings

  static int convertProfileFlags(ProfileStep step) {
    // TODO: maybe don't ignore this if we need to reach high flow values?
    int flag = ignoreLimit;

    if (step is ProfileStepFlow) flag |= ctrlF;
    if (step.sensor == TemperatureSensor.water) flag |= tMixTemp;
    if (step.transition == TransitionType.smooth) flag |= interpolate;

    if (step.exit != null) {
      flag |= doCompare;

      if (step.exit!.type == ExitType.flow) flag |= dcCompF;
      if (step.exit!.condition == ExitCondition.over) flag |= dcGT;
    }

    return flag;
  }
}
