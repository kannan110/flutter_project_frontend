import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class RatesScreen extends ConsumerStatefulWidget {
  const RatesScreen({super.key});
  @override ConsumerState<RatesScreen> createState() => _S();
}

class _S extends ConsumerState<RatesScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _products  = [];
  Map<String, double>       _rates     = {};
  Map<String, List<Map<String,dynamic>>> _history = {}; // product_id -> last 5 rates
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final products = await _c.from('master_products')
          .select('id,name,unit').eq('is_active', true).order('name');
      final history = await _c.from('rate_history')
          .select('product_id,rate_per_kg,effective_date')
          .eq('trader_id', tid)
          .order('effective_date', ascending: false)
          .limit(200);

      final Map<String, double> rates = {};
      final Map<String, List<Map<String,dynamic>>> hist = {};

      for (final h in history as List) {
        final pid  = h['product_id'] as String;
        final rate = (h['rate_per_kg'] as num).toDouble();
        if (!rates.containsKey(pid)) rates[pid] = rate;
        hist.putIfAbsent(pid, () => []);
        if (hist[pid]!.length < 30) hist[pid]!.add(Map<String,dynamic>.from(h as Map)); // U8 FIX: was 7, now 30 for full history view
      }

      if (!mounted) return;
      setState(() {
        _products = List<Map<String,dynamic>>.from(products);
        _rates    = rates;
        _history  = hist;
        _loading  = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _setRate(Map<String,dynamic> product) async {
    final tid  = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final pid  = product['id'] as String;
    final ctrl = TextEditingController(text: _rates[pid]?.toStringAsFixed(2) ?? '');

    final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rate — ${product['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Rate per kg', prefixText: '₹', suffixText: '/kg')),
          if ((_history[pid]?.isNotEmpty) == true) ...[
            const SizedBox(height: 14),
            const Text('Recent rates', style: TextStyle(fontSize: 11, color: kTextHint)),
            const SizedBox(height: 6),
            ..._history[pid]!.take(4).map((h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(DateFormat('d MMM y').format(DateTime.parse(h['effective_date'] as String)),
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                  Text('${Fmt.amount((h['rate_per_kg'] as num).toDouble())}/kg',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ]))),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v != null && v > 0) Navigator.pop(ctx, v);
              },
              child: const Text('Save Rate')),
        ]));

    ctrl.dispose();
    if (result == null) return;

    try {
      await _c.from('rate_history').insert({
        'trader_id':      tid,
        'product_id':     pid,
        'rate_per_kg':    result,
        'effective_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      });
      if (mounted) {
        setState(() {
          _rates[pid] = result;
          _history.putIfAbsent(pid, () => []).insert(0, {
            'rate_per_kg':    result,
            'effective_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          });
          if (_history[pid]!.length > 7) _history[pid]!.removeLast();
        });
        showSuccess(context, 'Rate updated to ${Fmt.amount(result)}/kg ✓');
      }
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  // U8 FIX: Full rate history bottom sheet — shows all entries beyond the 5 shown inline.
  void _showFullHistory(BuildContext ctx, String productName, List<Map<String,dynamic>> hist) {
    showModalBottomSheet(
        context: ctx,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (bctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (_, ctrl) => Column(children: [
              // Handle + header
              Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Column(children: [
                Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.history, color: kPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Rate History — $productName',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                  Text('${hist.length} entries',
                      style: const TextStyle(fontSize: 12, color: kTextHint)),
                ]),
                const SizedBox(height: 10),
                const Divider(height: 1),
              ])),
              // Full history list
              Expanded(child: ListView.separated(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  itemCount: hist.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final h = hist[i];
                    final d = DateTime.tryParse(h['effective_date'] as String? ?? '');
                    final r = (h['rate_per_kg'] as num).toDouble();
                    final isLatest = i == 0;
                    // Trend arrow vs previous
                    double? prevR;
                    if (i < hist.length - 1) prevR = (hist[i + 1]['rate_per_kg'] as num).toDouble();
                    final trend = prevR != null ? r.compareTo(prevR) : 0;
                    return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                            color: isLatest ? kPrimary.withValues(alpha: 0.06) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isLatest ? kPrimary.withValues(alpha: 0.2) : kBorder)),
                        child: Row(children: [
                          Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                  color: isLatest ? kPrimary.withValues(alpha: 0.12) : Colors.grey.shade100,
                                  shape: BoxShape.circle),
                              child: Center(child: Text('${hist.length - i}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                      color: isLatest ? kPrimary : kTextHint)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(d != null ? DateFormat('d MMMM y').format(d) : '—',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: isLatest ? kPrimary : kTextMain)),
                            if (isLatest)
                              const Text('Current rate', style: TextStyle(fontSize: 10, color: kPrimary)),
                          ])),
                          if (trend != 0) ...[
                            Icon(trend > 0 ? Icons.trending_up : Icons.trending_down,
                                color: trend > 0 ? Colors.green : Colors.red, size: 16),
                            const SizedBox(width: 4),
                          ],
                          Text(Fmt.amount(r),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                                  color: isLatest ? kPrimary : kTextMain)),
                          const Text('/kg', style: TextStyle(fontSize: 10, color: kTextHint)),
                        ]));
                  })),
            ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text("Today's Rates"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList()
        : _products.isEmpty
        ? const EmptyState(icon: Icons.price_change_outlined, message: 'No products configured')
        : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p    = _products[i];
          final pid  = p['id'] as String;
          final rate = _rates[pid];
          final hist = _history[pid] ?? [];

          // Trend: compare current to previous
          double? prevRate;
          if (hist.length >= 2) prevRate = (hist[1]['rate_per_kg'] as num).toDouble();
          final trend = (rate != null && prevRate != null)
              ? rate.compareTo(prevRate) : 0;

          return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rate == null ? Colors.orange.shade200 : kBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.set_meal_outlined, color: kPrimary, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'] as String,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('per ${p['unit'] ?? 'kg'}',
                        style: const TextStyle(fontSize: 11, color: kTextHint)),
                  ])),
                  Row(children: [
                    if (trend != 0) Icon(
                        trend > 0 ? Icons.trending_up : Icons.trending_down,
                        color: trend > 0 ? Colors.green : Colors.red, size: 18),
                    const SizedBox(width: 6),
                    rate != null
                        ? Text('${Fmt.amount(rate)}/kg',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kPrimary))
                        : GestureDetector(
                      onTap: () => _setRate(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text('Set Rate →',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: Colors.orange)),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 6),
                  IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: kPrimary),
                      onPressed: () => _setRate(p),
                      tooltip: 'Update rate'),
                ]),

                // U8 FIX: Rate history mini-timeline + "View all" link
                if (hist.length > 1) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('History', style: TextStyle(fontSize: 10, color: kTextHint, letterSpacing: 0.5)),
                    const Spacer(),
                    // U8 FIX: Show "View all X entries" when there are more than 5
                    if (hist.length > 5)
                      GestureDetector(
                          onTap: () => _showFullHistory(context, p['name'] as String, hist),
                          child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: kPrimary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.history, size: 11, color: kPrimary),
                                const SizedBox(width: 4),
                                Text('View all ${hist.length}',
                                    style: const TextStyle(fontSize: 10, color: kPrimary, fontWeight: FontWeight.w700)),
                              ]))),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: hist.take(5).toList().asMap().entries.map((e) {
                    final h = e.value;
                    final d = DateTime.tryParse(h['effective_date'] as String? ?? '');
                    final r = (h['rate_per_kg'] as num).toDouble();
                    final isLatest = e.key == 0;
                    return Expanded(child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                        decoration: BoxDecoration(
                            color: isLatest ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6)),
                        child: Column(children: [
                          Text(Fmt.amount(r),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                  color: isLatest ? kPrimary : kTextSub)),
                          Text(d != null ? DateFormat('d MMM').format(d) : '--',
                              style: const TextStyle(fontSize: 9, color: kTextHint)),
                        ])));
                  }).toList()),
                ],
              ]));
        }),
  );
}