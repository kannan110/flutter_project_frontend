import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class BatchDetailScreen extends ConsumerStatefulWidget {
  const BatchDetailScreen({super.key, required this.id});

  final String id;

  @override ConsumerState<BatchDetailScreen> createState() => _S();
}

class _S extends ConsumerState<BatchDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _batch;
  List<Map<String, dynamic>> _deliveries = [];
  List<Map<String, dynamic>> _challans = [];
  // DC Correction Lifecycle — the batch's shift approval status
  // determines which action (Verify/Edit vs. Correct Post-Approval)
  // each DC card offers. Fetched alongside everything else in _load().
  Map<String, dynamic>? _shift;
  bool get _isShiftApproved => (_shift?['shift_approval_status'] as String?) == 'approved';
  List<Map<String, dynamic>> _confirmedOrders = [];
  List<Map<String, dynamic>> _agents = [];
  bool _loading = true,
      _submitting = false;
  List<Map<String, dynamic>> _farms = []; // supplier master — for DC picker
  // Parent-level products only (e.g. Broiler, Country, Quail) — for the
  // mandatory DC product picker. Variant breakdown (Broiler Small/Medium/Big)
  // is recorded separately via loaded-stock confirmation, not here. Enforced
  // both here (parent_product_id IS NULL filter) and server-side in
  // pickup_batch/add_batch_dc (rejects variant ids even if somehow sent).
  List<Map<String, dynamic>> _parentProducts = [];

  // In-house stock per product — shown in the Add DC sheet when Source Type
  // = In-House, so the trader can see what's actually available at the
  // stock point before loading a DC against it. Read-only; reuses the same
  // get_available_stock RPC already used on the dashboard / agent DC form.
  List<Map<String, dynamic>> _inHouseStock = [];

  /// Filters the in-house stock preview to a selected product — returns all
  /// in-stock products when none is selected yet.
  List<Map<String, dynamic>> _visibleInHouseStock(String? productId) {
    if (productId == null) return _inHouseStock;
    return _inHouseStock.where((s) => s['product_id'] == productId).toList();
  }

  @override void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    if (mounted) setState(() => _loading = true);
    try {
      final b = await _c.from('delivery_batches')
          .select('*,delivery_agents(id,name,vehicle_no,phone)')
          .eq('id', widget.id).maybeSingle();
      final d = await _c.from('deliveries')
          .select(
          'id,status,orders(id,estimated_birds,total_quantity,retailers(shop_name))')
          .eq('batch_id', widget.id);
      final ch = await _c.from('delivery_challans')
          .select('*').eq('batch_id', widget.id).order('created_at');
      // DC Correction Lifecycle — need the shift's approval status to
      // decide which correction action each DC offers.
      Map<String, dynamic>? shift;
      try {
        final shiftId = b?['shift_id'];
        if (shiftId != null) {
          shift = await _c.from('delivery_shifts')
              .select('id,status,shift_approval_status')
              .eq('id', shiftId).maybeSingle();
        }
      } catch (_) {}
      // Only confirmed (not already in a batch)
      final co = await _c.from('orders')
          .select('id,estimated_birds,total_quantity,retailers(shop_name)')
          .eq('trader_id', tid!)
          .eq('status', 'confirmed');
      final ag = await _c.from('delivery_agents')
          .select('id,name,vehicle_no')
          .eq('trader_id', tid).eq('is_active', true).order('name');
      // Load supplier (farms) master for DC picker
      List<Map<String, dynamic>> farms = [];
      try {
        final f = await _c.from('farms')
            .select('id,farmer_name,farm_name,location,phone')
            .eq('trader_id', tid).eq('is_active', true)
            .order('farmer_name');
        farms = List<Map<String, dynamic>>.from(f as List? ?? []);
      } catch (_) {}
      // Load parent-level products only (e.g. Broiler, Country, Quail) for
      // the mandatory DC product picker. Variants excluded intentionally.
      List<Map<String, dynamic>> parentProducts = [];
      try {
        final pp = await _c.from('master_products')
            .select('id,name,category')
            .isFilter('parent_product_id', null)
            .eq('is_active', true)
            .order('sort_order');
        parentProducts = List<Map<String, dynamic>>.from(pp as List? ?? []);
      } catch (_) {}
      // In-house stock per product (read-only) — lets the trader see what's
      // available at the stock point before loading an In-House DC. Reuses
      // the existing get_available_stock RPC; no new backend logic.
      List<Map<String, dynamic>> inHouseStock = [];
      try {
        final raw = await _c
            .rpc('get_available_stock', params: {'p_trader_id': tid});
        inHouseStock = List<Map<String, dynamic>>.from(raw as List? ?? [])
            .where((r) => ((r['in_house_birds'] as num?) ?? 0) > 0 ||
            ((r['in_house_kg'] as num?) ?? 0) > 0)
            .toList();
      } catch (_) {}
      if (mounted) {
        setState(() {
        _batch = b;
        _deliveries = List<Map<String, dynamic>>.from(d);
        _challans = List<Map<String, dynamic>>.from(ch);
        _shift = shift;
        _confirmedOrders = List<Map<String, dynamic>>.from(co);
        _agents = List<Map<String, dynamic>>.from(ag);
        _farms = farms;
        _parentProducts = parentProducts;
        _inHouseStock = inHouseStock;
        _loading = false;
      });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOrder(String orderId) async {
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    try {
      final res = await _c.rpc('add_order_to_batch', params: {
        'p_batch_id': widget.id,
        'p_order_id': orderId,
        'p_trader_id': tid,
      });
      _load();
      if (mounted) {
        final isMidShift =
            (res as Map?)?.cast<String, dynamic>()['added_mid_shift'] == true;
        showSuccess(context, isMidShift
            ? '✓ Order added — agent will see it immediately'
            : '✓ Order added to batch');
      }
    } catch (e) {
      if (mounted) {
        showError(context,
          e.toString().replaceAll('Exception: ', '').replaceAll(
              'PostgrestException(message: ', ''));
      }
    }
  }

  Future<void> _removeDelivery(String deliveryId, String shopName) async {
    final ok = await confirmDialog(context,
        title: 'Remove from Batch',
        message: 'Remove "$shopName" from this batch? Order returns to Confirmed status.',
        confirmText: 'Remove', confirmColor: Colors.red);
    if (!ok) return;
    final tid = ref
        .read(appUserProvider)
        .valueOrNull
        ?.traderId;
    try {
      // Get the order_id for this delivery first
      final del = await _c.from('deliveries')
          .select('order_id')
          .eq('id', deliveryId)
          .maybeSingle();
      final orderId = del?['order_id'] as String?;

      // FIX: use remove_order_from_batch RPC — resets order status to 'confirmed'
      if (orderId != null && tid != null) {
        await _c.rpc('remove_order_from_batch', params: {
          'p_batch_id': widget.id,
          'p_order_id': orderId,
        });
      } else {
        // Fallback: manual update
        await _c.from('deliveries').update({'status': 'cancelled'}).eq(
            'id', deliveryId);
        if (orderId != null) {
          await _c.from('orders').update(
              {'status': 'confirmed', 'batch_id': null}).eq('id', orderId);
        }
      }
      if (mounted) {
        showSuccess(context, 'Removed ✓');
        _load();
      }
    } catch (e) {
      if (mounted) {
        showError(context,
          e.toString().replaceAll('Exception: ', '').replaceAll(
              'PostgrestException(message: ', ''));
      }
    }
  }

  Future<void> _reassignAgent() async {
    if (_agents.isEmpty) {
      showError(context, 'No active agents available');
      return;
    }
    Map<String, dynamic>? sel;
    await showModalBottomSheet(
        context: context, useRootNavigator: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) =>
            ListView(
                shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
              const Text('Reassign to Agent',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ..._agents.map((a) =>
                  ListTile(
                    leading: const Icon(Icons.delivery_dining, color: kPrimary),
                    title: Text(a['name'] as String),
                    subtitle: Text(a['vehicle_no'] as String? ?? ''),
                    trailing: _batch?['delivery_agent_id'] == a['id']
                        ? const StatusBadge('current', kPrimary, small: true)
                        : null,
                    onTap: () {
                      sel = a;
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
                  )),
            ]));
    if (sel == null || sel!['id'] == _batch?['delivery_agent_id']) return;
    final ok = await confirmDialog(context,
        title: 'Reassign Agent',
        message: 'Reassign batch to ${sel!['name']}?',
        confirmText: 'Reassign', confirmColor: kPrimary);
    if (!ok) return;
    try {
      await _c.from('delivery_batches').update(
          {'delivery_agent_id': sel!['id']}).eq('id', widget.id);
      // Also update all assigned deliveries in this batch
      await _c.from('deliveries').update({'delivery_agent_id': sel!['id']})
          .eq('batch_id', widget.id).inFilter(
          'status', ['assigned', 'picked_up', 'out_for_delivery']);
      if (mounted) {
        showSuccess(context, 'Reassigned to ${sel!['name']} ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  Future<void> _deleteBatch() async {
    final status = _batch?['status'] as String? ?? '';
    if (['picked_up', 'out_for_delivery'].contains(status)) {
      showError(context,
          'Cannot delete a batch in transit. Agent must close their shift first.');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Delete Batch',
        message: 'Delete this batch?\n\n'
            '• All deliveries will be cancelled\n'
            '• All DCs for this batch will be removed\n'
            '• Orders return to Confirmed status',
        confirmText: 'Delete Batch', confirmColor: Colors.red);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      // FIX: Delete in correct FK order
      // Step 1: Nullify batch_id on delivery_shifts if FK exists
      try {
        await _c.from('delivery_shifts').update({'batch_id': null}).eq(
            'batch_id', widget.id);
      } catch (_) {
        /* column may not exist — safe to ignore */
      }
      // Step 2: Delete delivery_challans (FK: batch_id -> delivery_batches.id)
      await _c.from('delivery_challans').delete().eq('batch_id', widget.id);
      // Step 3: Unlock orders linked to this batch (reset to confirmed)
      final deliveryRows = await _c
          .from('deliveries')
          .select('id, order_id')
          .eq('batch_id', widget.id);
      for (final d in (deliveryRows as List<dynamic>)) {
        final oid = d['order_id'];
        if (oid != null) {
          await _c.from('orders').update(
              {'status': 'confirmed', 'batch_id': null}).eq('id', oid);
        }
      }
      // Step 4: Delete deliveries (batch_id is NOT NULL — cannot nullify, must delete)
      await _c.from('deliveries').delete().eq('batch_id', widget.id);
      // Step 5: Now safe to delete the batch
      await _c.from('delivery_batches').delete().eq('id', widget.id);
      if (mounted) {
        showSuccess(context, 'Batch deleted ✓');
        context.go(R.dispatch);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '').replaceAll(
            'PostgrestException(message: ', '');
        showError(context, 'Delete failed: $msg');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _start() async {
    if (_deliveries
        .where((d) => d['status'] != 'cancelled')
        .isEmpty) {
      showError(context, 'Add at least one order first');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Start Deliveries',
        message: 'Mark batch as Out for Delivery?',
        confirmText: 'Start', confirmColor: kPrimary);
    if (!ok) return;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.rpc('start_batch_delivery', params: {'p_batch_id': widget.id});
      _load();
      if (mounted) showSuccess(context, 'Deliveries started ✓');
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
    finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addDC() async {
    final status = _batch?['status'] as String? ?? '';
    if (['completed', 'cancelled'].contains(status)) {
      showError(context, 'Cannot add DC to a $status batch');
      return;
    }

    final dcNumCtrl = TextEditingController();
    final farmerCtrl = TextEditingController();
    final farmLocCtrl = TextEditingController();
    final vehicleCtrl = TextEditingController(
        text: _batch?['delivery_agents']?['vehicle_no'] as String? ?? '');
    final grossWtCtrl = TextEditingController();
    final emptyWtCtrl = TextEditingController(text: '0');
    final birdsCtrl = TextEditingController();
    final cratesCtrl = TextEditingController(text: '0');
    final rateCtrl = TextEditingController();
    // ★ FIX (Batch Detail audit): default the DC Date to the batch's own
    // batch_date instead of today — a backdated batch (e.g. 05-Aug) should
    // never default this form to CURRENT_DATE. Re-read fresh every time
    // this sheet opens, so if the batch's date is ever corrected, the next
    // Add DC automatically picks up the new value with no extra wiring.
    final batchDateStr = _batch?['batch_date'] as String?;
    DateTime dcDate = batchDateStr != null
        ? (DateTime.tryParse(batchDateStr) ?? DateTime.now())
        : DateTime.now();
    String sourceType = 'farm';
    String? selectedFarmId;
    String? selectedProductId;
    String? selectedProductName;
    String? selectedFarmName;
    File? dcImage;
    String? dcImageUrl;
    bool uploadingDcImage = false;
    final picker = ImagePicker();
    // Validation errors render as a banner pinned to the TOP of this sheet
    // (not a bottom SnackBar, which — per showError's use of the app's
    // root ScaffoldMessenger — floats over the whole screen, not the sheet
    // itself, and can be missed while the trader's focus/scroll position
    // is down near the Save button).
    String? formError;
    final scrollCtrl = ScrollController();

    await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) =>
            StatefulBuilder(builder: (ctx, ss) {
              final grossVal = double.tryParse(grossWtCtrl.text) ?? 0;
              final emptyVal = double.tryParse(emptyWtCtrl.text) ?? 0;
              final netWt = (grossVal - emptyVal).clamp(0, double.infinity);
              final birds = int.tryParse(birdsCtrl.text) ?? 0;

              // In-House Stock Auto Fill — triggered explicitly from the
              // Source toggle and Product picker below (not on every
              // rebuild), so it fills once on the trigger event but never
              // fights the trader's own edits afterward. Uses the exact
              // same _visibleInHouseStock data already backing the
              // read-only "AVAILABLE IN-HOUSE STOCK" preview — no new
              // fetch, no duplicated stock calculation.
              void applyInHouseAutoFill() {
                if (sourceType != 'inhouse_stock' || selectedProductId == null) return;
                final match = _visibleInHouseStock(selectedProductId);
                if (match.isEmpty) return;
                final availBirds = (match.first['in_house_birds'] as num?)?.toInt() ?? 0;
                final availKg = (match.first['in_house_kg'] as num?)?.toDouble() ?? 0;
                grossWtCtrl.text = availKg.toStringAsFixed(2);
                emptyWtCtrl.text = '0';
                birdsCtrl.text = availBirds.toString();
              }

              // Validation errors surface as the top-of-sheet banner above,
              // not a bottom SnackBar — and scroll the sheet back to the
              // top so the trader actually sees it even if they were
              // scrolled down near the Save button.
              void showFieldError(String msg) {
                ss(() => formError = msg);
                if (scrollCtrl.hasClients) {
                  scrollCtrl.animateTo(0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut);
                }
              }

              return Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery
                      .of(ctx)
                      .viewInsets
                      .bottom + 20),
                  child: SingleChildScrollView(
                      controller: scrollCtrl,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Row(children: [
                              Text('Add DC', style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                              Spacer(),
                              Icon(
                                  Icons.receipt_long_outlined, color: kPrimary),
                            ]),
                            if (formError != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                    color: kError.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(
                                        kRadiusInner),
                                    border: Border.all(
                                        color: kError.withValues(alpha: 0.4))),
                                child: Row(children: [
                                  const Icon(Icons.error_outline,
                                      size: 18, color: kError),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(formError!,
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: kError))),
                                ]),
                              ),
                            ],
                            const SizedBox(height: 10),
                            SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(value: 'farm', icon: Icon(Icons
                                      .agriculture, size: 14), label: Text('Farm')),
                                  ButtonSegment(
                                      value: 'shop_collection', icon: Icon(Icons
                                      .store, size: 14), label: Text('Shop')),
                                  ButtonSegment(value: 'inhouse_stock',
                                      icon: Icon(Icons.warehouse_outlined,
                                          size: 14),
                                      label: Text('In-House')),
                                ],
                                selected: {sourceType},
                                onSelectionChanged: (s) =>
                                    ss(() {
                                      sourceType = s.first;
                                      applyInHouseAutoFill();
                                    })),
                            if (sourceType == 'inhouse_stock') ...[
                              const SizedBox(height: 8),
                              Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(
                                          kRadiusInner),
                                      border: Border.all(
                                          color: Colors.orange.shade200)),
                                  child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Icon(Icons.warehouse_outlined,
                                              color: Colors.orange, size: 14),
                                          SizedBox(width: 6),
                                          Text('IN-HOUSE DC — Internal Transfer',
                                              style: TextStyle(fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.orange)),
                                        ]),
                                        SizedBox(height: 4),
                                        Text(
                                            'Moves stock FROM in-house inventory TO agent.\n'
                                                'In-house stock DECREASES. Agent stock INCREASES.',
                                            style: TextStyle(fontSize: 10,
                                                color: Colors.orange,
                                                height: 1.4)),
                                      ])),
                              if (_visibleInHouseStock(selectedProductId)
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: kBgGrey,
                                        borderRadius:
                                        BorderRadius.circular(kRadiusInner),
                                        border: Border.all(color: kBorderLight)),
                                    child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              selectedProductId == null
                                                  ? 'AVAILABLE IN-HOUSE STOCK'
                                                  : 'AVAILABLE IN-HOUSE STOCK — $selectedProductName',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: kTextHint,
                                                  letterSpacing: 0.6)),
                                          const SizedBox(height: 6),
                                          ..._visibleInHouseStock(
                                              selectedProductId)
                                              .map((s) {
                                            final birds = (s['in_house_birds']
                                            as num?)
                                                ?.toInt() ?? 0;
                                            final kg = (s['in_house_kg']
                                            as num?)
                                                ?.toDouble() ?? 0;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 2),
                                              child: Row(children: [
                                                Expanded(
                                                    child: Text(
                                                        s['product_name']
                                                        as String? ??
                                                            '—',
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                            FontWeight.w700,
                                                            color: kNavy))),
                                                Text(
                                                    'Available: $birds Birds | ${kg.toStringAsFixed(2)} Kg',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                        FontWeight.w600,
                                                        color: kTextSub)),
                                              ]),
                                            );
                                          }),
                                        ])),
                              ],
                            ],
                            const SizedBox(height: 14),
                            const Text('Product *',
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kTextHint)),
                            const SizedBox(height: 4),
                            const Text(
                                'One product per DC. Variant breakdown '
                                    '(Small/Medium/Big) is confirmed separately '
                                    'after loading.',
                                style: TextStyle(fontSize: 11, color: kTextHint)),
                            const SizedBox(height: 8),
                            if (_parentProducts.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('No active products found.',
                                      style: TextStyle(color: kTextHint)))
                            else
                              Wrap(spacing: 8, runSpacing: 8,
                                  children: _parentProducts.map((p) {
                                    final id = p['id'] as String;
                                    final name = p['name'] as String? ?? '—';
                                    final selected = selectedProductId == id;
                                    return InkWell(
                                        onTap: () => ss(() {
                                          selectedProductId = id;
                                          selectedProductName = name;
                                          applyInHouseAutoFill();
                                        }),
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                                color: selected
                                                    ? kPrimary.withValues(alpha: 0.1)
                                                    : Colors.grey.shade100,
                                                borderRadius:
                                                BorderRadius.circular(20),
                                                border: Border.all(
                                                    color: selected
                                                        ? kPrimary
                                                        : Colors.grey.shade300,
                                                    width: selected ? 1.5 : 1)),
                                            child: Text(name,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: selected
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                    color: selected
                                                        ? kPrimary
                                                        : kTextHint))));
                                  }).toList()),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  controller: dcNumCtrl,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                      labelText: 'DC Number *'))),
                              const SizedBox(width: 10),
                              Expanded(child: InkWell(
                                  onTap: () async {
                                    // firstDate must never be after dcDate's
                                    // initial value (Flutter requires
                                    // initialDate within [firstDate, lastDate])
                                    // — a batch older than 7 days would
                                    // otherwise crash this picker now that
                                    // dcDate correctly defaults to the batch
                                    // date instead of today.
                                    final sevenDaysAgo = DateTime.now()
                                        .subtract(const Duration(days: 7));
                                    final pickerFirstDate =
                                    dcDate.isBefore(sevenDaysAgo)
                                        ? dcDate
                                        : sevenDaysAgo;
                                    final d = await showDatePicker(context: ctx,
                                        initialDate: dcDate,
                                        firstDate: pickerFirstDate,
                                        lastDate: DateTime.now());
                                    if (d != null) ss(() => dcDate = d);
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 16),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: Text(
                                          DateFormat('d MMM y').format(dcDate),
                                          style: const TextStyle(fontSize: 13))))),
                            ]),
                            const SizedBox(height: 8),
                            // ── Supplier picker ────────────────────────────────
                            StatefulBuilder(builder: (_, fss) =>
                                Column(children: [
                                  if (sourceType == 'farm' &&
                                      _farms.isNotEmpty) ...[
                                    GestureDetector(
                                        onTap: () =>
                                            showModalBottomSheet(
                                                context: context,
                                                useRootNavigator: true,
                                                isScrollControlled: true,
                                                shape: const RoundedRectangleBorder(
                                                    borderRadius: BorderRadius
                                                        .vertical(
                                                        top: Radius.circular(20))),
                                                builder: (pCtx) =>
                                                    StatefulBuilder(
                                                        builder: (pCtx, ps) {
                                                          String q = '';
                                                          final flt = q.isEmpty
                                                              ? _farms
                                                              : _farms.where((f) =>
                                                              (f['farmer_name'] as String? ??
                                                                  '')
                                                                  .toLowerCase()
                                                                  .contains(
                                                                  q.toLowerCase()))
                                                              .toList();
                                                          return DraggableScrollableSheet(
                                                              expand: false,
                                                              initialChildSize: 0.55,
                                                              maxChildSize: 0.85,
                                                              builder: (_, ctrl) =>
                                                                  Column(children: [
                                                                    Padding(
                                                                        padding: const EdgeInsets
                                                                            .fromLTRB(
                                                                            16, 12,
                                                                            16, 8),
                                                                        child: Column(
                                                                            children: [
                                                                              const Text(
                                                                                  'Select Supplier',
                                                                                  style: TextStyle(
                                                                                      fontSize: 15,
                                                                                      fontWeight: FontWeight
                                                                                          .w800)),
                                                                              const SizedBox(
                                                                                  height: 8),
                                                                              TextField(
                                                                                  textInputAction: TextInputAction
                                                                                      .search,
                                                                                  onSubmitted: (
                                                                                      _) =>
                                                                                      FocusScope
                                                                                          .of(
                                                                                          context)
                                                                                          .nextFocus(),
                                                                                  onChanged: (
                                                                                      v) =>
                                                                                      ps(() =>
                                                                                      q =
                                                                                          v),
                                                                                  decoration: const InputDecoration(
                                                                                      hintText: 'Search...',
                                                                                      prefixIcon: Icon(
                                                                                          Icons
                                                                                              .search,
                                                                                          size: 18),
                                                                                      isDense: true)),
                                                                            ])),
                                                                    const Divider(
                                                                        height: 1),
                                                                    Expanded(
                                                                        child: ListView
                                                                            .builder(
                                                                            controller: ctrl,
                                                                            padding: const EdgeInsets
                                                                                .all(
                                                                                10),
                                                                            itemCount: flt
                                                                                .length,
                                                                            itemBuilder: (
                                                                                _,
                                                                                i) {
                                                                              final f = flt[i];
                                                                              return ListTile(
                                                                                  dense: true,
                                                                                  leading: CircleAvatar(
                                                                                      radius: 14,
                                                                                      backgroundColor: kPrimary
                                                                                          .withValues(
                                                                                          alpha: 0.08),
                                                                                      child: Text(
                                                                                          (f['farmer_name'] as String? ??
                                                                                              '?')[0]
                                                                                              .toUpperCase(),
                                                                                          style: const TextStyle(
                                                                                              fontSize: 11,
                                                                                              fontWeight: FontWeight
                                                                                                  .w800,
                                                                                              color: kPrimary))),
                                                                                  title: Text(
                                                                                      f['farmer_name'] as String? ??
                                                                                          '—'),
                                                                                  subtitle: (f['farm_name'] as String?) !=
                                                                                      null
                                                                                      ? Text(
                                                                                      f['farm_name'] as String)
                                                                                      : null,
                                                                                  trailing: selectedFarmId ==
                                                                                      f['id']
                                                                                      ? const Icon(
                                                                                      Icons
                                                                                          .check_circle,
                                                                                      color: kPrimary,
                                                                                      size: 16)
                                                                                      : null,
                                                                                  onTap: () {
                                                                                    Navigator
                                                                                        .of(
                                                                                        pCtx,
                                                                                        rootNavigator: true)
                                                                                        .pop();
                                                                                    ss(() {
                                                                                      selectedFarmId =
                                                                                      f['id'] as String;
                                                                                      selectedFarmName =
                                                                                      f['farmer_name'] as String?;
                                                                                      farmerCtrl
                                                                                          .text =
                                                                                          f['farmer_name'] as String? ??
                                                                                              '';
                                                                                      if ((f['location'] as String?)
                                                                                          ?.isNotEmpty ==
                                                                                          true &&
                                                                                          farmLocCtrl
                                                                                              .text
                                                                                              .isEmpty) {
                                                                                        farmLocCtrl
                                                                                            .text =
                                                                                        f['location'] as String;
                                                                                      }
                                                                                    });
                                                                                  });
                                                                            })),
                                                                  ]));
                                                        })),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 11),
                                            decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(
                                                    kRadiusCard),
                                                border: Border.all(
                                                    color: selectedFarmId != null
                                                        ? kPrimary
                                                        : kBorder,
                                                    width: selectedFarmId != null
                                                        ? 1.5
                                                        : 1)),
                                            child: Row(children: [
                                              Icon(Icons.agriculture_outlined,
                                                  size: 15,
                                                  color: selectedFarmId != null
                                                      ? kPrimary
                                                      : kTextHint),
                                              const SizedBox(width: 8),
                                              Expanded(child: Text(
                                                  selectedFarmId != null
                                                      ? (selectedFarmName ?? '—')
                                                      : 'Select Supplier',
                                                  style: TextStyle(fontSize: 12,
                                                      fontWeight: selectedFarmId !=
                                                          null
                                                          ? FontWeight.w700
                                                          : FontWeight.normal,
                                                      color: selectedFarmId != null
                                                          ? kTextMain
                                                          : kTextHint))),
                                              const Icon(
                                                  Icons.chevron_right, size: 15,
                                                  color: kTextHint),
                                            ]))),
                                    const SizedBox(height: 4),
                                    const Center(child: Text('— or type manually —',
                                        style: TextStyle(
                                            fontSize: 10, color: kTextHint))),
                                    const SizedBox(height: 6),
                                  ],
                                ])),
                            TextField(
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                                controller: farmerCtrl,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                    labelText: sourceType == 'shop_collection'
                                        ? 'Shop Name *'
                                        : sourceType == 'inhouse_stock'
                                        ? 'Stock Point Name *'
                                        : 'Farmer Name *')),
                            const SizedBox(height: 8),
                            TextField(
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                                controller: farmLocCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Location (optional)')),
                            const SizedBox(height: 8),
                            TextField(
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    FocusScope.of(context).nextFocus(),
                                controller: vehicleCtrl,
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(
                                    labelText: 'Vehicle No.')),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  controller: grossWtCtrl,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Gross Wt (kg) *'),
                                  onChanged: (_) => ss(() {}))),
                              const SizedBox(width: 8),
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  controller: emptyWtCtrl,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'Empty Crate'),
                                  onChanged: (_) => ss(() {}))),
                              const SizedBox(width: 8),
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  controller: birdsCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Birds'),
                                  onChanged: (_) => ss(() {}))),
                            ]),
                            if (grossVal > 0) Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Net: ${netWt.toStringAsFixed(
                                    2)} kg${birds > 0 ? ' · Avg: ${(netWt / birds)
                                    .toStringAsFixed(3)} kg/bird' : ''}',
                                    style: const TextStyle(fontSize: 12,
                                        color: kPrimary,
                                        fontWeight: FontWeight.w700))),
                            const SizedBox(height: 8),
                            // ── DC Photo (optional here — this screen may run on
                            // desktop without a camera; the agent's mobile pickup
                            // flow is where the photo is mandatory) ─────────────
                            const Text('DC Photo',
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kTextHint)),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: uploadingDcImage ? null : () async {
                                final picked = await picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 70, maxWidth: 1200);
                                if (picked == null) return;
                                final file = File(picked.path);
                                ss(() { dcImage = file; uploadingDcImage = true; });
                                try {
                                  final path =
                                      'dc/${DateTime.now().millisecondsSinceEpoch}.jpg';
                                  await Supabase.instance.client.storage
                                      .from('dc-images').upload(path, file);
                                  final url = Supabase.instance.client.storage
                                      .from('dc-images').getPublicUrl(path);
                                  ss(() { dcImageUrl = url; uploadingDcImage = false; });
                                } catch (e) {
                                  ss(() => uploadingDcImage = false);
                                  if (ctx.mounted) {
                                    showError(ctx,
                                      'Photo upload failed — check connection');
                                  }
                                }
                              },
                              child: Container(
                                height: 80,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(kRadiusInner),
                                  border: Border.all(color: kBorder),
                                  color: kBgGrey,
                                ),
                                child: uploadingDcImage
                                    ? const Center(child: CircularProgressIndicator())
                                    : dcImage != null
                                    ? Image.file(dcImage!, fit: BoxFit.cover,
                                    width: double.infinity)
                                    : const Center(child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_a_photo_outlined,
                                          color: kTextHint, size: 20),
                                      SizedBox(height: 4),
                                      Text('Tap to attach DC photo (optional)',
                                          style: TextStyle(
                                              fontSize: 11, color: kTextHint)),
                                    ])),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  controller: cratesCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Crates'))),
                              const SizedBox(width: 8),
                              Expanded(child: TextField(
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  controller: rateCtrl,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: '₹/kg', prefixText: '₹'))),
                            ]),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: () async {
                                  if (dcNumCtrl.text
                                      .trim()
                                      .isEmpty) {
                                    showFieldError('DC number required');
                                    return;
                                  }
                                  if (farmerCtrl.text
                                      .trim()
                                      .isEmpty) {
                                    showFieldError('Name required');
                                    return;
                                  }
                                  final gross = double.tryParse(grossWtCtrl.text) ??
                                      0;
                                  if (gross <= 0) {
                                    showFieldError('Please enter Gross Weight.');
                                    return;
                                  }
                                  if (selectedProductId == null) {
                                    showFieldError('Please select a Product.');
                                    return;
                                  }
                                  final bCountCheck = int.tryParse(birdsCtrl.text) ??
                                      0;
                                  if (bCountCheck <= 0) {
                                    showFieldError('Please enter Bird Count.');
                                    return;
                                  }
                                  // Note: no need to reset formError here — the
                                  // sheet and all its local state (including
                                  // this StatefulBuilder) are torn down the
                                  // moment it closes below. Calling ss() this
                                  // late, right as the pop/dispose sequence
                                  // begins, was unnecessary and risked
                                  // scheduling one more rebuild frame against
                                  // controllers already mid-disposal.
                                  Navigator.of(ctx, rootNavigator: true).pop();
                                  try {
                                    final bStatus = _batch?['status'] as String? ??
                                        'assigned';
                                    final tid = ref
                                        .read(appUserProvider)
                                        .valueOrNull
                                        ?.traderId;
                                    // Load supplier list
                                    // farms loaded in _load() as _farms state field
                                    final empty = double.tryParse(
                                        emptyWtCtrl.text) ?? 0;
                                    final net = (gross - empty).clamp(
                                        0, double.infinity);
                                    final bCount = int.tryParse(birdsCtrl.text) ??
                                        0;
                                    final avg = bCount > 0 ? net / bCount : 0.0;

                                    if (bStatus == 'assigned') {
                                      final shiftRow = await _c.from(
                                          'delivery_shifts')
                                          .select('id')
                                          .eq('delivery_agent_id',
                                          _batch!['delivery_agent_id'])
                                          .eq('status', 'open')
                                          .maybeSingle();
                                      // FIX: pass p_source_type — was missing, inhouse_stock treated as farm
                                      await _c.rpc('pickup_batch', params: {
                                        'p_batch_id': widget.id,
                                        'p_shift_id': shiftRow?['id'],
                                        'p_dc_number': dcNumCtrl.text.trim(),
                                        'p_dc_date': dcDate.toIso8601String().split(
                                            'T')[0],
                                        'p_farmer_name': farmerCtrl.text.trim(),
                                        'p_farm_id': selectedFarmId,
                                        'p_farm_location': farmLocCtrl.text
                                            .trim()
                                            .isEmpty ? null : farmLocCtrl.text
                                            .trim(),
                                        'p_vehicle_number': vehicleCtrl.text
                                            .trim()
                                            .isEmpty ? null : vehicleCtrl.text
                                            .trim(),
                                        'p_driver_name': null,
                                        'p_supervisor_name': null,
                                        'p_gross_weight': gross,
                                        'p_empty_weight': empty,
                                        'p_net_weight': net,
                                        'p_avg_weight': avg > 0 ? avg : 0.0,
                                        'p_bird_count': bCount,
                                        'p_weak_birds': 0,
                                        'p_crates_count': int.tryParse(
                                            cratesCtrl.text) ?? 0,
                                        'p_farm_rate': rateCtrl.text.isEmpty
                                            ? null
                                            : double.tryParse(rateCtrl.text),
                                        'p_in_time': null,
                                        'p_out_time': null,
                                        'p_dc_photo_url': dcImageUrl,
                                        'p_source_type': sourceType,
                                        // FIX: was missing
                                        'p_product_id': selectedProductId,  // NEW: explicit, mandatory — no more guessing
                                      });
                                      // Advance picked_up → out_for_delivery so agent can complete
                                      await _c.rpc('start_batch_delivery',
                                          params: {'p_batch_id': widget.id});
                                    } else {
                                      await _c.rpc('add_batch_dc', params: {
                                        'p_batch_id': widget.id,
                                        'p_dc_number': dcNumCtrl.text.trim(),
                                        'p_dc_date': dcDate.toIso8601String().split(
                                            'T')[0],
                                        'p_farmer_name': farmerCtrl.text.trim(),
                                        'p_farm_id': selectedFarmId,
                                        'p_farm_location': farmLocCtrl.text
                                            .trim()
                                            .isEmpty ? null : farmLocCtrl.text
                                            .trim(),
                                        'p_vehicle_number': vehicleCtrl.text
                                            .trim()
                                            .isEmpty ? null : vehicleCtrl.text
                                            .trim(),
                                        'p_gross_weight': gross,
                                        'p_empty_weight': empty,
                                        'p_net_weight': net,
                                        'p_avg_weight': avg > 0 ? avg : 0.0,
                                        'p_bird_count': bCount,
                                        'p_crates_count': int.tryParse(
                                            cratesCtrl.text) ?? 0,
                                        'p_farm_rate': rateCtrl.text.isEmpty
                                            ? null
                                            : double.tryParse(rateCtrl.text),
                                        'p_source_type': sourceType,
                                        'p_product_id': selectedProductId,  // NEW: explicit, mandatory — no more guessing
                                        'p_dc_photo_url': dcImageUrl,
                                        // FIX: this screen previously always sent null —
                                        // now uploads through the same 'dc-images' bucket
                                        // the agent app uses, and sends the real URL.
                                      });
                                    }
                                    _load();
                                    if (mounted) showSuccess(context, 'DC added ✓');
                                  } catch (e) {
                                    if (mounted) {
                                      showError(context,
                                        e.toString().replaceAll('Exception: ', ''));
                                    }
                                  }
                                },
                                child: const Text('Save DC')),
                          ])));
            }));
    for (final c in [
      dcNumCtrl,
      farmerCtrl,
      farmLocCtrl,
      vehicleCtrl,
      grossWtCtrl,
      emptyWtCtrl,
      birdsCtrl,
      cratesCtrl,
      rateCtrl
    ]) {
      c.dispose();
    }
    scrollCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: kBgPage, body: LoadingList());
    }
    if (_batch == null) {
      return Scaffold(backgroundColor: kBgPage,
        appBar: AppBar(backgroundColor: kSurface),
        body: const Center(child: Text('Not found')));
    }
    final a = _batch!['delivery_agents'] as Map<String, dynamic>?;
    final status = _batch!['status'] as String? ?? 'assigned';
    final canEdit = !['completed', 'cancelled'].contains(status);
    final activeDeliveries = _deliveries.where((d) =>
    d['status'] != 'cancelled').toList();

    // DC totals — reconciled: prefer the DC-Verification-confirmed quantity
    // (dc_adjusted_birds/dc_adjusted_weight) over the original DC figure, so
    // this matches what approve_shift and Stock Management will use.
    final dcBirds = _challans.fold(
        0, (s, c) => s + ((c['dc_adjusted_birds'] as num?)?.toInt() ??
        (c['bird_count'] as num?)?.toInt() ?? 0));
    final dcWeight = _challans.fold(
        0.0, (s, c) => s + ((c['dc_adjusted_weight'] as num?)?.toDouble() ??
        (c['net_weight'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Batch Detail'),
        actions: [
          if (canEdit) ...[
            TextButton.icon(onPressed: _addDC,
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('+ DC')),
            IconButton(
                icon: const Icon(Icons.person_outline, size: 20),
                tooltip: 'Reassign Agent',
                onPressed: _reassignAgent),
          ],
          if (canEdit && status == 'assigned')
            IconButton(
                icon: const Icon(
                    Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: 'Delete Batch',
                onPressed: _deleteBatch),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [

        // ── Agent card ────────────────────────────────────────────
        WhiteCard(child: Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?['name'] as String? ?? '—',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            if (a?['vehicle_no'] != null)
              Text('Vehicle: ${a!['vehicle_no']}',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            if (a?['phone'] != null)
              Text('Phone: ${a!['phone']}',
                  style: const TextStyle(fontSize: 12, color: kTextHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusBadge(status, SC.order(status)),
            if (canEdit) ...[
              const SizedBox(height: 6),
              GestureDetector(
                  onTap: _reassignAgent,
                  child: const Row(children: [
                    Icon(Icons.swap_horiz, size: 14, color: kPrimary),
                    SizedBox(width: 4),
                    Text('Swap Agent', style: TextStyle(fontSize: 11,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
                  ])),
            ],
          ]),
        ])),
        const SizedBox(height: 14),

        // ── DC List ───────────────────────────────────────────────
        Row(children: [
          const Expanded(child: Text('Delivery Challans (DC)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          if (canEdit) TextButton.icon(
              onPressed: _addDC,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add DC')),
        ]),
        if (_challans.isNotEmpty) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  _miniStat('Total Birds', '$dcBirds', kPrimary),
                  _miniStat('Total Weight', '${dcWeight.toStringAsFixed(1)} kg',
                      Colors.teal),
                  _miniStat('DCs', '${_challans.length}', Colors.blue),
                ]))),
        if (_challans.isEmpty) Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.orange.shade200)),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('No DC yet. Add DC before dispatching.',
                  style: TextStyle(fontSize: 12, color: Colors.orange))),
            ]))
        else
          ..._challans
              .asMap()
              .entries
              .map((entry) {
            final idx = entry.key;
            final ch = entry.value;
            return _DcCard(key: ValueKey(ch['id']), challan: ch, index: idx + 1,
                isShiftApproved: _isShiftApproved, onChanged: _load);
          }),
        const SizedBox(height: 14),

        // ── Orders / Deliveries ───────────────────────────────────
        Row(children: [
          Expanded(child: Text('Orders (${activeDeliveries.length})',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        if (activeDeliveries.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(12),
              child: Text('No orders in this batch',
                  style: TextStyle(color: kTextHint))))
        else
          ...activeDeliveries.map((d) {
            final o = d['orders'] as Map<String, dynamic>?;
            final r = o?['retailers'] as Map<String, dynamic>?;
            final dStat = d['status'] as String? ?? '';
            final kg = (o?['total_quantity'] as num?)?.toStringAsFixed(1) ??
                '—';
            final birds = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
            return Container(
                margin: const EdgeInsets.only(bottom: 6),
                child: WhiteCard(padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment
                              .start, children: [
                            Text(r?['shop_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('$birds birds · $kg kg',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextSub)),
                          ])),
                      StatusBadge(dStat, SC.order(dStat), small: true),
                      if (canEdit && dStat == 'assigned') ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                            onTap: () =>
                                _removeDelivery(
                                    d['id'], r?['shop_name'] as String? ?? '—'),
                            child: const Icon(
                                Icons.remove_circle_outline, color: Colors.red,
                                size: 20)),
                      ],
                    ])));
          }),

        // Add confirmed orders — available during active shift (assigned, picked_up, out_for_delivery)
        if (['assigned', 'picked_up', 'out_for_delivery'].contains(status)) ...[
          const SizedBox(height: 8),
          const SectionHeader('ADD FROM CONFIRMED ORDERS'),
          // Mid-shift banner — shown when agent is already delivering
          if (status == 'out_for_delivery')
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(children: [
                Icon(Icons.local_shipping_outlined,
                    color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Agent is mid-shift. New orders will appear on their '
                      'screen immediately as out-for-delivery.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                )),
              ]),
            ),
          ...() {
            final alreadyInBatch = _deliveries.map((d) =>
            (d['orders'] as Map?)?.cast<String, dynamic>()['id']).toSet();
            final available = _confirmedOrders.where((o) =>
            !alreadyInBatch.contains(o['id'])).toList();
            if (available.isEmpty) {
              return [const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No confirmed orders available',
                      style: TextStyle(color: kTextHint, fontSize: 13)))
              ];
            }
            return available.map((o) {
              final r = o['retailers'] as Map<String, dynamic>?;
              return ListTile(
                  dense: true,
                  leading: const Icon(
                      Icons.store_outlined, size: 18, color: kPrimary),
                  title: Text(
                      r?['shop_name'] as String? ?? '—', style: const TextStyle(
                      fontSize: 13)),
                  subtitle: Text('${o['estimated_birds'] ??
                      0} birds · ${(o['total_quantity'] as num?)
                      ?.toStringAsFixed(0) ?? '—'} kg',
                      style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: kPrimary),
                      onPressed: () => _addOrder(o['id'])));
            }).toList();
          }(),
        ],

        const SizedBox(height: 20),

        // ── Action buttons ────────────────────────────────────────
        if (status == 'picked_up')
          ElevatedButton.icon(
              onPressed: _submitting ? null : _start,
              icon: _submitting
                  ? const SizedBox(width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow),
              label: const Text('Start Deliveries (Out for Delivery)',
                  style: TextStyle(fontWeight: FontWeight.w700))),
        if (status == 'assigned' && _challans.isNotEmpty)
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.blue.shade100)),
              child: const Text(
                  'DC saved — batch is out for delivery. Agent can now complete deliveries.',
                  style: TextStyle(fontSize: 12, color: Colors.blue))),
        if (status == 'out_for_delivery')
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.green.shade200)),
              child: const Row(children: [
                Icon(Icons.local_shipping, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text(
                    'Batch is Out for Delivery — agent is delivering now',
                    style: TextStyle(fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w600))),
              ])),
        if (canEdit && status == 'assigned') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _deleteBatch,
              icon: const Icon(
                  Icons.delete_outline, size: 18, color: Colors.red),
              label: const Text('Delete Batch'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red))),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _miniStat(String l, String v, Color c) =>
      Expanded(child: Column(children: [
        Text(v, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: c)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextHint),
            textAlign: TextAlign.center),
      ]));
}

