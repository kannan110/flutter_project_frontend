import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

// ignore: avoid_print
void _log(String m) => print('[Session] $m');

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

final appUserProvider = StateNotifierProvider<AppUserNotifier, AsyncValue<AppUser?>>(
  (ref) => AppUserNotifier(ref.watch(supabaseProvider)),
);

class AppUserNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final SupabaseClient _c;
  AppUserNotifier(this._c) : super(const AsyncValue.loading()) { _init(); }

  void _init() {
    _c.auth.onAuthStateChange.listen((e) {
      _log('Auth: ${e.event}');
      if (e.event == AuthChangeEvent.signedIn || e.event == AuthChangeEvent.tokenRefreshed) {
        _load();
      } else if (e.event == AuthChangeEvent.signedOut) {
        state = const AsyncValue.data(null);
      }
    });
    if (_c.auth.currentUser != null) _load();
    else state = const AsyncValue.data(null);
  }

  Future<void> _load() async {
    final user = _c.auth.currentUser;
    if (user == null) { state = const AsyncValue.data(null); return; }
    _log('Loading uid=${user.id}');
    state = const AsyncValue.loading();
    try {
      // Single join — user_roles RLS is now: user_id = auth.uid() only (no recursion)
      final row = await _c
          .from('user_roles')
          .select('role, trader_id, is_active, traders(id, company_name, company_code, subscription_end_date)')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (row == null) {
        // Trader owner without user_roles row yet
        _log('No user_roles row — checking traders.owner_user_id');
        final trader = await _c.from('traders')
            .select('id, company_name, company_code, subscription_end_date')
            .eq('owner_user_id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        if (trader != null) {
          _log('Auto-creating user_roles for trader owner');
          try {
            await _c.from('user_roles').upsert({
              'user_id': user.id, 'trader_id': trader['id'],
              'role': 'trader_admin', 'is_active': true,
            }, onConflict: 'user_id,trader_id');
          } catch (e) { _log('upsert non-fatal: $e'); }
          final sub = _pd(trader['subscription_end_date']);
          state = AsyncValue.data(AppUser(
            userId: user.id, traderId: trader['id'] as String,
            role: UserRole.traderAdmin,
            companyName: trader['company_name'] as String?,
            companyCode: trader['company_code'] as String?,
            isSubscriptionActive: sub == null || sub.isAfter(DateTime.now()),
            subscriptionEndDate: sub,
          ));
          return;
        }
        _log('No trader found → login screen');
        state = const AsyncValue.data(null);
        return;
      }

      final role     = UserRole.fromString(row['role'] as String?);
      final traderId = row['trader_id'] as String?;
      final tMap     = row['traders'] as Map<String, dynamic>?;
      final sub      = _pd(tMap?['subscription_end_date']);

      String? agentId;
      if (role == UserRole.deliveryStaff && traderId != null) {
        final a = await _c.from('delivery_agents')
            .select('id').eq('auth_user_id', user.id)
            .eq('trader_id', traderId).eq('is_active', true)
            .maybeSingle().timeout(const Duration(seconds: 5));
        agentId = a?['id'] as String?;
        _log('agentId=$agentId');
      }

      state = AsyncValue.data(AppUser(
        userId: user.id, traderId: traderId, role: role,
        companyName: tMap?['company_name'] as String?,
        companyCode: tMap?['company_code'] as String?,
        isSubscriptionActive: sub == null || sub.isAfter(DateTime.now()),
        subscriptionEndDate: sub, agentId: agentId,
      ));
      _log('Session OK ✓ role=${role.dbValue}');
    } catch (e, st) {
      _log('ERROR: $e\n$st');
      state = const AsyncValue.data(null); // go to login on any error
    }
  }

  DateTime? _pd(dynamic v) => v == null ? null : DateTime.tryParse(v as String);
  Future<void> reload() => _load();
  Future<void> signOut() async { await _c.auth.signOut(); state = const AsyncValue.data(null); }
}
