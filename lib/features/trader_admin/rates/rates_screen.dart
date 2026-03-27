import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class RatesScreen extends ConsumerStatefulWidget {
  const RatesScreen({super.key});
  @override
  ConsumerState<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends ConsumerState<RatesScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  Map<String, double> _currentRates = {};
  Map<String, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { for (final c in _controllers.values) c.dispose(); super.dispose(); }

  Future<void> _load() async {
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (traderId == null) return;
    setState(() => _loading = true);
    try {
      final products = List<Map<String, dynamic>>.from(
        await _client.from('master_products').select('id,name,name_tamil,category').eq('is_active', true).order('category'));
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final rates  = List<Map<String, dynamic>>.from(
        await _client.from('rate_history').select('product_id, rate_per_kg')
            .eq('trader_id', traderId).lte('effective_date', today).order('effective_date', ascending: false));

      final Map<String, double> currentRates = {};
      for (final r in rates) {
        final pid = r['product_id'] as String;
        currentRates.putIfAbsent(pid, () => (r['rate_per_kg'] as num).toDouble());
      }
      final Map<String, TextEditingController> ctrls = {};
      for (final p in products) {
        final pid = p['id'] as String;
        ctrls[pid] = TextEditingController(text: currentRates[pid]?.toStringAsFixed(2) ?? '');
      }
      setState(() { _products = products; _currentRates = currentRates; _controllers = ctrls; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showError(context, 'Failed to load rates');
    }
  }

  Future<void> _saveAll() async {
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    final userId   = ref.read(appUserProvider).valueOrNull?.userId;
    if (traderId == null) return;
    setState(() => _saving = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final p in _products) {
        final pid  = p['id'] as String;
        final text = _controllers[pid]?.text.trim() ?? '';
        final rate = double.tryParse(text);
        if (rate != null && rate > 0) {
          await _client.from('rate_history').upsert({
            'trader_id': traderId, 'product_id': pid,
            'rate_per_kg': rate, 'effective_date': today, 'set_by': userId,
          }, onConflict: 'trader_id,product_id,effective_date');
        }
      }
      showSuccess(context, 'Rates saved for today');
      _load();
    } catch (e) {
      showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Daily Rates'),
          Text(DateFormat('d MMM y').format(DateTime.now()),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFF9E9E9E))),
        ]),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _saveAll,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save All', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppTheme.primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Rates set here will apply to all orders created today. Order items lock the rate at order creation time.',
                      style: TextStyle(fontSize: 12, color: AppTheme.primary))),
                ]),
              ),
              ..._products.map((p) => _RateCard(
                product: p,
                currentRate: _currentRates[p['id'] as String],
                controller: _controllers[p['id'] as String]!,
              )),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _saving ? null : _saveAll, child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save All Rates')),
            ]),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.product, required this.currentRate, required this.controller});
  final Map<String, dynamic> product;
  final double? currentRate;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final cat = product['category'] as String? ?? '';
    final icon = switch (cat) {
      'broiler' => Icons.set_meal_outlined,
      'country' => Icons.egg_outlined,
      'layer'   => Icons.egg_alt_outlined,
      'egg'     => Icons.egg_outlined,
      _         => Icons.category_outlined,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppTheme.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (product['name_tamil'] != null)
            Text(product['name_tamil'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        ])),
        SizedBox(
          width: 110,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '₹/kg',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ]),
    );
  }
}
