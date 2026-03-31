import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class ShiftDetailScreen extends StatefulWidget {
  const ShiftDetailScreen({super.key, required this.id});
  final String id;
  @override State<ShiftDetailScreen> createState() => _S();
}
class _S extends State<ShiftDetailScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _shift;
  List<Map<String,dynamic>> _deliveries = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _c.from('delivery_shifts').select('*,delivery_agents(name,vehicle_no)').eq('id', widget.id).maybeSingle();
    final d = await _c.from('deliveries').select('id,status,orders(retailers(shop_name))').eq('delivery_shift_id', widget.id);
    if (mounted) setState(() { _shift = s; _deliveries = List<Map<String,dynamic>>.from(d); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    if (_shift == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    final s = _shift!;
    final a = s['delivery_agents'] as Map<String,dynamic>?;
    final status = s['status'] as String? ?? 'open';
    final startAt = DateTime.tryParse(s['shift_start_at'] as String? ?? '');
    final endAt = s['shift_end_at'] != null ? DateTime.tryParse(s['shift_end_at'] as String) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Shift Detail'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(a?['name'] as String? ?? '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), StatusBadge(status, SC.shift(status))]),
          if (a?['vehicle_no'] != null) Text('Vehicle: ${a!['vehicle_no']}', style: const TextStyle(fontSize: 12, color: kTextSub)),
          const Divider(height: 18),
          if (startAt != null) InfoRow('Started', DateFormat('d MMM y, h:mm a').format(startAt)),
          if (endAt != null) InfoRow('Ended', DateFormat('d MMM y, h:mm a').format(endAt)),
          InfoRow('Odometer Start', '${s['odometer_start'] ?? '—'} km'),
          InfoRow('Odometer End', '${s['odometer_end'] ?? '—'} km'),
          InfoRow('Orders', '${s['total_orders'] ?? 0}'),
          InfoRow('Cash Collected', Fmt.amount((s['total_cash_collected'] as num?)?.toDouble() ?? 0)),
          InfoRow('Expenses', Fmt.amount((s['total_expenses'] as num?)?.toDouble() ?? 0)),
        ])),
        const SizedBox(height: 14),
        const SectionHeader('DELIVERIES'),
        ..._deliveries.map((d) {
          final o = d['orders'] as Map<String,dynamic>?;
          final r = o?['retailers'] as Map<String,dynamic>?;
          return Container(margin: const EdgeInsets.only(bottom: 8), child: WhiteCard(padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: Text(r?['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              StatusBadge(d['status'] as String? ?? '—', SC.order(d['status'] as String? ?? ''), small: true),
            ])));
        }),
      ]),
    );
  }
}
