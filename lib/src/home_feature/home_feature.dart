import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/home_feature/tiles/status_tile.dart';

class HomeScreen extends StatelessWidget {
  static const routeName = '/home';
  const HomeScreen({super.key, required this.de1controller});

  final De1Controller de1controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueAccent, Colors.lightBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Dashboard Tiles
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 2.0,
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              children: [
                DashboardTile(title: "Tile 1", value: "Data 1"),
                DashboardTile(title: "Tile 2", value: "Data 2"),
                _status(
                  de1controller,
                ),
                DashboardTile(title: "Tile 4", value: "Data 4"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(De1Controller de1controller) {
    return StreamBuilder(
        stream: de1controller.de1,
        builder: (context, de1Snapshot) {
          switch (de1Snapshot.hasData) {
            case true:
              return StatusTile(
                de1: de1Snapshot.data!,
              );
            case false:
              return DashboardTile(
                  title: "Waiting for connection", value: "to DE1");
          }
        });
  }
}

class DashboardTile extends StatelessWidget {
  final String title;
  final String value;

  const DashboardTile({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
