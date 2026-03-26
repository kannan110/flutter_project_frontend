import 'package:flutter/material.dart';
// TODO: Implement RetailerLedgerScreen — full implementation coming in next module
class RetailerLedgerScreen extends StatelessWidget {
  const RetailerLedgerScreen({super.key, required this.retailerId});
  final String retailerId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RetailerLedgerScreen')),
    body: Center(child: Text('Loading RetailerLedgerScreen...')),
  );
}
