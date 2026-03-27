import 'package:supabase_flutter/supabase_flutter.dart';

class LedgerRepository {
  final SupabaseClient _client;
  LedgerRepository(this._client);

  Future<void> recordPayment({
    required String traderId,
    required String retailerId,
    required double amount,
    required String paymentMode,
    String? description,
    String? orderId,
    DateTime? entryDate,
  }) async {
    await _client.from('ledger_entries').insert({
      'trader_id': traderId,
      'retailer_id': retailerId,
      'entry_type': 'credit',
      'amount': amount,
      'payment_mode': paymentMode,
      'source_type': 'payment',
      'order_id': orderId,
      'entry_date': (entryDate ?? DateTime.now()).toIso8601String().split('T').first,
      'description': description ?? 'Payment received',
    });
  }

  Future<double> getOutstanding(String retailerId) async {
    final result = await _client.rpc(
        'get_retailer_outstanding', params: {'p_retailer_id': retailerId});
    return (result as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> fetchRetailerLedger({
    required String traderId,
    required String retailerId,
    int limit = 100,
  }) async {
    return List<Map<String, dynamic>>.from(
      await _client.from('ledger_entries').select('*')
          .eq('trader_id', traderId).eq('retailer_id', retailerId)
          .order('entry_date', ascending: false).limit(limit),
    );
  }
}
