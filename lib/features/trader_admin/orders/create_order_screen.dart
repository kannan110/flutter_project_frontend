import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// TASK 1: Multi-product order creation
class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _S();
}

class _OrderLine {
  Map<String, dynamic>? product;
  final birds = TextEditingController();
  final avgWt = TextEditingController();
  final totalWt = TextEditingController();
  final rate = TextEditingController();
  bool wtManual = false;
  double? suggestRate;
  // Phase 2: rate snapshot
  String?  rateSource;
  String?  rateSourceLabel;
  String?  rateZoneId;
  String?  rateZoneName;
  // Phase 2b: adjustment snapshot
  double?  baseRate;
  String?  pricingType;
  double?  adjustmentValue;

  double get kg  => double.tryParse(totalWt.text.trim()) ?? 0;
  double get r   => double.tryParse(rate.text.trim()) ?? 0;
  int    get b   => int.tryParse(birds.text.trim()) ?? 0;
  double get amt => kg * r;

  void autoCalcWeight() {
    if (wtManual) return;
    final bi = int.tryParse(birds.text.trim()) ?? 0;
    final av = double.tryParse(avgWt.text.trim()) ?? 0;
    if (bi > 0 && av > 0) totalWt.text = (bi * av).toStringAsFixed(2);
  }

  void dispose() {
    birds.dispose();
    avgWt.dispose();
    totalWt.dispose();
    rate.dispose();
  }
}

