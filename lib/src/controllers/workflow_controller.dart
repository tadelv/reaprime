import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:uuid/uuid.dart';

class WorkflowController extends ChangeNotifier {
  WorkflowController();

  Workflow _currentWorkflow = Workflow(
    id: Uuid().v4(),
    name: "Workflow",
    description: "Description",
    profile: Defaults.createDefaultProfile(),
    context: WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0),
    steamSettings: SteamSettings.defaults(),
    hotWaterData: HotWaterData.defaults(),
    rinseData: RinseData.defaults(),
  );
  int _revision = 0;

  Workflow newWorkflow() {
    return Workflow(
      id: Uuid().v4(),
      name: "Workflow",
      description: "Description",
      profile: Defaults.createDefaultProfile(),
      context: WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0),
      steamSettings: SteamSettings.defaults(),
      hotWaterData: HotWaterData.defaults(),
      rinseData: RinseData.defaults(),
    );
  }

  Workflow get currentWorkflow => _currentWorkflow;

  int get revision => _revision;

  void setWorkflow(Workflow newWorkflow) {
    _currentWorkflow = newWorkflow;
    _revision++;
    notifyListeners();
  }

  bool setWorkflowIfRevision(Workflow newWorkflow, int expectedRevision) {
    if (_revision != expectedRevision) {
      return false;
    }
    setWorkflow(newWorkflow);
    return true;
  }

  void updateWorkflow({
    String? name,
    String? description,
    Profile? profile,
    WorkflowContext? context,
    SteamSettings? steamSettings,
    HotWaterData? hotWaterData,
    RinseData? rinseData,
  }) {
    _currentWorkflow = _currentWorkflow.copyWith(
      name: name,
      description: description,
      profile: profile,
      context: context,
      steamSettings: steamSettings,
      hotWaterData: hotWaterData,
      rinseData: rinseData,
    );
    _revision++;
    notifyListeners();
  }
}

extension Defaults on Profile {
  static Profile createDefaultProfile() {
    return Profile(
      version: "1.0",
      title: "Default",
      notes: "Default notes",
      author: "Decent",
      beverageType: BeverageType.espresso,
      steps: [
        ProfileStepPressure(
          name: "Free flow",
          transition: TransitionType.fast,
          volume: 0.0,
          seconds: 120,
          temperature: 90.0,
          sensor: TemperatureSensor.coffee,
          pressure: 7.5,
        ),
      ],
      targetVolumeCountStart: 0,
      tankTemperature: 0,
    );
  }
}
