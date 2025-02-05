import 'package:flutter/material.dart';

class RealtimeShotFeature extends StatefulWidget {
  static const routeName = '/shot';

  const RealtimeShotFeature({super.key});

  @override
  State<StatefulWidget> createState() => _RealtimeShotFeatureState();
}

class _RealtimeShotFeatureState extends State<RealtimeShotFeature> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Realtime Shot'),
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Realtime Shot Feature',
                style: TextStyle(fontSize: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
