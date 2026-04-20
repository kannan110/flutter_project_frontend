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
        if (hist[pid]!.length < 7) hist[pid]!.add(Map<String,dynamic>.from(h as Map));
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text("Today's Rates"),
      actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    body: _loading ? const LoadingList()
        : _products.isEmpty
            ? const EmptyState(icon: Icons.price_change_outlined, message: 'No products configured')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
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
                              : const Text('Not set',
                                  style: TextStyle(fontSize: 13, color: Colors.orange)),
                        ]),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20, color: kPrimary),
                          onPressed: () => _setRate(p),
                          tooltip: 'Update rate'),
                      ]),

                      // Rate history mini-timeline
                      if (hist.length > 1) ...[
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        const Text('History', style: TextStyle(fontSize: 10, color: kTextHint, letterSpacing: 0.5)),
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
                              Text('${Fmt.amount(r)}',
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
