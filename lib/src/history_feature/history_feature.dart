import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HistoryFeature extends StatefulWidget {
  static const routeName = '/history';

  const HistoryFeature({
    super.key,
    required this.persistenceController,
  });

  final PersistenceController persistenceController;

  @override
  State<StatefulWidget> createState() => _HistoryFeatureState();
}

class _HistoryFeatureState extends State<HistoryFeature> {
  TextEditingController _searchController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("History")),
      body: body(context),
    );
  }

  Widget body(BuildContext context) {
    return SafeArea(
        child: Row(
      children: [
        leftColumn(context),
      ],
    ));
  }

  Widget leftColumn(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SearchBar(
          controller: _searchController,
					hintText: "Search shots",
        ),
        // ListView.builder(itemBuilder: (context, index) {
        //   return ShadCard(
        //     title: Text("Hello"),
        //   );
        // })
      ],
    );
  }
}
