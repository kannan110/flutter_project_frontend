import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftRepository {
  final SupabaseClient _client;
  ShiftRepository(this._client);

  Future<Map<String, dynamic>> openShift({
    required String agentId,
    required String traderId,
    required int openingBirdCount,
    required double openingWeight,
    required double odometerStart,
    String? odometerStartPhoto,
  }) async {
    final existing = await _client.from('delivery_shifts')
        .select('id').eq('delivery_agent_id', agentId)
        .eq('status', 'open').maybeSingle();
    if (existing != null) throw Exception('Agent already has an open shift');

    final result = await _client.from('delivery_shifts').insert({
      'delivery_agent_id': agentId,
      'trader_id': traderId,
      'shift_start_at': DateTime.now().toIso8601String(),
      'opening_bird_count': openingBirdCount,
      'opening_weight': openingWeight,
      'odometer_start': odometerStart,
      'odometer_start_photo': odometerStartPhoto,
      'status': 'open',
    }).select().single();

    await _client.from('delivery_agents')
        .update({'is_online': true, 'last_seen_at': DateTime.now().toIso8601String()})
        .eq('id', agentId);

    return result;
  }

  Future<void> closeShift({
    required String shiftId,
    required String agentId,
    required int closingBirdCount,
    required double closingWeight,
    required double odometerEnd,
    String? odometerEndPhoto,
    double expenses = 0,
  }) async {
    await _client.rpc('close_delivery_shift', params: {
      'p_shift_id': shiftId,
      'p_odometer_end': odometerEnd,
      'p_odometer_end_photo': odometerEndPhoto ?? '',
      'p_closing_bird_count': closingBirdCount,
      'p_closing_weight': closingWeight,
      'p_expenses': expenses,
    });
    await _client.from('delivery_agents')
        .update({'is_online': false, 'last_seen_at': DateTime.now().toIso8601String()})
        .eq('id', agentId);
  }

  Future<Map<String, dynamic>?> getOpenShift(String agentId) async {
    return await _client.from('delivery_shifts')
        .select('*').eq('delivery_agent_id', agentId)
        .eq('status', 'open').maybeSingle();
  }

  Future<List<Map<String, dynamic>>> getShifts({
    required String traderId,
    String? approvalStatus,
    int limit = 30,
  }) async {
    var query = _client.from('delivery_shifts')
        .select('*, delivery_agents(id,name,phone,vehicle_no)')
        .eq('trader_id', traderId)
        .order('shift_start_at', ascending: false)
        .limit(limit);
    if (approvalStatus != null) query = query.eq('shift_approval_status', approvalStatus);
    return List<Map<String, dynamic>>.from(await query);
  }

  Future<void> addExpense({
    required String shiftId,
    required String traderId,
    required String expenseType,
    required double amount,
    String? notes,
    String? receiptUrl,
  }) async {
    await _client.from('delivery_expenses').insert({
      'shift_id': shiftId,
      'trader_id': traderId,
      'expense_type': expenseType,
      'amount': amount,
      'notes': notes,
      'receipt_url': receiptUrl,
    });
  }
}
