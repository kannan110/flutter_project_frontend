// lib/core/providers/session_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (_) => Supabase.instance.client,
);

final appUserProvider =
    StateNotifierProvider<AppUserNotifier, AsyncValue<AppUser?>>(
  (ref) => AppUserNotifier(ref.watch(supabaseProvider)),
);

class AppUserNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  final SupabaseClient _client;

  AppUserNotifier(this._client) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        load();
      } else if (event.event == AuthChangeEvent.signedOut) {
        state = const AsyncValue.data(null);
      }
    });
    if (_client.auth.currentUser != null) {
      load();
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        state = const AsyncValue.data(null);
        return;
      }

      final roleStr =
          await _client.rpc('current_user_role') as String?;
      final traderId =
          await _client.rpc('current_user_trader_id') as String?;
      final subActive =
          await _client.rpc('is_subscription_active') as bool? ?? false;

      final role = UserRole.fromString(roleStr ?? 'trader_staff');

      String? companyName, companyCode, agentId;
      DateTime? subEnd;

      if (traderId != null) {
        final trader = await _client
            .from('traders')
            .select('company_name, company_code, subscription_end_date')
            .eq('id', traderId)
            .maybeSingle();
        companyName = trader?['company_name'] as String?;
        companyCode = trader?['company_code'] as String?;
        final endStr = trader?['subscription_end_date'] as String?;
        subEnd = endStr != null ? DateTime.tryParse(endStr) : null;
      }

      if (role == UserRole.deliveryStaff && traderId != null) {
        final agent = await _client
            .from('delivery_agents')
            .select('id')
            .eq('auth_user_id', user.id)
            .eq('trader_id', traderId)
            .maybeSingle();
        agentId = agent?['id'] as String?;
      }

      state = AsyncValue.data(AppUser(
        userId: user.id,
        traderId: traderId,
        role: role,
        companyName: companyName,
        companyCode: companyCode,
        isSubscriptionActive: subActive,
        subscriptionEndDate: subEnd,
        agentId: agentId,
      ));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    state = const AsyncValue.data(null);
  }
}
