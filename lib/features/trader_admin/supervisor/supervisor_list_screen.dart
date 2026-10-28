import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import 'assign_retailer_sheet.dart';

/// Mirrors agents_screen.dart's structure closely. All the per-row
/// numbers (assigned count, total outstanding, today's collection) come
/// from two extra trader-wide queries aggregated client-side by
/// supervisor — no new RPCs, no new collection table, reusing
/// retailers.outstanding_balance and ledger_entries.recorded_by exactly
/// as the audit proposed.
class SupervisorListScreen extends ConsumerStatefulWidget {
  const SupervisorListScreen({super.key});
  @override ConsumerState<SupervisorListScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorListScreen> {
  final _c = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _supervisors = [];
  List<Map<String, dynamic>> _filtered = [];
  Map<String, int> _assignedCount = {};       // supervisor_id -> count
  Map<String, double> _totalOutstanding = {}; // supervisor_id -> sum
  Map<String, double> _collectedToday = {};   // user_id -> sum
  bool _loading = true;

  void _applySearch(String q) {
    final lower = q.trim().toLowerCase();
    if (mounted) {
      setState(() => _filtered = lower.isEmpty
        ? List.from(_supervisors)
        : _supervisors.where((s) =>
    (s['name'] as String? ?? '').toLowerCase().contains(lower) ||
        (s['mobile'] as String? ?? '').toLowerCase().contains(lower)).toList());
    }
  }

  @override void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final sups = await _c.from('supervisor_profiles')
          .select('id,name,mobile,is_active,user_id')
          .eq('trader_id', tid).order('name');

      final retailers = await _c.from('retailers')
          .select('supervisor_id,outstanding_balance')
          .eq('trader_id', tid).eq('is_active', true);

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final payments = await _c.from('ledger_entries')
          .select('amount,recorded_by')
          .eq('trader_id', tid).eq('entry_type', 'credit').eq('source_type', 'payment')
          .eq('entry_date', today);

      final assignedCount = <String, int>{};
      final totalOutstanding = <String, double>{};
      for (final r in List<Map<String, dynamic>>.from(retailers as List? ?? [])) {
        final sid = r['supervisor_id'] as String?;
        if (sid == null) continue;
        assignedCount[sid] = (assignedCount[sid] ?? 0) + 1;
        totalOutstanding[sid] = (totalOutstanding[sid] ?? 0) + ((r['outstanding_balance'] as num?)?.toDouble() ?? 0);
      }

      final collectedToday = <String, double>{};
      for (final p in List<Map<String, dynamic>>.from(payments as List? ?? [])) {
        final uid = p['recorded_by'] as String?;
        if (uid == null) continue;
        collectedToday[uid] = (collectedToday[uid] ?? 0) + ((p['amount'] as num?)?.toDouble() ?? 0);
      }

      if (mounted) {
        setState(() {
        _supervisors = List<Map<String, dynamic>>.from(sups as List? ?? []);
        _assignedCount = assignedCount;
        _totalOutstanding = totalOutstanding;
        _collectedToday = collectedToday;
        _loading = false;
        _applySearch(_searchCtrl.text);
      });
      }
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> s) async {
    final current = s['is_active'] as bool? ?? true;
    final ok = await confirmDialog(context,
        title: current ? 'Deactivate Supervisor' : 'Activate Supervisor',
        message: current
            ? '${s['name']} will no longer be able to log in or collect payments.'
            : '${s['name']} will be able to log in again.',
        confirmText: current ? 'Deactivate' : 'Activate',
        confirmColor: current ? Colors.red : Colors.green);
    if (!ok) return;
    try {
      await _c.from('supervisor_profiles').update({'is_active': !current}).eq('id', s['id']);
      if (mounted) showSuccess(context, '${current ? 'Deactivated' : 'Activated'} ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _editSheet(Map<String, dynamic> s) async {
    final nameCtrl = TextEditingController(text: s['name'] as String? ?? '');
    final mobileCtrl = TextEditingController(text: s['mobile'] as String? ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Edit Supervisor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: mobileCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: const Text('Save'),
          ),
        ]),
      ),
    );
    if (saved != true) return;
    try {
      await _c.from('supervisor_profiles').update({
        'name': nameCtrl.text.trim(),
        'mobile': mobileCtrl.text.trim().isEmpty ? null : mobileCtrl.text.trim(),
      }).eq('id', s['id']);
      if (mounted) showSuccess(context, 'Updated ✓');
      _load();
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).valueOrNull;
    final companyCode = user?.companyCode ?? '—';
    final tid = user?.traderId ?? '';

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(title: const Text('Supervisors'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(R.createSupervisor),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add Supervisor')),
      bottomNavigationBar: const SizedBox(height: 80),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your Company Code — share with supervisors', style: TextStyle(fontSize: 11, color: kTextHint)),
              Text(companyCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kPrimary, letterSpacing: 3)),
            ])),
            IconButton(icon: const Icon(Icons.copy, color: kPrimary),
                onPressed: () { Clipboard.setData(ClipboardData(text: companyCode)); showSuccess(context, 'Copied!'); }),
          ]),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: AppSearchBar(controller: _searchCtrl, hint: 'Search by name or mobile…',
              onChanged: _applySearch, onClear: () { _searchCtrl.clear(); _applySearch(''); }),
        ),
        const Divider(height: 1),
        Expanded(child: _loading ? const LoadingList() : _supervisors.isEmpty
            ? EmptyState(icon: Icons.payments_outlined, message: 'No supervisors yet',
            sub: 'Add a supervisor and share the Company Code with them',
            onAction: () => context.push(R.createSupervisor), actionLabel: 'Add Supervisor')
            : RefreshIndicator(onRefresh: _load, child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final s = _filtered[i];
              final id = s['id'] as String;
              final uid = s['user_id'] as String?;
              final linked = uid != null;
              final active = s['is_active'] as bool? ?? true;
              final assigned = _assignedCount[id] ?? 0;
              final outstanding = _totalOutstanding[id] ?? 0;
              final today = uid != null ? (_collectedToday[uid] ?? 0) : 0;

              return Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: linked ? kBorderLight : Colors.orange.withValues(alpha: 0.4), width: linked ? 1 : 1.5)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                    Container(width: 46, height: 46,
                        decoration: BoxDecoration(color: linked ? kNavy.withValues(alpha: 0.08) : Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(linked ? Icons.payments_outlined : Icons.person_add_outlined,
                            color: linked ? kPrimary : Colors.orange, size: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(s['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: kNavy)),
                        if (!active) ...[const SizedBox(width: 6), const StatusBadge('inactive', Colors.grey, small: true)],
                      ]),
                      if (s['mobile'] != null) Text(s['mobile'] as String, style: const TextStyle(fontSize: 12, color: kTextSub)),
                      Text('$assigned retailer${assigned == 1 ? '' : 's'} · Outstanding ${Fmt.amount(outstanding)}',
                          style: const TextStyle(fontSize: 11, color: kTextHint)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Today', style: TextStyle(fontSize: 10, color: kTextHint)),
                      Text(Fmt.amount(today.toDouble()), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                          color: today > 0 ? Colors.green.shade700 : kTextSub)),
                    ]),
                  ])),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton(
                          onPressed: () => context.push(R.supervisorDetailPath(id)),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text('View Details', style: TextStyle(fontSize: 12))),
                      OutlinedButton(
                          onPressed: () => _editSheet(s),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text('Edit', style: TextStyle(fontSize: 12))),
                      OutlinedButton(
                          onPressed: () async {
                            final changed = await showAssignRetailersSheet(context,
                                traderId: tid, supervisorId: id, supervisorName: s['name'] as String? ?? '');
                            if (changed) _load();
                          },
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          child: const Text('Assign Retailers', style: TextStyle(fontSize: 12))),
                      OutlinedButton(
                          onPressed: () => _toggleActive(s),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 34), padding: const EdgeInsets.symmetric(horizontal: 12),
                              foregroundColor: active ? Colors.red : Colors.green,
                              side: BorderSide(color: active ? Colors.red : Colors.green)),
                          child: Text(active ? 'Deactivate' : 'Activate', style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
                  if (!linked) Container(
                      decoration: const BoxDecoration(color: Color(0xFFFFF3E0), borderRadius: BorderRadius.vertical(bottom: Radius.circular(19))),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: const Row(children: [
                        Icon(Icons.link_off, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text('Not linked yet — supervisor cannot log in',
                            style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
                      ])),
                ]),
              );
            }))),
      ]),
    );
  }
}