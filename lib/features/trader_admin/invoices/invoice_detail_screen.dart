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
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final inv = await _c.from('invoices')
        .select('*,retailers(shop_name,owner_name,phone,address),traders(company_name,phone,gst_number)')
        .eq('id', widget.id).maybeSingle();
    if (mounted) setState(() { _inv = inv; _loading = false; });
  }

  // Enhancement: build WhatsApp message text
  String _buildWhatsAppText() {
    final inv     = _inv!;
    final r       = inv['retailers'] as Map<String,dynamic>?;
    final t       = inv['traders']   as Map<String,dynamic>?;
    final date    = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final kg      = (inv['quantity_kg'] as num?)?.toDouble() ?? 0;
    final rate    = (inv['price_per_kg'] as num?)?.toDouble() ?? 0;
    final total   = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final coll    = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal     = (inv['balance_amount'] as num?)?.toDouble() ?? 0;
    final invNum  = inv['invoice_number'] as String? ?? '—';
    final dateStr = date != null ? DateFormat('d MMM y').format(date) : '—';

    return '''🐓 *${t?['company_name'] ?? 'Rooster Trader'}*

📄 *Invoice: $invNum*
📅 Date: $dateStr

👤 Customer: ${r?['shop_name'] ?? '—'}

────────────────────
🐔 Weight: ${kg.toStringAsFixed(2)} kg
💰 Rate:   ₹${rate.toStringAsFixed(2)}/kg
────────────────────
💵 Total:     ₹${total.toStringAsFixed(2)}
✅ Collected: ₹${coll.toStringAsFixed(2)}
⏳ Balance:   ₹${bal.toStringAsFixed(2)}
────────────────────

${bal > 0 ? '⚠️ Balance due: ₹${bal.toStringAsFixed(2)}' : '✅ Fully paid'}

_Rooster Trader PTOS_''';
  }

  Future<void> _shareWhatsApp() async {
    final text = _buildWhatsAppText();
    // Copy to clipboard — user can paste in WhatsApp
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showSuccess(context, 'Invoice text copied — paste in WhatsApp ✓');
      // Show the text so user can verify
      showDialog(context: context, useRootNavigator: true, builder: (ctx) => AlertDialog(
        title: const Text('WhatsApp Message Ready'),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 13))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(), child: const Text('Close')),
          ElevatedButton(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            Navigator.of(ctx, rootNavigator: true).pop();
            if (mounted) showSuccess(context, 'Copied ✓ Paste in WhatsApp');
          }, child: const Text('Copy Again')),
        ],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_inv == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Invoice not found')));
    final inv    = _inv!;
    final r      = inv['retailers'] as Map<String,dynamic>?;
    final date   = DateTime.tryParse(inv['invoice_date'] as String? ?? '');
    final status = inv['status'] as String? ?? 'draft';
    final kg     = (inv['quantity_kg'] as num?)?.toDouble() ?? 0;
    final birds  = inv['bird_count'] as int? ?? 0;
    final rate   = (inv['price_per_kg'] as num?)?.toDouble() ?? 0;
    final total  = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final coll   = (inv['collected_amount'] as num?)?.toDouble() ?? 0;
    final bal    = (inv['balance_amount'] as num?)?.toDouble() ?? 0;
    final disc   = (inv['discount_amount'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(inv['invoice_number'] as String? ?? 'Invoice'),
        actions: [
          // Enhancement: WhatsApp share
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share via WhatsApp',
            onPressed: _shareWhatsApp,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // Header card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('INVOICE', style: TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              StatusBadge(status, Colors.white70),
            ]),
            const SizedBox(height: 6),
            Text(inv['invoice_number'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            if (date != null) Text(DateFormat('d MMMM y').format(date), style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const Divider(color: Colors.white24, height: 18),
            Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            if (r?['owner_name'] != null) Text(r!['owner_name'] as String, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (r?['phone'] != null) Text(r!['phone'] as String, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ])),
        const SizedBox(height: 14),

        // Details
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('BILL DETAILS'),
          if (birds > 0) InfoRow('Birds', '$birds'),
          InfoRow('Weight', '${kg.toStringAsFixed(3)} kg'),
          InfoRow('Rate', '₹${rate.toStringAsFixed(2)} per kg'),
          if (disc > 0) InfoRow('Discount', '−${Fmt.amount(disc)}'),
          const Divider(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Bill', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(Fmt.amount(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kPrimary)),
          ]),
          if (coll > 0) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Collected', style: TextStyle(fontSize: 12, color: kTextSub)),
              Text(Fmt.amount(coll), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Balance Due', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(Fmt.amount(bal), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: bal > 0 ? Colors.orange : Colors.green)),
            ]),
          ],
        ])),
        const SizedBox(height: 14),

        // Share button
        ElevatedButton.icon(
          onPressed: _shareWhatsApp,
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Copy Invoice for WhatsApp'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('Copies formatted invoice text to clipboard — paste in WhatsApp', style: TextStyle(fontSize: 11, color: kTextHint), textAlign: TextAlign.center)),
        const SizedBox(height: 20),
      ]),
    );
  }
}
