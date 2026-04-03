import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});
  @override ConsumerState<DailyReportScreen> createState() => _S();
}

class _S extends ConsumerState<DailyReportScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _d;
  List<Map<String,dynamic>> _deliveries = [];
  List<Map<String,dynamic>> _agents     = [];
  bool _loading = true;
  DateTime _date = DateTime.now();
  int _tab = 0;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final dateStr = _date.toIso8601String().split('T')[0];
      final res = await _c.rpc('daily_report_summary',
          params: {'p_trader_id': tid, 'p_date': dateStr});

      // Load delivery-wise breakdown with loss data
      final dList = await _c.from('deliveries')
          .select('id,status,delivered_bird_count,delivered_total_weight,'
                  'dc_weight_kg,transport_loss_kg,mortality_birds,mortality_weight_kg,'
                  'total_loss_kg,loss_percentage,is_high_loss,'
                  'collected_amount,payment_mode,mortality_proof_url,delivery_agent_id,'
                  'orders(retailers(shop_name)),'
                  'delivery_batches(delivery_challans(dc_number,farmer_name)),'
                  'delivery_agents(name)')
          .eq('trader_id', tid)
          .eq('status', 'delivered')
          .gte('delivered_at', '${dateStr}T00:00:00')
          .lte('delivered_at', '${dateStr}T23:59:59')
          .order('delivered_at', ascending: false);

      // Load agent loss analytics
      final agentData = await _c.from('deliveries')
          .select('delivery_agent_id,dc_weight_kg,delivered_total_weight,'
                  'transport_loss_kg,mortality_birds,mortality_weight_kg,'
                  'total_loss_kg,loss_percentage,is_high_loss,'
                  'delivery_agents(name)')
          .eq('trader_id', tid)
          .eq('status', 'delivered')
          .gte('delivered_at', '${dateStr}T00:00:00')
          .lte('delivered_at', '${dateStr}T23:59:59');

      if (!mounted) return;
      setState(() {
        _d         = res as Map<String,dynamic>?;
        _deliveries = List<Map<String,dynamic>>.from(dList as List? ?? []);
        _agents     = _groupByAgent(List<Map<String,dynamic>>.from(agentData as List? ?? []));
        _loading   = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String,dynamic>> _groupByAgent(List<Map<String,dynamic>> rows) {
    final map = <String, Map<String,dynamic>>{};
    for (final r in rows) {
      final aId   = r['delivery_agent_id'] as String? ?? '';
      final aName = (r['delivery_agents'] as Map?)?['name'] as String? ?? '—';
      if (!map.containsKey(aId)) {
        map[aId] = {
          'agent_id': aId, 'agent_name': aName,
          'deliveries': 0, 'dc_weight': 0.0, 'delivered_weight': 0.0,
          'transport_loss': 0.0, 'mortality_birds': 0,
          'mortality_weight': 0.0, 'total_loss': 0.0, 'high_loss_count': 0,
        };
      }
      final m = map[aId]!;
      m['deliveries']       = (m['deliveries'] as int) + 1;
      m['dc_weight']        = (m['dc_weight'] as double) + ((r['dc_weight_kg'] as num?)?.toDouble() ?? 0);
      m['delivered_weight'] = (m['delivered_weight'] as double) + ((r['delivered_total_weight'] as num?)?.toDouble() ?? 0);
      m['transport_loss']   = (m['transport_loss'] as double) + ((r['transport_loss_kg'] as num?)?.toDouble() ?? 0);
      m['mortality_birds']  = (m['mortality_birds'] as int) + ((r['mortality_birds'] as num?)?.toInt() ?? 0);
      m['mortality_weight'] = (m['mortality_weight'] as double) + ((r['mortality_weight_kg'] as num?)?.toDouble() ?? 0);
      m['total_loss']       = (m['total_loss'] as double) + ((r['total_loss_kg'] as num?)?.toDouble() ?? 0);
      if (r['is_high_loss'] == true) m['high_loss_count'] = (m['high_loss_count'] as int) + 1;
    }
    return map.values.toList()..sort((a, b) => (b['total_loss'] as double).compareTo(a['total_loss'] as double));
  }

  String _buildShareText() {
    if (_d == null) return '';
    final d = _d!;
    final buf = StringBuffer();
    buf.writeln('🐓 *Daily Report — ${DateFormat('d MMMM y').format(_date)}*\n');
    buf.writeln('📊 *REVENUE*');
    buf.writeln('Gross Revenue:  ₹${(d['gross_revenue'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('Cash Collected: ₹${(d['cash_collected'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('Farm Cost:      ₹${(d['farm_cost'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('Expenses:       ₹${(d['total_expenses'] as num?)?.toStringAsFixed(0) ?? 0}');
    buf.writeln('Net Profit:     ₹${(d['net_profit'] as num?)?.toStringAsFixed(0) ?? 0}\n');
    buf.writeln('📦 *STOCK*');
    buf.writeln('Purchased: ${d['birds_purchased'] ?? 0} birds · ${(d['kg_purchased'] as num?)?.toStringAsFixed(0) ?? 0} kg');
    buf.writeln('Delivered: ${d['birds_delivered'] ?? 0} birds · ${(d['kg_delivered'] as num?)?.toStringAsFixed(0) ?? 0} kg');
    buf.writeln('Mortality: ${d['birds_mortality'] ?? 0} birds');
    buf.writeln('Returns:   ${d['birds_returned'] ?? 0} birds\n');

    // Loss summary
    if (_deliveries.isNotEmpty) {
      final totalDc      = _deliveries.fold(0.0, (s, d) => s + ((d['dc_weight_kg'] as num?)?.toDouble() ?? 0));
      final totalLoss    = _deliveries.fold(0.0, (s, d) => s + ((d['total_loss_kg'] as num?)?.toDouble() ?? 0));
      final highLossCount = _deliveries.where((d) => d['is_high_loss'] == true).length;
      final lossPct = totalDc > 0 ? (totalLoss / totalDc * 100) : 0;
      buf.writeln('⚖️ *LOSS ANALYSIS*');
      buf.writeln('Total DC Weight:  ${totalDc.toStringAsFixed(1)} kg');
      buf.writeln('Total Loss:       ${totalLoss.toStringAsFixed(2)} kg (${lossPct.toStringAsFixed(1)}%)');
      if (highLossCount > 0) buf.writeln('⚠️ High Loss Deliveries: $highLossCount');
      buf.writeln('');
    }

    if (_agents.isNotEmpty) {
      buf.writeln('🚛 *BY AGENT*');
      for (final a in _agents) {
        final dcWt   = (a['dc_weight'] as double);
        final lossPct = dcWt > 0 ? ((a['total_loss'] as double) / dcWt * 100) : 0;
        buf.writeln('${a['agent_name']}: ${a['deliveries']} deliveries · Loss ${lossPct.toStringAsFixed(1)}%');
      }
      buf.writeln('');
    }
    buf.writeln('_Rooster Trader_');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily Report'),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now());
            if (d != null && mounted) { setState(() => _date = d); _load(); }
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(DateFormat('d MMM').format(_date))),
        if (_d != null)
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _buildShareText()));
              if (mounted) showSuccess(context, 'Report copied — paste in WhatsApp ✓');
            }),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
    ),
    body: _loading ? const LoadingList() : Column(children: [
      // Tab bar
      Container(color: Colors.white, child: Row(children: [
        _tabBtn(0, 'Summary'),
        _tabBtn(1, 'Deliveries'),
        _tabBtn(2, 'Loss Analysis'),
        _tabBtn(3, 'By Agent'),
      ])),
      const Divider(height: 1),
      Expanded(child: _d == null
          ? EmptyState(icon: Icons.receipt_long_outlined,
              message: 'No data for ${DateFormat('d MMM y').format(_date)}')
          : RefreshIndicator(onRefresh: _load, child: _buildTab())),
    ]),
  );

  Widget _tabBtn(int idx, String label) => Expanded(child: InkWell(
    onTap: () => setState(() => _tab = idx),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
              color: _tab == idx ? kPrimary : Colors.transparent, width: 2))),
      child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: _tab == idx ? kPrimary : kTextHint)))));

  Widget _buildTab() {
    switch (_tab) {
      case 0: return _buildSummary();
      case 1: return _buildDeliveries();
      case 2: return _buildLossAnalysis();
      case 3: return _buildAgentReport();
      default: return _buildSummary();
    }
  }

  Widget _buildSummary() {
    final d = _d!;
    final distanceData = _deliveries.fold(0.0, (s, _) => s);
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Header
      Container(padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(DateFormat('EEEE, d MMMM y').format(_date),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text(Fmt.amount((d['gross_revenue'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          const Text('Gross Revenue', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _hStat('Collected', Fmt.amount((d['cash_collected'] as num?)?.toDouble() ?? 0)),
            Container(width: 1, height: 30, color: Colors.white24),
            _hStat('Birds', '${d['birds_delivered'] ?? 0}'),
            Container(width: 1, height: 30, color: Colors.white24),
            _hStat('Deliveries', '${d['orders_delivered'] ?? 0}'),
          ]),
        ])),
      const SizedBox(height: 14),
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('FINANCIAL'),
        _rowInfo('Gross Revenue', 'Invoice value of approved orders today',
            Fmt.amount((d['gross_revenue']   as num?)?.toDouble() ?? 0), kPrimary),
        _rowInfo('Cash Collected', 'Payments received from retailers (cash+UPI+bank)',
            Fmt.amount((d['cash_collected']  as num?)?.toDouble() ?? 0), Colors.green),
        _rowInfo('Farm Cost', 'DC purchase cost (farm rate × net weight)',
            Fmt.amount((d['farm_cost']       as num?)?.toDouble() ?? 0), Colors.orange),
        _rowInfo('Delivery Expenses', 'Agent fuel, toll, misc expenses (NOT deducted from collection)',
            Fmt.amount((d['total_expenses']  as num?)?.toDouble() ?? 0), Colors.red),
        const Divider(height: 14),
        _rowInfo('Net Profit', 'Gross Revenue − Farm Cost − Delivery Expenses',
            Fmt.amount((d['net_profit']      as num?)?.toDouble() ?? 0),
            ((d['net_profit'] as num?)?.toDouble() ?? 0) >= 0 ? kPrimary : Colors.red),
        _rowInfo('Total Outstanding', 'All unpaid retailer balances (ledger)',
            Fmt.amount((d['total_outstanding'] as num?)?.toDouble() ?? 0), Colors.orange),
      ])),
      const SizedBox(height: 10),
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('STOCK MOVEMENT'),
        _row('Purchased (DC)', '${d['birds_purchased'] ?? 0} birds · ${(d['kg_purchased'] as num?)?.toStringAsFixed(0) ?? 0} kg', Colors.blue),
        _row('Delivered',      '${d['birds_delivered'] ?? 0} birds · ${(d['kg_delivered'] as num?)?.toStringAsFixed(0) ?? 0} kg', kPrimary),
        _row('Mortality',      '${d['birds_mortality'] ?? 0} birds', Colors.red),
        _row('Returns',        '${d['birds_returned'] ?? 0} birds', Colors.purple),
      ])),
      const SizedBox(height: 10),
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('OPERATIONS'),
        _row('Active Agents',   '${d['agents_active'] ?? 0}'),
        _row('Shifts Closed',   '${d['shifts_closed'] ?? 0}'),
        _row('Orders Created',  '${d['orders_created'] ?? 0}'),
        _row('Invoices Raised', '${d['new_invoices'] ?? 0} · ${Fmt.amount((d['invoiced_amount'] as num?)?.toDouble() ?? 0)}'),
      ])),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _buildShareText()));
          if (mounted) showSuccess(context, 'Copied — paste in WhatsApp ✓');
        },
        icon: const Icon(Icons.share_outlined, size: 18),
        label: const Text('Copy Report for WhatsApp'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366))),
      const SizedBox(height: 20),
    ]);
  }

  Widget _buildDeliveries() {
    if (_deliveries.isEmpty) {
      return const EmptyState(icon: Icons.local_shipping_outlined, message: 'No deliveries today');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _deliveries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d       = _deliveries[i];
        final o       = d['orders'] as Map<String,dynamic>?;
        final r       = o?['retailers'] as Map<String,dynamic>?;
        final isHigh  = d['is_high_loss'] == true;
        final lossPct = (d['loss_percentage'] as num?)?.toDouble() ?? 0;
        final birds   = (d['delivered_bird_count'] as num?)?.toInt() ?? 0;
        final weight  = (d['delivered_total_weight'] as num?)?.toDouble() ?? 0;
        final collected = (d['collected_amount'] as num?)?.toDouble() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isHigh ? Colors.orange.shade300 : kBorder, width: isHigh ? 1.5 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r?['shop_name'] as String? ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              if (isHigh) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text('⚠️ Loss ${lossPct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.deepOrange))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _dStat('Birds', '$birds', kPrimary),
              _dStat('Weight', '${weight.toStringAsFixed(1)} kg', Colors.teal),
              _dStat('Collected', Fmt.amount(collected), Colors.green),
              _dStat('Loss', '${lossPct.toStringAsFixed(1)}%', isHigh ? Colors.red : kTextSub),
            ]),
            if (d['mortality_proof_url'] != null)
              Padding(padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.photo_outlined, size: 13, color: Colors.purple),
                  const SizedBox(width: 4),
                  const Text('Mortality proof attached', style: TextStyle(fontSize: 11, color: Colors.purple)),
                ])),
          ]));
      });
  }

  Widget _buildLossAnalysis() {
    if (_deliveries.isEmpty) {
      return const EmptyState(icon: Icons.analytics_outlined, message: 'No deliveries today');
    }
    final totalDc      = _deliveries.fold(0.0, (s, d) => s + ((d['dc_weight_kg'] as num?)?.toDouble() ?? 0));
    final totalDel     = _deliveries.fold(0.0, (s, d) => s + ((d['delivered_total_weight'] as num?)?.toDouble() ?? 0));
    final totalTransLoss = _deliveries.fold(0.0, (s, d) => s + ((d['transport_loss_kg'] as num?)?.toDouble() ?? 0));
    final totalMortBirds = _deliveries.fold(0,   (s, d) => s + ((d['mortality_birds'] as num?)?.toInt() ?? 0));
    final totalMortWt  = _deliveries.fold(0.0, (s, d) => s + ((d['mortality_weight_kg'] as num?)?.toDouble() ?? 0));
    final totalLoss    = _deliveries.fold(0.0, (s, d) => s + ((d['total_loss_kg'] as num?)?.toDouble() ?? 0));
    final highLoss     = _deliveries.where((d) => d['is_high_loss'] == true).toList();
    final lossPct      = totalDc > 0 ? (totalLoss / totalDc * 100) : 0;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: lossPct >= 2 ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lossPct >= 2 ? Colors.red.shade200 : Colors.green.shade200)),
        child: Column(children: [
          Text('${lossPct.toStringAsFixed(2)}%',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                  color: lossPct >= 2 ? Colors.red : Colors.green)),
          Text('Overall Loss', style: TextStyle(fontSize: 13, color: lossPct >= 2 ? Colors.red : Colors.green)),
          const SizedBox(height: 12),
          Row(children: [
            _lossStat2('DC Weight',   '${totalDc.toStringAsFixed(1)} kg',    Colors.blue),
            _lossStat2('Delivered',   '${totalDel.toStringAsFixed(1)} kg',   kPrimary),
            _lossStat2('Total Loss',  '${totalLoss.toStringAsFixed(2)} kg',  lossPct >= 2 ? Colors.red : Colors.orange),
          ]),
        ])),
      const SizedBox(height: 14),
      WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader('LOSS BREAKDOWN'),
        _row('Transport Loss',   '${totalTransLoss.toStringAsFixed(2)} kg', Colors.orange),
        _row('Mortality Birds',  '$totalMortBirds birds', Colors.red),
        _row('Mortality Weight', '${totalMortWt.toStringAsFixed(2)} kg', Colors.red),
        _row('Total Loss',       '${totalLoss.toStringAsFixed(2)} kg', Colors.red),
        const Divider(height: 14),
        _row('High Loss Deliveries', '${highLoss.length} / ${_deliveries.length}',
            highLoss.isNotEmpty ? Colors.orange : Colors.green),
      ])),
      if (highLoss.isNotEmpty) ...[
        const SizedBox(height: 12),
        const SectionHeader('⚠️ HIGH LOSS DELIVERIES (≥2%)'),
        ...highLoss.map((d) {
          final o = d['orders'] as Map<String,dynamic>?;
          final r = o?['retailers'] as Map<String,dynamic>?;
          final pct = (d['loss_percentage'] as num?)?.toDouble() ?? 0;
          final loss = (d['total_loss_kg'] as num?)?.toDouble() ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r?['shop_name'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('Loss: ${pct.toStringAsFixed(1)}% · ${loss.toStringAsFixed(2)} kg',
                    style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ])),
            ]));
        }),
      ],
    ]);
  }

  Widget _buildAgentReport() {
    if (_agents.isEmpty) {
      return const EmptyState(icon: Icons.delivery_dining_outlined, message: 'No agent data today');
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const SectionHeader('AGENT PERFORMANCE TODAY'),
      ..._agents.map((a) {
        final dcWt    = (a['dc_weight'] as double);
        final lossPct = dcWt > 0 ? ((a['total_loss'] as double) / dcWt * 100) : 0.0;
        final isHigh  = lossPct >= 2;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isHigh ? Colors.orange.shade300 : kBorder, width: isHigh ? 1.5 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.delivery_dining, size: 16, color: kPrimary),
              const SizedBox(width: 6),
              Text(a['agent_name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (isHigh) Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text('⚠️ High Loss', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _dStat('Deliveries', '${a['deliveries']}', kPrimary),
              _dStat('DC Weight', '${(a['dc_weight'] as double).toStringAsFixed(1)} kg', Colors.blue),
              _dStat('Mortality', '${a['mortality_birds']} birds', Colors.red),
              _dStat('Loss', '${lossPct.toStringAsFixed(1)}%', isHigh ? Colors.red : kTextSub),
            ]),
            if ((a['high_loss_count'] as int) > 0) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${a['high_loss_count']} high-loss deliveries need attention',
                  style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600))),
          ]));
      }),
    ]);
  }

  Widget _hStat(String l, String v) => Column(children: [
    Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)),
  ]);

  Widget _rowInfo(String label, String subtitle, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextMain)),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: kTextHint)),
      ])),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]));

  Widget _row(String l, String v, [Color? c]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c ?? kTextMain)),
    ]));

  Widget _dStat(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c), textAlign: TextAlign.center),
    Text(l, style: const TextStyle(fontSize: 9, color: kTextHint), textAlign: TextAlign.center),
  ]));

  Widget _lossStat2(String l, String v, Color c) => Expanded(child: Column(children: [
    Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
    Text(l, style: const TextStyle(fontSize: 10, color: kTextHint)),
  ]));
}
