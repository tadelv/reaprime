import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/history_feature/history_feature.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/util/shot_chart.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HistoryTile extends StatefulWidget {
  final PersistenceController persistenceController;
  final WorkflowController workflowController;

  const HistoryTile({
    super.key,
    required this.persistenceController,
    required this.workflowController,
  });

  @override
  State<HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<HistoryTile> {
  late StreamSubscription<void> _subscription;

  ShotRecord? _currentShot;
  int _totalShots = 0;
  int _currentIndex = 0; // 0 = most recent
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.persistenceController.shotsChanged.listen((_) {
      _currentIndex = 0;
      _loadCurrentShot();
    });
    _loadCurrentShot();
  }

  Future<void> _loadCurrentShot() async {
    final gen = ++_loadGeneration;
    final storage = widget.persistenceController.storageService;
    final total = await storage.countShots();
    if (total == 0) {
      if (mounted && gen == _loadGeneration) {
        setState(() {
          _totalShots = 0;
          _currentShot = null;
        });
      }
      return;
    }
    // Get shot metadata at current offset (ordered by timestamp desc — 0=newest)
    final metas = await storage.getShotsPaginated(
      limit: 1,
      offset: _currentIndex,
    );
    ShotRecord? fullShot;
    if (metas.isNotEmpty) {
      fullShot = await storage.getShot(metas.first.id);
    }
    Logger("History").fine(
      "loaded shot at index $_currentIndex / $total: ${fullShot?.timestamp}",
    );
    if (mounted && gen == _loadGeneration) {
      setState(() {
        _totalShots = total;
        _currentShot = fullShot;
      });
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentShot == null) {
      return Text("No shots yet.");
    }
    return _body(context);
  }

  Widget _body(BuildContext context) {
    var shot = _currentShot!;
    var canGoBack = _currentIndex < _totalShots - 1; // toward older
    var canGoForward = _currentIndex > 0; // toward newer
    return Semantics(
      explicitChildNodes: true,
      label: 'Shot history',
      child: Column(
      children: [
        Text(shot.shotTime()),
        Semantics(
          button: true,
          label:
              'View shot details for ${shot.workflow.profile.title} at ${shot.shotTime()}',
          child: TapRegion(
            child: ExcludeSemantics(child: _shotDetails(context, shot)),
            onTapInside: (cb) {
              Navigator.pushNamed(
                context,
                HistoryFeature.routeName,
                arguments: jsonEncode(shot.toJson()),
              );
            },
          ),
        ),
        _shotSummary(shot),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Semantics(
              button: true,
              label: 'Previous shot',
              child: ExcludeSemantics(
                child: ShadButton(
                  onPressed: () {
                    _currentIndex++;
                    _loadCurrentShot();
                  },
                  enabled: canGoBack,
                  child: Icon(LucideIcons.moveLeft),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Repeat workflow from this shot',
              child: ExcludeSemantics(
                child: ShadButton(
                  onPressed: () {
                    widget.workflowController.setWorkflow(shot.workflow);
                  },
                  child: Text("Repeat"),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Next shot',
              child: ExcludeSemantics(
                child: ShadButton(
                  onPressed: () {
                    _currentIndex--;
                    _loadCurrentShot();
                  },
                  enabled: canGoForward,
                  child: Icon(LucideIcons.moveRight),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    );
  }

  Widget _shotSummary(ShotRecord shot) {
    final doseIn =
        shot.annotations?.actualDoseWeight ??
        shot.workflow.context?.targetDoseWeight;
    final yield_ =
        shot.annotations?.actualYield ??
        shot.workflow.context?.targetYield ??
        shot.measurements.last.scale?.weight ??
        0.0;
    final parts = <String>[
      shot.workflow.profile.title,
      if (doseIn != null)
        '${doseIn.toStringAsFixed(1)} to ${yield_.toStringAsFixed(1)} grams',
      if (shot.workflow.context?.coffeeName != null)
        shot.workflow.context!.coffeeName!,
      if (shot.workflow.context?.grinderModel != null)
        shot.workflow.context!.grinderModel!,
    ];
    return Semantics(
      label: parts.join(', '),
      child: const SizedBox.shrink(),
    );
  }

  Widget _shotDetails(BuildContext context, ShotRecord shot) {
    final shotStart =
        shot.measurements
            .firstWhere(
              (el) =>
                  el.machine.state.substate == MachineSubstate.preinfusion ||
                  el.machine.state.substate == MachineSubstate.pouring,
              orElse: () => shot.measurements.first,
            )
            .machine
            .timestamp;
    final doseIn =
        shot.annotations?.actualDoseWeight ??
        shot.workflow.context?.targetDoseWeight;
    final doseOut = shot.workflow.context?.targetYield;
    final yield_ =
        shot.annotations?.actualYield ??
        shot.workflow.context?.targetYield ??
        shot.measurements.last.scale?.weight ??
        0.0;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: ShotChart(
            shotSnapshots: shot.measurements,
            shotStartTime: shotStart,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(shot.workflow.profile.title),
            if (doseIn != null && doseOut != null)
              Text(
                "${doseIn.toStringAsFixed(1)} : ${doseOut.toStringAsFixed(1)}",
              ),
            Text("${yield_.toStringAsFixed(1)}g"),
          ],
        ),
        if (shot.workflow.context?.coffeeName != null)
          Row(children: [Text(shot.workflow.context!.coffeeName!)]),
        if (shot.workflow.context?.grinderModel != null ||
            shot.workflow.context?.grinderSetting != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (shot.workflow.context?.grinderModel != null)
                Text(shot.workflow.context!.grinderModel!),
              if (shot.workflow.context?.grinderSetting != null)
                Text(shot.workflow.context!.grinderSetting!),
            ],
          ),
      ],
    );
  }
}
