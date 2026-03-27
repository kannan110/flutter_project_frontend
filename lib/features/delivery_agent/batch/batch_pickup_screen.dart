import 'package:flutter/material.dart';
// TODO: Implement BatchPickupScreen — full implementation coming in next module
class BatchPickupScreen extends StatelessWidget {
  const BatchPickupScreen({super.key, required this.batchId});
  final String batchId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BatchPickupScreen')),
    body: Center(child: Text('Loading BatchPickupScreen...')),
  );
}
