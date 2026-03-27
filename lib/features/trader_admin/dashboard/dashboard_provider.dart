import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final dashboardSummaryProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, traderId) async {
  final result = await Supabase.instance.client
      .rpc('dashboard_summary', params: {'p_trader_id': traderId});
  return Map<String, dynamic>.from(result as Map);
});
