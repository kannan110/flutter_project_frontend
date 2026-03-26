import 'package:flutter/material.dart';
// TODO: Implement ShiftDetailScreen — full implementation coming in next module
class ShiftDetailScreen extends StatelessWidget {
  const ShiftDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ShiftDetailScreen')),
    body: Center(child: Text('Loading ShiftDetailScreen...')),
  );
}
