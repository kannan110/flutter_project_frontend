import 'package:supabase_flutter/supabase_flutter.dart';

class ApprovalRepository {
  final SupabaseClient _client;
  ApprovalRepository(this._client);

  Future<String?> approveDelivery({
    required String deliveryId,
    required double finalRate,
    required double finalAmount,
    required String approvedBy,
    String? notes,
  }) async {
    return await _client.rpc('approve_delivery_and_order', params: {
      'p_delivery_id': deliveryId,
      'p_final_rate': finalRate,
      'p_final_amount': finalAmount,
      'p_approved_by': approvedBy,
      'p_approval_notes': notes,
    }) as String?;
  }

  Future<void> rejectDelivery({
    required String deliveryId,
    required String rejectedBy,
    required String reason,
  }) async {
    final delivery = await _client.from('deliveries')
        .select('order_id').eq('id', deliveryId).single();
    await Future.wait([
      _client.from('deliveries').update({
        'approval_status': 'rejected',
        'rejected_at': DateTime.now().toIso8601String(),
        'rejected_by': rejectedBy,
        'rejection_reason': reason,
      }).eq('id', deliveryId),
      _client.from('orders').update({'approval_status': 'rejected'})
          .eq('id', delivery['order_id']),
    ]);
  }
}
