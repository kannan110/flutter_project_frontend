import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/cards/metric_card.dart';

class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({super.key});
  @override ConsumerState<CashReconciliationScreen> createState() => _S();
}

class _S extends ConsumerState<CashReconciliationScreen> {
  final _c = Supabase.instance.client;

  List<Map<String,dynamic>> _pendingShifts  = [];
  List<Map<String,dynamic>> _history        = [];
  List<Map<String,dynamic>> _agentSummary   = [];  // Phase 6: per-agent summary
  bool    _loading = true;
  String? _error;                                  // Phase 6: surface errors
  // Phase 6: date filter for history
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to   = DateTime.now();
  String?  _filterAgentId;                         // null = all agents

  @override void initState() { super.initState(); _load(); }

  // ── ALL BUSINESS LOGIC PRESERVED + ENHANCED ───────────────────────────────
  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      // Pending unreconciled closed shifts
      final closed = await _c.from('delivery_shifts')
          .select('id,total_cash_collected,shift_start_at,delivery_agents(id,name)')
          .eq('trader_id', tid).eq('status', 'closed')
          .order('shift_start_at', ascending: false);

      final reconShiftIds = Set<String>.from(
          (await _c.from('cash_reconciliation').select('shift_id').eq('trader_id', tid))
              .map((r) => r['shift_id'] as String? ?? '').where((s) => s.isNotEmpty));

      // History with date filter — build query before order/limit
      var histQuery = _c.from('cash_reconciliation')
          .select('id,recon_date,expected_cash_total,cash_handed_in,discrepancy_amount,status,reconciled_at,agent_id,delivery_agents(name)')
          .eq('trader_id', tid)
          .gte('recon_date', DateFormat('yyyy-MM-dd').format(_from))
          .lte('recon_date', DateFormat('yyyy-MM-dd').format(_to));
      if (_filterAgentId != null) {
        histQuery = histQuery.eq('agent_id', _filterAgentId!);
      }
      final hist = await histQuery
          .order('reconciled_at', ascending: false)
          .limit(50);

