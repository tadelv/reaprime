import 'package:collection/collection.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/home_feature/tiles/status_tile.dart';

class HomeScreen extends StatelessWidget {
  static const routeName = '/home';
  const HomeScreen({super.key, required this.de1controller});

  final De1Controller de1controller;

  final double _leftColumWidth = 450;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
        appBar: AppBar(
          title: Text('ReaPrime'),
        ),
        body: _home(context));
  }

  Widget _home(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(
                width: 16,
              ),
              _leftColumn(context),
              SizedBox(
                width: 16,
              ),
              _rightColumn(context),
              SizedBox(
                width: 16,
              ),
            ],
          )),
    );
  }

  Widget _leftColumn(BuildContext context) {
    return Column(
      spacing: 12,
      children: [
        _historyCard(context),
      ],
    );
  }

  Widget _rightColumn(BuildContext context) {
    return Expanded(
      child: Column(
        spacing: 12,
        children: [
          _statusCard(context),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final theme = ShadTheme.of(context);
    return SizedBox(
        width: double.infinity,
        child: ShadCard(height: 200, child: _de1Status(context)));
  }

  Widget _de1Status(BuildContext context) {
    return StreamBuilder(
      stream: de1controller.de1,
      builder: (context, de1Available) {
        if (de1Available.hasData) {
          return SizedBox(child: StatusTile(de1: de1Available.data!));
        } else {
          return Text("Connecting to DE1");
        }
      },
    );
  }

  Widget _historyCard(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
        width: _leftColumWidth,
        title: Text(
          'Last shot',
          style: theme.textTheme.h4,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Name'),
              const ShadInput(placeholder: Text('Name of your project')),
              const SizedBox(height: 6),
              const Text('Framework'),
              ShadButton(
                  onPressed: () {
                    print("f");
                  },
                  child: Text("Press")),
            ],
          ),
        ));
  }
}
