import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Full reconciliation drill-down opened when trader taps the Live Stock card.
/// Shows: Opening → DC → Transfers → Returns → Mortality → Current Balance
/// Plus per-agent ownership and recent movements.
class StockDetailScreen extends ConsumerStatefulWidget {
  const StockDetailScreen({super.key});
  @override ConsumerState<StockDetailScreen> createState() => _S();
}

class _S extends ConsumerState<StockDetailScreen> {
  final _c = Supabase.instance.client;

  List<StockPosition> _positions    = [];
  List<Map<String,dynamic>> _ledger = [];
  List<AgentStockStatus>    _agents = [];
  bool _loading = true;

  // Computed breakdown from stock_ledger
  int    _openingBirds   = 0;
  double _openingKg      = 0;
  int    _purchasedBirds = 0;
  double _purchasedKg    = 0;
  int    _transferInBirds = 0;
  double _transferInKg    = 0;
  int    _transferOutBirds = 0;
  double _transferOutKg    = 0;
  int    _deliveredBirds = 0;
  double _deliveredKg    = 0;
  int    _returnedBirds  = 0;
  double _returnedKg     = 0;
  int    _mortalityBirds = 0;
  double _mortalityKg    = 0;
  int    _shrinkBirds    = 0;
  double _shrinkKg       = 0;
  int    _shiftReturnBirds = 0;
  double _shiftReturnKg   = 0;
  int    _closingBirds   = 0;
  double _closingKg      = 0;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    final tid  = user?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);

    // ── Query 1: Stock positions ─────────────────────────────────────────────
    List<StockPosition> positions = [];
    try {
      final r0 = await _c
          .rpc('get_available_stock', params: {'p_trader_id': tid})
          .timeout(const Duration(seconds: 10));
      positions = ((r0 as List?) ?? [])
          .map((s) => StockPosition.fromMap(s as Map<String,dynamic>))
          .toList();
    } catch (_) {}

    // ── Query 2: Stock ledger movements ─────────────────────────────────────
    // Isolated so it ALWAYS runs even if query 1 or 3 fails.
    // Select exactly the columns needed — agent name via FK join.
    List<Map<String,dynamic>> ledger = [];
    try {
      final r1 = await _c
          .from('stock_ledger')
          .select('id,entry_date,movement_type,quantity_birds,quantity_kg,'
          'notes,agent_id,delivery_agents(name),master_products(name)')
          .eq('trader_id', tid)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 10));
      ledger = List<Map<String,dynamic>>.from((r1 as List?) ?? []);
    } catch (e) {
      // Non-fatal — movements section shows empty state
    }

    // ── Query 3: Agent statuses from dashboard_summary ───────────────────────
    List<AgentStockStatus> agents = [];
    try {
      final r2 = await _c
          .rpc('dashboard_summary', params: {'p_trader_id': tid})
          .timeout(const Duration(seconds: 10));
      final dashMap = r2 as Map<String,dynamic>?;
      agents = ((dashMap?['agent_status'] as List?) ?? [])
          .map((a) => AgentStockStatus.fromMap(a as Map<String,dynamic>))
          .toList();
    } catch (_) {}

    if (!mounted) return;

    // ── Compute breakdown totals from ledger ──────────────────────────────────
    int ob=0, pb=0, tib=0, tob=0, db=0, rb=0, mb=0, sb=0, scb=0, cb=0;
    double ok=0, pk=0, tik=0, tok=0, dk=0, rk=0, mk=0, sk=0, sck=0, ck=0;
    for (final row in ledger) {
      final mt = row['movement_type'] as String? ?? '';
      final b  = (row['quantity_birds'] as num?)?.toInt()    ?? 0;
      final k  = (row['quantity_kg']    as num?)?.toDouble() ?? 0;
      switch (mt) {
        case 'opening':           ob+=b; ok+=k;
        case 'purchased':         pb+=b; pk+=k;
        case 'transferred_in':    tib+=b; tik+=k;
        case 'transferred_out':   tob+=b; tok+=k;
        case 'delivered':         db+=b; dk+=k;
        case 'returned_in':       rb+=b; rk+=k;
        case 'mortality':         mb+=b; mk+=k;
        case 'shrinkage':         sb+=b; sk+=k;
        case 'shift_close_return':scb+=b; sck+=k;
        case 'closing_stock':     cb+=b; ck+=k;
      }
    }

    setState(() {
      _positions        = positions;
      _ledger           = ledger;
      _agents           = agents;
      _openingBirds=ob;  _openingKg=ok;
      _purchasedBirds=pb; _purchasedKg=pk;
      _transferInBirds=tib; _transferInKg=tik;
      _transferOutBirds=tob; _transferOutKg=tok;
      _deliveredBirds=db; _deliveredKg=dk;
      _returnedBirds=rb;  _returnedKg=rk;
      _mortalityBirds=mb; _mortalityKg=mk;
      _shrinkBirds=sb;    _shrinkKg=sk;
      _shiftReturnBirds=scb; _shiftReturnKg=sck;
      _closingBirds=cb;   _closingKg=ck;
      _loading=false;
    });
  }

  // ── Computed live balance ────────────────────────────────────────────────
  int    get _liveBalanceBirds => _positions.isNotEmpty ? _positions.first.availableBirds : 0;
  double get _liveBalanceKg    => _positions.isNotEmpty ? _positions.first.availableKg    : 0;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: kBgGrey,
      appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Live Stock Detail', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('Full reconciliation breakdown', style: TextStyle(fontSize: 10, color: kTextHint)),
          ]),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const LoadingList()
          : RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(14), children: [
            // ── 1. Current live balance — primary metric ─────────────────
            _buildLiveBalanceBanner(),
            const SizedBox(height: 12),

            // ── 2. Stock flow waterfall ──────────────────────────────────
            _buildFlowCard(),
            const SizedBox(height: 12),

            // ── 3. Stock ownership per agent ─────────────────────────────
            if (_agents.isNotEmpty) ...[
              _buildOwnershipCard(),
              const SizedBox(height: 12),
            ],

            // ── 4. Recent movements (last 20, grouped by today/earlier) ──
            _buildRecentMovements(),
            const SizedBox(height: 20),
          ])));

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. LIVE BALANCE BANNER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildLiveBalanceBanner() {
    final p   = _positions.isNotEmpty ? _positions.first : null;
    final neg = (p?.isNegative ?? false);
    final low = (p?.hasLowStock ?? false);
    final c   = neg ? Colors.red : low ? Colors.orange : const Color(0xFF1B7A3E);
    final bg  = neg ? Colors.red.shade50 : low ? Colors.orange.shade50 : Colors.green.shade50;
    final bc  = neg ? Colors.red.shade200 : low ? Colors.orange.shade200 : Colors.green.shade200;

    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: bc, width: 1.5),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(children: [
          Row(children: [
            Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.inventory_2_outlined, color: c, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CURRENT AVAILABLE STOCK',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: kTextSub)),
              Text('$_liveBalanceBirds Birds  •  ${_liveBalanceKg.toStringAsFixed(1)} kg',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c, height: 1.1)),
            ])),
            _statusBadge(),
          ]),
          if (p != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: c.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            // Quick secondary metrics
            Row(children: [
              _bannerStat('Loaded Today', '+${p.todayPurchased} birds', Colors.blue),
              _vLine(c),
              _bannerStat('Delivered Today', '${p.todayDelivered} birds', kPrimary),
              _vLine(c),
              _bannerStat('All-Time In', '${p.totalInBirds} birds', Colors.grey.shade600),
            ]),
          ],
        ]));
  }

  Widget _statusBadge() {
    final allAgentsClear = _agents.every((a) => a.liveStockBirds == 0 && a.pendingDeliveries == 0);
    final anyPending     = _agents.any((a) => a.pendingDeliveries > 0);
    final anyStock       = _agents.any((a) => a.liveStockBirds > 0);

    String label; Color c; IconData ic;
    if (_liveBalanceBirds < 0) {
      label='MISMATCH'; c=Colors.red; ic=Icons.error_outline;
    } else if (anyPending) {
      label='PENDING'; c=Colors.orange; ic=Icons.pending_outlined;
    } else if (anyStock) {
      label='WITH AGENTS'; c=Colors.blue; ic=Icons.people_outline;
    } else {
      label='BALANCED'; c=Colors.green; ic=Icons.check_circle_outline;
    }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, color: c, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.5)),
        ]));
  }

  Widget _bannerStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    const SizedBox(height: 2),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _vLine(Color c) => Container(width: 1, height: 30, color: c.withValues(alpha: 0.15));

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. STOCK FLOW WATERFALL
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFlowCard() {
    final rows = <_FlowRow>[
      if (_openingBirds > 0)
        _FlowRow('Opening Stock',    '+$_openingBirds birds',   '${_openingKg.toStringAsFixed(1)} kg',  true,  Colors.blue.shade700,  Icons.home_outlined),
      if (_purchasedBirds > 0)
        _FlowRow('Farm DC Loaded',   '+$_purchasedBirds birds', '${_purchasedKg.toStringAsFixed(1)} kg', true, Colors.green.shade700, Icons.add_shopping_cart),
      if (_transferInBirds > 0)
        _FlowRow('Transfer In',      '+$_transferInBirds birds','${_transferInKg.toStringAsFixed(1)} kg', true, Colors.teal,           Icons.swap_horiz),
      if (_returnedBirds > 0)
        _FlowRow('Customer Return',  '+$_returnedBirds birds',  '${_returnedKg.toStringAsFixed(1)} kg',  true, Colors.purple,         Icons.assignment_return_outlined),
      if (_deliveredBirds > 0)
        _FlowRow('Delivered',        '−$_deliveredBirds birds', '${_deliveredKg.toStringAsFixed(1)} kg',  false, kPrimary,            Icons.local_shipping_outlined),
      if (_transferOutBirds > 0)
        _FlowRow('Transfer Out',     '−$_transferOutBirds birds','${_transferOutKg.toStringAsFixed(1)} kg',false,Colors.indigo,        Icons.swap_horiz),
      if (_mortalityBirds > 0)
        _FlowRow('Mortality',        '−$_mortalityBirds birds', '${_mortalityKg.toStringAsFixed(1)} kg',  false, Colors.red,          Icons.sentiment_very_dissatisfied_outlined),
      if (_shrinkBirds > 0 || _shrinkKg > 0)
        _FlowRow('Shrinkage',        '−$_shrinkBirds birds',    '${_shrinkKg.toStringAsFixed(1)} kg',     false, Colors.deepOrange,   Icons.compress_outlined),
      if (_shiftReturnBirds > 0)
        _FlowRow('Shift Return',     '−$_shiftReturnBirds birds','${_shiftReturnKg.toStringAsFixed(1)} kg',false,Colors.purple,       Icons.assignment_return_outlined),
      if (_closingBirds > 0)
        _FlowRow('Write-Off',        '−$_closingBirds birds',   '${_closingKg.toStringAsFixed(1)} kg',    false, Colors.grey,         Icons.lock_outline),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                const Icon(Icons.account_tree_outlined, size: 16, color: kPrimary),
                const SizedBox(width: 8),
                const Text('Stock Flow Breakdown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextMain)),
                const Spacer(),
                const Text('All-time cumulative', style: TextStyle(fontSize: 10, color: kTextHint)),
              ])),
          const Divider(height: 1),

          // Flow rows
          ...rows.asMap().entries.map((e) {
            final i = e.key; final r = e.value;
            final isLast = i == rows.length - 1;
            return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    border: !isLast
                        ? const Border(bottom: BorderSide(color: kBorder, width: 0.5))
                        : null),
                child: Row(children: [
                  // Icon pill
                  Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                          color: r.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(r.icon, color: r.color, size: 14)),
                  const SizedBox(width: 12),
                  // Label
                  Expanded(child: Text(r.label,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextMain))),
                  // Value
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(r.birds,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: r.isInflow ? Colors.green.shade700 : Colors.red.shade700)),
                    Text(r.kg, style: const TextStyle(fontSize: 10, color: kTextSub)),
                  ]),
                ]));
          }),

          // Balance footer
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
              child: Row(children: [
                const Icon(Icons.account_balance_outlined, color: kPrimary, size: 16),
                const SizedBox(width: 10),
                const Text('LIVE BALANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kPrimary, letterSpacing: 0.5)),
                const Spacer(),
                Text('$_liveBalanceBirds birds  •  ${_liveBalanceKg.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kPrimary)),
              ])),
        ]));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. STOCK OWNERSHIP PER AGENT
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOwnershipCard() {
    final withStock    = _agents.where((a) => a.liveStockBirds > 0).toList();
    final withoutStock = _agents.where((a) => a.liveStockBirds == 0).toList();

    return Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                const Icon(Icons.people_alt_outlined, size: 16, color: kPrimary),
                const SizedBox(width: 8),
                const Text('Stock Ownership', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${_agents.length} agents', style: const TextStyle(fontSize: 10, color: kTextHint)),
              ])),
          const Divider(height: 1),

          // Agents with stock first (orange row), then balanced (green)
          ...[...withStock, ...withoutStock].asMap().entries.map((e) {
            final i = e.key; final a = e.value;
            final hasStock  = a.liveStockBirds > 0;
            final hasPend   = a.pendingDeliveries > 0;
            final isLast    = i == _agents.length - 1;

            // Status label
            String statusLabel; Color statusColor; IconData statusIcon;
            if (!a.hasOpenShift && hasStock) {
              statusLabel='RETURN PENDING'; statusColor=Colors.red; statusIcon=Icons.warning_amber_rounded;
            } else if (hasPend) {
              statusLabel='DELIVERING'; statusColor=Colors.orange; statusIcon=Icons.local_shipping_outlined;
            } else if (hasStock) {
              statusLabel='HOLDING STOCK'; statusColor=Colors.blue; statusIcon=Icons.inventory_outlined;
            } else {
              statusLabel='BALANCED'; statusColor=Colors.green; statusIcon=Icons.check_circle_outline;
            }

            return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: hasStock ? Colors.orange.shade50.withValues(alpha: 0.4) : Colors.transparent,
                    border: !isLast
                        ? const Border(bottom: BorderSide(color: kBorder, width: 0.5))
                        : null),
                child: Row(children: [
                  // Avatar
                  CircleAvatar(radius: 18,
                      backgroundColor: hasStock ? Colors.orange.withValues(alpha: 0.15) : Colors.grey.shade100,
                      child: Text(a.agentName.isNotEmpty ? a.agentName[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                              color: hasStock ? Colors.orange.shade800 : kTextSub))),
                  const SizedBox(width: 12),
                  // Name + vehicle
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.agentName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextMain)),
                    Row(children: [
                      // Shift status dot
                      Container(width: 6, height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: a.hasOpenShift ? Colors.green : Colors.grey.shade400)),
                      Text(a.hasOpenShift ? 'Shift Open' : 'Shift Closed',
                          style: TextStyle(fontSize: 9, color: a.hasOpenShift ? Colors.green : kTextHint)),
                      if (a.vehicleNo != null && a.vehicleNo!.isNotEmpty) ...[
                        const Text(' · ', style: TextStyle(fontSize: 9, color: kTextHint)),
                        Text(a.vehicleNo!, style: const TextStyle(fontSize: 9, color: kTextHint)),
                      ],
                    ]),
                  ])),
                  // Stock in hand
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(hasStock ? '${a.liveStockBirds} birds' : '—',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: hasStock ? Colors.orange.shade800 : Colors.green)),
                    if (hasStock) Text('${a.liveStockKg.toStringAsFixed(1)} kg',
                        style: const TextStyle(fontSize: 10, color: kTextSub)),
                  ]),
                  const SizedBox(width: 10),
                  // Status badge
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, color: statusColor, size: 10),
                        const SizedBox(width: 3),
                        Text(statusLabel, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: statusColor)),
                      ])),
                ]));
          }),

          // Total footer
          if (withStock.isNotEmpty) Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
              child: Row(children: [
                const Icon(Icons.people_outline, color: Colors.orange, size: 14),
                const SizedBox(width: 6),
                Text('${withStock.length} agent(s) holding stock',
                    style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${withStock.fold(0,(s,a)=>s+a.liveStockBirds)} birds  •  '
                    '${withStock.fold(0.0,(s,a)=>s+a.liveStockKg).toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
              ])),
        ]));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. RECENT MOVEMENTS (last 20)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRecentMovements() {
    final recent = _ledger.take(20).toList();
    if (recent.isEmpty) {
      return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder)),
          child: const Row(children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: kTextHint),
            SizedBox(width: 10),
            Text('No movements recorded yet.',
                style: TextStyle(fontSize: 12, color: kTextSub)),
          ]));
    }

    final inTypes = {'opening','purchased','returned_in','transferred_in'};
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Group: today vs earlier
    final today   = recent.where((r) => (r['entry_date'] as String?)?.startsWith(todayStr) == true).toList();
    final earlier = recent.where((r) => !((r['entry_date'] as String?)?.startsWith(todayStr) == true)).toList();

    String typeLabel(String mt) => switch(mt) {
      'opening'            => 'Opening Stock',
      'purchased'          => 'Farm DC',
      'transferred_in'     => 'Transfer In',
      'transferred_out'    => 'Transfer Out',
      'delivered'          => 'Delivered',
      'returned_in'        => 'Customer Return',
      'mortality'          => 'Mortality',
      'shrinkage'          => 'Shrinkage',
      'shift_close_return' => 'Shift Return',
      'closing_stock'      => 'Write-Off',
      _ => mt.replaceAll('_', ' '),
    };

    Color typeColor(String mt) => switch(mt) {
    'opening'||'purchased'  => Colors.green.shade700,
    'transferred_in'       => Colors.teal,
    'returned_in'          => Colors.purple,
    'delivered'            => kPrimary,
    'transferred_out'      => Colors.indigo,
    'mortality'            => Colors.red,
    'shrinkage'            => Colors.deepOrange,
    'shift_close_return'   => Colors.purple.shade700,
    'closing_stock'        => Colors.grey,
    _ => kTextSub,
    };

    Widget movRow(Map<String,dynamic> row) {
      final mt    = row['movement_type'] as String? ?? '';
      final birds = (row['quantity_birds'] as num?)?.toInt()    ?? 0;
      final kg    = (row['quantity_kg']    as num?)?.toDouble() ?? 0;
      final date  = DateTime.tryParse(row['entry_date'] as String? ?? '');
      final agent = (row['delivery_agents'] as Map?)?['name'] as String?;
      final notes = row['notes'] as String?;
      final isIn  = inTypes.contains(mt);
      final c     = typeColor(mt);
      final sub   = agent ?? (notes?.isNotEmpty == true ? notes! : null);

      // Colored left-accent card using ClipRRect + Row pattern
      // (Flutter forbids borderRadius with non-uniform border colors)
      return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder)),
          clipBehavior: Clip.antiAlias,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 3-px colored accent bar (no borderRadius issue — clipped by parent)
                Container(width: 4, height: 56, color: c),
                const SizedBox(width: 12),
                // Left: label + subtitle
                Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(typeLabel(mt),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
                          if (sub != null) ...[
                            const SizedBox(height: 2),
                            Text(sub,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, color: kTextHint)),
                          ],
                        ]))),
                // Right: birds + kg + date
                Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${isIn ? '+' : '−'}$birds birds',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: isIn ? Colors.green.shade700 : Colors.red.shade700)),
                          if (kg > 0)
                            Text('${kg.toStringAsFixed(1)} kg',
                                style: const TextStyle(fontSize: 10, color: kTextSub)),
                          if (date != null)
                            Text(DateFormat('d MMM').format(date),
                                style: const TextStyle(fontSize: 9, color: kTextHint)),
                        ])),
              ]));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('RECENT MOVEMENTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8))),
      if (today.isNotEmpty) ...[
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
              const Text('TODAY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.green, letterSpacing: 0.6)),
            ])),
        ...today.map(movRow),
        const SizedBox(height: 8),
      ],
      if (earlier.isNotEmpty) ...[
        Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle)),
              const Text('EARLIER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kTextSub, letterSpacing: 0.6)),
            ])),
        ...earlier.map(movRow),
      ],
    ]);
  }
}

// ── Data class for stock flow rows ───────────────────────────────────────────
class _FlowRow {
  final String label, birds, kg;
  final bool isInflow;
  final Color color;
  final IconData icon;
  const _FlowRow(this.label, this.birds, this.kg, this.isInflow, this.color, this.icon);
}