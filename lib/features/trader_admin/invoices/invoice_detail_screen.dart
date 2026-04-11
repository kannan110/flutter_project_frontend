import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;
  @override State<InvoiceDetailScreen> createState() => _S();
}

class _S extends State<InvoiceDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _inv;
  List<Map<String,dynamic>> _items = []; // order_items per product
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Load invoice with retailer + trader info
      final inv = await _c.from('invoices')
          .select('*,'
                  'retailers(shop_name,owner_name,phone,address),'
                  'traders(company_name,phone,gst_number)')
          .eq('id', widget.id)
          .maybeSingle();

      // Load order_items for this invoice's order
      List<Map<String,dynamic>> items = [];
      final orderId = inv?['order_id'] as String?;
      if (orderId != null) {
        final raw = await _c.from('order_items')
            .select('id,bird_count,avg_weight_per_bird,total_weight,rate_per_kg,line_total,'
                    'master_products(name,unit)')
            .eq('order_id', orderId)
            .order('created_at');
        items = List<Map<String,dynamic>>.from(raw as List? ?? []);
      }

      if (!mounted) return;
      setState(() { _inv = inv; _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isMultiItem => _items.length >= 2;

  String _buildWhatsAppText() {
    final inv    = _inv!;
    final r      = inv['retailers'] as Map<String,dynamic>?;
    final t      = inv['traders']   as Map<String,dynamic>?;
    final date   = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final total  = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final coll   = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal    = (inv['balance_amount']   as num?)?.toDouble() ?? 0;
    final invNum = inv['invoice_number'] as String? ?? '—';
    final dateStr = date != null ? DateFormat('d MMM y').format(date) : '—';

    final buf = StringBuffer();
    buf.writeln('🐓 *${t?['company_name'] ?? 'Rooster Trader'}*');
    buf.writeln();
    buf.writeln('📄 *Invoice: $invNum*');
    buf.writeln('📅 Date: $dateStr');
    buf.writeln();
    buf.writeln('👤 Customer: ${r?['shop_name'] ?? '—'}');
    buf.writeln();
    buf.writeln('────────────────────');

    if (_isMultiItem) {
      // Per-product breakdown
      for (final item in _items) {
        final mp      = item['master_products'] as Map<String,dynamic>?;
        final name    = mp?['name'] as String? ?? 'Product';
        final birds   = (item['bird_count'] as num?)?.toInt() ?? 0;
        final wt      = (item['total_weight'] as num?)?.toDouble() ?? 0;
        final rate    = (item['rate_per_kg'] as num?)?.toDouble() ?? 0;
        final lineT   = (item['line_total'] as num?)?.toDouble() ?? (wt * rate);
        final avg     = (item['avg_weight_per_bird'] as num?)?.toDouble() ?? 0;
        buf.writeln('🐔 *$name*');
        if (birds > 0) buf.writeln('   Birds: $birds${avg > 0 ? ' (avg ${avg.toStringAsFixed(2)} kg/bird)' : ''}');
        buf.writeln('   Weight: ${wt.toStringAsFixed(2)} kg');
        buf.writeln('   Rate:   ₹${rate.toStringAsFixed(2)}/kg');
        buf.writeln('   Amount: ₹${lineT.toStringAsFixed(2)}');
        buf.writeln();
      }
    } else {
      final kg   = (inv['quantity_kg'] as num?)?.toDouble() ?? 0;
      final rate = (inv['price_per_kg'] as num?)?.toDouble() ?? 0;
      final birds = inv['bird_count'] as int? ?? 0;
      if (birds > 0) buf.writeln('🐔 Birds: $birds');
      buf.writeln('⚖️ Weight: ${kg.toStringAsFixed(2)} kg');
      buf.writeln('💰 Rate:   ₹${rate.toStringAsFixed(2)}/kg');
      buf.writeln();
    }

    buf.writeln('────────────────────');
    buf.writeln('💵 Total:     ₹${total.toStringAsFixed(2)}');
    buf.writeln('✅ Collected: ₹${coll.toStringAsFixed(2)}');
    buf.writeln('⏳ Balance:   ₹${bal.toStringAsFixed(2)}');
    buf.writeln('────────────────────');
    buf.writeln();
    buf.writeln(bal > 0 ? '⚠️ Balance due: ₹${bal.toStringAsFixed(2)}' : '✅ Fully paid');
    buf.writeln();
    buf.writeln('_Rooster Trader PTOS_');
    return buf.toString();
  }

  Future<void> _shareWhatsApp() async {
    final text = _buildWhatsAppText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccess(context, 'Invoice copied — paste in WhatsApp ✓');
    showDialog(context: context, useRootNavigator: true, builder: (ctx) => AlertDialog(
      title: const Text('WhatsApp Invoice Ready'),
      content: SingleChildScrollView(child: SelectableText(text,
          style: const TextStyle(fontSize: 13, height: 1.5))),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
            child: const Text('Close')),
        ElevatedButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.of(ctx, rootNavigator: true).pop();
            if (mounted) showSuccess(context, 'Copied ✓');
          },
          child: const Text('Copy Again')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_inv == null) return Scaffold(
        appBar: AppBar(), body: const Center(child: Text('Invoice not found')));

    final inv    = _inv!;
    final r      = inv['retailers'] as Map<String,dynamic>?;
    final date   = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final status = inv['status'] as String? ?? 'draft';
    final kg     = (inv['quantity_kg']      as num?)?.toDouble() ?? 0;
    final birds  = inv['bird_count'] as int? ?? 0;
    final rate   = (inv['price_per_kg']     as num?)?.toDouble() ?? 0;
    final total  = (inv['total_amount']     as num?)?.toDouble() ?? 0;
    final coll   = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal    = (inv['balance_amount']   as num?)?.toDouble() ?? 0;
    final disc   = (inv['discount_amount']  as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(inv['invoice_number'] as String? ?? 'Invoice'),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _shareWhatsApp),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Header card ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 10,
                  color: Colors.white60, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              StatusBadge(status, Colors.white70),
            ]),
            const SizedBox(height: 4),
            Text(inv['invoice_number'] as String? ?? '—',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            if (date != null)
              Text(DateFormat('d MMMM y').format(date),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const Divider(color: Colors.white24, height: 18),
            Text(r?['shop_name'] as String? ?? '—',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            if (r?['owner_name'] != null)
              Text(r!['owner_name'] as String,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (r?['phone'] != null)
              Text(r!['phone'] as String,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ])),
        const SizedBox(height: 14),

        // ── Item breakdown ───────────────────────────────────────────
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SectionHeader('BILL DETAILS')),
            if (_isMultiItem) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
              child: Text('${_items.length} products',
                  style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w700))),
          ]),

          if (_isMultiItem) ...[
            // ── Multi-product itemised table ─────────────────────────
            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Expanded(flex: 3, child: Text('Product',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextHint))),
                const SizedBox(width: 6),
                const Expanded(flex: 2, child: Text('Birds / Wt',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextHint),
                    textAlign: TextAlign.center)),
                const SizedBox(width: 6),
                const Expanded(flex: 2, child: Text('Rate',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextHint),
                    textAlign: TextAlign.center)),
                const Expanded(flex: 2, child: Text('Amount',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextHint),
                    textAlign: TextAlign.right)),
              ])),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // One row per item
            ..._items.map((item) {
              final mp     = item['master_products'] as Map<String,dynamic>?;
              final name   = mp?['name'] as String? ?? 'Product';
              final iBirds = (item['bird_count']       as num?)?.toInt()    ?? 0;
              final iWt    = (item['total_weight']      as num?)?.toDouble() ?? 0;
              final iRate  = (item['rate_per_kg']       as num?)?.toDouble() ?? 0;
              final iTotal = (item['line_total']        as num?)?.toDouble() ?? (iWt * iRate);
              final iAvg   = (item['avg_weight_per_bird'] as num?)?.toDouble() ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Product name badge
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(name, style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: kPrimary))),
                  ]),
                  const SizedBox(height: 8),
                  // Detail row
                  Row(children: [
                    _itemCol('Birds',  iBirds > 0 ? '$iBirds' : '—', Colors.teal),
                    _itemCol('Weight', '${iWt.toStringAsFixed(2)} kg', Colors.blue),
                    _itemCol('Avg/bird', iAvg > 0 ? '${iAvg.toStringAsFixed(3)} kg' : '—', kTextSub),
                    _itemCol('Rate',   '₹${iRate.toStringAsFixed(2)}/kg', Colors.orange),
                  ]),
                  const SizedBox(height: 6),
                  // Line total
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '${iWt.toStringAsFixed(2)} kg × ₹${iRate.toStringAsFixed(2)} = ${Fmt.amount(iTotal)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kPrimary))),
                ]));
            }),

            const Divider(height: 14),
            // Grand total row
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_items.fold(0, (s, i) => s + ((i['bird_count'] as num?)?.toInt() ?? 0))} birds total  ·  '
                   '${_items.fold(0.0, (s, i) => s + ((i['total_weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)} kg',
                  style: const TextStyle(fontSize: 12, color: kTextSub)),
            ]),

          ] else ...[
            // ── Single item (legacy) ──────────────────────────────────
            if (birds > 0) InfoRow('Birds',  '$birds'),
            InfoRow('Weight', '${kg.toStringAsFixed(3)} kg'),
            InfoRow('Rate',   '₹${rate.toStringAsFixed(2)} per kg'),
            if (disc > 0) InfoRow('Discount', '−${Fmt.amount(disc)}'),
          ],

          // ── Summary ──────────────────────────────────────────────────
          const Divider(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Bill',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(Fmt.amount(total),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPrimary)),
          ]),
          if (disc > 0) ...[
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Discount', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text('−${Fmt.amount(disc)}',
                  style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
          ],
          if (coll > 0) ...[
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Collected', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text(Fmt.amount(coll),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Balance Due',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(Fmt.amount(bal),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                      color: bal > 0 ? Colors.orange : Colors.green)),
            ]),
          ],
          if (bal <= 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                SizedBox(width: 6),
                Text('Fully Paid', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
              ])),
          ],
        ])),
        const SizedBox(height: 14),

        // ── Share button ─────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _shareWhatsApp,
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Copy Invoice for WhatsApp'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              minimumSize: const Size(double.infinity, 48))),
        const SizedBox(height: 6),
        const Center(child: Text(
            'Copies formatted invoice to clipboard — paste in WhatsApp',
            style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center)),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _itemCol(String label, String value, Color color) => Expanded(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 9, color: kTextHint)),
    Text(value,  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
  ]));
}
