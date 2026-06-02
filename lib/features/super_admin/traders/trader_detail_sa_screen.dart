import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class TraderDetailSaScreen extends StatefulWidget {
  const TraderDetailSaScreen({super.key, required this.traderId});
  final String traderId;
  @override State<TraderDetailSaScreen> createState() => _S();
}

class _S extends State<TraderDetailSaScreen> with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _data;
  List<Map<String,dynamic>> _plans = [];
  bool _loading = true, _saving = false;
  late TabController _tabs;

  @override void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final r0 = await _c.rpc('sa_get_trader_detail', params: {'p_trader_id': widget.traderId});
      final r1 = await _c.from('subscription_plans').select('id,name,base_price,duration_days,max_orders,max_retailers,max_agents,features').eq('is_active', true).order('base_price');
      if (!mounted) return;
      setState(() {
        _data  = r0 as Map<String,dynamic>?;
        _plans = List<Map<String,dynamic>>.from(r1 as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  Future<void> _action(String action, {Map<String,dynamic>? extra}) async {
    if (mounted) setState(() => _saving = true);
    try {
      await _c.rpc('sa_control_trader', params: {
        'p_trader_id': widget.traderId,
        'p_action': action,
        ...?extra,
      });
      showSuccess(context, 'Action "$action" applied ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String,dynamic>? get _trader   => (_data?['trader']   as Map?)?.cast<String,dynamic>();
  Map<String,dynamic>? get _usage    => (_data?['usage']    as Map?)?.cast<String,dynamic>();
  Map<String,dynamic>? get _features => (_data?['features'] as Map?)?.cast<String,dynamic>();
  Map<String,dynamic>? get _plan     => (_data?['plan']     as Map?)?.cast<String,dynamic>();
  Map<String,dynamic>? get _stats    => (_data?['stats']    as Map?)?.cast<String,dynamic>();
  List get _payments => (_data?['payments'] as List? ?? []);
  List get _alerts   => (_data?['alerts']   as List? ?? []);
  List get _users    => (_data?['users']    as List? ?? []);

  @override
  Widget build(BuildContext context) {
    final t      = _trader;
    final status  = t?['status'] as String? ?? 'active';
    final approval = t?['approval_status'] as String? ?? 'approved';

    return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A2E),
            foregroundColor: Colors.white,
            leading: IconButton(icon: const Icon(Icons.arrow_back),
                onPressed: () { if (context.canPop()) context.pop(); else context.go(R.saTraders); }),
            title: Text(t?['company_name'] as String? ?? 'Trader',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            actions: [
              if (!_loading && !_saving)
                PopupMenuButton<String>(
                    color: Colors.white,
                    onSelected: (v) async {
                      switch (v) {
                        case 'approve':
                          final planId = await _pickPlan();
                          if (planId != null) _action('upgrade_plan', extra: {'p_plan_id': planId});
                        case 'suspend':
                          final r = await _promptText('Reason for suspension');
                          _action('suspend', extra: {'p_notes': r});
                        case 'activate': _action('activate');
                        case 'reset':   _action('reset_usage');
                        case 'extend':
                          final days = await _promptDays();
                          if (days != null) _action('extend_sub', extra: {'p_extend_days': days});
                        case 'payment': _showPaymentForm();
                      }
                    },
                    itemBuilder: (_) => [
                      if (approval == 'pending')
                        const PopupMenuItem(value: 'approve', child: Text('✅ Approve & Assign Plan')),
                      if (status == 'active')
                        const PopupMenuItem(value: 'suspend', child: Text('⏸️ Suspend')),
                      if (status == 'suspended')
                        const PopupMenuItem(value: 'activate', child: Text('▶️ Activate')),
                      const PopupMenuItem(value: 'reset',   child: Text('🔄 Reset Usage')),
                      const PopupMenuItem(value: 'extend',  child: Text('📅 Extend Subscription')),
                      const PopupMenuItem(value: 'payment', child: Text('💰 Record Payment')),
                    ]),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
            bottom: TabBar(
                controller: _tabs,
                indicatorColor: const Color(0xFF4ECDC4),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Usage'),
                  Tab(text: 'Features'),
                  Tab(text: 'Billing'),
                ])),
        body: _loading ? const LoadingList()
            : TabBarView(controller: _tabs, children: [
          _buildOverview(),
          _buildUsage(),
          _buildFeatures(),
          _buildBilling(),
        ]));
  }

  // ── Overview Tab ─────────────────────────────────────────────────────────
  Widget _buildOverview() {
    final t = _trader;
    final stats = _stats;
    final status  = t?['status'] as String? ?? 'active';
    final approval = t?['approval_status'] as String? ?? 'approved';

    Color statusColor = switch(approval == 'pending' ? 'pending' : status) {
      'pending'   => Colors.orange,
      'active'    => Colors.green,
      'suspended' => Colors.red,
      _           => Colors.grey,
    };

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Status
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: statusColor.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(status == 'active' ? Icons.check_circle_outline : Icons.warning_outlined,
                color: statusColor, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(approval == 'pending' ? 'Pending Approval'
                  : '${status[0].toUpperCase()}${status.substring(1)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: statusColor)),
              Text('Plan: ${_plan?['name'] ?? 'None'} · Code: ${t?['company_code'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: kTextSub)),
            ])),
            if (approval == 'pending') ...[
              TextButton(
                  onPressed: () async {
                    final planId = await _pickPlan();
                    if (planId != null && mounted) _action('upgrade_plan', extra: {'p_plan_id': planId});
                  },
                  child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green))),
            ],
          ])),
      const SizedBox(height: 12),

      // Stats
      if (stats != null) ...[
        Row(children: [
          _statBox('Orders', '${stats['orders_total'] ?? 0}', Colors.blue),
          const SizedBox(width: 8),
          _statBox('30d Orders', '${stats['orders_30d'] ?? 0}', kPrimary),
          const SizedBox(width: 8),
          _statBox('Delivered', '${stats['deliveries'] ?? 0}', Colors.green),
          const SizedBox(width: 8),
          _statBox('Revenue 30d', Fmt.amount((stats['revenue_30d'] as num?)?.toDouble() ?? 0), Colors.purple),
        ]),
        const SizedBox(height: 12),
      ],

      // Company details
      const SectionHeader('COMPANY'),
      WhiteCard(child: Column(children: [
        _row('Company',   t?['company_name']),
        _row('Code',      t?['company_code']),
        _row('Owner',     t?['owner_email'] ?? t?['contact_person']),
        _row('Phone',     t?['phone']),
        _row('City',      '${t?['city'] ?? '—'}, ${t?['state'] ?? '—'}'),
        _row('GST',       t?['gst_number']),
        _row('Email',     t?['email']),
        _row('Joined',    t?['created_at'] != null
            ? DateFormat('d MMM y').format(DateTime.parse(t!['created_at'] as String)) : null),
      ])),
      const SizedBox(height: 10),

      // Subscription
      const SectionHeader('SUBSCRIPTION'),
      WhiteCard(child: Column(children: [
        _row('Plan',   _plan?['name'] ?? 'None'),
        _row('Start',  t?['subscription_start']),
        _row('End',    t?['subscription_end_date']),
        _row('Grace',  t?['grace_until']),
        _row('Trial',  t?['trial_ends_at'] != null
            ? DateFormat('d MMM y').format(DateTime.parse(t!['trial_ends_at'] as String)) : null),
        if (t?['notes'] != null) _row('Notes', t?['notes']),
        if (t?['rejection_reason'] != null) _row('Rejection', t?['rejection_reason'], Colors.red),
      ])),
      const SizedBox(height: 10),

      // Users
      if (_users.isNotEmpty) ...[
        const SectionHeader('USERS & ROLES'),
        ..._users.map((u) {
          final um = (u as Map).cast<String,dynamic>();
          return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
              child: Row(children: [
                const Icon(Icons.person_outline, size: 16, color: kNavy),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(um['email'] as String? ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Text(um['role'] as String? ?? '—', style: const TextStyle(fontSize: 10, color: kTextSub)),
                ])),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: um['is_active'] == true ? Colors.green.shade100 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: Text(um['is_active'] == true ? 'Active' : 'Inactive',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                            color: um['is_active'] == true ? Colors.green : Colors.grey))),
              ]));
        }),
      ],

      // Alerts
      if (_alerts.isNotEmpty) ...[
        const SectionHeader('ACTIVE ALERTS'),
        ..._alerts.map((a) {
          final am = (a as Map).cast<String,dynamic>();
          final sev = am['severity'] as String? ?? 'info';
          final c = sev == 'critical' ? Colors.red : Colors.orange;
          return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(kRadiusChip), border: Border.all(color: c.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: c, size: 16), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(am['title'] as String? ?? '—', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
                  Text(am['message'] as String? ?? '—', style: const TextStyle(fontSize: 11, color: kTextSub)),
                ])),
              ]));
        }),
      ],
      const SizedBox(height: 20),
    ]);
  }

  // ── Usage Tab ─────────────────────────────────────────────────────────────
  Widget _buildUsage() {
    final u = _usage;
    final p = _plan;
    if (u == null) return const EmptyState(icon: Icons.analytics_outlined, message: 'No usage data');

    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionHeader('USAGE vs LIMITS'),
      _usageCard('Orders',    u['orders_used'],    p?['max_orders'],    Colors.blue),
      _usageCard('Agents',    u['agents_used'],    p?['max_agents'],    Colors.teal),
      _usageCard('Retailers', u['retailers_used'], p?['max_retailers'], Colors.purple),
      const SizedBox(height: 16),
      const SectionHeader('ACTIVITY'),
      WhiteCard(child: Column(children: [
        _row('Last Order', u['last_order_at'] != null
            ? DateFormat('d MMM y HH:mm').format(DateTime.parse(u['last_order_at'] as String)) : 'Never'),
        _row('Last Reset', u['last_reset_at'] != null
            ? DateFormat('d MMM y').format(DateTime.parse(u['last_reset_at'] as String)) : '—'),
        _row('Updated', u['updated_at'] != null
            ? DateFormat('d MMM y HH:mm').format(DateTime.parse(u['updated_at'] as String)) : '—'),
      ])),
      const SizedBox(height: 16),
      ElevatedButton.icon(
          onPressed: _saving ? null : () async {
            final ok = await confirmDialog(context,
                title: 'Reset Usage',
                message: 'This will reset orders, agents, and retailers counters to 0.',
                confirmText: 'Reset', confirmColor: Colors.orange);
            if (ok) _action('reset_usage');
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Reset Usage Counters'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange)),
      const SizedBox(height: 20),
    ]);
  }

  Widget _usageCard(String label, dynamic used, dynamic limit, Color color) {
    final u = (used as num?)?.toDouble() ?? 0;
    final l = (limit as num?)?.toDouble();
    final pct = l != null && l > 0 ? (u / l).clamp(0.0, 1.0) : null;
    final c = pct == null ? color : pct >= 1.0 ? Colors.red : pct >= 0.8 ? Colors.orange : color;

    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: pct != null && pct >= 0.8 ? c.withValues(alpha: 0.4) : kBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const Spacer(),
            Text(
                l != null ? '${u.toInt()} / ${l.toInt()}' : '${u.toInt()} / ∞',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c)),
          ]),
          if (pct != null) ...[
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(kRadiusChip),
                child: LinearProgressIndicator(value: pct, minHeight: 10,
                    backgroundColor: kBorder, valueColor: AlwaysStoppedAnimation(c))),
            const SizedBox(height: 4),
            Text('${(pct * 100).toStringAsFixed(1)}% used',
                style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
          ],
        ]));
  }

  // ── Features Tab ──────────────────────────────────────────────────────────
  Widget _buildFeatures() {
    final f = _features;
    final overrides = (_trader?['feature_overrides'] as Map?)?.cast<String,dynamic>() ?? {};

    final flags = [
      ('dc_upload',        'DC Upload',         f?['dc_upload']),
      ('dc_pdf',           'DC PDF',             f?['dc_pdf']),
      ('invoice_pdf',      'Invoice PDF',        f?['invoice_pdf']),
      ('whatsapp',         'WhatsApp Sharing',   f?['whatsapp']),
      ('loss_tracking',    'Loss Tracking',      f?['loss_tracking']),
      ('instant_orders',   'Instant Orders',     f?['instant_orders']),
      ('analytics',        'Analytics',          f?['analytics']),
      ('route_planning',   'Route Planning',     f?['route_planning']),
      ('money_collection', 'Money Collection',   f?['money_collection']),
      ('partial_delivery', 'Partial Delivery',   f?['partial_delivery']),
      ('crate_tracking',   'Crate Tracking',     f?['crate_tracking']),
    ];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
          padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(kRadiusCard)),
          child: const Text(
              '💡 Toggles here override the plan defaults. Overridden features are shown with an ✏️ icon.',
              style: TextStyle(fontSize: 12, color: Colors.blue))),
      const SectionHeader('FEATURE FLAGS'),
      ...flags.map((entry) {
        final key = entry.$1; final label = entry.$2;
        final planVal = entry.$3 as bool? ?? false;
        final isOverridden = overrides.containsKey(key);
        final currentVal = isOverridden ? (overrides[key] as bool? ?? planVal) : planVal;

        return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: isOverridden ? Colors.amber.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: isOverridden ? Colors.amber.shade300 : kBorder)),
            child: Row(children: [
              Icon(currentVal ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 18,
                  color: currentVal ? Colors.green : Colors.grey),
              const SizedBox(width: 10),
              Expanded(child: Row(children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (isOverridden) const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('✏️', style: TextStyle(fontSize: 12))),
                if (!planVal && currentVal) Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(kRadiusChip)),
                    child: const Text('Override ON', style: TextStyle(fontSize: 8, color: Colors.green, fontWeight: FontWeight.w700))),
              ])),
              Switch(
                  value: currentVal,
                  onChanged: _saving ? null : (v) => _action('set_feature',
                      extra: {'p_feature_key': key, 'p_feature_val': v}),
                  activeColor: kPrimary),
            ]));
      }),
      const SizedBox(height: 16),
      const SectionHeader('REPORT & SUPPORT LEVEL'),
      WhiteCard(child: Column(children: [
        _row('Reports Level', f?['reports_level'] ?? 'basic'),
        _row('Support Level', f?['support_level'] ?? 'email'),
      ])),
      const SizedBox(height: 20),
    ]);
  }

  // ── Billing Tab ───────────────────────────────────────────────────────────
  Widget _buildBilling() => ListView(padding: const EdgeInsets.all(16), children: [
    const SectionHeader('BILLING SUMMARY'),
    WhiteCard(child: Column(children: [
      _row('Current Plan', _plan?['name'] ?? 'None'),
      _row('Plan Price', _plan?['base_price'] != null ? '₹${_plan!['base_price']}/period' : '—'),
      _row('Sub Start', _trader?['subscription_start']),
      _row('Sub End', _trader?['subscription_end_date']),
      _row('Grace Until', _trader?['grace_until']),
    ])),
    const SizedBox(height: 14),
    Row(children: [
      Expanded(child: OutlinedButton.icon(
          onPressed: () => _showPaymentForm(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Record Payment'))),
      const SizedBox(width: 10),
      Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final days = await _promptDays();
            if (days != null && mounted) _action('extend_sub', extra: {'p_extend_days': days});
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: const Text('Extend Subscription'))),
    ]),
    const SizedBox(height: 16),

    if (_payments.isNotEmpty) ...[
      const SectionHeader('PAYMENT HISTORY'),
      ..._payments.map((p) {
        final pm = (p as Map).cast<String,dynamic>();
        final amt = (pm['amount'] as num?)?.toDouble() ?? 0;
        final date = pm['created_at'] != null
            ? DateFormat('d MMM y').format(DateTime.parse(pm['created_at'] as String)) : '—';
        return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
            child: Row(children: [
              const Icon(Icons.receipt_outlined, size: 16, color: kNavy),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Fmt.amount(amt),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kNavy)),
                Text('$date · ${pm['payment_mode'] ?? 'manual'}${pm['payment_ref'] != null ? ' · ${pm['payment_ref']}' : ''}',
                    style: const TextStyle(fontSize: 11, color: kTextSub)),
                if (pm['notes'] != null) Text(pm['notes'] as String,
                    style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: pm['status'] == 'completed' ? Colors.green.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(kRadiusChip)),
                  child: Text(pm['status'] as String? ?? 'completed',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: pm['status'] == 'completed' ? Colors.green : Colors.orange))),
            ]));
      }),
    ] else
      const EmptyState(icon: Icons.receipt_long_outlined, message: 'No payment history yet'),
    const SizedBox(height: 20),
  ]);

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<String?> _pickPlan() async {
    String? selected;
    await showModalBottomSheet(context: context, builder: (ctx) =>
        Container(padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Select Plan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ..._plans.map((p) => ListTile(
                  title: Text(p['name'] as String),
                  subtitle: Text('₹${p['base_price']} · ${p['duration_days']}d · '
                      'Orders: ${p['max_orders'] ?? '∞'} · Agents: ${p['max_agents'] ?? '∞'}'),
                  onTap: () { selected = p['id'] as String; Navigator.pop(ctx); },
                  trailing: const Icon(Icons.chevron_right))),
            ])));
    return selected;
  }

  Future<String?> _promptText(String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: Text(hint),
        content: TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ]));
  }

  Future<int?> _promptDays() async {
    final ctrl = TextEditingController(text: '30');
    final res = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Extend by (days)'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Days', suffixText: 'days')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Extend')),
        ]));
    return int.tryParse(res ?? '');
  }

  void _showPaymentForm() {
    final amtCtrl  = TextEditingController();
    final refCtrl  = TextEditingController();
    final noteCtrl = TextEditingController();
    String mode = 'manual';
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20, right: 20, top: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Record Payment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(controller: amtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹) *', prefixText: '₹')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  value: mode,
                  decoration: const InputDecoration(labelText: 'Payment Mode'),
                  items: ['manual','upi','bank','card'].map((m) =>
                      DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => ss(() => mode = v!)),
              const SizedBox(height: 10),
              TextField(controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Transaction Ref (optional)')),
              const SizedBox(height: 10),
              TextField(controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 16),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                  onPressed: () {
                    final amt = double.tryParse(amtCtrl.text);
                    if (amt == null || amt <= 0) return;
                    Navigator.pop(ctx);
                    _action('record_payment', extra: {
                      'p_payment_amount': amt,
                      'p_payment_mode':   mode,
                      'p_payment_ref':    refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                      'p_notes':          noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    });
                  },
                  child: const Text('Record Payment')),
            ]))));
  }

  Widget _statBox(String label, String value, Color color) =>
      Expanded(child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: kTextSub), textAlign: TextAlign.center),
          ])));

  Widget _row(String l, dynamic v, [Color? c]) {
    if (v == null || v.toString().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 90, child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
          Expanded(child: Text(v.toString(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: c ?? kTextMain))),
        ]));
  }
}