import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _S();
}

class _S extends ConsumerState<StockScreen> {
  final _c = Supabase.instance.client;
  List<StockPosition> _positions = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _challans = [];
  bool _loading = true;
  int _tab = 0; // 0=Summary, 1=Movements, 2=DCs

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final r0 =
          await _c.rpc('get_available_stock', params: {'p_trader_id': tid});
      final r1 = await _c
          .from('stock_ledger')
          .select(
              'id,entry_date,movement_type,quantity_birds,quantity_kg,notes,master_products(name)')
          .eq('trader_id', tid)
          .order('created_at', ascending: false)
          .limit(60);
      final r2 = await _c
          .from('master_products')
          .select('id,name')
          .eq('is_active', true);
      final r3 = await _c
          .from('delivery_challans')
          .select(
              'id,dc_number,dc_date,farmer_name,farm_location,vehicle_number,'
              'bird_count,gross_weight,empty_crate_weight,net_weight,'
              'avg_bird_weight,crates_count,farm_rate,dc_photo_url,created_at,'
              'delivery_batches(id,delivery_agents(name))')
          .eq('trader_id', tid)
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;
      setState(() {
        _positions = ((r0 as List?) ?? [])
            .map((s) => StockPosition.fromMap(s as Map<String, dynamic>))
            .toList();
        _ledger = List<Map<String, dynamic>>.from((r1 as List?) ?? []);
        _products = List<Map<String, dynamic>>.from((r2 as List?) ?? []);
        _challans = List<Map<String, dynamic>>.from((r3 as List?) ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted)
        showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _recordOpening() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (_products.isEmpty || !mounted) return;

    Map<String, dynamic>? selProd;
    final birdsCtrl = TextEditingController();
    final kgCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Record Opening Stock',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Map<String, dynamic>>(
                      hint: const Text('Product *'),
                      items: _products
                          .map((p) => DropdownMenuItem(
                              value: p, child: Text(p['name'] as String)))
                          .toList(),
                      onChanged: (v) => selProd = v),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            controller: birdsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Birds *', suffixText: 'birds'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) =>
                                FocusScope.of(context).nextFocus(),
                            controller: kgCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Weight (kg) *', suffixText: 'kg'))),
                  ]),
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
                        if (selProd == null) return;
                        final b = int.tryParse(birdsCtrl.text);
                        final k = double.tryParse(kgCtrl.text);
                        if (b == null || k == null || b <= 0 || k <= 0) return;
                        Navigator.of(ctx, rootNavigator: true).pop();
                        try {
                          await _c.rpc('record_opening_stock', params: {
                            'p_trader_id': tid,
                            'p_product_id': selProd!['id'],
                            'p_birds': b,
                            'p_kg': k,
                            'p_notes': notesCtrl.text.trim().isEmpty
                                ? null
                                : notesCtrl.text.trim(),
                            'p_created_by': uid,
                          });
                          _load();
                          if (mounted)
                            showSuccess(context, 'Opening stock recorded ✓');
                        } catch (e) {
                          if (mounted) showError(context, e.toString());
                        }
                      },
                      child: const Text('Save')),
                ])));
    birdsCtrl.dispose();
    kgCtrl.dispose();
    notesCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
            backgroundColor: kSurface,
            title: const Text('Stock Management'),
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
            ]),
        // Reserve space so FAB clears the parent TraderShell glass bottom nav
        bottomNavigationBar: const SizedBox(height: 80),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _recordOpening,
            icon: const Icon(Icons.add),
            label: const Text('Opening Stock')),
        body: _loading
            ? const LoadingList()
            : Column(children: [
                // Tab bar
                Container(
                    color: Colors.white,
                    child: Row(children: [
                      _tabBtn(0, 'Summary'),
                      _tabBtn(1, 'Movements'),
                      _tabBtn(2, 'DCs (${_challans.length})'),
                    ])),
                const Divider(height: 1),
                Expanded(
                    child:
                        RefreshIndicator(onRefresh: _load, child: _buildTab())),
              ]),
      );

  Widget _tabBtn(int idx, String label) => Expanded(
      child: InkWell(
          onTap: () => setState(() => _tab = idx),
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: _tab == idx ? kPrimary : Colors.transparent,
                          width: 2))),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _tab == idx ? kPrimary : kTextHint)))));

  Widget _buildTab() {
    switch (_tab) {
      case 0:
        return _buildSummary();
      case 1:
        return _buildMovements();
      case 2:
        return _buildDCs();
      default:
        return _buildSummary();
    }
  }

  Widget _buildSummary() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        if (_positions.isEmpty)
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200)),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'No stock yet. Tap + to record opening stock or add a DC.',
                        style: TextStyle(fontSize: 13, color: Colors.orange))),
              ]))
        else
          ..._positions.map((p) => _stockCard(p)),
      ]);

  Widget _stockCard(StockPosition p) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: p.isNegative
                  ? Colors.red.shade200
                  : p.hasLowStock
                      ? Colors.orange.shade200
                      : kBorder)),
      child: Column(children: [
        // Header
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Expanded(
                  child: Text(p.productName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800))),
              if (p.isNegative)
                const StatusBadge('NEGATIVE', Colors.red)
              else if (p.hasLowStock)
                const StatusBadge('LOW', Colors.orange)
              else
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Text('OK',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.w700))),
            ])),
        // Available (big)
        Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.isNegative
                    ? Colors.red.shade50
                    : p.hasLowStock
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${p.availableBirds}',
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: p.isNegative
                          ? Colors.red
                          : p.hasLowStock
                              ? Colors.orange
                              : Colors.green)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('birds available now',
                    style: TextStyle(fontSize: 13, color: kTextSub)),
                Text('${p.availableKg.toStringAsFixed(1)} kg available',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kTextMain)),
                Text('Today DC: +${p.todayPurchased} birds',
                    style: const TextStyle(fontSize: 11, color: Colors.blue)),
              ]),
            ])),
        // CORRECTED breakdown — no double-counting.
        // available_birds = purchased - delivered - closing_stock - mortality
        // in_house_birds = birds at stock point (shift_close_return, subset of available)
        // agent_birds = available - in_house (still with active agents)
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(children: [
              // Primary: available breakdown (most important to trader)
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: kBgGrey, borderRadius: BorderRadius.circular(8)),
                  child: Column(children: [
                    const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Text('LOCATION OF AVAILABLE STOCK',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: kTextHint,
                                  letterSpacing: 0.6)),
                        ])),
                    Row(children: [
                      _stockStat(
                          'In-House',
                          '${p.inHouseBirds}',
                          '${p.inHouseKg.toStringAsFixed(0)} kg',
                          p.inHouseBirds > 0 ? Colors.teal : kTextHint),
                      _stockStat(
                          'With Agents',
                          '${p.agentBirds}',
                          '${p.agentKg.toStringAsFixed(0)} kg',
                          p.agentBirds > 0 ? Colors.orange : kTextHint),
                      _stockStat(
                          'Total Available',
                          '${p.availableBirds}',
                          '${p.availableKg.toStringAsFixed(0)} kg',
                          p.isNegative
                              ? Colors.red
                              : p.hasLowStock
                                  ? Colors.orange
                                  : Colors.green),
                    ]),
                  ])),
              const SizedBox(height: 8),
              // Secondary: system-wide totals
              Row(children: [
                _stockStat('Total Purchased', '${p.totalInBirds}',
                    '${p.totalInKg.toStringAsFixed(0)} kg', Colors.blue),
                _stockStat('Total Sold', '${p.totalOutBirds}',
                    '${p.totalOutKg.toStringAsFixed(0)} kg', kPrimary),
                _stockStat('Mortality', '${p.mortalityBirds}', '',
                    p.mortalityBirds > 0 ? Colors.red : kTextHint),
                _stockStat(
                    'Shrinkage',
                    p.shrinkageKg > 0
                        ? '${p.shrinkageKg.toStringAsFixed(1)} kg'
                        : '—',
                    '',
                    p.shrinkageKg > 0 ? Colors.deepOrange : kTextHint),
              ]),
              if (p.transferredInBirds > 0 || p.transferredOutBirds > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.swap_horiz,
                              size: 12, color: Colors.teal),
                          const SizedBox(width: 6),
                          Text(
                              'Transfers: +${p.transferredInBirds} in  ·  −${p.transferredOutBirds} out  '
                              '(net ${p.transferredInBirds - p.transferredOutBirds} — location change only, no stock impact)',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.teal)),
                        ]))),
            ])),
      ]));

  Widget _stockStat(String l, String v, String sub, Color c) => Expanded(
          child: Column(children: [
        Text(v,
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
        if (sub.isNotEmpty)
          Text(sub, style: const TextStyle(fontSize: 9, color: kTextSub)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
      ]));

  Widget _buildMovements() {
    if (_ledger.isEmpty) {
      return const EmptyState(
          icon: Icons.receipt_long_outlined, message: 'No movements recorded');
    }
    // BUG 5 FIX: transferred_in is an INFLOW — must be in isIn list so it shows '+'
    final isIn = (String t) =>
        ['opening', 'purchased', 'returned_in', 'transferred_in'].contains(t);
    return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _ledger.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final l = _ledger[i];
          final prod = l['master_products'] as Map<String, dynamic>?;
          final mt = l['movement_type'] as String? ?? '—';
          final date = DateTime.tryParse(l['entry_date'] as String? ?? '');
          final birds = (l['quantity_birds'] as num?)?.toInt() ?? 0;
          final kg = (l['quantity_kg'] as num?)?.toDouble() ?? 0;
          final c = _movementColor(mt);
          final inward = isIn(mt);
          return Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      const Border.fromBorderSide(BorderSide(color: kBorder))),
              child: ListTile(
                  dense: true,
                  leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: Icon(_movementIcon(mt), color: c, size: 16)),
                  title: Text(
                      '${prod?['name'] ?? '—'} · ${mt.replaceAll('_', ' ')}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(l['notes'] as String? ?? '',
                      style: const TextStyle(fontSize: 10, color: kTextHint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${inward ? '+' : '−'}$birds birds',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c)),
                        if (kg > 0)
                          Text('${kg.toStringAsFixed(1)} kg',
                              style: const TextStyle(
                                  fontSize: 10, color: kTextHint)),
                        if (date != null)
                          Text(DateFormat('d MMM').format(date),
                              style: const TextStyle(
                                  fontSize: 9, color: kTextHint)),
                      ])));
        });
  }

  Widget _buildDCs() {
    if (_challans.isEmpty) {
      return const EmptyState(
          icon: Icons.receipt_long_outlined,
          message: 'No DCs recorded',
          sub: 'DCs are created when agents pick up from farms');
    }
    return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _challans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final ch = _challans[i];
          final batch = ch['delivery_batches'] as Map<String, dynamic>?;
          final agent = batch?['delivery_agents'] as Map<String, dynamic>?;
          final date = DateTime.tryParse(ch['dc_date'] as String? ?? '');
          final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
          final birds = (ch['bird_count'] as num?)?.toInt() ?? 0;
          final crates = (ch['crates_count'] as num?)?.toInt() ?? 0;
          final rate = (ch['farm_rate'] as num?)?.toDouble();
          final hasImg = ch['dc_photo_url'] != null;

          return Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      const Border.fromBorderSide(BorderSide(color: kBorder))),
              child: Column(children: [
                // Header row
                Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.1),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.receipt_long_outlined,
                              color: kPrimary, size: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(ch['dc_number'] as String? ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            if (date != null)
                              Text(DateFormat('d MMM y').format(date),
                                  style: const TextStyle(
                                      fontSize: 11, color: kTextHint)),
                          ])),
                      if (hasImg)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.photo_outlined,
                                      size: 12, color: Colors.green),
                                  SizedBox(width: 3),
                                  Text('Photo',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green,
                                          fontWeight: FontWeight.w700)),
                                ])),
                    ])),
                // Farm details
                Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ch['farmer_name'] != null)
                            Row(children: [
                              const Icon(Icons.agriculture,
                                  size: 13, color: kTextHint),
                              const SizedBox(width: 4),
                              Text(ch['farmer_name'] as String,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              if (ch['farm_location'] != null) ...[
                                const Text(' · ',
                                    style: TextStyle(color: kTextHint)),
                                Expanded(
                                    child: Text(ch['farm_location'] as String,
                                        style: const TextStyle(
                                            fontSize: 12, color: kTextSub),
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ]),
                          if (ch['vehicle_number'] != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(children: [
                                  const Icon(Icons.local_shipping_outlined,
                                      size: 13, color: kTextHint),
                                  const SizedBox(width: 4),
                                  Text(ch['vehicle_number'] as String,
                                      style: const TextStyle(
                                          fontSize: 11, color: kTextSub)),
                                  if (agent != null) ...[
                                    const Text(' · Agent: ',
                                        style: TextStyle(
                                            fontSize: 11, color: kTextHint)),
                                    Text(agent['name'] as String? ?? '—',
                                        style: const TextStyle(
                                            fontSize: 11, color: kTextSub)),
                                  ],
                                ])),
                        ])),
                // Stats row
                Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12))),
                    child: Row(children: [
                      _dcStat('Birds', '$birds', kPrimary),
                      _dcStat('Net Wt', '${net.toStringAsFixed(1)} kg',
                          Colors.teal),
                      _dcStat('Crates', '$crates', Colors.blue),
                      _dcStat(
                          'Rate',
                          rate != null ? '₹${rate.toStringAsFixed(0)}/kg' : '—',
                          Colors.orange),
                    ])),
              ]));
        });
  }

  Widget _dcStat(String l, String v, Color c) => Expanded(
          child: Column(children: [
        Text(v,
            style:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint)),
      ]));

  Color _movementColor(String t) => switch (t) {
        'opening' => Colors.blue,
        'purchased' => Colors.green,
        'returned_in' => Colors.purple,
        'transferred_in' =>
          Colors.teal, // BUG 5 FIX: was grey (looked like outflow)
        'delivered' => kPrimary,
        'allocated' => Colors.orange,
        'transferred_out' =>
          Colors.indigo, // BUG 5 FIX: distinct colour from delivered
        'mortality' => Colors.red,
        'shrinkage' => Colors.deepOrange,
        'shift_close_return' => Colors.purple,
        'closing_stock' => Colors.grey,
        _ => Colors.grey,
      };

  IconData _movementIcon(String t) => switch (t) {
        'opening' => Icons.home_outlined,
        'purchased' => Icons.add_shopping_cart,
        'returned_in' => Icons.assignment_return_outlined,
        'transferred_in' => Icons.swap_horiz, // BUG 5 FIX: distinct icon
        'transferred_out' => Icons.swap_horiz,
        'delivered' => Icons.local_shipping_outlined,
        'allocated' => Icons.inventory_outlined,
        'mortality' => Icons.sentiment_very_dissatisfied_outlined,
        'shrinkage' => Icons.compress_outlined,
        'shift_close_return' => Icons.assignment_return_outlined,
        'closing_stock' => Icons.lock_outline,
        _ => Icons.circle_outlined,
      };
}
