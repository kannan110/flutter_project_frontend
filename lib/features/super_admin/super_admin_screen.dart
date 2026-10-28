import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

class SuperAdminScreen extends ConsumerStatefulWidget {
  const SuperAdminScreen({super.key});
  @override ConsumerState<SuperAdminScreen> createState() => _S();
}

class _S extends ConsumerState<SuperAdminScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _traders = [];
  List<Map<String,dynamic>> _plans   = [];
  bool _loading = true;
  int  _tab     = 0; // 0=Pending, 1=All, 2=Plans

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // FIX 1: Call each RPC separately with correct casting.
      // get_all_traders returns jsonb (a JSON array) — cast via List
      final tradersRaw = await _c.rpc('get_all_traders');
      final plansRaw   = await _c.from('subscription_plans')
          .select('id,name,duration_days,base_price,max_orders,max_retailers,max_agents,is_active')
          .order('base_price');

      if (!mounted) return;
      setState(() {
        // FIX 2: jsonb from RPC comes back as List<dynamic> in supabase-flutter
        _traders = List<Map<String,dynamic>>.from(
            (tradersRaw as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)));
        _plans   = List<Map<String,dynamic>>.from(
            (plansRaw   as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString()
            .replaceAll('Exception: ', '')
            .replaceAll('PostgrestException(message: ', '')
            .replaceAll(')', ''));
      }
    }
  }

  Future<void> _action(String traderId, String action,
      {String? planId, String? reason}) async {
    try {
      await _c.rpc('approve_trader', params: {
        'p_trader_id': traderId,
        'p_action':    action,
        'p_plan_id':   planId,
        'p_reason':    reason,
      });
      if (mounted) showSuccess(context, '${_actionLabel(action)} ✓');
      _load();
    } catch (e) {
      if (mounted) {
        showError(context, e.toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', ''));
      }
    }
  }

  String _actionLabel(String a) => switch (a) {
    'approve'  => 'Approved',
    'reject'   => 'Rejected',
    'suspend'  => 'Suspended',
    'activate' => 'Activated',
    _          => a,
  };

  void _approveDialog(Map<String,dynamic> t) {
    Map<String,dynamic>? selPlan;
    final activePlans = _plans.where((p) => p['is_active'] == true).toList();
    showDialog(
        context: context, useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.verified_outlined, color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('Approve: ${t['company_name']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            content: SizedBox(width: 340, child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoChip(Icons.email_outlined,        t['owner_email']   ?? '—'),
                  _infoChip(Icons.phone_outlined,         t['phone']         ?? '—'),
                  _infoChip(Icons.location_city_outlined, '${t['city'] ?? '—'} · ${t['company_code'] ?? '—'}'),
                  const SizedBox(height: 16),
                  const Text('Select Subscription Plan *',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Map<String,dynamic>>(
                      initialValue: selPlan, isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Choose plan'),
                      items: activePlans.map((p) {
                        final price = (p['base_price'] as num?) ?? 0;
                        final days  = (p['duration_days'] as num?) ?? 0;
                        return DropdownMenuItem(
                            value: p,
                            child: Text(
                                '${p['name']} — ${price > 0 ? '₹$price' : 'Free'} · $days days',
                                style: const TextStyle(fontSize: 13)));
                      }).toList(),
                      onChanged: (v) => ss(() => selPlan = v)),
                  if (selPlan != null) Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Max orders:   ${selPlan!['max_orders']   ?? 'Unlimited'}',
                                style: const TextStyle(fontSize: 11, color: kTextSub)),
                            Text('Max agents:   ${selPlan!['max_agents']   ?? 'Unlimited'}',
                                style: const TextStyle(fontSize: 11, color: kTextSub)),
                            Text('Max retailers: ${selPlan!['max_retailers'] ?? 'Unlimited'}',
                                style: const TextStyle(fontSize: 11, color: kTextSub)),
                          ]))),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                  child: const Text('Cancel')),
              ElevatedButton.icon(
                  onPressed: selPlan == null ? null : () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    _action(t['id'] as String, 'approve', planId: selPlan!['id'] as String);
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve')),
            ])));
  }

  void _rejectDialog(Map<String,dynamic> t) {
    final ctrl = TextEditingController();
    showDialog(
        context: context, useRootNavigator: true,
        builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.cancel_outlined, color: kError, size: 22),
              SizedBox(width: 8),
              Text('Reject Registration',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
            content: SizedBox(width: 340, child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              Text('${t['company_name']}  ·  ${t['owner_email'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 14),
              TextField(controller: ctrl, maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                      alignLabelWithHint: true)),
            ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kError),
                  onPressed: () {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    _action(t['id'] as String, 'reject',
                        reason: ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
                  },
                  child: const Text('Reject')),
            ]));
  }

  Future<void> _suspendActivate(Map<String,dynamic> t) async {
    final isSuspended = t['status'] == 'suspended';
    final action = isSuspended ? 'activate' : 'suspend';
    final ok = await confirmDialog(context,
        title: isSuspended ? 'Activate Trader' : 'Suspend Trader',
        message: '${isSuspended ? 'Reactivate' : 'Suspend'} ${t['company_name']}?\n\n'
            '${isSuspended
            ? 'They will regain full access.'
            : 'All logins will be blocked.'}',
        confirmText: isSuspended ? 'Activate' : 'Suspend',
        confirmColor: isSuspended ? Colors.green : Colors.orange);
    if (ok && mounted) _action(t['id'] as String, action);
  }

  @override
  Widget build(BuildContext context) {
    final pending   = _traders.where((t) => t['approval_status'] == 'pending').toList();
    final approved  = _traders.where((t) => t['approval_status'] == 'approved').toList();
    final rejected  = _traders.where((t) => t['approval_status'] == 'rejected').toList();
    final suspended = _traders.where((t) => t['status'] == 'suspended').toList();
    final display   = switch (_tab) {
      0 => pending,
      1 => _traders,
      _ => <Map<String,dynamic>>[],
    };

    return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            title: const Row(children: [
              Text('🛡️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Super Admin', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            actions: [
              IconButton(
                  icon: const Icon(Icons.refresh_outlined),
                  onPressed: _load, tooltip: 'Refresh'),
              IconButton(
                  icon: const Icon(Icons.logout_outlined),
                  tooltip: 'Sign out',
                  onPressed: () => ref.read(appUserProvider.notifier).signOut()),
            ]),
        body: Column(children: [

          // ── Stats bar ──────────────────────────────────────────────────────
          Container(
              color: kNavy,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                _stat('Total',     '${_traders.length}',  Colors.white),
                _statDivider(),
                _stat('Pending',   '${pending.length}',   Colors.yellowAccent),
                _statDivider(),
                _stat('Active',    '${approved.length}',  Colors.greenAccent),
                _statDivider(),
                _stat('Rejected',  '${rejected.length}',  Colors.orangeAccent),
                _statDivider(),
                _stat('Suspended', '${suspended.length}', Colors.redAccent),
              ])),

          // ── Tabs ───────────────────────────────────────────────────────────
          Container(
              color: Colors.white,
              child: Row(children: [
                _tabBtn(0, 'Pending',     pending.length),
                _tabBtn(1, 'All Traders', _traders.length),
                _tabBtn(2, 'Plans',       _plans.length),
              ])),
          const Divider(height: 1),

          // ── Body ───────────────────────────────────────────────────────────
          Expanded(child: _loading
              ? const LoadingList()
              : _tab == 2
              ? _buildPlans()
              : display.isEmpty
              ? EmptyState(
              icon: _tab == 0
                  ? Icons.inbox_outlined
                  : Icons.business_outlined,
              message: _tab == 0
                  ? 'No pending registrations ✓'
                  : 'No traders yet')
              : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: display.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _traderCard(display[i])))),
        ]));
  }

  // ── Trader card ────────────────────────────────────────────────────────────
  Widget _traderCard(Map<String,dynamic> t) {
    final status     = t['status']          as String? ?? '';
    final approval   = t['approval_status'] as String? ?? '';
    final isPending   = approval == 'pending';
    final isApproved  = approval == 'approved' && status == 'active';
    final isSuspended = status == 'suspended';
    final isRejected  = approval == 'rejected';

    final borderColor = switch (approval) {
      'pending'  => Colors.orange.shade300,
      'rejected' => Colors.red.shade200,
      _          => isSuspended ? Colors.orange.shade200 : kBorder,
    };
    final statusColor = switch (status) {
      'active'    => Colors.green,
      'suspended' => Colors.orange,
      'blocked'   => Colors.red,
      _           => kTextSub,
    };

    final userCount  = (t['user_count']  as num?)?.toInt() ?? 0;
    final agentCount = (t['agent_count'] as num?)?.toInt() ?? 0;

    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isPending ? 1.5 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(
                    (t['company_name'] as String? ?? 'T')[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: kNavy)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['company_name'] as String? ?? '—',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('${t['company_code'] ?? '—'}  ·  ${t['city'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
              if (t['plan_name'] != null)
                Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(t['plan_name'] as String,
                        style: const TextStyle(fontSize: 9, color: kNavy,
                            fontWeight: FontWeight.w700))),
            ])),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(
                    isPending   ? '⏳ PENDING' :
                    isSuspended ? '⚠ SUSPENDED' :
                    isRejected  ? '✗ REJECTED' :
                    '✓ ACTIVE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                        color: statusColor))),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Details
          Wrap(runSpacing: 4, spacing: 16, children: [
            _detailItem(Icons.email_outlined,
                t['owner_email'] ?? '—'),
            _detailItem(Icons.phone_outlined,
                t['phone'] ?? '—'),
            _detailItem(Icons.calendar_today_outlined,
                'Joined ${_fmt(t['created_at'])}'),
            _detailItem(Icons.group_outlined,
                '$userCount users · $agentCount agents'),
            if (t['trial_ends_at'] != null)
              _detailItem(Icons.hourglass_bottom_outlined,
                  'Trial ends ${_fmt(t['trial_ends_at'])}'),
            if (t['subscription_end_date'] != null)
              _detailItem(Icons.verified_outlined,
                  'Sub ends ${_fmt(t['subscription_end_date'])}'),
            if (t['rejection_reason'] != null)
              _detailItem(Icons.info_outline,
                  'Reason: ${t['rejection_reason']}', Colors.red),
            if (t['enterprise_note'] != null)
              _detailItem(Icons.sticky_note_2_outlined,
                  t['enterprise_note'] as String, Colors.purple),
          ]),

          // Action buttons
          if (isPending) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                  onPressed: () => _rejectDialog(t),
                  icon: const Icon(Icons.cancel_outlined, size: 14),
                  label: const Text('Reject',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kError,
                      side: const BorderSide(color: kError)))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: ElevatedButton.icon(
                  onPressed: () => _approveDialog(t),
                  icon: const Icon(Icons.verified_outlined, size: 14),
                  label: const Text('Approve & Assign Plan',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
            ]),
          ] else if (isApproved || isSuspended) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
                onPressed: () => _suspendActivate(t),
                icon: Icon(
                    isSuspended
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                    size: 14,
                    color: isSuspended ? Colors.green : Colors.orange),
                label: Text(
                    isSuspended ? 'Activate' : 'Suspend',
                    style: TextStyle(fontSize: 12,
                        color: isSuspended ? Colors.green : Colors.orange)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: isSuspended ? Colors.green : Colors.orange)))),
          ],
        ]));
  }

  // ── Plans tab ──────────────────────────────────────────────────────────────
  Widget _buildPlans() {
    if (_plans.isEmpty) {
      return const EmptyState(icon: Icons.workspace_premium_outlined,
          message: 'No subscription plans found');
    }
    return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p     = _plans[i];
          final price = (p['base_price'] as num?) ?? 0;
          final days  = (p['duration_days'] as num?) ?? 0;
          final Color c = switch (p['name'] as String? ?? '') {
            'Free Trial' || 'Free'  => Colors.teal,
            'Basic'      || 'Starter' => Colors.blue,
            'Standard'              => Colors.indigo,
            'Premium'    || 'Pro'   => Colors.purple,
            'Enterprise'            => Colors.deepPurple,
            _                       => kPrimary,
          };
          return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Center(child: Icon(Icons.workspace_premium_outlined,
                        color: c, size: 22))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(p['name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(price > 0 ? '₹$price' : 'Free',
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w900, color: c)),
                  ]),
                  Text(
                      '$days days'
                          '${p['max_orders']   != null ? ' · ${p['max_orders']} orders'   : ' · Unlimited orders'}'
                          '${p['max_agents']   != null ? ' · ${p['max_agents']} agents'   : ' · Unlimited agents'}'
                          '${p['max_retailers'] != null ? ' · ${p['max_retailers']} shops' : ''}',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                  const SizedBox(height: 6),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: p['is_active'] == true
                              ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(p['is_active'] == true ? 'Active' : 'Inactive',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: p['is_active'] == true
                                  ? Colors.green : Colors.red))),
                ])),
              ]));
        });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _stat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: Colors.white60,
        letterSpacing: 0.3)),
  ]));

  Widget _statDivider() => Container(
      width: 1, height: 28, color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _tabBtn(int idx, String label, int count) => Expanded(child: InkWell(
      onTap: () => setState(() => _tab = idx),
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: _tab == idx ? kPrimary : Colors.transparent, width: 2))),
          child: Text('$label${count > 0 ? ' ($count)' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: _tab == idx ? kPrimary : kTextHint)))));

  Widget _infoChip(IconData ic, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 13, color: kPrimary), const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]);

  Widget _detailItem(IconData ic, String v, [Color? c]) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 12, color: c ?? kTextHint), const SizedBox(width: 4),
        Text(v, style: TextStyle(fontSize: 11, color: c ?? kTextSub)),
      ]);

  String _fmt(dynamic s) {
    if (s == null) return '—';
    try { return DateFormat('d MMM y').format(DateTime.parse(s.toString())); }
    catch (_) { return s.toString(); }
  }
}