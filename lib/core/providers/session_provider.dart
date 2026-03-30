import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

// ignore: avoid_print
void _log(String msg) => print('[SessionProvider] $msg');

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

final appUserProvider = StateNotifierProvider<AppUserNotifier, AsyncValue<AppUser?>>(
  (ref) => AppUserNotifier(ref.watch(supabaseProvider)),
);

class AppUserNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final SupabaseClient _client;

  AppUserNotifier(this._client) : super(const AsyncValue.loading()) {
    _log('Initializing...');
    _init();
  }

  void _init() {
    _client.auth.onAuthStateChange.listen((event) {
      _log('Auth event: ${event.event} | user: ${event.session?.user.email}');
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        _load();
      } else if (event.event == AuthChangeEvent.signedOut) {
        _log('Signed out - clearing user');
        state = const AsyncValue.data(null);
      }
    });
    if (_client.auth.currentUser != null) {
      _log('Already logged in as ${_client.auth.currentUser!.email}');
      _load();
    } else {
      _log('No current user - showing login');
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _load() async {
    final user = _client.auth.currentUser;
    if (user == null) { _log('_load: no user'); state = const AsyncValue.data(null); return; }

    _log('_load: uid=${user.id} email=${user.email}');
    state = const AsyncValue.loading();

    try {
      _log('_load: querying user_roles + traders...');
      final roleRow = await _client
          .from('user_roles')
          .select('role, trader_id, is_active, traders(id, company_name, company_code, subscription_end_date)')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      _log('_load: roleRow=$roleRow');

      if (roleRow == null) {
        _log('_load: no user_roles row - trying traders.owner_user_id fallback');
        final ownedTrader = await _client
            .from('traders')
            .select('id, company_name, company_code, subscription_end_date')
            .eq('owner_user_id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        _log('_load: ownedTrader=$ownedTrader');
        if (ownedTrader != null) {
          _log('_load: auto-creating user_roles row...');
          try {
            await _client.from('user_roles').upsert({
              'user_id': user.id, 'trader_id': ownedTrader['id'],
              'role': 'trader_admin', 'is_active': true,
            }, onConflict: 'user_id,trader_id');
          } catch (e) { _log('_load: upsert failed (non-fatal): $e'); }
          final endStr = ownedTrader['subscription_end_date'] as String?;
          final subEnd = endStr != null ? DateTime.tryParse(endStr) : null;
          state = AsyncValue.data(AppUser(
            userId: user.id, traderId: ownedTrader['id'] as String,
            role: UserRole.traderAdmin, companyName: ownedTrader['company_name'] as String?,
            companyCode: ownedTrader['company_code'] as String?,
            isSubscriptionActive: subEnd == null || subEnd.isAfter(DateTime.now()),
            subscriptionEndDate: subEnd,
          ));
          _log('_load: resolved via owner fallback');
          return;
        }
        _log('_load: no trader found - going to login');
        state = const AsyncValue.data(null);
        return;
      }

      final role     = UserRole.fromString(roleRow['role'] as String?);
      final traderId = roleRow['trader_id'] as String?;
      final tMap     = roleRow['traders'] as Map<String, dynamic>?;
      final endStr   = tMap?['subscription_end_date'] as String?;
      final subEnd   = endStr != null ? DateTime.tryParse(endStr) : null;
      _log('_load: role=$role traderId=$traderId company=${tMap?['company_name']}');

      String? agentId;
      if (role == UserRole.deliveryStaff && traderId != null) {
        _log('_load: delivery staff - fetching agent record...');
        final agent = await _client
            .from('delivery_agents')
            .select('id')
            .eq('auth_user_id', user.id)
            .eq('trader_id', traderId)
            .eq('is_active', true)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
        agentId = agent?['id'] as String?;
        _log('_load: agentId=$agentId');
      }

      state = AsyncValue.data(AppUser(
        userId: user.id, traderId: traderId, role: role,
        companyName: tMap?['company_name'] as String?,
        companyCode: tMap?['company_code'] as String?,
        isSubscriptionActive: subEnd == null || subEnd.isAfter(DateTime.now()),
        subscriptionEndDate: subEnd, agentId: agentId,
      ));
      _log('_load: SUCCESS role=${role.dbValue} company=${tMap?['company_name']}');
    } catch (e, st) {
      _log('_load: ERROR $e');
      _log('_load: stack $st');
      state = const AsyncValue.data(null);
    }
  }

  Future<void> reload() { _log('reload()'); return _load(); }

  Future<void> signOut() async {
    _log('signOut()');
    await _client.auth.signOut();
    state = const AsyncValue.data(null);
  }
}
