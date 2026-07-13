import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AGENT SIMPLE ENTRY (multi-product)
//
// Fast proxy-entry path for when a delivery agent is absent/unable to enter
// their own data. Collapses "Instant Order" + "Record Delivery" into one
// screen for the common case: retailer already known, quantities already
// final (delivered = ordered), no mortality/returns/partial/photos needed.
//
// Flow (ONE atomic creation, then ONE completion call):
//   agent_create_instant_order_multi  → order + all order_items + batch + delivery
//   complete_delivery                 → stock deduction, status='delivered',
//                                        approval_status stays 'pending'
//
// Zero business logic here. All stock movements, rate resolution, and
// invoice/ledger creation happen in the reused RPCs and the existing
// Approvals flow — this screen only assembles inputs and calls them.
// ─────────────────────────────────────────────────────────────────────────────

class AgentSimpleEntrySheet extends ConsumerStatefulWidget {
  const AgentSimpleEntrySheet({
    super.key,
    required this.agentId,
    required this.agentName,
    required this.onDone,
    required this.onRecoveryNeeded,
  });

  final String agentId;
  final String agentName;
  final VoidCallback onDone;

  /// Called when the order/delivery was created successfully but
  /// complete_delivery failed. The sheet has already been popped by the
  /// time this fires, so the caller should navigate using its OWN stable
  /// context (the Hub screen's), not the sheet's — which is being torn down.
  final void Function(String deliveryId) onRecoveryNeeded;

  @override
  ConsumerState<AgentSimpleEntrySheet> createState() =>
      _AgentSimpleEntrySheetState();
}

class _SimpleLine {
  Map<String, dynamic>? product;
  final birdsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  // Stock precheck (informational only — final check happens in complete_delivery)
  int? availableBirds;
  bool checkingStock = false;

  int get birds => int.tryParse(birdsCtrl.text.trim()) ?? 0;
  double get weight => double.tryParse(weightCtrl.text.trim()) ?? 0;

  void dispose() {
    birdsCtrl.dispose();
    weightCtrl.dispose();
  }
}

class _AgentSimpleEntrySheetState extends ConsumerState<AgentSimpleEntrySheet> {
  final _c = Supabase.instance.client;

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _selRetailer;
  List<_SimpleLine> _lines = [_SimpleLine()];

