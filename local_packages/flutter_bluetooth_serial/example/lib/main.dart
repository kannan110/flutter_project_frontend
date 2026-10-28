import 'package:flutter/material.dart';

import './MainPage.dart';

void main() => runApp(const ExampleApplication());

class ExampleApplication extends StatelessWidget {
  const ExampleApplication({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MainPage());
  }
}
