import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';

class CashReconciliationScreen extends ConsumerStatefulWidget {
  const CashReconciliationScreen({super.key});

  @override
  ConsumerState<CashReconciliationScreen> createState() => _S();
}

class _S extends ConsumerState<CashReconciliationScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _pendingShifts = [];
  List<Map<String, dynamic>> _filteredPending = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _filteredHistory = [];
  final _searchCtrl = TextEditingController();

  void _applySearch(String q) {
    if (!mounted) return;
    final lower = q.trim().toLowerCase();
    bool match(Map<String,dynamic> s) {
      final a = s['delivery_agents'] as Map<String,dynamic>?;
      return (a?['name'] as String? ?? '').toLowerCase().contains(lower);
    }
    setState(() {
      _filteredPending = lower.isEmpty ? List.from(_pendingShifts) : _pendingShifts.where(match).toList();
      _filteredHistory = lower.isEmpty ? List.from(_history) : _history.where(match).toList();
    });
  }
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applySearch(_searchCtrl.text));
  }
  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final closed = await _c
          .from('delivery_shifts')
          .select(
              'id,total_cash_collected,shift_start_at,delivery_agents(id,name)')
          .eq('trader_id', tid)
          .eq('status', 'closed')
          .order('shift_start_at', ascending: false);
      final reconShiftIds = Set<String>.from((await _c
              .from('cash_reconciliation')
              .select('shift_id')
              .eq('trader_id', tid))
          .map((r) => r['shift_id'] as String? ?? '')
          .where((s) => s.isNotEmpty));
      final hist = await _c
          .from('cash_reconciliation')
          .select(
              'id,recon_date,expected_cash_total,cash_handed_in,discrepancy_amount,status,reconciled_at,delivery_agents(name)')
          .eq('trader_id', tid)
          .order('reconciled_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      if (mounted)
        setState(() {
          _pendingShifts = List<Map<String, dynamic>>.from(closed)
              .where((s) => !reconShiftIds.contains(s['id']))
              .toList();
          _history = List<Map<String, dynamic>>.from(hist);
          _applySearch(_searchCtrl.text);
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reconcile(Map<String, dynamic> shift) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final a = shift['delivery_agents'] as Map<String, dynamic>?;
    final expected = (shift['total_cash_collected'] as num?)?.toDouble() ?? 0;
    final cashCtrl = TextEditingController(text: expected.toStringAsFixed(2));
    final notesCtrl = TextEditingController();

    // Same form for both: bottom sheet on mobile, centred dialog on web.
    Widget form(BuildContext ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reconcile — ${a?['name'] ?? '—'}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Expected from app: ${Fmt.amount(expected)}',
                      style: const TextStyle(fontSize: 12, color: kTextSub)),
                  const SizedBox(height: 12),
                  TextField(
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      controller: cashCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Cash actually handed in (₹) *',
                          prefixText: '₹')),
                  const SizedBox(height: 10),
                  TextField(
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      controller: notesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Notes (optional)')),
                  const SizedBox(height: 16),
                  ElevatedButton(
                      onPressed: () async {
                        final amt = double.tryParse(cashCtrl.text);
                        if (amt == null) return;
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          await _c.rpc('perform_cash_reconciliation', params: {
                            'p_trader_id': tid,
                            'p_shift_id': shift['id'],
                            'p_cash_handed_in': amt,
                            'p_reconciled_by': uid,
                            'p_notes': notesCtrl.text.trim().isEmpty
                                ? null
                                : notesCtrl.text.trim(),
                          });
                          _load();
                          if (mounted) showSuccess(context, 'Reconciled ✓');
                        } catch (e) {
                          if (mounted) showError(context, e.toString());
                        }
                      },
                      child: const Text('Submit Reconciliation')),
                ]));
    if (context.isDesktop) {
      await showDialog(
          context: context,
          useRootNavigator: true,
          builder: (ctx) => Dialog(
                backgroundColor: WebColors.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WebRadius.dialog)),
                child: SizedBox(width: WebSize.dialogMd, child: form(ctx)),
              ));
    } else {
      await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useRootNavigator: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: form);
    }
    // controllers are ephemeral locals — GC handles disposal
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — header, KPI row, Pending / History tabs as tables.
  // ═══════════════════════════════════════════════════════════════════════
  int _webTab = 0;
  bool _dense = true;

  Widget _buildWeb() {
    final pendingCash = _pendingShifts.fold<double>(0,
        (s, x) => s + ((x['total_cash_collected'] as num?)?.toDouble() ?? 0));
    final netDisc = _history.fold<double>(0,
        (s, h) => s + ((h['discrepancy_amount'] as num?)?.toDouble() ?? 0));
    final exact = _history.where((h) =>
        (((h['discrepancy_amount'] as num?)?.toDouble() ?? 0).abs()) < 0.01).length;

    String fmtDate(String? iso) {
      final d = DateTime.tryParse(iso ?? '');
      return d != null ? DateFormat('d MMM y').format(d) : '—';
    }

    Widget agentCell(Map<String, dynamic> r) {
      final name = (r['delivery_agents'] as Map?)?['name'] as String? ?? '—';
      return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600,
              color: WebColors.text1));
    }

    final pendingTable = WebDataTable<Map<String, dynamic>>(
      columns: const [
        WebColumn('Shift Date', width: 150),
        WebColumn('Agent', flex: 3),
        WebColumn('Expected Cash', width: 170, align: TextAlign.right),
        WebColumn('Action', width: 160, align: TextAlign.center),
      ],
      rows: _filteredPending,
      paginate: true,
      dense: _dense,
      loading: _loading,
      emptyText: 'All shifts reconciled ✓',
      cellBuilder: (s, col) => switch (col) {
        0 => Text(fmtDate(s['shift_start_at'] as String?),
            style: const TextStyle(fontSize: 13, color: WebColors.text2)),
        1 => agentCell(s),
        2 => Text(Fmt.amount((s['total_cash_collected'] as num?)?.toDouble() ?? 0),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                color: WebColors.text1)),
        _ => WebButton(label: 'Reconcile', icon: Icons.fact_check_outlined,
            onPressed: () => _reconcile(s)),
      },
    );

    final historyTable = WebDataTable<Map<String, dynamic>>(
      columns: const [
        WebColumn('Reconciled', width: 150),
        WebColumn('Agent', flex: 3),
        WebColumn('Expected', width: 150, align: TextAlign.right),
        WebColumn('Handed In', width: 150, align: TextAlign.right),
        WebColumn('Difference', width: 180, align: TextAlign.center),
      ],
      rows: _filteredHistory,
      paginate: true,
      dense: _dense,
      loading: _loading,
      emptyText: 'No reconciliations yet',
      cellBuilder: (h, col) {
        final disc = (h['discrepancy_amount'] as num?)?.toDouble() ?? 0;
        return switch (col) {
          0 => Text(fmtDate(h['reconciled_at'] as String?),
              style: const TextStyle(fontSize: 13, color: WebColors.text2)),
          1 => agentCell(h),
          2 => Text(Fmt.amount((h['expected_cash_total'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontSize: 13.5, color: WebColors.text2)),
          3 => Text(Fmt.amount((h['cash_handed_in'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: WebColors.text1)),
          _ => disc.abs() < 0.01
              ? const WebLabel('Exact ✓', color: WebColors.success)
              : disc > 0
                  ? WebLabel('+${Fmt.amount(disc.abs())} excess',
                      color: WebColors.info)
                  : WebLabel('${Fmt.amount(disc.abs())} short',
                      color: WebColors.error),
        };
      },
    );

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Cash Reconciliation',
        subtitle: "Match each closed shift's cash against what the agent handed in",
        crumbs: const [
          Crumb('Dashboard', R.dashboard),
          Crumb('Cash Reconciliation'),
        ],
        action: WebIconButton(icon: Icons.refresh_rounded,
            tooltip: 'Refresh', onTap: _load),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Shifts to Reconcile',
              value: '${_pendingShifts.length}',
              icon: Icons.pending_actions_outlined,
              color: _pendingShifts.isEmpty
                  ? WebColors.success : WebColors.warning),
          WebKpiCard(label: 'Cash Expected', value: Fmt.amount(pendingCash),
              sub: 'from shifts not yet reconciled',
              icon: Icons.payments_outlined, color: WebColors.navy),
          WebKpiCard(label: 'Exact Matches', value: '$exact',
              sub: 'of last ${_history.length} reconciliations',
              icon: Icons.verified_outlined, color: WebColors.success),
          WebKpiCard(label: 'Net Difference', value: Fmt.amount(netDisc),
              sub: netDisc < 0 ? 'short overall' : 'excess / even overall',
              icon: Icons.compare_arrows_rounded,
              color: netDisc < 0 ? WebColors.error : WebColors.info),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('Pending', count: _filteredPending.length,
                  color: WebColors.warning),
              WebTab('History', count: _filteredHistory.length),
            ],
            selected: _webTab,
            onChanged: (i) => setState(() => _webTab = i),
          ),
          WebListToolbar(
            search: WebSearchField(
              controller: _searchCtrl,
              hint: 'Search by agent name…',
              debounce: const Duration(milliseconds: 200),
              onChanged: _applySearch,
            ),
            trailing: [
              const Text('Dense', style: WebText.bodySub),
              Switch(value: _dense,
                  activeTrackColor: WebColors.navy,
                  onChanged: (v) => setState(() => _dense = v)),
            ],
          ),
          _webTab == 0 ? pendingTable : historyTable,
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => context.isDesktop ? _buildWeb() : Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            backgroundColor: kSurface,
            title: const Text('Cash Reconciliation'),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
            ]),
        body: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppSearchBar(
              controller: _searchCtrl,
              hint: 'Search by agent name…',
              onChanged: _applySearch,
              onClear: () { _searchCtrl.clear(); _applySearch(''); },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _loading
            ? const LoadingList()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                    if (_filteredPending.isEmpty)
                      Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade200)),
                          child: const Row(children: [
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 22),
                            SizedBox(width: 10),
                            Text('All shifts reconciled ✓',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700))
                          ]))
                    else ...[
                      const SectionHeader('PENDING RECONCILIATION'),
                      ..._filteredPending.map((s) {
                        final a = s['delivery_agents'] as Map<String, dynamic>?;
                        final exp =
                            (s['total_cash_collected'] as num?)?.toDouble() ??
                                0;
                        final date = DateTime.tryParse(
                            s['shift_start_at'] as String? ?? '');
                        return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.orange.shade200, width: 1.5)),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(a?['name'] as String? ?? '—',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    Text('Expected: ${Fmt.amount(exp)}',
                                        style: const TextStyle(
                                            fontSize: 12, color: kTextSub)),
                                    if (date != null)
                                      Text(DateFormat('d MMM y').format(date),
                                          style: const TextStyle(
                                              fontSize: 11, color: kTextHint)),
                                  ])),
                              ElevatedButton(
                                  onPressed: () => _reconcile(s),
                                  style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(80, 36)),
                                  child: const Text('Reconcile',
                                      style: TextStyle(fontSize: 12))),
                            ]));
                      }),
                    ],
                    if (_filteredHistory.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const SectionHeader('HISTORY'),
                      ..._filteredHistory.map((h) {
                        final a = h['delivery_agents'] as Map<String, dynamic>?;
                        final exp =
                            (h['expected_cash_total'] as num?)?.toDouble() ?? 0;
                        final actual =
                            (h['cash_handed_in'] as num?)?.toDouble() ?? 0;
                        final disc =
                            (h['discrepancy_amount'] as num?)?.toDouble() ?? 0;
                        final date = DateTime.tryParse(
                            h['reconciled_at'] as String? ?? '');
                        return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: WhiteCard(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(a?['name'] as String? ?? '—',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13)),
                                        if (date != null)
                                          Text(
                                              DateFormat('d MMM y')
                                                  .format(date),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: kTextHint)),
                                        Text('Expected: ${Fmt.amount(exp)}',
                                            style: const TextStyle(
                                                fontSize: 11, color: kTextSub)),
                                      ])),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(Fmt.amount(actual),
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                            disc.abs() < 0.01
                                                ? 'Exact ✓'
                                                : disc > 0
                                                    ? '+${Fmt.amount(disc.abs())} excess'
                                                    : '${Fmt.amount(disc.abs())} short',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: disc.abs() < 0.01
                                                    ? Colors.green
                                                    : disc > 0
                                                        ? Colors.blue
                                                        : Colors.red)),
                                      ]),
                                ])));
                      }),
                    ],
                  ]),
          ),
        ]),
      );
}