// ── DC Card — expandable with image ─────────────────────────────────────────
class _DcCard extends StatefulWidget {
  const _DcCard({super.key, required this.challan, required this.index,
    required this.isShiftApproved, required this.onChanged});

  final Map<String, dynamic> challan;
  final int index;
  final bool isShiftApproved;
  final VoidCallback onChanged;

  @override State<_DcCard> createState() => _DcCardState();
}

class _DcCardState extends State<_DcCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.challan;
    final date = DateTime.tryParse(ch['dc_date'] as String? ?? '');
    final net = (ch['net_weight'] as num?)?.toDouble() ?? 0;
    final gross = (ch['gross_weight'] as num?)?.toDouble() ?? 0;
    final empty = (ch['empty_crate_weight'] as num?)?.toDouble() ?? 0;
    final birds = (ch['bird_count'] as num?)?.toInt() ?? 0;
    final confirmedBirds = (ch['dc_adjusted_birds'] as num?)?.toInt();
    final confirmedWt = (ch['dc_adjusted_weight'] as num?)?.toDouble();
    final displayBirds = confirmedBirds ?? birds;
    final displayWt = confirmedWt ?? net;
    final isReconciled = confirmedBirds != null || confirmedWt != null;
    final crates = (ch['crates_count'] as num?)?.toInt() ?? 0;
    final rate = (ch['farm_rate'] as num?)?.toDouble();
    final photoUrl = ch['dc_photo_url'] as String?;
    final hasPic = photoUrl != null && photoUrl.isNotEmpty;

    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasPic ? Colors.green.shade200 : kBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4, offset: const Offset(0, 2))
            ]),
        child: Column(children: [
          // ── Header (always visible) ────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${widget.index}',
                          style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w900, color: kPrimary)))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(ch['dc_number'] as String? ?? '—',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(width: 8),
                      if (isReconciled) Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('Confirmed', style: TextStyle(
                              fontSize: 9, color: Colors.blue,
                              fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      if (hasPic) Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.photo_outlined, size: 10,
                                color: Colors.green),
                            SizedBox(width: 3),
                            Text('Photo', style: TextStyle(fontSize: 9,
                                color: Colors.green,
                                fontWeight: FontWeight.w700)),
                          ])),
                    ]),
                    Text(
                        '${ch['farmer_name'] ?? '—'} · $displayBirds birds · ${displayWt
                            .toStringAsFixed(1)} kg'
                            '${isReconciled ? ' (DC: $birds · ${net.toStringAsFixed(1)} kg)' : ''}',
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
                  Row(children: [
                    if (date != null) Text(DateFormat('d MMM').format(date),
                        style: const TextStyle(fontSize: 10, color: kTextHint)),
                    const SizedBox(width: 4),
                    Icon(_expanded ? Icons.keyboard_arrow_up : Icons
                        .keyboard_arrow_down,
                        size: 18, color: kTextHint),
                  ]),
                ])),
          ),

          // ── Expanded detail ────────────────────────────────────
          if (_expanded) Container(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Divider(height: 12),

                // Weight breakdown
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FF),
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      _row('Gross Weight', '${gross.toStringAsFixed(2)} kg'),
                      _row('Empty Crate Weight',
                          '${empty.toStringAsFixed(2)} kg'),
                      _row('Net Weight', '${net.toStringAsFixed(2)} kg',
                          kPrimary),
                      _row('Bird Count', '$birds birds'),
                      _row('Crates', '$crates'),
                      if (rate != null) _row(
                          'Farm Rate', '₹${rate.toStringAsFixed(2)}/kg'),
                      if (rate != null && net > 0)
                        _row('Farm Amount', '₹${(rate * net).toStringAsFixed(
                            2)}', Colors.green),
                    ])),

                // DC Correction Lifecycle — Before Approval (verify_dc) or
                // After Approval (correct_dc_post_approval), same shared
                // sheet, only the target RPC and mandatory-reason
                // requirement differ. Reuses WeightCalc for the Gross/
                // Empty → Net computation, same as every other weight
                // entry point in the app.
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _showEditSheet(context),
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: (widget.isShiftApproved ? Colors.deepOrange : kPrimary).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(widget.isShiftApproved ? Icons.build_outlined : Icons.edit_outlined,
                              size: 13, color: widget.isShiftApproved ? Colors.deepOrange : kPrimary),
                          const SizedBox(width: 4),
                          Text(widget.isShiftApproved ? 'Correct DC (Post-Approval)' : 'Verify / Edit DC',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: widget.isShiftApproved ? Colors.deepOrange : kPrimary)),
                        ])),
                  ),
                ),

                // Extra info
                if (ch['farm_location'] != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(
                        Icons.location_on_outlined, size: 13, color: kTextSub),
                    const SizedBox(width: 4),
                    Expanded(child: Text(ch['farm_location'] as String,
                        style: const TextStyle(fontSize: 11, color: kTextSub))),
                  ]),
                ],
                if (ch['vehicle_number'] != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.directions_car_outlined, size: 13,
                        color: kTextSub),
                    const SizedBox(width: 4),
                    Text(ch['vehicle_number'] as String,
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ]),
                ],

                // DC Photo
                if (hasPic) ...[
                  const SizedBox(height: 12),
                  const Row(children: [
                    Icon(Icons.photo_library_outlined, size: 13,
                        color: Colors.green),
                    SizedBox(width: 6),
                    Text('DC Photo Proof',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.green)),
                  ]),
                  const SizedBox(height: 8),
                  GestureDetector(
                      onTap: () => _showImageFull(context, photoUrl),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(kRadiusCard),
                          child: Stack(children: [
                            Image.network(
                              photoUrl,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, prog) =>
                              prog == null ? child
                                  : Container(height: 180,
                                  color: Colors.grey.shade100,
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))),
                              errorBuilder: (_, __, ___) =>
                                  Container(
                                      height: 80, color: Colors.grey.shade100,
                                      child: const Center(
                                          child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                    Icons.broken_image_outlined,
                                                    color: Colors.grey),
                                                Text('Image unavailable',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey)),
                                              ]))),
                            ),
                            Positioned(bottom: 8, right: 8,
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6)),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.zoom_in, size: 12,
                                              color: Colors.white),
                                          SizedBox(width: 4),
                                          Text('Tap to expand',
                                              style: TextStyle(fontSize: 10,
                                                  color: Colors.white)),
                                        ]))),
                          ])))
                ] else
                  ...[
                    const SizedBox(height: 8),
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(kRadiusInner),
                            border: Border.all(color: Colors.orange.shade200)),
                        child: const Row(children: [
                          Icon(Icons.camera_alt_outlined, size: 14,
                              color: Colors.orange),
                          SizedBox(width: 6),
                          Text('No DC photo uploaded yet',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange)),
                        ])),
                  ],
              ])),
        ]));
  }

  void _showImageFull(BuildContext context, String url) {
    showDialog(
        context: context, useRootNavigator: true, builder: (ctx) =>
        Dialog(
            insetPadding: const EdgeInsets.all(8),
            child: Stack(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url, fit: BoxFit.contain)),
              Positioned(top: 8, right: 8,
                  child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(
                              Icons.close, color: Colors.white, size: 18)))),
            ])));
  }

  // ── DC Correction Lifecycle — Before/After Approval sheet ────────────────
  Future<void> _showEditSheet(BuildContext context) async {
    final ch = widget.challan;
    final dcNumCtrl = TextEditingController(text: ch['dc_number'] as String? ?? '');
    final farmerCtrl = TextEditingController(text: ch['farmer_name'] as String? ?? '');
    final vehicleCtrl = TextEditingController(text: ch['vehicle_number'] as String? ?? '');
    final locationCtrl = TextEditingController(text: ch['farm_location'] as String? ?? '');
    final cratesCtrl = TextEditingController(text: (ch['crates_count'] as num?)?.toString() ?? '');
    final birdsCtrl = TextEditingController(
        text: ((ch['dc_adjusted_birds'] as num?) ?? (ch['bird_count'] as num?))?.toString() ?? '');
    final weightCtrl = TextEditingController(
        text: ((ch['dc_adjusted_weight'] as num?) ?? (ch['net_weight'] as num?))?.toStringAsFixed(2) ?? '');
    final notesCtrl = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet(
        context: context, isScrollControlled: true, useRootNavigator: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
              expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
              builder: (_, scrollCtrl) => SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.isShiftApproved ? 'Correct DC (Post-Approval)' : 'Verify / Edit DC',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        widget.isShiftApproved
                            ? 'This shift is already approved. A reason is required, and stock/batch costing will be recalculated.'
                            : 'Weight/bird corrections update agent stock and batch balance. Does not affect orders, billing or revenue.',
                        style: const TextStyle(fontSize: 11, color: kTextHint)),
                    const SizedBox(height: 16),
                    TextField(controller: dcNumCtrl, decoration: const InputDecoration(labelText: 'DC Number')),
                    const SizedBox(height: 10),
                    TextField(controller: farmerCtrl, decoration: const InputDecoration(labelText: 'Farmer / Source Name')),
                    const SizedBox(height: 10),
                    TextField(controller: vehicleCtrl, decoration: const InputDecoration(labelText: 'Vehicle Number')),
                    const SizedBox(height: 10),
                    TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Farm Location')),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: TextField(controller: cratesCtrl, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Crates'))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: birdsCtrl, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Confirmed Bird Count'))),
                    ]),
                    const SizedBox(height: 10),
                    TextField(controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Confirmed Net Weight (kg)')),
                    const SizedBox(height: 10),
                    TextField(controller: notesCtrl, maxLines: 2,
                        decoration: InputDecoration(
                            labelText: widget.isShiftApproved ? 'Reason for correction (required)' : 'Verification Notes',
                            hintText: widget.isShiftApproved
                                ? 'Explain why this DC needs correcting after approval'
                                : 'Required if bird count or weight was corrected',
                            alignLabelWithHint: true)),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                        onPressed: submitting ? null : () async {
                          final userId = Supabase.instance.client.auth.currentUser?.id;
                          final origBirds = (ch['bird_count'] as num?)?.toInt() ?? 0;
                          final origWt = (ch['net_weight'] as num?)?.toDouble() ?? 0;
                          final newBirds = int.tryParse(birdsCtrl.text.trim());
                          final newWt = double.tryParse(weightCtrl.text.trim());
                          final adjBirds = (newBirds != null && newBirds != origBirds) ? newBirds : null;
                          final adjWt = (newWt != null && newWt != origWt) ? newWt : null;
                          final notes = notesCtrl.text.trim();

                          if (widget.isShiftApproved && notes.isEmpty) {
                            showError(context, 'A reason is required to correct a DC after shift approval');
                            return;
                          }
                          if (!widget.isShiftApproved && (adjBirds != null || adjWt != null) && notes.isEmpty) {
                            showError(context, 'Please add a note explaining the correction');
                            return;
                          }

                          setSheetState(() => submitting = true);
                          String? nf(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
                          try {
                            if (widget.isShiftApproved) {
                              await Supabase.instance.client.rpc('correct_dc_post_approval', params: {
                                'p_challan_id': ch['id'],
                                'p_corrected_by': userId,
                                'p_reason': notes,
                                'p_adjusted_weight': adjWt,
                                'p_confirmed_birds': adjBirds,
                                'p_dc_number': nf(dcNumCtrl),
                                'p_farmer_name': nf(farmerCtrl),
                                'p_vehicle_number': nf(vehicleCtrl),
                                'p_farm_location': nf(locationCtrl),
                                'p_crates_count': int.tryParse(cratesCtrl.text.trim()),
                              }).timeout(const Duration(seconds: 12));
                            } else {
                              await Supabase.instance.client.rpc('verify_dc', params: {
                                'p_challan_id': ch['id'],
                                'p_verified_by': userId,
                                'p_notes': notes.isEmpty ? null : notes,
                                'p_adjusted_weight': adjWt,
                                'p_confirmed_birds': adjBirds,
                                'p_dc_number': nf(dcNumCtrl),
                                'p_farmer_name': nf(farmerCtrl),
                                'p_vehicle_number': nf(vehicleCtrl),
                                'p_farm_location': nf(locationCtrl),
                                'p_crates_count': int.tryParse(cratesCtrl.text.trim()),
                              }).timeout(const Duration(seconds: 12));
                            }
                            if (context.mounted) {
                              Navigator.of(ctx, rootNavigator: true).pop();
                              showSuccess(context, '✅ DC updated');
                              widget.onChanged();
                            }
                          } catch (e) {
                            setSheetState(() => submitting = false);
                            if (context.mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
                          }
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: widget.isShiftApproved ? Colors.deepOrange : Colors.blue),
                        child: submitting
                            ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(widget.isShiftApproved ? 'Submit Correction' : 'Save',
                            style: const TextStyle(color: Colors.white)))),
                    const SizedBox(height: 10),
                  ])));
        }));
  }

  Widget _row(String l, String v, [Color? c]) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(width: 120,
                child: Text(
                    l, style: const TextStyle(fontSize: 11, color: kTextSub))),
            Text(v, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c ?? kTextMain)),
          ]));
}