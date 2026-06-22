import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// Pre-shift order entry. Mirrors InstantOrderScreen's structure deliberately —
// same form, same patterns — but the gate is INVERTED (available only when
// NO shift is open) and the destination RPC creates a 'pending' order for
// trader approval instead of an immediate, self-assigned delivery.
//
// Does NOT touch deliveries / delivery_batches / stock_ledger — order only,
// exactly like a retailer-placed order. Once a trader approves it (existing
// Order Detail screen, same action used for retailer orders today), it
// becomes a normal 'confirmed' order and flows through dispatch/batch
// assignment exactly like any other order. Reject uses the existing
// Cancel Order action — no new code path.
class PendingOrderScreen extends ConsumerStatefulWidget {
  const PendingOrderScreen({super.key});

  @override
  ConsumerState<PendingOrderScreen> createState() => _S();
}

class _S extends ConsumerState<PendingOrderScreen> {
  final _c = Supabase.instance.client;
  final _birdsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _hasOpenShift = false; // if true, this screen is NOT available
  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];

  // Orders this agent has created that are still waiting — visible from
  // creation until a trader assigns them to a batch. The moment
  // add_order_to_batch runs, status moves past 'confirmed' (to 'assigned'
  // or 'out_for_delivery') and the order naturally drops out of this list —
  // no separate flag needed, the existing status model already covers it.
  List<Map<String, dynamic>> _myOrders = [];
  Map<String, dynamic>? _selRetailer;
  Map<String, dynamic>? _selProduct;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    final agentId = user?.agentId;
    final traderId = user?.traderId;
    if (agentId == null || traderId == null) {
      if (mounted)
        setState(() {
          _loading = false;
        });
      return;
    }
    try {
      // INVERTED gate vs InstantOrderScreen: this screen is for BEFORE shift
      // open. If a shift IS open, the agent should use Instant Order instead.
      final shift = await _c
          .from('delivery_shifts')
          .select('id')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();
      final results = await Future.wait([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', traderId)
            .eq('is_active', true)
            .order('shop_name'),
        _c
            .from('master_products')
            .select('id,name,unit')
            .eq('is_active', true)
            .order('name'),
      ]);
      // Isolated own try/catch — a failure here should not block the form
      // above it from loading and being usable.
      List<Map<String, dynamic>> myOrders = [];
      try {
        final mine = await _c
            .from('orders')
            .select('id,status,total_quantity,estimated_birds,final_price,'
            'total_amount,order_date,retailers(shop_name)')
            .eq('created_by_agent_id', agentId)
            .inFilter('status', ['pending', 'confirmed']).order('created_at',
            ascending: false);
        myOrders = List<Map<String, dynamic>>.from(mine as List? ?? []);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _hasOpenShift = shift != null;
        _retailers = List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _myOrders = myOrders;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _birds => int.tryParse(_birdsCtrl.text.trim()) ?? 0;

  double get _weight => double.tryParse(_weightCtrl.text.trim()) ?? 0;

  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;

  double get _total => _weight * _rate;

  Future<void> _submit() async {
    setState(() => _err = null);
    if (_selRetailer == null) {
      setState(() => _err = 'Select a retailer');
      return;
    }
    if (_weight <= 0) {
      setState(() => _err = 'Enter weight (kg)');
      return;
    }

    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;

    final ok = await confirmDialog(context,
        title: '📋 Submit Order for Approval',
        message: 'Retailer: ${_selRetailer!['shop_name']}\n'
            '${_birds > 0 ? 'Birds: $_birds  ·  ' : ''}Weight: ${_weight.toStringAsFixed(1)} kg\n'
            '${_rate > 0 ? 'Est. Amount: ${Fmt.amount(_total)}\n' : ''}\n'
            'This order will be sent to the trader for approval. '
            'It will NOT be dispatched or affect stock until approved.',
        confirmText: 'Submit',
        confirmColor: kPrimary);
    if (!ok || !mounted) return;

    if (mounted) setState(() => _submitting = true);
    try {
      final res = await _c.rpc('agent_create_pending_order', params: {
        'p_agent_id': agentId,
        'p_retailer_id': _selRetailer!['id'],
        'p_product_id': _selProduct?['id'],
        'p_birds': _birds > 0 ? _birds : null,
        'p_weight_kg': _weight,
        'p_rate_per_kg': _rate > 0 ? _rate : null,
        'p_notes':
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      if (!mounted) return;
      final result = res as Map<String, dynamic>;
      showSuccess(
          context,
          '📋 Order submitted for approval!\n'
              '${result['retailer_name']} — ${_birds > 0 ? '$_birds birds · ' : ''}${_weight.toStringAsFixed(1)} kg'
              '${_rate > 0 ? '\nEst. Amount: ${Fmt.amount(_total)}' : ''}\n'
              'Trader will review and approve.');
      // Stay on this screen and refresh — the agent should see their order
      // appear in "My Submitted Orders" immediately, not navigate away blind.
      _birdsCtrl.clear();
      _weightCtrl.clear();
      _rateCtrl.clear();
      _notesCtrl.clear();
      setState(() {
        _selRetailer = null;
        _selProduct = null;
      });
      _load();
    } catch (e) {
      if (mounted)
        setState(() {
          _err = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', '')
              .replaceAll(')', '');
        });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop())
                  context.pop();
                else
                  context.go(R.agentHome);
              }),
          title: const Text('📋 Create Order (Pending Approval)'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
          ]),
      body: _loading
          ? const LoadingList()
          : _hasOpenShift
          ? _buildShiftOpenBlock()
          : _buildForm());

  // Available ONLY pre-shift. If a shift is already open, point the agent
  // to Instant Order instead — do not let both paths run simultaneously.
  Widget _buildShiftOpenBlock() => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.electric_bolt, size: 64, color: kTextHint),
            const SizedBox(height: 16),
            const Text('Shift Already Open',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Use Instant Order for orders during an active shift.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kTextSub)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
                onPressed: () => context.go(R.instantOrder),
                icon: const Icon(Icons.electric_bolt),
                label: const Text('Go to Instant Order')),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () {
                  if (context.canPop())
                    context.pop();
                  else
                    context.go(R.agentHome);
                },
                child: const Text('← Back to Home')),
          ])));

  Widget _buildForm() => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
    // Link to the dedicated My Orders screen (tracks Pending / Approved /
    // Cancelled / Assigned across this order's full lifecycle) instead of
    // duplicating that list inline here.
    if (_myOrders.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onTap: () => context.push(R.agentMyOrders),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
            child: Row(children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 20, color: kPrimary),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${_myOrders.length} order${_myOrders.length == 1 ? '' : 's'} submitted',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: kPrimary)),
                        const Text('Tap to track status',
                            style: TextStyle(fontSize: 11, color: kTextSub)),
                      ])),
              const Icon(Icons.arrow_forward_ios,
                  size: 14, color: kPrimary),
            ]),
          ),
        ),
      ),

    // Mode banner
    Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          const Icon(Icons.pending_actions_outlined,
              color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pending Approval Mode',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.orange,
                            fontSize: 13)),
                    Text('Trader must approve before this order is dispatched.',
                        style: TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
          Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('No Shift',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700))),
        ])),

    if (_err != null)
      Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: Colors.red.shade200)),
          child: Row(children: [
            const Icon(Icons.error_outline, color: kError, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_err!,
                    style: const TextStyle(color: kError, fontSize: 13))),
          ])),

    const SectionHeader('SELECT RETAILER *'),
    _retailers.isEmpty
        ? Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10)),
        child: const Text(
            'No retailers found. Ask admin to add retailers.',
            style: TextStyle(color: Colors.deepOrange)))
        : DropdownButtonFormField<Map<String, dynamic>>(
        value: _selRetailer,
        isExpanded: true,
        decoration: const InputDecoration(
            hintText: 'Choose retailer / shop',
            prefixIcon:
            Icon(Icons.store_outlined, size: 18, color: kPrimary)),
        items: _retailers
            .map((r) => DropdownMenuItem(
            value: r,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r['shop_name'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  if (r['phone'] != null)
                    Text(r['phone'] as String,
                        style: const TextStyle(
                            fontSize: 10, color: kTextHint)),
                ])))
            .toList(),
        onChanged: (v) => setState(() => _selRetailer = v)),

    if (_selRetailer?['address'] != null)
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 12, color: kTextSub),
            const SizedBox(width: 4),
            Expanded(
                child: Text(_selRetailer!['address'] as String,
                    style: const TextStyle(fontSize: 11, color: kTextSub))),
          ])),
    const SizedBox(height: 16),

    const SectionHeader('PRODUCT (OPTIONAL)'),
    if (_products.isNotEmpty)
      DropdownButtonFormField<Map<String, dynamic>>(
          value: _selProduct,
          isExpanded: true,
          decoration: const InputDecoration(
              hintText: 'Select product',
              prefixIcon:
              Icon(Icons.egg_alt_outlined, size: 18, color: kPrimary)),
          items: [
            const DropdownMenuItem(
                value: null,
                child: Text('No product selected',
                    style: TextStyle(color: kTextHint))),
            ..._products.map((p) => DropdownMenuItem(
                value: p,
                child: Text(p['name'] as String,
                    style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: (v) => setState(() => _selProduct = v)),
    const SizedBox(height: 16),

    const SectionHeader('QUANTITY'),
    Row(children: [
      Expanded(
          child: TextField(
              controller: _birdsCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Bird Count (optional)',
                  suffixText: 'birds',
                  prefixIcon:
                  Icon(Icons.numbers, size: 18, color: kPrimary)))),
      const SizedBox(width: 12),
      Expanded(
          child: TextField(
              controller: _weightCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Weight (kg) *',
                  suffixText: 'kg',
                  prefixIcon: Icon(Icons.scale_outlined,
                      size: 18, color: kPrimary)))),
    ]),
    if (_birds > 0 && _weight > 0)
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Avg: ${(_weight / _birds * 1000).toStringAsFixed(0)} g/bird',
              style: const TextStyle(fontSize: 11, color: kTextSub))),
    const SizedBox(height: 16),

    const SectionHeader('ESTIMATED PRICING (TRADER SETS FINAL RATE)'),
    Row(children: [
      Expanded(
          child: TextField(
              controller: _rateCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Rate per kg (₹, optional)',
                  prefixText: '₹',
                  prefixIcon: Icon(Icons.currency_rupee,
                      size: 18, color: kPrimary)))),
      const SizedBox(width: 12),
      Expanded(
          child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _total > 0
                      ? kPrimary.withValues(alpha: 0.08)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Est. Total',
                        style: TextStyle(fontSize: 10, color: kTextHint)),
                    Text(_total > 0 ? Fmt.amount(_total) : '—',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _total > 0 ? kPrimary : kTextHint)),
                  ]))),
    ]),
    const SizedBox(height: 16),

    TextField(
        controller: _notesCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            alignLabelWithHint: true,
            prefixIcon:
            Icon(Icons.notes_outlined, size: 18, color: kPrimary))),
    const SizedBox(height: 24),

    if (_selRetailer != null && _weight > 0)
      Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: Colors.orange.shade300)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.pending_actions_outlined,
                      size: 16, color: Colors.orange),
                  SizedBox(width: 6),
                  Text('Order Summary',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.orange,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                _row('Retailer', _selRetailer!['shop_name'] as String),
                if (_birds > 0) _row('Birds', '$_birds birds'),
                _row('Weight', '${_weight.toStringAsFixed(2)} kg'),
                if (_rate > 0)
                  _row('Est. Rate', '₹${_rate.toStringAsFixed(2)}/kg'),
                if (_total > 0) _row('Est. Total', Fmt.amount(_total)),
                _row('Status', 'Pending trader approval'),
              ])),

    ElevatedButton.icon(
        onPressed: (_submitting || _selRetailer == null) ? null : _submit,
        style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 54),
            backgroundColor: kPrimary),
        icon: _submitting
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Colors.white))
            : const Icon(Icons.send_outlined, size: 20),
        label: Text(
            _submitting ? 'Submitting...' : '📋 Submit for Approval',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800))),
    const SizedBox(height: 20),
  ]);

  Widget _row(String l, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(
            width: 90,
            child:
            Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
        Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700))),
      ]));
}