  String _entryMode = 'called';
  String _payMode = 'credit';
  bool _loading = true;
  bool _submitting = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final results = await Future.wait([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c
            .from('master_products')
            .select('id,name,unit')
            .eq('is_active', true)
            .order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _retailers = List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Per-product stock precheck (informational; complete_delivery still
  //    does the authoritative family-pooled check at completion time) ───────
  Future<void> _checkStock(_SimpleLine line) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || line.product == null) return;
    setState(() => line.checkingStock = true);
    try {
      final res = await _c.rpc('get_available_stock', params: {
        'p_trader_id': tid,
        'p_product_id': line.product!['id'],
        'p_agent_id': widget.agentId,
      });
      final rows = res as List?;
      final avail = (rows != null && rows.isNotEmpty)
          ? (rows.first['available_birds'] as num?)?.toInt()
          : null;
      if (mounted) {
        setState(() {
          line.availableBirds = avail;
          line.checkingStock = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => line.checkingStock = false);
    }
  }

  void _addLine() {
    setState(() => _lines.add(_SimpleLine()));
  }

  void _removeLine(int idx) {
    final removed = _lines[idx];
    setState(() {
      _lines.removeAt(idx);
      if (_lines.isEmpty) _lines.add(_SimpleLine());
    });
    removed.dispose();
  }

  double get _totalWeight => _lines.fold(0.0, (s, l) => s + l.weight);
  int get _totalBirds => _lines.fold(0, (s, l) => s + l.birds);

  Future<void> _submit() async {
    setState(() => _err = null);

    if (_selRetailer == null) {
      setState(() => _err = 'Select a retailer');
      return;
    }
    final activeLines = _lines.where((l) => l.product != null).toList();
    if (activeLines.isEmpty) {
      setState(() => _err = 'Add at least one product');
      return;
    }
    for (int i = 0; i < activeLines.length; i++) {
      if (activeLines[i].weight <= 0) {
        setState(() => _err =
        'Enter delivered weight for ${activeLines[i].product!['name']}');
        return;
      }
    }
    // Duplicate product guard (client-side; DB trigger only catches whole-order dupes)
    final productIds = activeLines.map((l) => l.product!['id']).toList();
    if (productIds.toSet().length != productIds.length) {
      setState(() => _err = 'Each product can only appear once — remove the duplicate row.');
      return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    final itemSummary = activeLines
        .map((l) => '${l.product!['name']}: ${l.birds > 0 ? '${l.birds} birds, ' : ''}${l.weight.toStringAsFixed(1)} kg')
        .join('\n');

    final ok = await confirmDialog(
      context,
      title: 'Complete Delivery',
      message: '${_selRetailer!['shop_name']}\n\n$itemSummary\n\n'
          'Payment: $_payMode\n'
          'Acting on behalf of ${widget.agentName}.',
      confirmText: 'Complete',
      confirmColor: kNavy,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);

    // ── Step 1: atomic creation (order + all order_items + batch + delivery) ──
    Map<String, dynamic> createRes;
    try {
      final res = await _c.rpc('agent_create_instant_order_multi', params: {
        'p_agent_id': widget.agentId,
        'p_retailer_id': _selRetailer!['id'],
        'p_items': activeLines
            .map((l) => {
          'product_id': l.product!['id'],
          'birds': l.birds > 0 ? l.birds : null,
          'weight_kg': l.weight,
        })
            .toList(),
        'p_payment_mode': _payMode,
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
      });
      createRes = Map<String, dynamic>.from(res as Map);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _err = _cleanError(e);
        });
      }
      return; // Nothing was created — atomic RPC rolled back entirely.
    }

    final deliveryId = createRes['delivery_id'] as String;
    final totalBirds = (createRes['total_birds'] as num?)?.toInt() ?? _totalBirds;
    final totalWeight = (createRes['total_weight'] as num?)?.toDouble() ?? _totalWeight;

    // ── Step 2: complete the delivery (stock deduction, status=delivered) ──
    try {
      await _c.rpc('complete_delivery', params: {
        'p_delivery_id': deliveryId,
        'p_birds_delivered': totalBirds,
        'p_delivered_total_weight': totalWeight,
        'p_payment_mode': _payMode,
        'p_collected_amount': 0,
        'p_mortality_birds': 0,
        'p_returned_birds': 0,
        'p_returned_weight': 0,
        'p_shrinkage_kg': 0,
        'p_rejected_birds': 0,
        'p_crates_dropped': 0,
        'p_crates_collected': 0,
        'p_crates_returned': 0,
        'p_is_partial': false,
        'p_remaining_action': 'same',
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
      });

      if (mounted) {
        showSuccess(
            context,
            '✅ Delivery completed for ${widget.agentName}\n'
                '${_selRetailer!['shop_name']} — ${activeLines.length} product(s)');
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
      }
    } catch (e) {
      // ── Recovery: order + delivery + all order_items DID get created
      //    successfully (step 1 committed). Only completion failed — most
      //    likely insufficient stock discovered at this later check.
      //    Do not lose the order: route straight to the full Record Delivery
      //    screen for this exact delivery so staff can resolve it there
      //    (adjust weight, partial delivery, transfer, etc.) ────────────────
      if (mounted) {
        setState(() => _submitting = false);
        await confirmDialog(
          context,
          title: 'Order created — delivery not completed',
          message:
          '${_selRetailer!['shop_name']}\'s order was created, but the '
              'delivery could not be completed:\n\n${_cleanError(e)}\n\n'
              'Finish it from Record Delivery.',
          confirmText: 'Open Record Delivery',
          confirmColor: Colors.orange,
        );
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
        // Navigate using the Hub's own stable context (passed via callback),
        // not this sheet's context — which is being torn down by the pop above.
        widget.onRecoveryNeeded(deliveryId);
      }
      return;
    }

    if (mounted) setState(() => _submitting = false);
  }

  String _cleanError(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('PostgrestException(message: ', '')
      .replaceAll(')', '');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: _loading
          ? const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: kBorderLight,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded,
                      color: kNavy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Simple Entry',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('For ${widget.agentName}',
                          style: const TextStyle(
                              fontSize: 12, color: kTextHint)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const SectionHeader('RETAILER'),
            if (_retailers.isEmpty)
              const Text('No retailers found.',
                  style: TextStyle(color: kTextHint, fontSize: 12))
            else
              SearchableRetailerPicker(
                items: _retailers,
                labelKey: 'shop_name',
                hint: 'Choose retailer / shop',
                sheetTitle: 'Select Retailer',
                value: _selRetailer,
                onChanged: (v) => setState(() => _selRetailer = v),
              ),
            const SizedBox(height: 16),

            const SectionHeader('PRODUCTS'),
            const SizedBox(height: 6),
            ..._lines.asMap().entries.map((entry) {
              final idx = entry.key;
              final line = entry.value;
              return _ProductRow(
                line: line,
                products: _products,
                onProductChanged: (p) {
                  setState(() => line.product = p);
                  if (p != null) _checkStock(line);
                },
                onChanged: () => setState(() {}),
                onRemove: _lines.length > 1 ? () => _removeLine(idx) : null,
              );
            }),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Product'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kNavy,
                side: const BorderSide(color: kNavy),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRadiusInner)),
              ),
            ),
            const SizedBox(height: 16),

            if (_totalBirds > 0 || _totalWeight > 0)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                ),
                child: Text(
                  'Total: $_totalBirds birds · ${_totalWeight.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: kNavy),
                ),
              ),
            const SizedBox(height: 16),

            const Text('HOW DID AGENT REPORT?',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: kTextHint,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            EntryModeSelector(
              value: _entryMode,
              onChanged: (v) => setState(() => _entryMode = v),
            ),
            const SizedBox(height: 16),

            const SectionHeader('PAYMENT MODE'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'credit', label: Text('Credit')),
                ButtonSegment(value: 'cash', label: Text('Cash')),
                ButtonSegment(value: 'upi', label: Text('UPI')),
              ],
              selected: {_payMode},
              onSelectionChanged: (s) => setState(() => _payMode = s.first),
            ),
            const SizedBox(height: 20),

            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kErrorBg,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                  ),
                  child: Text(_err!,
                      style: const TextStyle(fontSize: 12, color: kError)),
                ),
              ),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
                child: _submitting
                    ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Text('Complete',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact per-product row: product picker + birds (optional) + weight (mandatory)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.line,
    required this.products,
    required this.onProductChanged,
    required this.onChanged,
    required this.onRemove,
  });

  final _SimpleLine line;
  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>?> onProductChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Map<String, dynamic>>(
                  value: line.product,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: 'Select product',
                    isDense: true,
                  ),
                  items: products
                      .map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ))
                      .toList(),
                  onChanged: onProductChanged,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: kTextHint),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.birdsCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                      labelText: 'Birds',
                      isDense: true,
                      suffixText: 'birds'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.weightCtrl,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                      labelText: 'Delivered Weight',
                      isDense: true,
                      suffixText: 'kg'),
                ),
              ),
            ],
          ),
          if (line.product != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: line.checkingStock
                  ? const Text('Checking stock…',
                  style: TextStyle(fontSize: 11, color: kTextHint))
                  : line.availableBirds != null
                  ? Text(
                'Available: ${line.availableBirds} birds for this agent',
                style: TextStyle(
                  fontSize: 11,
                  color: (line.availableBirds ?? 0) < line.birds
                      ? kError
                      : kTextHint,
                  fontWeight:
                  (line.availableBirds ?? 0) < line.birds
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}