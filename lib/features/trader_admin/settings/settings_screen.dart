import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _buildScaffold(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('More'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Profile card — navy gradient ───────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kNavy, kNavyMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(kRadiusHero),
            ),
            padding: const EdgeInsets.all(22),
            child: Row(children: [
              // Avatar with gold ring
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kGoldLight, width: 2),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: Text(
                    _initials(user?.companyName),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kGoldLight),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.companyName ?? 'Rooster Trader',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(user?.role.label ?? '—',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB4C6F4),
                                fontWeight: FontWeight.w600)),
                      ])),
            ]),
          ),

          // ── Company code card ─────────────────────────────────────────
          if (user?.companyCode != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child:
                  const Icon(Icons.qr_code_rounded, color: kNavy, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Company Code',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: kTextHint,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                          Text(user!.companyCode!,
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: kNavy,
                                  letterSpacing: 3)),
                        ])),
                const Text('Share with agents',
                    style: TextStyle(fontSize: 10, color: kTextHint)),
              ]),
            ),

          // ── OPERATIONS section ─────────────────────────────────────────
          _sectionLabel('ACCOUNT'),
          _menuCard(context, [
            _item(context, Icons.storefront_outlined, 'Profile', R.traderProfile),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('PREFERENCES'),
          _menuCard(context, const [_AutoApproveQuickEntryTile()]),

          const SizedBox(height: 12),
          _sectionLabel('OPERATIONS'),
          _menuCard(context, [
            _item(context, Icons.analytics_outlined, 'Analytics', R.analytics),
            _item(context, Icons.summarize_outlined, 'Reports & Analytics',
                R.reportsHub),
            _item(context, Icons.shopping_cart_outlined, 'Purchase Management',
                R.purchase),
            _item(context, Icons.receipt_long_outlined, 'Daily Report',
                R.dailyReport),
            _item(context, Icons.calendar_month_outlined,
                'Daily Stock Snapshots', R.dailyStock),
            _item(context, Icons.account_balance_outlined,
                'Cash Reconciliation', R.cashRecon),
            _item(context, Icons.lock_clock_outlined, 'Day Closure',
                R.dayClosure),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('CATALOGUE'),
          _menuCard(context, [
            _item(context, Icons.store_outlined, 'Retailers', R.retailers),
            _item(context, Icons.delivery_dining_outlined, 'Delivery Agents',
                R.agents),
            // Plug & Play — only shown when the trader's Supervisor
            // module is enabled (super admin toggle). Hidden entirely
            // when off, matching "Trader cannot create Supervisor
            // accounts" / "menus/screens are hidden".
            if (user?.supervisorModuleEnabled == true)
              _item(context, Icons.payments_outlined, 'Supervisors',
                  R.supervisorList),
            _item(context, Icons.map_outlined, 'Delivery Areas',
                R.areaManagement),
            _item(context, Icons.manage_accounts_outlined, 'User Management',
                R.userMgmt),
            _item(context, Icons.local_offer_outlined, 'Pricing', R.pricingHub),
            _item(context, Icons.history_outlined, 'Rate History', R.zoneRateHistory),
            _item(context, Icons.receipt_long_outlined, 'Expense Rules',
                R.expenseRules),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('INVENTORY'),
          _menuCard(context, [
            _item(context, Icons.inventory_outlined, 'Stock', R.stock),
            _item(context, Icons.inventory_2_outlined, 'Crates', R.crates),
            _item(context, Icons.assignment_return_outlined, 'Returns',
                R.returns),
          ]),

          const SizedBox(height: 12),
          _sectionLabel('REPORTS'),
          _menuCard(context, [
            _item(context, Icons.receipt_long_outlined, 'Invoices', R.invoices),
            _item(context, Icons.account_balance_wallet_outlined, 'Ledger',
                R.ledger),
            _item(context, Icons.schedule_outlined, 'Shifts', R.shifts),
            _item(context, Icons.warning_amber_outlined, 'Alerts', R.alerts),
          ]),

          const SizedBox(height: 24),

          // ── Sign out ──────────────────────────────────────────────────
          InkWell(
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'Sign Out', message: 'Sign out of Rooster Trader?');
              if (ok && context.mounted) {
                ref.read(appUserProvider.notifier).signOut();
              }
            },
            borderRadius: BorderRadius.circular(kRadiusCard),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kError.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: kError, size: 20),
                  SizedBox(width: 10),
                  Text('Sign Out',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kError)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Center(
            child: Text('Rooster Trader PTOS v2.0',
                style: TextStyle(fontSize: 11, color: kTextHint)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label,
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: kTextHint,
            letterSpacing: 0.8)),
  );

  Widget _menuCard(BuildContext context, List<Widget> items) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight),
      boxShadow: kCardShadow,
    ),
    child: Column(children: items),
  );

  Widget _item(BuildContext ctx, IconData icon, String label, String route) {
    const isLast = false; // divider handled by container
    return InkWell(
      onTap: () => ctx.go(route),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(kRadiusInner),
            ),
            child: Icon(icon, size: 18, color: kNavy),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kTextMain))),
          const Icon(Icons.chevron_right_rounded, size: 18, color: kTextHint),
        ]),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => ResponsiveLayout(
    mobile: (_) => _buildScaffold(context, ref),
    desktop: (_) => _buildScaffold(context, ref),
  );
}

// Settings → Preferences → Auto-approve Quick Entry
// (traders.auto_approve_quick_entry). On: Quick Entries the trader saves are
// approved straight away. Off: they wait in Approvals. Agent entries always
// wait for approval either way.
class _AutoApproveQuickEntryTile extends ConsumerStatefulWidget {
  const _AutoApproveQuickEntryTile();

  @override
  ConsumerState<_AutoApproveQuickEntryTile> createState() =>
      _AutoApproveQuickEntryTileState();
}

class _AutoApproveQuickEntryTileState
    extends ConsumerState<_AutoApproveQuickEntryTile> {
  final _c = Supabase.instance.client;
  bool? _on; // null while loading
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final t = await _c.from('traders')
          .select('auto_approve_quick_entry').eq('id', tid).maybeSingle();
      if (mounted) {
        setState(() => _on = (t?['auto_approve_quick_entry'] as bool?) ?? false);
      }
    } catch (_) {
      if (mounted) setState(() => _on = false);
    }
  }

  Future<void> _set(bool v) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final before = _on;
    setState(() { _on = v; _saving = true; });
    try {
      await _c.from('traders')
          .update({'auto_approve_quick_entry': v}).eq('id', tid);
      if (mounted) {
        showSuccess(context,
            v ? 'Quick Entries will be approved straight away'
              : 'Quick Entries will wait in Approvals');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _on = before);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: kNavy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(kRadiusInner),
        ),
        child: const Icon(Icons.verified_outlined, size: 18, color: kNavy),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Auto-approve Quick Entry',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: kTextMain)),
          SizedBox(height: 2),
          Text('Quick Entries you save are approved and invoiced at once. '
              'Agent entries still wait for your approval.',
              style: TextStyle(fontSize: 11, color: kTextHint)),
        ]),
      ),
      const SizedBox(width: 8),
      if (_on == null || _saving)
        const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
      else
        Switch(value: _on!, onChanged: _set),
    ]),
  );
}