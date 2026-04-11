import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class SuperDashboardScreen extends ConsumerStatefulWidget {
  const SuperDashboardScreen({super.key});
  @override ConsumerState<SuperDashboardScreen> createState() => _S();
}

class _S extends ConsumerState<SuperDashboardScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _stats;
  List<Map<String,dynamic>> _traders = [];
  List<Map<String,dynamic>> _alerts  = [];
  bool _loading = true, _scanning = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r0 = await _c.rpc('sa_get_platform_stats');
      final r1 = await _c.rpc('sa_get_all_traders');
      final r2 = await _c.from('platform_alerts')
            .select('id,trader_id,alert_type,severity,title,message,created_at,traders(company_name)')
            .eq('is_resolved', false)
            .order('created_at', ascending: false)
            .limit(30);
      if (!mounted) return;
      setState(() {
        _stats   = r0 as Map<String,dynamic>?;
        _traders = List<Map<String,dynamic>>.from(r1 as List? ?? []);
        _alerts  = List<Map<String,dynamic>>.from(r2 as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _runAlertScan() async {
    if (mounted) setState(() => _scanning = true);
    try {
      await _c.rpc('sa_run_alert_scan');
      if (mounted) showSuccess(context, 'Alert scan complete ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _resolveAlert(String alertId) async {
    await _c.from('platform_alerts')
        .update({'is_resolved': true, 'resolved_at': DateTime.now().toIso8601String()})
        .eq('id', alertId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final critical  = _alerts.where((a) => a['severity'] == 'critical').length;
    final pending   = _traders.where((t) => t['approval_status'] == 'pending').toList();
    final nearLimit = _traders.where((t) =>
        ((t['orders_pct'] as num?) ?? 0) >= 80 ||
        ((t['agents_pct'] as num?) ?? 0) >= 80 ||
        ((t['retailers_pct'] as num?) ?? 0) >= 80).toList();

    return Scaffold(
      backgroundColor: kBgGrey,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.shield_outlined, color: Color(0xFF4ECDC4), size: 20),
          SizedBox(width: 8),
          Text('SaaS Control', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        actions: [
          if (critical > 0) Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.warning_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 3),
              Text('$critical', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
            ])),
          IconButton(
            tooltip: 'Run Alert Scan',
            icon: _scanning
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.radar_outlined),
            onPressed: _scanning ? null : _runAlertScan),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(appUserProvider.notifier).signOut()),
        ]),
      body: _loading ? const LoadingList()
          : RefreshIndicator(onRefresh: _load, child: ListView(
              padding: const EdgeInsets.all(16), children: [

            // Revenue Banner
            if (s != null) _RevenueBanner(stats: s),
            const SizedBox(height: 12),

            // Health grid
            if (s != null) ...[
              const _Label('PLATFORM HEALTH'),
              GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.35,
                children: [
                  _kpi('Active',    '${s['traders_active'] ?? 0}',   Colors.green,  Icons.check_circle_outline),
                  _kpi('Pending',   '${s['traders_pending'] ?? 0}',  Colors.orange, Icons.pending_outlined),
                  _kpi('Suspended', '${s['traders_suspended'] ?? 0}',Colors.red,    Icons.pause_circle_outlined),
                  _kpi('Expiring',  '${s['traders_expiring'] ?? 0}', Colors.amber,  Icons.timer_outlined),
                  _kpi('Expired',   '${s['traders_expired'] ?? 0}',  Colors.red,    Icons.cancel_outlined),
                  _kpi('Inactive',  '${s['traders_inactive'] ?? 0}', Colors.grey,   Icons.bedtime_outlined),
                ]),
              const SizedBox(height: 10),
            ],

            // Quick nav
            Row(children: [
              _navBtn(Icons.business_outlined,       'Traders', Colors.blue,   () => context.go(R.saTraders)),
              const SizedBox(width: 8),
              _navBtn(Icons.egg_alt_outlined,        'Products',Colors.teal,   () => context.go(R.saProducts)),
              const SizedBox(width: 8),
              _navBtn(Icons.card_membership_outlined,'Plans',   Colors.purple, () => context.go(R.saPlans)),
            ]),
            const SizedBox(height: 14),

            // Alerts
            if (_alerts.isNotEmpty) ...[
              Row(children: [
                const Expanded(child: _Label('ACTIVE ALERTS')),
                Text('${_alerts.length} open', style: const TextStyle(fontSize: 11, color: kTextSub)),
              ]),
              ..._alerts.take(5).map((a) => _AlertCard(
                  alert: a, onResolve: () => _resolveAlert(a['id'] as String))),
              const SizedBox(height: 8),
            ],

            // Pending approval
            if (pending.isNotEmpty) ...[
              const _Label('⏳ PENDING APPROVAL'),
              ...pending.map((t) => _TraderRow(
                  trader: t, onTap: () => context.push(R.saTraderDetail(t['id'] as String)))),
              const SizedBox(height: 8),
            ],

            // Near limit
            if (nearLimit.isNotEmpty) ...[
              const _Label('⚠️ NEAR USAGE LIMIT'),
              ...nearLimit.take(4).map((t) => _TraderRow(
                  trader: t, onTap: () => context.push(R.saTraderDetail(t['id'] as String)))),
              const SizedBox(height: 8),
            ],

            // Plan distribution
            if (s?['plan_distribution'] != null) ...[
              const _Label('PLAN DISTRIBUTION'),
              _PlanDistribution(
                  data: List<Map<String,dynamic>>.from(s!['plan_distribution'] as List? ?? [])),
              const SizedBox(height: 8),
            ],

            // All traders
            Row(children: [
              const Expanded(child: _Label('ALL TRADERS')),
              TextButton(onPressed: () => context.go(R.saTraders), child: const Text('View all →')),
            ]),
            ..._traders.take(6).map((t) => _TraderRow(
                trader: t, onTap: () => context.push(R.saTraderDetail(t['id'] as String)))),
            const SizedBox(height: 20),
          ])));
  }

  Widget _kpi(String label, String value, Color color, IconData icon) =>
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: kTextSub)),
      ]));

  Widget _navBtn(IconData ic, String l, Color c, VoidCallback onTap) =>
    Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.2))),
        child: Column(children: [
          Icon(ic, color: c, size: 22),
          const SizedBox(height: 4),
          Text(l, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ]))));
}

