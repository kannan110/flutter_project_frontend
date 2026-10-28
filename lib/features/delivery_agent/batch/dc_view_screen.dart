import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// DC View Screen — shows all DCs for a batch with full details
class DcViewScreen extends StatefulWidget {
  const DcViewScreen({super.key, required this.batchId});
  final String batchId;
  @override State<DcViewScreen> createState() => _S();
}

class _S extends State<DcViewScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _challans = [];
  Map<String,dynamic>? _batch;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final b = await _c.from('delivery_batches')
          .select('id,status,vehicle_no,delivery_agents(name,phone,vehicle_no)')
          .eq('id', widget.batchId)
          .maybeSingle();
      final cList = await _c.from('delivery_challans')
          .select('*')
          .eq('batch_id', widget.batchId)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _batch    = b;
        _challans = List<Map<String,dynamic>>.from(cList as List? ?? []);
        _loading  = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = _batch?['delivery_agents'] as Map<String,dynamic>?;
    final totalBirds  = _challans.fold(0,   (s, c) => s + ((c['bird_count'] as num?)?.toInt() ?? 0));
    final totalWeight = _challans.fold(0.0, (s, c) => s + ((c['net_weight'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () { if (context.canPop()) {
              context.pop();
            } else {
              context.go(R.agentHome);
            } }),
        title: Text('DCs — ${_challans.length} challan${_challans.length == 1 ? '' : 's'}'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const LoadingList()
          : _challans.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'No DCs recorded for this batch')
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
        Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.delivery_dining, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                Expanded(child: Text(agent?['name'] as String? ?? '—',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                StatusBadge(_batch?['status'] as String? ?? '', SC.order(_batch?['status'] as String? ?? '')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _summStat('Total Birds',  '$totalBirds',                              Colors.blue),
                _summStat('Total Weight', '${totalWeight.toStringAsFixed(1)} kg',    kPrimary),
                _summStat('DCs',          '${_challans.length}',                      Colors.teal),
                _summStat('Vehicle',      agent?['vehicle_no'] as String? ?? '—',    kTextSub),
              ]),
            ])),

        // ── Individual DC cards ──────────────────────────
        ..._challans.asMap().entries.map((entry) {
          final idx = entry.key;
          final ch  = entry.value;
          final gross  = (ch['gross_weight'] as num?)?.toDouble() ?? 0;
          final empty  = (ch['empty_crate_weight'] as num?)?.toDouble() ?? 0;
          final net    = (ch['net_weight'] as num?)?.toDouble() ?? 0;
          final birds  = (ch['bird_count'] as num?)?.toInt() ?? 0;
          final crates = (ch['crates_count'] as num?)?.toInt() ?? 0;
          final avg    = (ch['avg_bird_weight'] as num?)?.toDouble() ?? 0;
          final rate   = (ch['farm_rate'] as num?)?.toDouble();
          final dcDate = ch['dc_date'] as String?;
          final hasPic = ch['dc_photo_url'] != null;

          return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kBorder),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6, offset: const Offset(0, 2))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // DC header
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.05),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(6)),
                          child: Text('DC ${idx + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(ch['dc_number'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                      if (dcDate != null)
                        Text(DateFormat('d MMM y').format(DateTime.parse(dcDate)),
                            style: const TextStyle(fontSize: 12, color: kTextSub)),
                    ])),

                Padding(padding: const EdgeInsets.all(14), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Farm / Source info
                  Row(children: [
                    const Icon(Icons.agriculture_outlined, size: 14, color: kPrimary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ch['farmer_name'] as String? ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  ]),
                  if (ch['farm_location'] != null) Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Text(ch['farm_location'] as String,
                          style: const TextStyle(fontSize: 11, color: kTextSub))),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Weight breakdown
                  const Text('WEIGHT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: kTextHint, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Row(children: [
                    _wStat('Gross',    '${gross.toStringAsFixed(2)} kg',  Colors.blue),
                    _wStat('Empty Crates', '${empty.toStringAsFixed(2)} kg', Colors.orange),
                    _wStat('Net Weight', '${net.toStringAsFixed(2)} kg',  kPrimary),
                  ]),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Bird details
                  const Text('BIRDS & CRATES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: kTextHint, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  Row(children: [
                    _wStat('Bird Count',   '$birds birds',   Colors.teal),
                    _wStat('Crates',       '$crates',         Colors.purple),
                    _wStat('Avg/bird',
                        avg > 0 ? '${(avg * 1000).toStringAsFixed(0)} g' : net > 0 && birds > 0
                            ? '${(net / birds * 1000).toStringAsFixed(0)} g' : '—',
                        kTextSub),
                  ]),

                  // Vehicle, driver, rate
                  if (ch['vehicle_number'] != null || ch['driver_name'] != null || rate != null) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Wrap(spacing: 16, runSpacing: 4, children: [
                      if (ch['vehicle_number'] != null)
                        _chip(Icons.directions_car_outlined, ch['vehicle_number'] as String),
                      if (ch['driver_name'] != null)
                        _chip(Icons.person_outline, ch['driver_name'] as String),
                      if (rate != null)
                        _chip(Icons.currency_rupee, '₹${rate.toStringAsFixed(2)}/kg farm rate'),
                    ]),
                  ],

                  // DC photo indicator
                  if (hasPic || ch['in_time'] != null || ch['out_time'] != null) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(children: [
                      if (hasPic) ...[
                        const Icon(Icons.photo_outlined, size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                        const Text('DC photo attached', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 16),
                      ],
                      if (ch['in_time'] != null)
                        Text('In: ${ch['in_time']}  Out: ${ch['out_time'] ?? '—'}',
                            style: const TextStyle(fontSize: 11, color: kTextSub)),
                    ]),
                  ],

                  // Amount if rate present
                  if (rate != null && net > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            'Farm Amount: ₹${(rate * net).toStringAsFixed(2)}  (${net.toStringAsFixed(2)} kg × ₹${rate.toStringAsFixed(2)})',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary))),
                  ],
                ])),
              ]));
        }),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _summStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c), overflow: TextOverflow.ellipsis),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _wStat(String l, String v, Color c) => Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]));

  Widget _chip(IconData ic, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(ic, size: 12, color: kTextSub),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
  ]);
}