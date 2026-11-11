import 'package:supabase_flutter/supabase_flutter.dart';

/// Settings → Preferences → Auto-approve shift close
/// (traders.auto_approve_shift_close).
///
/// Call right after the TRADER closes a shift. When the setting is on, the
/// shift is approved through the same `approve_shift` RPC the Shift Detail
/// screen's Approve button uses. Returns a line to append to the success
/// message ('' when the setting is off). Never throws: if approval fails the
/// shift simply waits in Shifts, exactly as when the setting is off.
Future<String> autoApproveShiftIfEnabled({
  required SupabaseClient client,
  required String? traderId,
  required String shiftId,
  required String? userId,
}) async {
  if (traderId == null) return '';
  try {
    final t = await client
        .from('traders')
        .select('auto_approve_shift_close')
        .eq('id', traderId)
        .maybeSingle();
    if (!((t?['auto_approve_shift_close'] as bool?) ?? false)) return '';
  } catch (_) {
    return ''; // setting unreadable: leave it for approval, as before
  }
  try {
    await client.rpc('approve_shift', params: {
      'p_shift_id': shiftId,
      'p_approved_by': userId,
      'p_notes': 'Auto-approved on close by trader',
      'p_actor_type': 'trader',
      'p_entry_mode': 'system',
    });
    return '\nShift approved';
  } catch (e) {
    final msg = e
        .toString()
        .replaceAll('Exception: ', '')
        .replaceAll('PostgrestException(message: ', '');
    return '\nNot auto-approved ($msg). It is waiting in Shifts.';
  }
}