class _S extends ConsumerState<CreateOrderScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _retailers = [], _products = [];
  Map<String, dynamic>? _selRetailer;
  List<_OrderLine> _lines = [_OrderLine()];
  bool _saving = false, _dataLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final r = await _c
          .from('retailers')
          .select('id,shop_name')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .order('shop_name');
      // Phase 3: only show trader-enabled products (not all master_products)
      final p = await _c
          .rpc('get_trader_enabled_products', params: {'p_trader_id': tid});
      if (mounted)
        setState(() {
          _retailers = List<Map<String, dynamic>>.from(r);
          _products  = List<Map<String, dynamic>>.from(p as List? ?? []);
          _dataLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _dataLoading = false);
    }
  }

  Future<void> _fetchRate(int idx) async {
    final line = _lines[idx];
    if (_selRetailer == null || line.product == null) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final kg = line.kg > 0 ? line.kg : line.b * 1.8;
    if (kg <= 0) return;
    try {
      // Phase 2b: Use v4 cascade (Customer adj → Zone → Default)
      final res = await _c.rpc('get_effective_rate_v4', params: {
        'p_trader_id':   tid,
        'p_retailer_id': _selRetailer!['id'],
        'p_product_id':  line.product!['id'],
        'p_quantity_kg': kg,
      });
      // v4 returns a TABLE row; take first result
      final rows = res as List?;
      if (rows == null || rows.isEmpty) return;
      final row          = rows.first as Map<String, dynamic>;
      final rate         = (row['rate'] as num?)?.toDouble() ?? 0;
      final baseRate     = (row['base_rate'] as num?)?.toDouble();
      final source       = row['rate_source'] as String? ?? 'default_rate';
      final label        = row['rate_label'] as String? ?? '';
      final pricingType  = row['pricing_type'] as String? ?? 'none';
      final adjValue     = (row['adjustment_value'] as num?)?.toDouble() ?? 0;
      final zoneId       = row['zone_id'] as String?;
      final zoneName     = row['zone_name'] as String?;
      if (mounted && rate > 0) {
        setState(() {
          line.suggestRate     = rate;
          line.baseRate        = baseRate;
          line.rateSource      = source;
          line.rateSourceLabel = label;
          line.pricingType     = pricingType;
          line.adjustmentValue = adjValue;
          line.rateZoneId      = zoneId;
          line.rateZoneName    = zoneName;
          if (line.rate.text.isEmpty) line.rate.text = rate.toStringAsFixed(2);
        });
      }
    } catch (_) {}
  }

  void _addLine() {
    setState(() => _lines.add(_OrderLine()));
  }

  void _removeLine(int idx) {
    if (_lines.length == 1) return;
    _lines[idx].dispose();
    setState(() => _lines.removeAt(idx));
  }

  double get _totalAmt => _lines.fold(0.0, (s, l) => s + l.amt);

  double get _totalKg => _lines.fold(0.0, (s, l) => s + l.kg);

  int get _totalBirds => _lines.fold(0, (s, l) => s + l.b);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_selRetailer == null) {
      showError(context, 'Select a customer');
      return;
    }
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].product == null) {
        showError(context, 'Select product for line ${i + 1}');
        return;
      }
      if (_lines[i].kg <= 0) {
        showError(context, 'Enter weight for line ${i + 1}');
        return;
      }
    }

    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _saving = true);
    try {
      // Use first line's product_id on the order header (for backward compat)
      final firstLine = _lines.first;
      final order = await _c
          .from('orders')
          .insert({
        'trader_id': tid,
        'retailer_id': _selRetailer!['id'],
        'product_id': firstLine.product!['id'],
        'status': 'pending', // auto-confirmed by DB trigger
        'order_date': DateTime.now().toIso8601String().split('T')[0],
        if (_totalBirds > 0) 'estimated_birds': _totalBirds,
        if (_totalKg > 0) 'total_quantity': _totalKg,
        if (_totalAmt > 0) 'total_amount': _totalAmt,
        if (firstLine.r > 0) 'final_price': firstLine.r,
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
      })
          .select()
          .single();

      // Insert one order_item per product line — with Phase 2b full rate snapshot
      for (final line in _lines) {
        await _c.from('order_items').insert({
          'order_id':        order['id'],
          'trader_id':       tid,
          'product_id':      line.product!['id'],
          if (line.b > 0)   'bird_count':   line.b,
          if (line.kg > 0)  'total_weight': line.kg,
          if (line.r > 0)   'rate_per_kg':  line.r,
          if (line.amt > 0) 'line_total':   line.amt,
          // Rate snapshot — what v4 resolved and how
          if (line.r > 0)                'applied_rate':      line.r,
          if (line.baseRate != null)     'base_rate':         line.baseRate,
          if (line.rateSource != null)   'rate_source':       line.rateSource,
          if (line.pricingType != null)  'adjustment_type':   line.pricingType,
          if (line.adjustmentValue != null && line.adjustmentValue! > 0)
            'adjustment_value':  line.adjustmentValue,
          if (line.rateZoneId != null)   'rate_zone_id':      line.rateZoneId,
          if (line.rateZoneName != null) 'rate_zone_name':    line.rateZoneName,
        });
      }

      if (mounted) {
        showSuccess(context, 'Order created & confirmed ✓');
        if (context.canPop())
          context.pop();
        else
          context.go(R.orders);
      }
    } catch (e) {
      if (mounted)
        showError(
            context,
            e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: kBgPage,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('New Order'),
      ),
      body: _dataLoading
          ? const LoadingList()
          : _products.isEmpty
          ? EmptyState(
        icon: Icons.egg_alt_outlined,
        message: 'No Products Enabled',
        sub: 'Enable the products you trade in Pricing → Products tab before creating orders.',
        actionLabel: 'Go to Pricing',
        onAction: () => context.push(R.pricingHub),
      )
          : Form(
          key: _form,
          child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance + bottomInset),
              children: [
                // ── Customer ───────────────────────────────────────────
                const SectionHeader('CUSTOMER'),
                SearchableRetailerPicker(
                    items: _retailers,
                    labelKey: 'shop_name',
                    hint: 'Select Customer',
                    sheetTitle: 'Select Customer',
                    prefixIcon: const Icon(Icons.store_outlined,
                        size: 20, color: kPrimary),
                    value: _selRetailer,
                    onChanged: (v) {
                      setState(() => _selRetailer = v);
                      for (int i = 0; i < _lines.length; i++) _fetchRate(i);
                    },
                    validator: (v) =>
                    v == null ? 'Select a customer' : null),
                const SizedBox(height: 16),

                // ── Order Lines (multi-product) ────────────────────────
                const SectionHeader('PRODUCTS'),
                ..._lines
                    .asMap()
                    .entries
                    .map((e) => _buildProductLine(e.key)),

                // Add product line button
                OutlinedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Another Product'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44))),
                const SizedBox(height: 16),

                // ── Order total summary ───────────────────────────────
                if (_lines.length > 1 || _totalKg > 0)
                  Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [kNavy, kNavyMid],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          boxShadow: kCardShadow),
                      child: Row(children: [
                        _summStat('Birds', '$_totalBirds', Colors.blue),
                        _summStat(
                            'Weight',
                            '${_totalKg.toStringAsFixed(1)} kg',
                            Colors.teal),
                        _summStat('Total', Fmt.amount(_totalAmt), kPrimary),
                      ])),

                const SizedBox(height: 14),
                TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_outlined,
                            size: 20, color: kPrimary))),
                const SizedBox(height: 24),

                // Auto-confirm info banner
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(kRadiusInner),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.3))),
                    child: const Row(children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Order will be auto-confirmed immediately upon creation.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.green))),
                    ])),
                const SizedBox(height: 14),

                ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    child: _saving
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                        : const Text('Create & Confirm Order',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700))),
                const SizedBox(height: 20),
              ])),
    );
  }

  Widget _buildProductLine(int idx) {
    final line = _lines[idx];
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight),
            boxShadow: kCardShadow),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: kPrimary, borderRadius: BorderRadius.circular(6)),
                child: Text('Item ${idx + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))),
            const Spacer(),
            if (_lines.length > 1)
              IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _removeLine(idx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints()),
          ]),
          const SizedBox(height: 10),

          // Product dropdown
          DropdownButtonFormField<Map<String, dynamic>>(
              value: line.product,
              hint: const Text('Select Product'),
              decoration: const InputDecoration(
                  prefixIcon:
                  Icon(Icons.set_meal_outlined, size: 18, color: kPrimary),
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              isExpanded: true,
              items: _products
                  .map((p) => DropdownMenuItem(
                  value: p, child: Text(p['name'] as String)))
                  .toList(),
              onChanged: (v) {
                setState(() => line.product = v);
                _fetchRate(idx);
              },
              validator: (v) => v == null ? 'Select product' : null),
          const SizedBox(height: 8),

          // Birds + Avg weight
          Row(children: [
            Expanded(
                child: TextFormField(
                    controller: line.birds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Birds',
                        suffixText: 'birds',
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    onChanged: (_) {
                      line.autoCalcWeight();
                      setState(() {});
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: TextFormField(
                    controller: line.avgWt,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Avg wt/bird',
                        suffixText: 'kg',
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    onChanged: (_) {
                      line.autoCalcWeight();
                      setState(() {});
                    })),
          ]),
          const SizedBox(height: 8),

          // Total weight + Rate
          Row(children: [
            Expanded(
                child: TextFormField(
                    controller: line.totalWt,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Weight (kg) *',
                        suffixText: 'kg',
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    onChanged: (v) {
                      line.wtManual = v.isNotEmpty;
                      setState(() {});
                    },
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                        ? 'Enter weight'
                        : null)),
            const SizedBox(width: 8),
            Expanded(
                child: TextFormField(
                    controller: line.rate,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: 'Rate (₹/kg)',
                        prefixText: '₹',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        suffixIcon: line.suggestRate != null
                            ? Tooltip(
                            message:
                            'Suggested: ₹${line.suggestRate!.toStringAsFixed(2)}',
                            child: const Icon(Icons.info_outline,
                                size: 16, color: Colors.blue))
                            : null),
                    onChanged: (_) => setState(() {}))),
          ]),

          // Line total
          if (line.kg > 0 && line.r > 0)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('Line total: ${Fmt.amount(line.amt)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kPrimary)),
                ])),
        ]));
  }

  Widget _summStat(String l, String v, Color c) => Expanded(
      child: Column(children: [
        Text(v,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: kGoldLight)),
        Text(l,
            style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFB4C6F4),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      ]));
}