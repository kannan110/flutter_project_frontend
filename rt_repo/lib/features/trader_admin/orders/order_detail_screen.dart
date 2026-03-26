import 'package:flutter/material.dart';
// TODO: Implement OrderDetailScreen — full implementation coming in next module
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OrderDetailScreen')),
    body: Center(child: Text('Loading OrderDetailScreen...')),
  );
}
