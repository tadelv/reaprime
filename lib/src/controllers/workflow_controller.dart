import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:uuid/uuid.dart';

class WorkflowController extends ChangeNotifier {
  WorkflowController();

  Workflow _currentWorkflow = Workflow(
    id: Uuid().v4(),
    name: "Workflow",
    description: "Description",
    profile: Defaults.createDefaultProfile(),
    doseData: DoseData(doseIn: 18.0, doseOut: 36.0),
  );

  Workflow newWorkflow() {
    return Workflow(
      id: Uuid().v4(),
      name: "Workflow",
      description: "Description",
      profile: Defaults.createDefaultProfile(),
      doseData: DoseData(doseIn: 18.0, doseOut: 36.0),
    );
  }

  Workflow get currentWorkflow => _currentWorkflow;

  void setWorkflow(Workflow newWorkflow) {
    _currentWorkflow = newWorkflow;
    notifyListeners();
  }
}

extension Defaults on Profile {
  static Profile createDefaultProfile() {
    return Profile(
        version: "1.0",
        title: "Default",
        notes: "Default notes",
        author: "Vid",
        beverageType: BeverageType.espresso,
        steps: [
          ProfileStepPressure(
            name: "run wild",
            transition: TransitionType.fast,
            volume: 0.0,
            seconds: 120,
            temperature: 90.0,
            sensor: TemperatureSensor.coffee,
            pressure: 7.5,
          )
        ],
        targetVolumeCountStart: 0,
        tankTemperature: 0);
  }
}