      // Phase 6: per-agent summary via new RPC
      List<Map<String,dynamic>> agentSummary = [];
      try {
        final res = await _c.rpc('get_cash_recon_summary', params: {'p_trader_id': tid});
        agentSummary = List<Map<String,dynamic>>.from(res as List? ?? []);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _pendingShifts = List<Map<String,dynamic>>.from(closed)
            .where((s) => !reconShiftIds.contains(s['id'])).toList();
        _history      = List<Map<String,dynamic>>.from(hist);
        _agentSummary = agentSummary;
        _loading      = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reconcile(Map<String,dynamic> shift) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final a = shift['delivery_agents'] as Map<String,dynamic>?;
    final expected = (shift['total_cash_collected'] as num?)?.toDouble() ?? 0;
    final cashCtrl  = TextEditingController(text: expected.toStringAsFixed(2));
    final notesCtrl = TextEditingController();

    await showModalBottomSheet(
        context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Reconcile — ${a?['name'] ?? '—'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              ]),
              const SizedBox(height: 4),
              Text('Expected: ${Fmt.amount(expected)}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                  controller: cashCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Cash actually handed in (₹) *',
                      prefixText: '₹')),
              const SizedBox(height: 10),
              TextField(controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)')),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(cashCtrl.text);
                    if (amt == null) return;
                    Navigator.of(ctx, rootNavigator: true).pop();
                    try {
                      await _c.rpc('perform_cash_reconciliation', params: {
                        'p_trader_id': tid, 'p_shift_id': shift['id'],
                        'p_cash_handed_in': amt, 'p_reconciled_by': uid,
                        'p_notes': notesCtrl.text.trim().isEmpty
                            ? null : notesCtrl.text.trim(),
                      });
                      _load();
                      if (mounted) showSuccess(context, 'Reconciled ✓');
                    } catch (e) {
                      if (mounted) showError(context, e.toString());
                    }
                  },
                  child: const Text('Submit Reconciliation')),
            ])));
    cashCtrl.dispose(); notesCtrl.dispose();
  }

  // Phase 6: date range picker for history filter
  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null && mounted) {
      setState(() { _from = range.start; _to = range.end; });
      _load();
    }
  }

  Widget _buildScaffold(BuildContext context) {
    final totalPending = _pendingShifts.fold(
        0.0, (s, sh) => s + ((sh['total_cash_collected'] as num?)?.toDouble() ?? 0));
    final totalDiscrepancy = _agentSummary.fold(
        0.0, (s, a) => s + ((a['total_discrepancy'] as num?)?.toDouble() ?? 0));
    final isDesktop = context.isDesktop;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kSurface,
          title: const Text('Cash Reconciliation'),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingList()
          : _error != null
          ? Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: kTextHint),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSub, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry')),
          ])))
          : Column(children: [

        // ── Phase 6: Summary strip (desktop) ──────────────────────────
        if (isDesktop && (_pendingShifts.isNotEmpty || _agentSummary.isNotEmpty))
          Container(
            color: kSurface,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: MetricStrip(metrics: [
              MetricCard(
                  label: 'Pending Reconciliation',
                  value: '${_pendingShifts.length}',
                  color: _pendingShifts.isNotEmpty ? Colors.orange : Colors.green,
                  icon: Icons.pending_actions_outlined),
              MetricCard(
                  label: 'Expected Pending',
                  value: Fmt.amount(totalPending),
                  color: Colors.orange,
                  icon: Icons.account_balance_wallet_outlined),
              MetricCard(
                  label: 'History (${DateFormat("d MMM").format(_from)}–${DateFormat("d MMM").format(_to)})',
                  value: '${_history.length}',
                  icon: Icons.history_outlined),
              MetricCard(
                  label: 'Total Discrepancy',
                  value: Fmt.amount(totalDiscrepancy.abs()),
                  color: totalDiscrepancy.abs() > 0 ? Colors.red : Colors.green,
                  icon: Icons.balance_outlined),
            ]),
          ),

        // ── Phase 6: Filters row ───────────────────────────────────────
        Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            // Date range
            GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: kBgPage,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.date_range_outlined, size: 16, color: kPrimary),
                  const SizedBox(width: 6),
                  Text(
                      '${DateFormat("d MMM").format(_from)} – ${DateFormat("d MMM y").format(_to)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            // Agent filter
            if (_agentSummary.isNotEmpty)
              Expanded(child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _filterChip('All', null),
                  ..._agentSummary.map((a) =>
                      _filterChip(
                          (a['agent_name'] as String? ?? '—').split(' ').first,
                          a['agent_id'] as String?)),
                ]),
              )),
          ]),
        ),
        const Divider(height: 1),

        // ── Body ──────────────────────────────────────────────────────
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [

            // Pending shifts
            if (_pendingShifts.isEmpty)
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200)),
                  child: const Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 22),
                    SizedBox(width: 10),
                    Text('All shifts reconciled ✓',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                  ]))
            else ...[
              const SectionHeader('PENDING RECONCILIATION'),
              ..._pendingShifts.map((s) {
                final a   = s['delivery_agents'] as Map<String,dynamic>?;
                final exp = (s['total_cash_collected'] as num?)?.toDouble() ?? 0;
                final date= DateTime.tryParse(s['shift_start_at'] as String? ?? '');
                return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200, width: 1.5)),
                    child: Row(children: [
                      Container(width: 40, height: 40,
                          decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.hourglass_top_rounded,
                              color: Colors.orange, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a?['name'] as String? ?? '—',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Expected: ${Fmt.amount(exp)}',
                            style: const TextStyle(fontSize: 12, color: kTextSub)),
                        if (date != null)
                          Text(DateFormat('d MMM y · h:mm a').format(date.toLocal()),
                              style: const TextStyle(fontSize: 11, color: kTextHint)),
                      ])),
                      ElevatedButton(
                          onPressed: () => _reconcile(s),
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(90, 38)),
                          child: const Text('Reconcile',
                              style: TextStyle(fontSize: 12))),
                    ]));
              }),
            ],

            // Phase 6: Per-agent summary section
            if (_agentSummary.isNotEmpty) ...[
              const SizedBox(height: 8),
              const SectionHeader('PER-AGENT SUMMARY'),
              ..._agentSummary.map((a) {
                final pending  = (a['pending_shifts']   as num?)?.toInt()    ?? 0;
                final expected = (a['pending_expected'] as num?)?.toDouble() ?? 0;
                final lastDate = a['last_recon_date'] as String?;
                final disc     = (a['total_discrepancy'] as num?)?.toDouble() ?? 0;
                return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: WhiteCard(padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Container(width: 36, height: 36,
                              decoration: BoxDecoration(
                                  color: kNavy.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Center(child: Text(
                                  (a['agent_name'] as String? ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w800,
                                      color: kNavy, fontSize: 14)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a['agent_name'] as String? ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            if (lastDate != null)
                              Text('Last: ${DateFormat("d MMM y").format(DateTime.parse(lastDate))}',
                                  style: const TextStyle(fontSize: 11, color: kTextHint)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            if (pending > 0) Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.shade200)),
                                child: Text('$pending pending · ${Fmt.amount(expected)}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                        color: Colors.orange))),
                            if (disc.abs() > 0.01) ...[
                              const SizedBox(height: 4),
                              Text(
                                  disc > 0 ? '+${Fmt.amount(disc.abs())} excess'
                                      : '${Fmt.amount(disc.abs())} total short',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                      color: disc > 0 ? Colors.blue : Colors.red)),
                            ],
                          ]),
                        ])));
              }),
            ],

            // History (filtered)
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 8),
              const SectionHeader('HISTORY'),
              ..._history.map((h) {
                final a      = h['delivery_agents'] as Map<String,dynamic>?;
                final exp    = (h['expected_cash_total'] as num?)?.toDouble() ?? 0;
                final actual = (h['cash_handed_in']      as num?)?.toDouble() ?? 0;
                final disc   = (h['discrepancy_amount']  as num?)?.toDouble() ?? 0;
                final date   = DateTime.tryParse(h['reconciled_at'] as String? ?? '');
                return Container(margin: const EdgeInsets.only(bottom: 8),
                    child: WhiteCard(padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a?['name'] as String? ?? '—',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if (date != null)
                              Text(DateFormat('d MMM y').format(date.toLocal()),
                                  style: const TextStyle(fontSize: 11, color: kTextHint)),
                            Text('Expected: ${Fmt.amount(exp)}',
                                style: const TextStyle(fontSize: 11, color: kTextSub)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(Fmt.amount(actual),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                                disc.abs() < 0.01 ? 'Exact ✓'
                                    : disc > 0 ? '+${Fmt.amount(disc.abs())} excess'
                                    : '${Fmt.amount(disc.abs())} short',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                    color: disc.abs() < 0.01 ? Colors.green
                                        : disc > 0 ? Colors.blue : Colors.red)),
                          ]),
                        ])));
              }),
            ] else if (_history.isEmpty && !_loading) ...[
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kBgPage,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorderLight)),
                  child: Text(
                      'No reconciliation history for ${DateFormat("d MMM").format(_from)} – ${DateFormat("d MMM y").format(_to)}',
                      style: const TextStyle(fontSize: 12, color: kTextHint),
                      textAlign: TextAlign.center)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _filterChip(String label, String? agentId) {
    final active = _filterAgentId == agentId;
    return GestureDetector(
      onTap: () { setState(() => _filterAgentId = agentId); _load(); },
      child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: active ? kNavy : kBgPage,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: active ? kNavy : kBorderLight)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : kTextSub))),
    );
  }

  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildScaffold(context),
  );
}