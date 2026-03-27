import 'package:flutter/material.dart';
// TODO: Implement RetailerDetailScreen — full implementation coming in next module
class RetailerDetailScreen extends StatelessWidget {
  const RetailerDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RetailerDetailScreen')),
    body: Center(child: Text('Loading RetailerDetailScreen...')),
  );
}
