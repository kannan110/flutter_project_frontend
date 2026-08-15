import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'assign_retailer_sheet.dart';

/// Profile + Assigned Retailers + one ledger_entries fetch (recorded_by
/// = this supervisor's user_id), grouped three ways client-side:
/// chronological (History), by date (Date-wise Summary), by retailer
/// (Retailer-wise Summary). "Collection History" and "Payment History"
/// from the spec are the same underlying data in this schema (there's no
/// separate attempt/visit log, only recorded payments) — shown once as
/// "History" rather than duplicated under two names.
class SupervisorDetailScreen extends ConsumerStatefulWidget {
  const SupervisorDetailScreen({super.key, required this.supervisorId});
  final String supervisorId;
  @override ConsumerState<SupervisorDetailScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorDetailScreen> with SingleTickerProviderStateMixin {
  final _c = Supabase.instance.client;
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _loading = true;
  Map<String, dynamic>? _supervisor;
  List<Map<String, dynamic>> _assignedRetailers = [];
  List<Map<String, dynamic>> _payments = []; // raw ledger_entries rows, joined shop_name

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final s = await _c.from('supervisor_profiles')
          .select('id,name,mobile,is_active,user_id,trader_id')
          .eq('id', widget.supervisorId).maybeSingle();
      if (s == null) { if (mounted) setState(() => _loading = false); return; }

      final retailers = await _c.from('retailers')
          .select('id,shop_name,phone,outstanding_balance')
          .eq('supervisor_id', widget.supervisorId).eq('is_active', true)
          .order('shop_name');

      List<Map<String, dynamic>> payments = [];
      final uid = s['user_id'] as String?;
      if (uid != null) {
        final p = await _c.from('ledger_entries')
            .select('id,amount,payment_mode,description,entry_date,created_at,retailer_id,retailers(shop_name)')
            .eq('recorded_by', uid).eq('entry_type', 'credit').eq('source_type', 'payment')
            .order('entry_date', ascending: false).order('created_at', ascending: false)
            .limit(500);
        payments = List<Map<String, dynamic>>.from(p as List? ?? []);
      }

      if (mounted) setState(() {
        _supervisor = s;
        _assignedRetailers = List<Map<String, dynamic>>.from(retailers as List? ?? []);
        _payments = payments;
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  Map<String, double> get _byDate {
    final m = <String, double>{};
    for (final p in _payments) {
      final d = p['entry_date'] as String;
      m[d] = (m[d] ?? 0) + ((p['amount'] as num?)?.toDouble() ?? 0);
    }
    return m;
  }

  Map<String, double> get _byRetailer {
    final m = <String, double>{};
    for (final p in _payments) {
      final shop = (p['retailers'] as Map?)?['shop_name'] as String? ?? 'Unknown';
      m[shop] = (m[shop] ?? 0) + ((p['amount'] as num?)?.toDouble() ?? 0);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId ?? '';
    final total = _payments.fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        title: Text(_supervisor?['name'] as String? ?? 'Supervisor'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [
          Tab(text: 'Profile'), Tab(text: 'History'), Tab(text: 'By Date'), Tab(text: 'By Retailer'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _supervisor == null
          ? const Center(child: Text('Supervisor not found'))
          : TabBarView(controller: _tabs, children: [
        _profileTab(tid, total),
        _historyTab(),
        _byDateTab(),
        _byRetailerTab(),
      ]),
    );
  }

  Widget _profileTab(String tid, double total) => RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_supervisor?['name'] as String? ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kNavy)),
              const SizedBox(width: 8),
              StatusBadge((_supervisor?['is_active'] as bool? ?? true) ? 'active' : 'inactive',
                  (_supervisor?['is_active'] as bool? ?? true) ? Colors.green : Colors.grey, small: true),
            ]),
            if (_supervisor?['mobile'] != null) ...[
              const SizedBox(height: 4),
              Text(_supervisor!['mobile'] as String, style: const TextStyle(fontSize: 13, color: kTextSub)),
            ],
            const SizedBox(height: 4),
            Text(_supervisor?['user_id'] != null ? 'Linked ✓' : 'Not linked yet',
                style: TextStyle(fontSize: 12, color: _supervisor?['user_id'] != null ? Colors.green.shade700 : Colors.orange.shade700, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _kpiCard('Total Collected (all time)', Fmt.amount(total), Colors.green.shade700, Icons.payments_outlined)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Text('ASSIGNED RETAILERS', style: TextStyle(fontSize: 11, color: kTextHint, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final changed = await showAssignRetailersSheet(context,
                  traderId: tid, supervisorId: widget.supervisorId, supervisorName: _supervisor?['name'] as String? ?? '');
              if (changed) _load();
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit', style: TextStyle(fontSize: 12)),
          ),
        ]),
        if (_assignedRetailers.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('No retailers assigned.', style: TextStyle(color: kTextHint))),
        ..._assignedRetailers.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight)),
          child: Row(children: [
            Expanded(child: Text(r['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Text(Fmt.amount((r['outstanding_balance'] as num?)?.toDouble() ?? 0),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                    color: ((r['outstanding_balance'] as num?) ?? 0) > 0 ? Colors.orange.shade700 : Colors.green.shade700)),
          ]),
        )),
        const SizedBox(height: 40),
      ]));

  Widget _kpiCard(String label, String value, Color color, IconData icon) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
      child: Row(children: [
        Icon(icon, color: color, size: 22), const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600))),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      ]));

  Widget _historyTab() => _payments.isEmpty
      ? const Center(child: Text('No payments recorded yet.', style: TextStyle(color: kTextHint)))
      : RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: _payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = _payments[i];
        final shop = (p['retailers'] as Map?)?['shop_name'] as String? ?? 'Customer';
        final amt = (p['amount'] as num?)?.toDouble() ?? 0;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${DateFormat('d MMM yyyy').format(DateTime.parse(p['entry_date'] as String))} · ${(p['payment_mode'] as String? ?? '').toUpperCase()}',
                  style: const TextStyle(fontSize: 11, color: kTextHint)),
            ])),
            Text(Fmt.amount(amt), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700)),
          ]),
        );
      }));

  Widget _byDateTab() {
    final entries = _byDate.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return entries.isEmpty
        ? const Center(child: Text('No data.', style: TextStyle(color: kTextHint)))
        : ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final e = entries[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight)),
            child: Row(children: [
              Text(DateFormat('d MMM yyyy').format(DateTime.parse(e.key)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Text(Fmt.amount(e.value), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700)),
            ]),
          );
        });
  }

  Widget _byRetailerTab() {
    final entries = _byRetailer.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.isEmpty
        ? const Center(child: Text('No data.', style: TextStyle(color: kTextHint)))
        : ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final e = entries[i];
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight)),
            child: Row(children: [
              Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text(Fmt.amount(e.value), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade700)),
            ]),
          );
        });
  }
}