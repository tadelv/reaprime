import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/shot_parameters.dart';
import 'package:uuid/uuid.dart';

class WorkflowController {
  Profile? loadedProfile;
  TargetShotParameters? targetShotParameters;

  WorkflowController({this.loadedProfile});

  Workflow currentWorkflow() {
    return Workflow(
      id: Uuid().v4(),
      name: "Workflow",
      description: "Description",
      profile: loadedProfile!,
      shotParameters: targetShotParameters!,
    );
  }
}
