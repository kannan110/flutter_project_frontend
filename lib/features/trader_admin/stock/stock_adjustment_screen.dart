import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════
// IN-HOUSE STOCK ADJUSTMENT SCREEN (Phase 1 — In-House Stock Operations)
//
// Backend: record_stock_adjustment_v1 — reads current in-house balance via
// get_available_stock, computes the delta, and writes exactly one
// stock_ledger row through the shared fn_write_stock_movement engine. No
// business logic lives here; this screen only collects inputs and displays
// the result + audit history. Stock is never edited directly.
// ══════════════════════════════════════════════════════════════════════════

const _kAdjustmentTypes = [
  (value: 'weight_loss', label: 'Weight Loss', icon: Icons.trending_down, hint: 'Natural weight loss over time — birds unchanged, weight reduced'),
  (value: 'mortality', label: 'Mortality', icon: Icons.warning_amber_rounded, hint: 'Birds died while in-house'),
  (value: 'physical_count', label: 'Physical Count', icon: Icons.fact_check_outlined, hint: 'Correct to match an actual physical count — can increase or decrease'),
  (value: 'manual', label: 'Manual Adjustment', icon: Icons.edit_note, hint: 'Any other correction, with a reason'),
];

const _kReasonCodes = [
  'Natural weight loss',
  'Died in-house',
  'Physical count mismatch',
  'Data entry correction',
  'Other',
];

class StockAdjustmentScreen extends ConsumerStatefulWidget {
  const StockAdjustmentScreen({super.key});

  @override
  ConsumerState<StockAdjustmentScreen> createState() => _S();
}

class _S extends ConsumerState<StockAdjustmentScreen> {
  final _c = Supabase.instance.client;

  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _history = [];

  Map<String, dynamic>? _selectedProduct;
  int _currentBirds = 0;
  double _currentKg = 0;
  bool _loadingBalance = false;

  String _adjustmentType = _kAdjustmentTypes.first.value;
  final _birdsAfterCtrl = TextEditingController();
  final _kgAfterCtrl = TextEditingController();
  String? _reasonCode;
  final _remarksCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _birdsAfterCtrl.dispose();
    _kgAfterCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  String? get _traderId => ref.read(appUserProvider).valueOrNull?.traderId;
  String? get _userId => ref.read(appUserProvider).valueOrNull?.userId;

