import 'package:flutter/material.dart';
// TODO: Implement InvoiceDetailScreen — full implementation coming in next module
class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('InvoiceDetailScreen')),
    body: Center(child: Text('Loading InvoiceDetailScreen...')),
  );
}
