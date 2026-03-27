import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersRepository {
  final SupabaseClient _client;
  OrdersRepository(this._client);

  Future<Map<String, dynamic>> createOrder({
    required String traderId,
    required String retailerId,
    required String productId,
    required int birdCount,
    required double totalQuantityKg,
    required String paymentType,
    String? notes,
    DateTime? deliveryDate,
    String source = 'trader',
  }) async {
    final rateResult = await _client.rpc(
      'get_current_rate',
      params: {'p_trader_id': traderId, 'p_product_id': productId},
    );
    final ratePerKg = (rateResult as num?)?.toDouble() ?? 0.0;
    final lineTotal = totalQuantityKg * ratePerKg;

    final order = await _client.from('orders').insert({
      'trader_id': traderId,
      'retailer_id': retailerId,
      'product_id': productId,
      'total_quantity': totalQuantityKg,
      'estimated_birds': birdCount,
      'total_amount': lineTotal,
      'payment_type': paymentType,
      'source': source,
      'notes': notes,
      'delivery_date':
          deliveryDate?.toIso8601String().split('T').first,
      'status': 'pending',
    }).select().single();

    final orderId = order['id'] as String;

    if (ratePerKg > 0) {
      await _client.from('order_items').insert({
        'order_id': orderId,
        'trader_id': traderId,
        'product_id': productId,
        'bird_count': birdCount,
        'avg_weight_per_bird':
            birdCount > 0 ? totalQuantityKg / birdCount : null,
        'total_weight': totalQuantityKg,
        'rate_per_kg': ratePerKg,
        'line_total': lineTotal,
      });
    }

    return order;
  }

  Future<List<Map<String, dynamic>>> fetchOrders({
    required String traderId,
    String? status,
    int limit = 50,
  }) async {
    var query = _client
        .from('orders')
        .select('*, retailers(id,shop_name,owner_name,phone), master_products(id,name,category)')
        .eq('trader_id', traderId)
        .order('created_at', ascending: false)
        .limit(limit);
    if (status != null) query = query.eq('status', status);
    return List<Map<String, dynamic>>.from(await query);
  }

  Future<Map<String, dynamic>?> fetchOrder(String id) async {
    return await _client.from('orders')
        .select('*, retailers(*), master_products(*), order_items(*), deliveries(*)')
        .eq('id', id).maybeSingle();
  }

  Future<void> updateStatus(String id, String status) async {
    await _client.from('orders').update({'status': status}).eq('id', id);
  }

  Future<void> confirm(String id) async =>
      updateStatus(id, 'confirmed');

  Future<void> cancel(String id) async =>
      updateStatus(id, 'cancelled');
}