  Future<void> _load() async {
    final tid = _traderId;
    if (tid == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final products = await _c
          .from('master_products')
          .select('id,name')
          .eq('is_active', true)
          .order('name');
      final history = await _c
          .from('stock_adjustments')
          .select('id,adjustment_type,adjustment_date,birds_before,kg_before,'
              'birds_after,kg_after,birds_delta,kg_delta,reason_code,remarks,'
              'created_at,master_products(name)')
          .eq('trader_id', tid)
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(products as List? ?? []);
        _history = List<Map<String, dynamic>>.from(history as List? ?? []);
        _loading = false;
      });
      if (_products.isNotEmpty) {
        _selectProduct(_products.first);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _selectProduct(Map<String, dynamic> product) async {
    final tid = _traderId;
    if (tid == null || !mounted) return;
    setState(() {
      _selectedProduct = product;
      _loadingBalance = true;
    });
    try {
      final res = await _c.rpc('get_available_stock', params: {
        'p_trader_id': tid,
        'p_product_id': product['id'],
      });
      final row = ((res as List?) ?? []).isNotEmpty ? (res as List).first as Map<String, dynamic> : null;
      if (!mounted) return;
      setState(() {
        _currentBirds = (row?['in_house_birds'] as num?)?.toInt() ?? 0;
        _currentKg = (row?['in_house_kg'] as num?)?.toDouble() ?? 0;
        _loadingBalance = false;
        // Pre-fill "after" fields with the current balance so the trader
        // only edits the number(s) that actually changed.
        _birdsAfterCtrl.text = _currentBirds.toString();
        _kgAfterCtrl.text = _currentKg == _currentKg.roundToDouble()
            ? _currentKg.toStringAsFixed(0)
            : _currentKg.toStringAsFixed(1);
      });
    } catch (e) {
      if (mounted) setState(() => _loadingBalance = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _submit() async {
    final tid = _traderId;
    final uid = _userId;
    if (tid == null || _selectedProduct == null || !mounted) return;

    final birdsAfter = int.tryParse(_birdsAfterCtrl.text.trim());
    final kgAfter = double.tryParse(_kgAfterCtrl.text.trim());
    if (birdsAfter == null || birdsAfter < 0 || kgAfter == null || kgAfter < 0) {
      showError(context, 'Enter a valid bird count and weight.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await _c.rpc('record_stock_adjustment_v1', params: {
        'p_trader_id': tid,
        'p_product_id': _selectedProduct!['id'],
        'p_adjustment_type': _adjustmentType,
        'p_birds_after': birdsAfter,
        'p_kg_after': kgAfter,
        'p_reason_code': _reasonCode,
        'p_remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
        'p_created_by': uid,
      });
      if (!mounted) return;
      final result = res as Map<String, dynamic>;
      final birdsDelta = result['birds_delta'] as int;
      final kgDelta = (result['kg_delta'] as num).toDouble();
      setState(() {
        _submitting = false;
        _reasonCode = null;
        _remarksCtrl.clear();
      });
      showSuccess(
        context,
        'Adjustment recorded ✓  (${birdsDelta >= 0 ? '+' : ''}$birdsDelta birds, '
        '${kgDelta >= 0 ? '+' : ''}${kgDelta.toStringAsFixed(1)} kg)',
      );
      await _load();
      if (_selectedProduct != null) await _selectProduct(_selectedProduct!);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('In-House Stock Adjustment'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
      body: _loading
          ? const LoadingList()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildProductPicker(),
                const SizedBox(height: 14),
                if (_selectedProduct != null) _buildBalanceCard(),
                const SizedBox(height: 14),
                if (_selectedProduct != null) _buildAdjustmentForm(),
                const SizedBox(height: 24),
                const Text('Recent Adjustments', style: kTypeSectionTitle),
                const SizedBox(height: 10),
                ..._history.map(_buildHistoryTile),
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No adjustments recorded yet.')),
                  ),
              ],
            ),
    );
  }

  Widget _buildProductPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSurfaceHigh),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<Map<String, dynamic>>(
          initialValue: _selectedProduct,
          decoration: const InputDecoration(
            labelText: 'Product',
            border: InputBorder.none,
          ),
          items: _products
              .map((p) => DropdownMenuItem(value: p, child: Text(p['name'] as String)))
              .toList(),
          onChanged: (p) {
            if (p != null) _selectProduct(p);
          },
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kNavy, kNavyMid]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: _loadingBalance
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(color: kGoldLight)),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _balanceStat('Birds (In-House)', _currentBirds.toString()),
                Container(width: 1, height: 36, color: Colors.white24),
                _balanceStat('Weight (In-House)', '${_currentKg.toStringAsFixed(1)} kg'),
              ],
            ),
    );
  }

  Widget _balanceStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: kGoldLight, fontSize: 22, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildAdjustmentForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kSurfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Adjustment Type', style: kTypeSectionTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kAdjustmentTypes.map((t) {
              final selected = _adjustmentType == t.value;
              return ChoiceChip(
                label: Text(t.label),
                avatar: Icon(t.icon, size: 16, color: selected ? kSurface : kNavy),
                selected: selected,
                selectedColor: kNavy,
                labelStyle: TextStyle(color: selected ? kSurface : kNavy, fontWeight: FontWeight.w700),
                onSelected: (_) => setState(() => _adjustmentType = t.value),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            _kAdjustmentTypes.firstWhere((t) => t.value == _adjustmentType).hint,
            style: const TextStyle(fontSize: 12, color: kNavyLight),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _birdsAfterCtrl,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(labelText: 'New Bird Count *', suffixText: 'birds'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _kgAfterCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(labelText: 'New Weight *', suffixText: 'kg'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _reasonCode,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: _kReasonCodes
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _reasonCode = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remarksCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kSurface),
                    )
                  : const Text('Save Adjustment'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> row) {
    final birdsDelta = (row['birds_delta'] as num?)?.toInt() ?? 0;
    final kgDelta = (row['kg_delta'] as num?)?.toDouble() ?? 0;
    final type = row['adjustment_type'] as String? ?? '';
    final typeLabel = _kAdjustmentTypes
        .firstWhere((t) => t.value == type, orElse: () => _kAdjustmentTypes.last)
        .label;
    final productName = (row['master_products'] as Map<String, dynamic>?)?['name'] as String? ?? '';
    final date = row['adjustment_date'] as String? ?? '';
    final positive = birdsDelta >= 0 && kgDelta >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSurfaceHigh),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$typeLabel — $productName',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  date.isNotEmpty ? DateFormat('dd MMM yyyy').format(DateTime.parse(date)) : '',
                  style: const TextStyle(fontSize: 11, color: kNavyLight),
                ),
                if ((row['remarks'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(row['remarks'] as String,
                        style: const TextStyle(fontSize: 11, color: kNavyLight)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${birdsDelta >= 0 ? '+' : ''}$birdsDelta birds',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: positive ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              Text(
                '${kgDelta >= 0 ? '+' : ''}${kgDelta.toStringAsFixed(1)} kg',
                style: TextStyle(
                  fontSize: 12,
                  color: positive ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
