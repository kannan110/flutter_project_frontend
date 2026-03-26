import 'package:flutter/material.dart';
// TODO: Implement ApprovalDetailScreen — full implementation coming in next module
class ApprovalDetailScreen extends StatelessWidget {
  const ApprovalDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ApprovalDetailScreen')),
    body: Center(child: Text('Loading ApprovalDetailScreen...')),
  );
}
