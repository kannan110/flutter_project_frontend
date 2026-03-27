import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class BatchDetailScreen extends ConsumerStatefulWidget {
  const BatchDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends ConsumerState<BatchDetailScreen> {
  final _client = Supabase.instance.client;
  Map<String, dynamic>? _batch;
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final b = await _client.from('delivery_batches').select('*, delivery_agents(id,name,phone,vehicle_no), delivery_challans(*)').eq('id', widget.id).maybeSingle();
    final d = List<Map<String, dynamic>>.from(await _client.from('deliveries')
        .select('*, orders(*, retailers(id,shop_name,owner_name,phone))').eq('batch_id', widget.id).order('assigned_at'));
    if (mounted) setState(() { _batch = b; _deliveries = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_batch == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Batch not found')));
    final agent  = _batch!['delivery_agents'] as Map<String, dynamic>?;
    final status = _batch!['status'] as String? ?? 'assigned';
    final challans = _batch!['delivery_challans'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Batch Detail'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StatusBadge(status.replaceAll('_', ' '), StatusColors.order(status)),
              const Spacer(),
              Text(DateFormat('d MMM HH:mm').format(DateTime.tryParse(_batch!['created_at'] as String? ?? '') ?? DateTime.now()),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
            ]),
            const SizedBox(height: 10),
            InfoRow('Agent',        agent?['name'] ?? '—'),
            InfoRow('Vehicle',      agent?['vehicle_no'] ?? '—'),
            InfoRow('Total Orders', '${_batch!['total_orders']} orders'),
            InfoRow('Total Weight', '${(_batch!['total_weight'] as num?)?.toStringAsFixed(2) ?? 0} kg'),
            InfoRow('Total Amount', '₹${(_batch!['total_amount'] as num?)?.toStringAsFixed(2) ?? 0}', valueColor: AppTheme.primary),
            if (_batch!['farm_name'] != null) InfoRow('Farm', _batch!['farm_name'] as String),
          ]),
        ),
        if (challans.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader('DELIVERY CHALLAN'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('DC Number',   (challans.first as Map)['dc_number'] as String? ?? '—'),
              InfoRow('Farmer',      (challans.first as Map)['farmer_name'] as String? ?? '—'),
              InfoRow('Gross Wt',   '${((challans.first as Map)['gross_weight'] as num?)?.toStringAsFixed(2) ?? 0} kg'),
              InfoRow('Net Wt',     '${((challans.first as Map)['net_weight'] as num?)?.toStringAsFixed(2) ?? 0} kg'),
              InfoRow('Bird Count', '${(challans.first as Map)['bird_count'] ?? 0}'),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        const SectionHeader('DELIVERIES'),
        ..._deliveries.map((d) {
          final order    = d['orders'] as Map<String, dynamic>?;
          final retailer = order?['retailers'] as Map<String, dynamic>?;
          final dStatus  = d['status'] as String? ?? 'assigned';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                border: const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE)))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(retailer?['shop_name'] ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(retailer?['phone'] as String? ?? '—', style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
                if ((d['delivered_total_weight'] as num?) != null)
                  Text('${(d['delivered_total_weight'] as num).toStringAsFixed(2)} kg delivered',
                      style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
              ])),
              StatusBadge(dStatus.replaceAll('_', ' '), StatusColors.order(dStatus)),
            ]),
          );
        }),
      ]),
    );
  }
}
