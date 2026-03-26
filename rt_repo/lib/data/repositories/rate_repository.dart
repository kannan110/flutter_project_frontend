import 'package:supabase_flutter/supabase_flutter.dart';

class RateRepository {
  final SupabaseClient _client;
  RateRepository(this._client);

  Future<void> setRate({
    required String traderId,
    required String productId,
    required double ratePerKg,
    String? notes,
    String? setBy,
  }) async {
    await _client.from('rate_history').upsert({
      'trader_id': traderId,
      'product_id': productId,
      'rate_per_kg': ratePerKg,
      'effective_date': DateTime.now().toIso8601String().split('T').first,
      'notes': notes,
      'set_by': setBy,
    }, onConflict: 'trader_id, product_id, effective_date');
  }

  Future<Map<String, double>> getAllTodayRates(String traderId) async {
    final rows = await _client.from('rate_history')
        .select('product_id, rate_per_kg')
        .eq('trader_id', traderId)
        .lte('effective_date', DateTime.now().toIso8601String().split('T').first)
        .order('effective_date', ascending: false);
    final rates = <String, double>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final pid = row['product_id'] as String;
      if (!rates.containsKey(pid)) {
        rates[pid] = (row['rate_per_kg'] as num).toDouble();
      }
    }
    return rates;
  }
}
