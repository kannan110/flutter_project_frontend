import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.id});
  final String id;
  @override ConsumerState<OrderDetailScreen> createState() => _S();
}

class _S extends ConsumerState<OrderDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _order;
  Map<String,dynamic>? _invoice;
  List<Map<String,dynamic>> _invoices = [];
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  // ── ALL BUSINESS LOGIC PRESERVED EXACTLY ──────────────────────────────────
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final o = await _c.from('orders')
        .select('*,retailers(shop_name,owner_name,phone,address)')
        .eq('id', widget.id).maybeSingle();
    final items = await _c.from('order_items')
        .select('*,master_products(name)').eq('order_id', widget.id);
    // FIX: an order can now have multiple invoices — one per delivery attempt
    // (Order 1:N Delivery, Delivery 1:1 Invoice). Fetch all instead of a single
    // row. Financial totals (total/balance/collected) are read from the order
    // row itself, which the backend keeps correctly summed across every
    // invoice for that order. _invoice (latest) is kept only for display
    // metadata (invoice_number/rate/kg on the summary card).
    final invRaw = await _c.from('invoices')
        .select('*')
        .eq('order_id', widget.id)
        .order('created_at', ascending: false);
    final invList = List<Map<String,dynamic>>.from(invRaw as List? ?? []);
    if (mounted) {
      setState(() {
      _order = o;
      _items = List<Map<String,dynamic>>.from(items);
      _invoices = invList;
      _invoice = invList.isNotEmpty ? invList.first : null;
      _loading = false;
    });
    }
  }

  Future<void> _updateStatus(String s) async {
    try { await _c.from('orders').update({'status': s}).eq('id', widget.id); _load();
    if (mounted) showSuccess(context, 'Status updated'); }
    catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _confirmRetailerOrder() async {
    DateTime selectedDate = DateTime.now();
    final dateCtrl = TextEditingController(
        text: '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}');
    String slot = 'today';
    await showDialog(
        context: context, useRootNavigator: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
            title: const Text('Confirm Retailer Order'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Set delivery date and confirm the order.',
                  style: TextStyle(fontSize: 12, color: kTextSub)),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Deliver: ', style: TextStyle(fontSize: 12)),
                Expanded(child: SegmentedButton<String>(
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 'today',    label: Text('Today')),
                      ButtonSegment(value: 'tomorrow', label: Text('Tomorrow')),
                    ],
                    selected: {slot},
                    onSelectionChanged: (s) {
                      ss(() {
                        slot = s.first;
                        selectedDate = slot == 'tomorrow'
                            ? DateTime.now().add(const Duration(days: 1))
                            : DateTime.now();
                        dateCtrl.text =
                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}';
                      });
                    })),
              ]),
              const SizedBox(height: 8),
              Text('Delivery Date: ${dateCtrl.text}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(), child: const Text('Cancel')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    Navigator.of(ctx, rootNavigator: true).pop();
                    try {
                      await _c.rpc('confirm_retailer_order', params: {
                        'p_order_id':      widget.id,
                        'p_delivery_date': '${selectedDate.year}'
                            '-${selectedDate.month.toString().padLeft(2,"0")}'
                            '-${selectedDate.day.toString().padLeft(2,"0")}',
                      });
                      _load();
                      if (mounted) {
                        showSuccess(context,
                          'Order confirmed for ${dateCtrl.text}. Retailer notified.');
                      }
                    } catch (e) {
                      if (mounted) showError(context, e.toString().replaceAll('Exception: ',''));
                    }
                  },
                  child: const Text('Confirm Order')),
            ])));
  }

  Future<void> _cancelOrder() async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Cancel Order'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This will cancel the order at any stage and adjust stock if already dispatched.',
            style: TextStyle(fontSize: 13, color: Colors.orange)),
        const SizedBox(height: 12),
        TextField(controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Customer request')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonCtrl.text.trim().isEmpty ? 'Cancelled by trader' : reasonCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            child: const Text('Cancel Order')),
      ],
    ));
    if (reason == null || !mounted) return;
    try {
      await _c.rpc('cancel_order', params: {'p_order_id': widget.id, 'p_reason': reason});
      if (mounted) { showSuccess(context, 'Order cancelled ✓'); _load(); }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── PARTIAL PROGRESS — redesigned, same data ───────────────────────────────
  Widget _buildPartialProgress() {
    final o            = _order!;
    final totalBirds   = (o['estimated_birds']   as num?)?.toInt()    ?? 0;
    final totalKg      = (o['total_quantity']     as num?)?.toDouble() ?? 0;
    final fulfilledB   = (o['fulfilled_birds']    as num?)?.toInt()    ?? 0;
    final fulfilledKg  = (o['fulfilled_quantity'] as num?)?.toDouble() ?? 0;
    final backorderB   = (o['backorder_birds']    as num?)?.toInt()    ?? 0;
    final backorderKg  = (o['backorder_quantity'] as num?)?.toDouble() ?? 0;
    final partialCount = (o['partial_count']      as num?)?.toInt()    ?? 0;
    final pct = totalBirds > 0 ? (fulfilledB / totalBirds).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:        Colors.orange.shade50,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border:       Border.all(color: Colors.orange.withValues(alpha: 0.35), width: 1.5),
        boxShadow:    kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:        Colors.orange,
              borderRadius: BorderRadius.circular(kRadiusChip),
            ),
            child: Text('Partial Delivery — Attempt $partialCount',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Fulfilled', style: TextStyle(fontSize: 12, color: kTextSub,
              fontWeight: FontWeight.w600)),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: Colors.orange)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value:           pct,
            minHeight:       10,
            backgroundColor: Colors.orange.shade100,
            valueColor:      const AlwaysStoppedAnimation(Colors.orange),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _pCol('Ordered',   '$totalBirds birds',    '${totalKg.toStringAsFixed(1)} kg',   Colors.blue),
          Container(width: 1, height: 50, color: Colors.orange.shade200,
              margin: const EdgeInsets.symmetric(horizontal: 10)),
          _pCol('Delivered', '$fulfilledB birds',    '${fulfilledKg.toStringAsFixed(1)} kg', Colors.green),
          Container(width: 1, height: 50, color: Colors.orange.shade200,
              margin: const EdgeInsets.symmetric(horizontal: 10)),
          _pCol('Remaining', '$backorderB birds',    '${backorderKg.toStringAsFixed(1)} kg',
              backorderB > 0 ? Colors.orange : Colors.grey),
        ]),
      ]),
    );
  }

  Widget _pCol(String l, String birds, String kg, Color c) =>
      Expanded(child: Column(children: [
        Text(l, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700,
            letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(birds, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c)),
        Text(kg, style: TextStyle(fontSize: 11, color: c.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600)),
      ]));

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD — premium mobile UI
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: kBgPage, body: LoadingList());
    if (_order == null) {
      return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(backgroundColor: kSurface),
        body: const Center(child: Text('Not found')));
    }

    final r          = _order!['retailers'] as Map<String,dynamic>?;
    final status     = _order!['status']    as String? ?? 'pending';
    final date       = DateTime.tryParse(_order!['created_at'] as String? ?? '');
    final birds      = _order!['estimated_birds'] as int? ?? 0;
    final totalKg    = (_order!['total_quantity'] as num?)?.toDouble() ?? 0;
    final hasInv     = _invoice != null;
    final sc         = SC.order(status);

    // FIX: an order can have multiple invoices (one per delivery attempt).
    // Financial totals must come from the order row, which the backend keeps
    // correctly summed across every invoice — reading a single invoice's
    // amount here would silently understate the order once it has 2+
    // delivery attempts. _invoice (latest) is used only for display-only
    // metadata below (rate/kg), never for money totals.
    final displayAmt = (_order!['total_amount']     as num?)?.toDouble() ?? 0;
    final balAmt     = (_order!['balance_amount']   as num?)?.toDouble() ?? 0;
    final collAmt    = (_order!['collected_amount'] as num?)?.toDouble() ?? 0;
    final rateKg  = hasInv
        ? (_invoice!['price_per_kg']   as num?)?.toDouble()
        : (_order!['final_price']      as num?)?.toDouble();
    final invKg   = hasInv ? (_invoice!['quantity_kg'] as num?)?.toDouble() : null;

    final isDesktop = context.isDesktop;

    // Build shared content sections as widget lists
    final contentSections = <Widget>[

      // ── Customer hero card ─────────────────────────────────────────
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kNavy, kNavyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(kRadiusHero),
          boxShadow: [BoxShadow(
              color: kNavy.withValues(alpha: 0.3),
              blurRadius: 20, offset: const Offset(0, 6))],
        ),
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r?['shop_name'] as String? ?? '—',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                  color: Colors.white)),
          if (r?['owner_name'] != null) ...[
            const SizedBox(height: 4),
            Text(r!['owner_name'] as String,
                style: const TextStyle(fontSize: 14, color: Color(0xFFB4C6F4),
                    fontWeight: FontWeight.w600)),
          ],
          if (r?['phone'] != null) ...[
            const SizedBox(height: 2),
            Text(r!['phone'] as String,
                style: const TextStyle(fontSize: 13, color: Color(0xFFB4C6F4))),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color:        sc.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(kRadiusChip),
                border:       Border.all(color: sc.withValues(alpha: 0.4)),
              ),
              child: Text(status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                      color: status == 'delivered' || status == 'closed'
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFED7AA),
                      letterSpacing: 0.5)),
            ),
            const SizedBox(width: 10),
            if (date != null)
              Text(DateFormat('d MMM y').format(date),
                  style: const TextStyle(fontSize: 12,
                      color: Color(0xFFB4C6F4))),
          ]),
        ]),
      ),

      // ── Partial delivery progress ──────────────────────────────────
      if (_order!['is_partial_delivery'] == true ||
          _order!['status'] == 'partially_delivered')
        _buildPartialProgress(),

      // ── Order items ────────────────────────────────────────────────
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(color: kBorderLight),
          boxShadow:    kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(children: [
              Icon(Icons.shopping_basket_outlined,
                  color: kGold, size: 16),
              SizedBox(width: 8),
              Text('ORDER ITEMS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                      color: kNavy, letterSpacing: 0.6)),
            ]),
          ),
          const Divider(height: 20, indent: 18, endIndent: 18, color: kBorderLight),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text('No items', style: TextStyle(color: kTextHint, fontSize: 13)),
            )
          else
            ..._items.asMap().entries.map((e) {
              final i    = e.key;
              final item = e.value;
              final p    = item['master_products'] as Map<String,dynamic>?;
              final w    = (item['total_weight'] as num?)?.toDouble();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  border: i < _items.length - 1
                      ? const Border(bottom: BorderSide(color: kBorderLight))
                      : null,
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color:        kNavy.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(kRadiusInner),
                    ),
                    child: const Center(child: Text('🐔',
                        style: TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p?['name'] as String? ?? '—',
                      style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w700, color: kNavy))),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (item['bird_count'] != null)
                      Text('${item['bird_count']} birds',
                          style: const TextStyle(fontSize: 14,
                              fontWeight: FontWeight.w900, color: kNavy)),
                    if (w != null)
                      Text('${w.toStringAsFixed(2)} kg',
                          style: const TextStyle(fontSize: 12, color: kTextSub,
                              fontWeight: FontWeight.w600)),
                  ]),
                ]),
              );
            }),
          const SizedBox(height: 4),
        ]),
      ),

      // ── Amount card ────────────────────────────────────────────────
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color:        kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border:       Border.all(color: kBorderLight),
          boxShadow:    kCardShadow,
        ),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.currency_rupee_rounded, color: kGold, size: 16),
            const SizedBox(width: 8),
            const Text('AMOUNT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                    color: kNavy, letterSpacing: 0.6)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        hasInv ? kSuccess.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusChip),
                border: Border.all(
                  color: hasInv ? kSuccess.withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Text(hasInv ? 'Billed ✓' : 'Estimate',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                      color: hasInv ? kSuccess : Colors.orange)),
            ),
          ]),
          const Divider(height: 20, color: kBorderLight),
          if (birds > 0)   _amtRow('Birds ordered',     '$birds'),
          if (totalKg > 0) _amtRow('Weight ordered',    '${totalKg.toStringAsFixed(2)} kg'),
          if (hasInv) ...[
            _amtRow('Delivered weight', '${(invKg ?? 0).toStringAsFixed(2)} kg'),
            // FIX: was always showing invoices.price_per_kg (a blended
            // Total ÷ Weight average) labeled simply "Rate" — for multi-product
            // orders this hides each product's real rate behind one misleading
            // number (e.g. Broiler ₹202 + Broiler Small ₹190 shown as "₹199").
            // Single product (the only case where an average IS the real rate):
            // show "Rate" as before, unchanged.
            // Multi-product: show each product's own applied_rate instead —
            // sourced from order_items, the same per-line data already proven
            // correct in invoice_detail_screen.dart. No new fetch needed.
            if (_items.length <= 1 && rateKg != null)
              _amtRow('Rate', '₹${rateKg.toStringAsFixed(2)} / kg')
            else if (_items.length > 1)
              ..._items.map((item) {
                final name = (item['master_products']
                as Map<String, dynamic>?)?['name'] as String? ??
                    'Product';
                final r = (item['applied_rate'] as num?)?.toDouble() ??
                    (item['rate_per_kg'] as num?)?.toDouble();
                if (r == null) return const SizedBox.shrink();
                return _amtRow('$name rate', '₹${r.toStringAsFixed(2)} / kg');
              }),
          ],
          if (_order!['payment_type'] != null)
            _amtRow('Payment', (_order!['payment_type'] as String).toUpperCase()),
          const Divider(height: 20, color: kBorderLight),
          // Total
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(hasInv ? 'Invoice Amount' : 'Estimated Amount',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: kNavy)),
            Text(Fmt.amount(displayAmt),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                    color: kNavy)),
          ]),
          if (hasInv) ...[
            const SizedBox(height: 8),
            _amtRow('Collected', Fmt.amount(collAmt),
                valueColor: kSuccess),
            _amtRowBold('Balance', Fmt.amount(balAmt),
                valueColor: balAmt > 0 ? Colors.orange : kSuccess),
          ] else ...[
            const SizedBox(height: 6),
            const Text('Actual amount set at delivery approval',
                style: TextStyle(fontSize: 11, color: kTextHint)),
          ],
          if (_order!['notes'] != null) ...[
            const Divider(height: 20, color: kBorderLight),
            _amtRow('Notes', _order!['notes'] as String),
          ],
          if ((_order!['remarks'] as String?)?.trim().isNotEmpty == true) ...[
            const Divider(height: 20, color: kBorderLight),
            _amtRow('Remarks', _order!['remarks'] as String),
          ],
        ]),
      ),

      // ── Invoice link(s) ──────────────────────────────────────────────
      // FIX: an order can now have multiple invoices (one per delivery
      // attempt). Show one button per invoice instead of assuming a single
      // invoice exists.
      if (_invoices.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final inv in _invoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(R.invoiceDetailPath(inv['id'])),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      _invoices.length > 1
                          ? 'View Invoice ${inv['invoice_number'] ?? ''} '
                          '(${Fmt.amount((inv['total_amount'] as num?)?.toDouble() ?? 0)})'
                          : 'View Invoice ${inv['invoice_number'] ?? ''}',
                    ),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50)),
                  ),
                ),
            ],
          ),
        ),

      // ── Actions ────────────────────────────────────────────────────
      if (!['cancelled','invoiced','closed'].contains(status)) ...[

        // Retailer order pending confirmation
        if (status == 'pending' && _order!['source'] == 'retailer') ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.orange.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border:       Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.store_outlined, size: 14, color: Colors.orange),
                SizedBox(width: 6),
                Text('Retailer Order — Awaiting Confirmation',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: Colors.orange)),
              ]),
              SizedBox(height: 4),
              Text('Review the order, set delivery date and confirm.',
                  style: TextStyle(fontSize: 11, color: kTextSub)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: _confirmRetailerOrder,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Confirm Order + Set Delivery Date'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 52)),
          ),
          const SizedBox(height: 10),
        ],

        // Agent-entered order pending approval (pre-shift order entry).
        // Reuses _confirmRetailerOrder() / confirm_retailer_order RPC as-is —
        // the RPC's source guard was extended to accept 'delivery_agent'
        // alongside 'retailer'; no separate approval code path exists.
        if (status == 'pending' && _order!['source'] == 'delivery_agent') ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.orange.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border:       Border.all(color: Colors.orange.withValues(alpha: 0.35)),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.delivery_dining_outlined, size: 14, color: Colors.orange),
                SizedBox(width: 6),
                Text('Agent Order — Awaiting Approval',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: Colors.orange)),
              ]),
              SizedBox(height: 4),
              Text('Entered by delivery agent before shift. Review and approve, or cancel below.',
                  style: TextStyle(fontSize: 11, color: kTextSub)),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: _confirmRetailerOrder,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Approve Order + Set Delivery Date'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 52)),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
      ],

      if (status == 'confirmed') ...[
        OutlinedButton.icon(
          onPressed: () => context.go(R.dispatch),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: const Text('Assign to Batch → Dispatch'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50)),
        ),
        const SizedBox(height: 10),
      ],

      OutlinedButton.icon(
        onPressed: _cancelOrder,
        icon: const Icon(Icons.cancel_outlined, size: 18, color: kError),
        label: const Text('Cancel Order'),
        style: OutlinedButton.styleFrom(
            foregroundColor:  kError,
            side:             const BorderSide(color: kError),
            minimumSize:      const Size(double.infinity, 50)),
      ),
    ];

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: kBgPage,
        appBar: AppBar(
          backgroundColor: kSurface,
          title: const Text('Order Detail'),
          actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: contentSections,
        ),
      );
    }

    // ── Desktop 2-column layout ──────────────────────────────────────────
    // Split: first N sections go left, financial + actions go right
    // We put the last 2 whitecard blocks (billing + actions) in the right panel
    final leftSections  = contentSections.length > 3
        ? contentSections.sublist(0, contentSections.length - 2)
        : contentSections;
    final rightSections = contentSections.length > 3
        ? contentSections.sublist(contentSections.length - 2)
        : <Widget>[];

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Order Detail'),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Left: customer + items ─────────────────────────────────────
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 40),
            children: leftSections,
          ),
        ),
        Container(width: 1, color: kBorderLight),
        // ── Right: billing + actions ───────────────────────────────────
        SizedBox(
          width: 340,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 24, 40),
            children: rightSections,
          ),
        ),
      ]),
    );
  }

  Widget _amtRow(String label, String value, {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: kTextSub,
              fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: valueColor ?? kTextMain)),
        ]),
      );

  Widget _amtRowBold(String label, String value, {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: kNavy)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
              color: valueColor ?? kNavy)),
        ]),
      );
}