// ── Revenue Banner ──────────────────────────────────────────────────────────
class _RevenueBanner extends StatelessWidget {
  const _RevenueBanner({required this.stats});
  final Map<String,dynamic> stats;
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]),
        borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('MRR', style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1)),
          Text(Fmt.amount((stats['mrr'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          Text('ARR: ${Fmt.amount((stats['arr'] as num?)?.toDouble() ?? 0)}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${stats['traders_total'] ?? 0}',
              style: const TextStyle(color: Color(0xFF4ECDC4), fontSize: 26, fontWeight: FontWeight.w900)),
          const Text('Traders', style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 6),
          Text('${stats['orders_30d'] ?? 0} orders/30d',
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _s('Revenue', Fmt.amount((stats['total_revenue'] as num?)?.toDouble() ?? 0), Colors.greenAccent),
        _s('Today', '${stats['orders_today'] ?? 0} orders', Colors.yellowAccent),
        _s('Alerts', '${stats['active_alerts'] ?? 0}', Colors.redAccent),
        _s('Critical', '${stats['critical_alerts'] ?? 0}', Colors.orangeAccent),
      ]),
    ]));
  Widget _s(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
    Text(l, style: const TextStyle(color: Colors.white54, fontSize: 9)),
  ]));
}

// ── Plan Distribution ───────────────────────────────────────────────────────
class _PlanDistribution extends StatelessWidget {
  const _PlanDistribution({required this.data});
  final List<Map<String,dynamic>> data;
  @override Widget build(BuildContext context) {
    final total = data.fold(0, (s, d) => s + ((d['count'] as num?)?.toInt() ?? 0));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
      child: Column(children: data.map((d) {
        final count = (d['count'] as num?)?.toInt() ?? 0;
        final pct = total > 0 ? count / total : 0.0;
        return Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d['plan'] as String? ?? '—',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              Text('$count', style: const TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(width: 12),
              Text(Fmt.amount((d['revenue'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct, minHeight: 5,
                  backgroundColor: kBorder, valueColor: const AlwaysStoppedAnimation(kPrimary))),
          ]));
      }).toList()));
  }
}

