import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryRepository {
  final SupabaseClient _client;
  DeliveryRepository(this._client);

  Future<void> completeDelivery({
    required String deliveryId,
    required int birdsDelivered,
    required double deliveredTotalWeight,
    required int receivedBirdCount,
    required double receivedTotalWeight,
    int rejectedBirds = 0,
    int mortalityBirds = 0,
    double returnedBirds = 0,
    double returnedWeight = 0,
    int cratesDropped = 0,
    int cratesCollected = 0,
    int cratesReturned = 0,
    required double collectedAmount,
    required String paymentMode,
    String? deliveryNotes,
  }) async {
    await _client.rpc('complete_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_birds_delivered': birdsDelivered,
      'p_delivered_total_weight': deliveredTotalWeight,
      'p_received_bird_count': receivedBirdCount,
      'p_received_total_weight': receivedTotalWeight,
      'p_rejected_birds': rejectedBirds,
      'p_mortality_birds': mortalityBirds,
      'p_returned_birds': returnedBirds,
      'p_returned_weight': returnedWeight,
      'p_crates_dropped': cratesDropped,
      'p_crates_collected': cratesCollected,
      'p_crates_returned': cratesReturned,
      'p_collected_amount': collectedAmount,
      'p_payment_mode': paymentMode,
      'p_delivery_notes': deliveryNotes,
    });
  }

  Future<void> retailerConfirm({
    required String deliveryId,
    required int confirmedBirdCount,
    required double confirmedWeight,
    String status = 'confirmed',
  }) async {
    await _client.from('deliveries').update({
      'retailer_confirmation_status': status,
      'retailer_confirmed_bird_count': confirmedBirdCount,
      'retailer_confirmed_weight': confirmedWeight,
      'retailer_confirmation_at': DateTime.now().toIso8601String(),
    }).eq('id', deliveryId);
  }

  Future<List<Map<String, dynamic>>> fetchAgentDeliveries({
    required String agentId,
    String? shiftId,
  }) async {
    var query = _client.from('deliveries')
        .select('*, orders(*, retailers(id,shop_name,owner_name,phone,address,latitude,longitude))')
        .eq('delivery_agent_id', agentId)
        .order('assigned_at');
    if (shiftId != null) query = query.eq('delivery_shift_id', shiftId);
    return List<Map<String, dynamic>>.from(await query);
  }

  Future<List<Map<String, dynamic>>> fetchPendingApprovals(String traderId) async {
    return List<Map<String, dynamic>>.from(await _client.from('deliveries')
        .select('*, orders(*, retailers(id,shop_name,owner_name)), delivery_agents(id,name,phone)')
        .eq('trader_id', traderId)
        .eq('status', 'delivered')
        .eq('approval_status', 'pending')
        .order('delivered_at', ascending: false));
  }
}
