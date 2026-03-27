import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});
  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products  = [];
  String? _selectedRetailer;
  String? _selectedProduct;
  double _currentRate = 0;
  bool _loadingRate = false;

  final _birdsCtrl  = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();
  String _paymentType = 'credit';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _birdsCtrl.dispose(); _weightCtrl.dispose(); _notesCtrl.dispose(); super.dispose();
  }

  Future<void> _loadData() async {
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (traderId == null) return;
    final r = await _client.from('retailers').select('id,shop_name,owner_name').eq('trader_id', traderId).eq('is_active', true).eq('approval_status', 'approved').order('shop_name');
    final p = await _client.from('master_products').select('id,name,category').eq('is_active', true);
    if (mounted) setState(() { _retailers = List<Map<String, dynamic>>.from(r); _products = List<Map<String, dynamic>>.from(p); });
  }

  Future<void> _fetchRate() async {
    if (_selectedProduct == null) return;
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (traderId == null) return;
    setState(() => _loadingRate = true);
    try {
      final rate = await _client.rpc('get_current_rate', params: {'p_trader_id': traderId, 'p_product_id': _selectedProduct});
      setState(() => _currentRate = (rate as num?)?.toDouble() ?? 0);
    } catch (_) {
      setState(() => _currentRate = 0);
    } finally {
      if (mounted) setState(() => _loadingRate = false);
    }
  }

  double get _estimatedTotal {
    final w = double.tryParse(_weightCtrl.text) ?? 0;
    return w * _currentRate;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRetailer == null) { showError(context, 'Select a retailer'); return; }
    if (_selectedProduct == null)  { showError(context, 'Select a product'); return; }
    setState(() => _submitting = true);
    try {
      final traderId = ref.read(appUserProvider).valueOrNull?.traderId!;
      final birds  = int.tryParse(_birdsCtrl.text) ?? 0;
      final weight = double.tryParse(_weightCtrl.text) ?? 0;
      if (_currentRate <= 0) throw Exception('No rate set for today. Please set the rate first.');

      // Insert order
      final order = await _client.from('orders').insert({
        'trader_id': traderId, 'retailer_id': _selectedRetailer,
        'product_id': _selectedProduct, 'estimated_birds': birds,
        'total_quantity': weight, 'total_amount': weight * _currentRate,
        'payment_type': _paymentType, 'source': 'trader',
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': 'pending',
      }).select().single();

      // Lock rate in order_items — the billing chain keystone
      await _client.from('order_items').insert({
        'order_id': order['id'], 'trader_id': traderId,
        'product_id': _selectedProduct, 'bird_count': birds,
        'total_weight': weight, 'rate_per_kg': _currentRate,
        'line_total': weight * _currentRate,
      });

      if (mounted) {
        showSuccess(context, 'Order created successfully');
        context.go(Routes.orders);
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionHeader('RETAILER'),
          DropdownButtonFormField<String>(
            value: _selectedRetailer,
            hint: const Text('Select retailer'),
            decoration: const InputDecoration(),
            items: _retailers.map((r) => DropdownMenuItem(
              value: r['id'] as String,
              child: Text(r['shop_name'] as String),
            )).toList(),
            onChanged: (v) => setState(() => _selectedRetailer = v),
            validator: (v) => v == null ? 'Select a retailer' : null,
          ),
          const SizedBox(height: 16),
          const SectionHeader('PRODUCT & RATE'),
          DropdownButtonFormField<String>(
            value: _selectedProduct,
            hint: const Text('Select product'),
            decoration: const InputDecoration(),
            items: _products.map((p) => DropdownMenuItem(
              value: p['id'] as String,
              child: Text(p['name'] as String),
            )).toList(),
            onChanged: (v) async {
              setState(() { _selectedProduct = v; _currentRate = 0; });
              await _fetchRate();
            },
            validator: (v) => v == null ? 'Select a product' : null,
          ),
          const SizedBox(height: 8),
          if (_selectedProduct != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _currentRate > 0 ? AppTheme.primary.withOpacity(0.07) : Colors.orange.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _currentRate > 0 ? AppTheme.primary.withOpacity(0.2) : Colors.orange.withOpacity(0.3)),
              ),
              child: _loadingRate
                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(children: [
                      Icon(_currentRate > 0 ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                          size: 16, color: _currentRate > 0 ? AppTheme.primary : Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        _currentRate > 0 ? "Today's rate: ₹${_currentRate.toStringAsFixed(2)}/kg" : "No rate set for today",
                        style: TextStyle(fontSize: 13, color: _currentRate > 0 ? AppTheme.primary : Colors.orange, fontWeight: FontWeight.w500),
                      ),
                      if (_currentRate == 0) ...[
                        const Spacer(),
                        TextButton(onPressed: () => context.go(Routes.rates), child: const Text('Set Rate', style: TextStyle(fontSize: 12))),
                      ],
                    ]),
            ),
          const SizedBox(height: 16),
          const SectionHeader('QUANTITY'),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _birdsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bird count'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if ((double.tryParse(v) ?? 0) <= 0) return 'Must be > 0';
                  return null;
                },
              ),
            ),
          ]),
          if (_currentRate > 0 && (double.tryParse(_weightCtrl.text) ?? 0) > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Estimated total', style: TextStyle(fontSize: 13, color: Color(0xFF757575))),
                Text('₹${_estimatedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          const SectionHeader('PAYMENT TYPE'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'credit', label: Text('Credit'), icon: Icon(Icons.credit_card, size: 16)),
              ButtonSegment(value: 'cash',   label: Text('Cash'),   icon: Icon(Icons.money, size: 16)),
              ButtonSegment(value: 'upi',    label: Text('UPI'),    icon: Icon(Icons.phone_android, size: 16)),
            ],
            selected: {_paymentType},
            onSelectionChanged: (s) => setState(() => _paymentType = s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Order'),
          ),
        ]),
      ),
    );
  }
}