// ── Alert Card ───────────────────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onResolve});
  final Map<String,dynamic> alert;
  final VoidCallback onResolve;
  @override Widget build(BuildContext context) {
    final sev = alert['severity'] as String? ?? 'info';
    final c = sev == 'critical' ? Colors.red : sev == 'warning' ? Colors.orange : Colors.blue;
    final trader = (alert['traders'] as Map?)?.cast<String,dynamic>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(sev == 'critical' ? Icons.error_outline : Icons.warning_amber_rounded, color: c, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alert['title'] as String? ?? '—',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: c)),
          Text('${trader?['company_name'] ?? ''} · ${alert['message'] ?? ''}',
              style: const TextStyle(fontSize: 10, color: kTextSub), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        TextButton(
          onPressed: onResolve,
          style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          child: const Text('✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
      ]));
  }
}

// ── Trader Row with usage bars ───────────────────────────────────────────────
class _TraderRow extends StatelessWidget {
  const _TraderRow({required this.trader, required this.onTap});
  final Map<String,dynamic> trader;
  final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final approval = trader['approval_status'] as String? ?? 'approved';
    final status   = trader['status'] as String? ?? 'active';
    final daysLeft = (trader['days_left'] as num?)?.toInt();
    final alerts   = (trader['alert_count'] as num?)?.toInt() ?? 0;
    final inactive = trader['is_inactive'] == true;
    final hasLimits = trader['max_orders'] != null || trader['max_agents'] != null;

    Color c = switch(approval == 'pending' ? 'pending' : status) {
      'active'    => Colors.green,
      'pending'   => Colors.orange,
      'suspended' => Colors.red,
      _           => Colors.grey,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: approval == 'pending' ? Colors.orange.shade300
                     : alerts > 0 ? Colors.red.shade300 : kBorder,
                width: (approval == 'pending' || alerts > 0) ? 1.5 : 1)),
        child: Column(children: [
          Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(
                  (trader['company_name'] as String? ?? '?')[0].toUpperCase(),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(trader['company_name'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                if (alerts > 0) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                  child: Text('$alerts ⚠', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800))),
              ]),
              Text('${trader['plan_name'] ?? 'No plan'} · ${trader['city'] ?? '—'}',
                  style: const TextStyle(fontSize: 10, color: kTextSub)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(approval == 'pending' ? 'PENDING' : status.toUpperCase(),
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: c))),
              if (daysLeft != null && daysLeft <= 7)
                Text('${daysLeft}d left', style: const TextStyle(fontSize: 9, color: Colors.red)),
              if (inactive && daysLeft == null)
                const Text('inactive', style: TextStyle(fontSize: 9, color: kTextHint)),
              const Icon(Icons.chevron_right, size: 14, color: kTextHint),
            ]),
          ]),
          if (hasLimits) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (trader['max_orders'] != null) Expanded(child: _Bar(
                  l: 'Orders', used: trader['orders_used'], lim: trader['max_orders'])),
              if (trader['max_agents'] != null) ...[const SizedBox(width: 8),
                Expanded(child: _Bar(l: 'Agents', used: trader['agents_used'], lim: trader['max_agents']))],
              if (trader['max_retailers'] != null) ...[const SizedBox(width: 8),
                Expanded(child: _Bar(l: 'Shops', used: trader['retailers_used'], lim: trader['max_retailers']))],
            ]),
          ],
        ])));
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.l, required this.used, required this.lim});
  final String l; final dynamic used, lim;
  @override Widget build(BuildContext context) {
    final u = (used as num?)?.toDouble() ?? 0;
    final m = (lim  as num?)?.toDouble() ?? 1;
    final p = (u / m).clamp(0.0, 1.0);
    final c = p >= 1.0 ? Colors.red : p >= 0.8 ? Colors.orange : kPrimary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(l, style: const TextStyle(fontSize: 8, color: kTextHint)),
        const Spacer(),
        Text('${u.toInt()}/$lim', style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 2),
      ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
          value: p, minHeight: 3, backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation(c))),
    ]);
  }
}

class _Label extends StatelessWidget {
  const _Label(this.t);
  final String t;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
        color: kTextHint, letterSpacing: 0.8)));
}
