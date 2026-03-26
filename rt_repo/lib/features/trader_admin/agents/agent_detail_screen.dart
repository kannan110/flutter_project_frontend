import 'package:flutter/material.dart';
// TODO: Implement AgentDetailScreen — full implementation coming in next module
class AgentDetailScreen extends StatelessWidget {
  const AgentDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AgentDetailScreen')),
    body: Center(child: Text('Loading AgentDetailScreen...')),
  );
}
