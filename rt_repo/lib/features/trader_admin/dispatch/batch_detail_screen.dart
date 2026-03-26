import 'package:flutter/material.dart';
// TODO: Implement BatchDetailScreen — full implementation coming in next module
class BatchDetailScreen extends StatelessWidget {
  const BatchDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BatchDetailScreen')),
    body: Center(child: Text('Loading BatchDetailScreen...')),
  );
}
