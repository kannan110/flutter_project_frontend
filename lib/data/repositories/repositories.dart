import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class OrdersRepository {
  final SupabaseClient _c;
  OrdersRepository(this._c);

  Future<Map<String, dynamic>> createOrder({required String traderId, required String retailerId,
      required String productId, required int birdCount, required double totalWeightKg,
      required String paymentType, String? notes}) async {
    final rate = await _c.rpc('get_current_rate', params: {'p_trader_id': traderId, 'p_product_id': productId});
    final rateVal = (rate as num?)?.toDouble() ?? 0.0;
    if (rateVal <= 0) throw Exception('No rate set for today. Please set rates first.');
    final lineTotal = totalWeightKg * rateVal;
    final order = await _c.from('orders').insert({
      'trader_id': traderId, 'retailer_id': retailerId, 'product_id': productId,
      'estimated_birds': birdCount, 'total_quantity': totalWeightKg, 'total_amount': lineTotal,
      'payment_type': paymentType, 'source': 'trader', 'notes': notes, 'status': 'pending',
    }).select().single();
    await _c.from('order_items').insert({
      'order_id': order['id'], 'trader_id': traderId, 'product_id': productId,
      'bird_count': birdCount, 'total_weight': totalWeightKg, 'rate_per_kg': rateVal, 'line_total': lineTotal,
    });
    return order;
  }
}

class RateRepository {
  final SupabaseClient _c;
  RateRepository(this._c);
  Future<void> setRate({required String traderId, required String productId, required double ratePerKg, String? setBy}) async {
    await _c.from('rate_history').upsert({
      'trader_id': traderId, 'product_id': productId, 'rate_per_kg': ratePerKg,
      'effective_date': DateFormat('yyyy-MM-dd').format(DateTime.now()), 'set_by': setBy,
    }, onConflict: 'trader_id,product_id,effective_date');
  }
}

class LedgerRepository {
  final SupabaseClient _c;
  LedgerRepository(this._c);
  Future<void> recordPayment({required String traderId, required String retailerId,
      required double amount, required String paymentMode, String? description}) async {
    await _c.from('ledger_entries').insert({
      'trader_id': traderId, 'retailer_id': retailerId, 'entry_type': 'credit',
      'amount': amount, 'payment_mode': paymentMode, 'source_type': 'payment',
      'entry_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'description': description ?? 'Payment received',
    });
  }
}
