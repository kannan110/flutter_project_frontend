import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

final supabaseProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

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
    // Listen to auth state changes
    _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        _load();
      } else if (event.event == AuthChangeEvent.signedOut) {
        state = const AsyncValue.data(null);
      }
    });

    // If already logged in, load immediately
    if (_client.auth.currentUser != null) {
      _load();
    } else {
      // Not logged in — resolve immediately, never hang
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }

    try {
      // Single query: join user_roles + traders in one shot
      // This avoids 3 sequential RPCs that could timeout/hang
      final roleRow = await _client
          .from('user_roles')
          .select(
              'role, trader_id, is_active, traders(id, company_name, company_code, subscription_end_date)')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      // No role row = user exists in auth but not in user_roles
      // Resolve with null so router redirects to login, never hangs
      if (roleRow == null) {
        state = const AsyncValue.data(null);
        return;
      }

      final role = UserRole.fromString(roleRow['role'] as String?);
      final traderId = roleRow['trader_id'] as String?;
      final traderData = roleRow['traders'] as Map<String, dynamic>?;
      final companyName = traderData?['company_name'] as String?;
      final companyCode = traderData?['company_code'] as String?;
      final endStr = traderData?['subscription_end_date'] as String?;
      final subEnd = endStr != null ? DateTime.tryParse(endStr) : null;
      final subActive = subEnd == null || subEnd.isAfter(DateTime.now());

      // For delivery agents, also fetch their agent record
      String? agentId;
      if (role == UserRole.deliveryStaff && traderId != null) {
        final agent = await _client
            .from('delivery_agents')
            .select('id')
            .eq('auth_user_id', user.id)
            .eq('trader_id', traderId)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
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
    } catch (e) {
      // On ANY error (network, timeout, RLS) → resolve null → login screen
      // NEVER leave the app stuck on a loading spinner
      state = const AsyncValue.data(null);
    }
  }

  Future<void> reload() => _load();

  Future<void> signOut() async {
    await _client.auth.signOut();
    state = const AsyncValue.data(null);
  }
}
