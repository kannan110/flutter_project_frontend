import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/ui_mode_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class DeliveryHistoryScreen extends ConsumerStatefulWidget {
  const DeliveryHistoryScreen({super.key, required this.orderId});
  final String orderId;
  @override ConsumerState<DeliveryHistoryScreen> createState() => _S();
}

class _S extends ConsumerState<DeliveryHistoryScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _history = [];
  Map<String,dynamic>? _order;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final o = await _c.from('orders')
          .select('id,estimated_birds,total_quantity,fulfilled_birds,'
          'fulfilled_quantity,backorder_birds,backorder_quantity,'
          'partial_count,is_partial_delivery,status,'
          'retailers(shop_name)')
          .eq('id', widget.orderId)
          .maybeSingle();
      final h = await _c.from('delivery_history')
          .select('*')
          .eq('order_id', widget.orderId)
          .order('attempt_number');
      if (!mounted) return;
      setState(() {
        _order   = o;
        _history = List<Map<String,dynamic>>.from(h as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSimple = ref.watch(uiModeProvider).isSimple;
    if (isSimple && !_loading) {
      return _buildSimpleView();
    }
    final r = _order?['retailers'] as Map<String,dynamic>?;
    final totalBirds    = ((_order?['estimated_birds']   as num?)?.toInt()    ?? 0);
    final totalWeight   = ((_order?['total_quantity']     as num?)?.toDouble() ?? 0);
    final doneBirds     = ((_order?['fulfilled_birds']    as num?)?.toInt()    ?? 0);
    final doneWeight    = ((_order?['fulfilled_quantity'] as num?)?.toDouble() ?? 0);
    final remBirds      = ((_order?['backorder_birds']    as num?)?.toInt()    ?? 0);
    final remWeight     = ((_order?['backorder_quantity'] as num?)?.toDouble() ?? 0);
    final isPartial     = _order?['is_partial_delivery'] == true;
    final pct           = totalWeight > 0 ? (doneWeight / totalWeight * 100) : 0;

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r?['shop_name'] as String? ?? 'Delivery History',
                style: const TextStyle(fontSize: 16)),
            if (isPartial) const Text('Partial Order', style: TextStyle(fontSize: 11, color: Colors.orange)),
          ]),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading ? const LoadingList() : _history.isEmpty
          ? const EmptyState(icon: Icons.history, message: 'No delivery history yet')
          : ListView(padding: const EdgeInsets.all(16), children: [

        // ── Order progress banner ──────────────────────────────
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: isPartial ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isPartial ? Colors.orange.shade300 : Colors.green.shade300)),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                StatusBadge(_order?['status'] as String? ?? '', SC.order(_order?['status'] as String? ?? '')),
              ]),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      color: pct >= 100 ? Colors.green : Colors.orange)),
              const SizedBox(height: 6),
              Text('${pct.toStringAsFixed(0)}% fulfilled',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(children: [
                _pStat('Total', '$totalBirds birds\n${totalWeight.toStringAsFixed(1)} kg', Colors.blue),
                _pStat('Delivered', '$doneBirds birds\n${doneWeight.toStringAsFixed(1)} kg', Colors.green),
                _pStat('Remaining', '$remBirds birds\n${remWeight.toStringAsFixed(1)} kg',
                    remBirds > 0 ? Colors.orange : Colors.grey),
              ]),
            ])),
        const SizedBox(height: 16),

        // ── Attempt cards ──────────────────────────────────────
        const SectionHeader('DELIVERY ATTEMPTS'),
        ..._history.asMap().entries.map((e) {
          final idx = e.key;
          final h   = e.value;
          final birds   = (h['birds_delivered']     as num?)?.toInt()    ?? 0;
          final weight  = (h['weight_delivered_kg'] as num?)?.toDouble() ?? 0;
          final remB    = (h['birds_remaining']     as num?)?.toInt()    ?? 0;
          final remW    = (h['weight_remaining_kg'] as num?)?.toDouble() ?? 0;
          final cash    = (h['collected_amount']    as num?)?.toDouble() ?? 0;
          final partial = h['is_partial'] == true;
          final at      = h['delivered_at'] != null
              ? DateFormat('d MMM y · h:mm a').format(DateTime.parse(h['delivered_at']).toLocal())
              : '—';
          final isLast  = idx == _history.length - 1;

          return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: partial ? Colors.orange.shade200 : Colors.green.shade200, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: partial ? Colors.orange.shade50 : Colors.green.shade50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: partial ? Colors.orange : Colors.green,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Attempt ${h['attempt_number']}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(at, style: const TextStyle(fontSize: 11, color: kTextSub))),
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: partial ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(partial ? '⚡ PARTIAL' : '✅ COMPLETE',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                                  color: partial ? Colors.orange.shade700 : Colors.green.shade700))),
                    ])),
                Padding(padding: const EdgeInsets.all(14), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Agent
                  Row(children: [
                    const Icon(Icons.delivery_dining, size: 14, color: kPrimary),
                    const SizedBox(width: 6),
                    Text(h['agent_name'] as String? ?? '—',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  // Stats
                  Row(children: [
                    _aStat('Delivered', '$birds birds', Colors.teal),
                    _aStat('Weight', '${weight.toStringAsFixed(1)} kg', kPrimary),
                    _aStat('Collected', Fmt.amount(cash), Colors.green),
                    if (partial) _aStat('Remaining', '$remB birds', Colors.orange),
                  ]),
                  if (partial && remW > 0) Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${remW.toStringAsFixed(1)} kg remaining after this delivery',
                          style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
                  if ((h['notes'] as String?)?.isNotEmpty == true) Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(h['notes'] as String,
                          style: const TextStyle(fontSize: 11, color: kTextSub))),
                  // Last attempt with remaining — show pending badge
                  if (isLast && partial && remB > 0) Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200)),
                          child: Text('⏳ Pending: $remB birds · ${remW.toStringAsFixed(1)} kg — awaiting next delivery',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange)))),
                ])),
              ]));
        }),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _pStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    const SizedBox(height: 2),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]));

  Widget _aStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
  ]));

  // ══════════════════════════════════════════════════════════════════════════
  // SIMPLE MODE VIEW — large cards, emoji-first, minimal info
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSimpleView() {
    final r = _order?['retailers'] as Map<String,dynamic>?;
    final totalBirds = ((_order?['estimated_birds'] as num?)?.toInt() ?? 0);
    final totalWeight = ((_order?['total_quantity'] as num?)?.toDouble() ?? 0);
    final doneBirds = ((_order?['fulfilled_birds'] as num?)?.toInt() ?? 0);
    final doneWeight = ((_order?['fulfilled_quantity'] as num?)?.toDouble() ?? 0);
    final remBirds = ((_order?['backorder_birds'] as num?)?.toInt() ?? 0);
    final remWeight = ((_order?['backorder_quantity'] as num?)?.toDouble() ?? 0);
    final isPartial = _order?['is_partial_delivery'] == true;
    final pct = totalWeight > 0 ? (doneWeight / totalWeight * 100) : 0;
    final shopName = r?['shop_name'] as String? ?? 'Delivery History';

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () { if (context.canPop()) context.pop(); else context.go(R.agentDeliveries); }),
        title: Text('📋 $shopName',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _history.isEmpty
          ? Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📭', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text('No delivery history yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextSub)),
        ]),
      )
          : ListView(padding: const EdgeInsets.all(16), children: [
        // ── Progress hero card ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isPartial
                  ? [const Color(0xFFE65100), const Color(0xFFEF6C00)]
                  : [const Color(0xFF1B5E20), const Color(0xFF2E7D32)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(children: [
            Text(isPartial ? '⚡' : '✅', style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(shopName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text('${pct.toStringAsFixed(0)}% delivered',
                style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            // KPIs
            Row(children: [
              _simpleKpi('📦', '$totalBirds', 'Ordered'),
              _simpleKpi('✅', '$doneBirds', 'Delivered'),
              _simpleKpi('⏳', '$remBirds', 'Pending'),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        // ── Attempt cards ──────────────────────────────────
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('DELIVERY ATTEMPTS',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
        ),
        ..._history.asMap().entries.map((e) {
          final idx = e.key;
          final h = e.value;
          final birds = (h['birds_delivered'] as num?)?.toInt() ?? 0;
          final weight = (h['weight_delivered_kg'] as num?)?.toDouble() ?? 0;
          final remB = (h['birds_remaining'] as num?)?.toInt() ?? 0;
          final remW = (h['weight_remaining_kg'] as num?)?.toDouble() ?? 0;
          final cash = (h['collected_amount'] as num?)?.toDouble() ?? 0;
          final partial = h['is_partial'] == true;
          final at = h['delivered_at'] != null
              ? DateFormat('d MMM, h:mm a').format(DateTime.parse(h['delivered_at']).toLocal())
              : '—';
          final isLast = idx == _history.length - 1;
          final agentName = h['agent_name'] as String? ?? '—';

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: partial ? Colors.orange.shade200 : Colors.green.shade200,
                  width: partial ? 2 : 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header with attempt badge
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: partial ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Attempt ${h['attempt_number']}',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(at, style: const TextStyle(fontSize: 12, color: kTextSub))),
              ]),
              const SizedBox(height: 14),
              // Agent
              Row(children: [
                const Text('🚚', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(agentName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(partial ? '⚡ PARTIAL' : '✅ COMPLETE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: partial ? Colors.orange.shade700 : Colors.green.shade700)),
              ]),
              const SizedBox(height: 14),
              // Stats
              Row(children: [
                _simpleStat('🐔', '$birds', 'birds'),
                _simpleStat('⚖️', '${weight.toStringAsFixed(1)}', 'kg'),
                _simpleStat('💰', Fmt.amount(cash), 'cash'),
                if (partial) _simpleStat('⏳', '$remB', 'left'),
              ]),
              // Notes
              if ((h['notes'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(h['notes'] as String,
                      style: const TextStyle(fontSize: 13, color: kTextSub)),
                ),
              ],
              // Pending badge for last attempt
              if (isLast && partial && remB > 0) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text('⏳ Pending: $remB birds · ${remW.toStringAsFixed(1)} kg',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.orange)),
                ),
              ],
            ]),
          );
        }),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _simpleKpi(String emoji, String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
            textAlign: TextAlign.center),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
            textAlign: TextAlign.center),
      ]),
    ),
  );

  Widget _simpleStat(String emoji, String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 2),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center),
        ]),
        Text(label,
            style: const TextStyle(fontSize: 10, color: kTextHint),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}