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
    if (_c.auth.currentUser != null) {
      _load();
    } else {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _load() async {
    final user = _c.auth.currentUser;
    if (user == null) { state = const AsyncValue.data(null); return; }
    _log('Loading uid=${user.id}');
    state = const AsyncValue.loading();
    try {
      // Step 1: get user_roles row (RLS: user_id = auth.uid() — no join, no recursion)
      final row = await _c
          .from('user_roles')
          .select('role, trader_id, is_active')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('role', ascending: true)  // trader_admin comes before delivery_staff
          .limit(1)
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
        _log('No trader found — orphaned auth user, sending to link screen');
        // Return a minimal AppUser with unknown role so router sends to agent link
        // instead of login (prevents infinite signedIn → null → login loop)
        state = AsyncValue.data(AppUser(
          userId: user.id,
          traderId: null,
          role: UserRole.unknown,
          companyName: null,
          companyCode: null,
          isSubscriptionActive: false,
          subscriptionEndDate: null,
          agentId: null,
        ));
        return;
      }

      final role     = UserRole.fromString(row['role'] as String?);
      final traderId = row['trader_id'] as String?;

      // Step 2: fetch trader separately
      Map<String, dynamic>? tMap;
      if (traderId != null) {
        try {
          tMap = await _c.from('traders')
              .select('id,company_name,company_code,subscription_end_date,status,approval_status')
              .eq('id', traderId)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
        } catch (e) { _log('Trader fetch non-fatal: $e'); }
      }
      final sub            = _pd(tMap?['subscription_end_date']);
      final traderStatus   = tMap?['status']          as String? ?? 'active';
      final approvalStatus = tMap?['approval_status'] as String? ?? 'approved';

      // Check if super admin — based on user_roles.role = 'super_admin'
      final isSa = role == UserRole.superAdmin;

      String? agentId;
      if (role == UserRole.deliveryStaff && traderId != null) {
        final a = await _c.from('delivery_agents')
            .select('id').eq('auth_user_id', user.id)
            .eq('trader_id', traderId).eq('is_active', true)
            .maybeSingle().timeout(const Duration(seconds: 5));
        agentId = a?['id'] as String?;
        _log('agentId=$agentId');
      }

      // Supervisor / Collection Agent module (Plug & Play) — resolve for
      // BOTH the supervisor themselves (agentId-equivalent: which
      // supervisor_profiles row is this?) and for trader_admin (needs the
      // module-enabled flag too, purely to show/hide "Create Supervisor"
      // in Settings — no other role needs this field at all).
      String? supervisorId;
      var supervisorModuleEnabled = false;
      if (traderId != null && (role == UserRole.supervisor || role == UserRole.traderAdmin)) {
        try {
          final tf = await _c.from('trader_features')
              .select('supervisor_module').eq('trader_id', traderId)
              .maybeSingle().timeout(const Duration(seconds: 5));
          supervisorModuleEnabled = (tf?['supervisor_module'] as bool?) ?? false;
        } catch (e) { _log('trader_features fetch non-fatal: $e'); }
      }
      if (role == UserRole.supervisor && traderId != null) {
        final s = await _c.from('supervisor_profiles')
            .select('id').eq('user_id', user.id)
            .eq('trader_id', traderId).eq('is_active', true)
            .maybeSingle().timeout(const Duration(seconds: 5));
        supervisorId = s?['id'] as String?;
        _log('supervisorId=$supervisorId');
      }

      // Resolve retailer session
      String? retailerId;
      String? shopName;
      if (role == UserRole.retailerUser) {
        try {
          final rs = await _c.rpc('get_retailer_session',
              params: {'p_user_id': user.id})
              .timeout(const Duration(seconds: 5));
          if (rs is Map) {
            retailerId = rs['retailer_id'] as String?;
            shopName   = rs['shop_name']   as String?;
            _log('retailerId=\$retailerId');
          }
        } catch (e) { _log('retailer session: \$e'); }
      }

      state = AsyncValue.data(AppUser(
        userId:              user.id,
        traderId:            traderId,
        role:                isSa ? UserRole.superAdmin : role,
        companyName:         tMap?['company_name']   as String?,
        companyCode:         tMap?['company_code']   as String?,
        isSubscriptionActive: sub == null || sub.isAfter(DateTime.now()),
        subscriptionEndDate: sub,
        agentId:             agentId,
        retailerId:          retailerId,
        shopName:            shopName,
        traderStatus:        traderStatus,
        approvalStatus:      approvalStatus,
        isSuperAdmin:        isSa,
        supervisorId:            supervisorId,
        supervisorModuleEnabled: supervisorModuleEnabled,
      ));
      _log('Session OK ✓ role=${role.dbValue}');
    } catch (e, st) {
      _log('SESSION ERROR: $e');
      _log('STACKTRACE: $st');
      // Instead of silently going to null (which loops to login),
      // surface the error so the UI can show it
      state = AsyncValue.error(e, st);
    }
  }

  DateTime? _pd(dynamic v) => v == null ? null : DateTime.tryParse(v as String);
  Future<void> reload() => _load();
  Future<void> signOut() async { await _c.auth.signOut(); state = const AsyncValue.data(null); }
}