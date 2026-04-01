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
  bool _loading = true;
  DateTime _date = DateTime.now();

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('daily_report_summary', params: {
        'p_trader_id': tid,
        'p_date': _date.toIso8601String().split('T')[0],
      });
      if (!mounted) return;
      if (mounted) setState(() { _d = res as Map<String,dynamic>?; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _buildShareText() {
    if (_d == null) return '';
    final d = _d!;
    final dateStr   = DateFormat('d MMMM y').format(_date);
    final revenue   = (d['total_revenue'] as num?)?.toDouble()   ?? 0;
    final collected = (d['total_collected'] as num?)?.toDouble() ?? 0;
    final birds     = d['total_birds'] ?? d['total_delivered'] ?? 0;
    final weight    = (d['total_weight'] ?? d['total_weight_kg'] as num?)?.toStringAsFixed(1) ?? '0';
    final cash      = (d['cash_collected']  as num?)?.toDouble() ?? 0;
    final upi       = (d['upi_collected']   as num?)?.toDouble() ?? 0;
    final credit    = (d['credit_given']    as num?)?.toDouble() ?? 0;
    final deliveries= d['total_deliveries'] ?? d['delivered_count'] ?? 0;
    final mortality = d['mortality'] ?? 0;
    final returns   = d['returns_birds'] ?? 0;

    final buf = StringBuffer();
    buf.writeln('🐓 *Daily Report — $dateStr*');
    buf.writeln('');
    buf.writeln('📊 *SUMMARY*');
    buf.writeln('Revenue:      ₹${revenue.toStringAsFixed(2)}');
    buf.writeln('Collected:    ₹${collected.toStringAsFixed(2)}');
    buf.writeln('');
    buf.writeln('📦 *VOLUME*');
    buf.writeln('Birds:        $birds');
    buf.writeln('Weight:       $weight kg');
    buf.writeln('Deliveries:   $deliveries');
    buf.writeln('');
    buf.writeln('💰 *CASH FLOW*');
    buf.writeln('Cash:         ₹${cash.toStringAsFixed(2)}');
    buf.writeln('UPI:          ₹${upi.toStringAsFixed(2)}');
    buf.writeln('Credit:       ₹${credit.toStringAsFixed(2)}');
    if (mortality > 0 || returns > 0) {
      buf.writeln('');
      buf.writeln('⚠ *LOSSES*');
      if (mortality > 0) buf.writeln('Mortality:    $mortality birds');
      if (returns > 0)   buf.writeln('Returns:      $returns birds');
    }

    final agents = d['agent_breakdown'] as List?;
    if (agents != null && agents.isNotEmpty) {
      buf.writeln('');
      buf.writeln('🚛 *BY AGENT*');
      for (final a in agents) {
        final row = a as Map<String,dynamic>;
        buf.writeln('${row['agent_name'] ?? '—'}: ${row['birds'] ?? 0} birds · ₹${((row['revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}');
      }
    }
    buf.writeln('');
    buf.writeln('_Rooster Trader_');
    return buf.toString();
  }

  Future<void> _share() async {
    final text = _buildShareText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSuccess(context, 'Report copied — paste in WhatsApp ✓');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily Report'),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final d = await showDatePicker(context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now());
            if (d != null && mounted) { setState(() => _date = d); _load(); }
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(DateFormat('d MMM').format(_date))),
        if (_d != null)
          IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Share', onPressed: _share),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
    ),
    body: _loading
        ? const LoadingList()
        : _d == null
            ? EmptyState(icon: Icons.receipt_long_outlined,
                message: 'No data for ${DateFormat('d MMM y').format(_date)}',
                sub: 'Select a different date or check if deliveries were completed')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  // ── Date header ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(14)),
                    child: Column(children: [
                      Text(DateFormat('EEEE, d MMMM y').format(_date),
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        Fmt.amount((_d!['total_revenue'] as num?)?.toDouble() ?? 0),
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                      const Text('Total Revenue', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 8),
                      // Key metrics row
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _hStat('Collected', Fmt.amount((_d!['total_collected'] as num?)?.toDouble() ?? 0)),
                        Container(width: 1, height: 30, color: Colors.white24),
                        _hStat('Birds', '${_d!['total_birds'] ?? _d!['total_delivered'] ?? 0}'),
                        Container(width: 1, height: 30, color: Colors.white24),
                        _hStat('Weight', '${((_d!['total_weight'] ?? _d!['total_weight_kg']) as num?)?.toStringAsFixed(0) ?? 0} kg'),
                      ]),
                    ])),
                  const SizedBox(height: 14),

                  // ── Volume ───────────────────────────────────────
                  WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionHeader('VOLUME'),
                    _row('Birds Delivered', '${_d!['total_birds'] ?? _d!['total_delivered'] ?? 0}'),
                    _row('Total Weight', '${((_d!['total_weight'] ?? _d!['total_weight_kg']) as num?)?.toStringAsFixed(1) ?? 0} kg'),
                    _row('Deliveries Completed', '${_d!['total_deliveries'] ?? _d!['delivered_count'] ?? 0}'),
                    _row('Orders Created', '${_d!['total_orders'] ?? 0}'),
                  ])),
                  const SizedBox(height: 10),

                  // ── Cash flow ────────────────────────────────────
                  WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionHeader('CASH FLOW'),
                    _row('Total Revenue',   Fmt.amount((_d!['total_revenue']   as num?)?.toDouble() ?? 0), kPrimary),
                    _row('Total Collected', Fmt.amount((_d!['total_collected'] as num?)?.toDouble() ?? 0), Colors.green),
                    const Divider(height: 14),
                    _row('  Cash',    Fmt.amount((_d!['cash_collected'] as num?)?.toDouble() ?? 0)),
                    _row('  UPI',     Fmt.amount((_d!['upi_collected']  as num?)?.toDouble() ?? 0)),
                    _row('  Credit',  Fmt.amount((_d!['credit_given']   as num?)?.toDouble() ?? 0), Colors.orange),
                    const Divider(height: 14),
                    _row('Outstanding (Cumulative)',
                        Fmt.amount((_d!['total_outstanding'] as num?)?.toDouble() ?? 0), Colors.red),
                  ])),
                  const SizedBox(height: 10),

                  // ── Stock ────────────────────────────────────────
                  WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionHeader('STOCK MOVEMENT'),
                    _row('Birds Purchased (DC)', '${_d!['birds_purchased'] ?? 0}', Colors.blue),
                    _row('Birds Delivered',       '${_d!['birds_delivered'] ?? 0}', kPrimary),
                    if ((_d!['mortality'] as num? ?? 0) > 0)
                      _row('Mortality', '${_d!['mortality'] ?? 0}', Colors.red),
                    if ((_d!['returns_birds'] as num? ?? 0) > 0)
                      _row('Returns to Stock', '${_d!['returns_birds'] ?? 0}', Colors.purple),
                  ])),

                  // ── Agent breakdown ──────────────────────────────
                  if ((_d!['agent_breakdown'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionHeader('BY AGENT'),
                      ...(_d!['agent_breakdown'] as List).map((a) {
                        final row = a as Map<String,dynamic>;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            const Icon(Icons.delivery_dining, size: 14, color: kPrimary),
                            const SizedBox(width: 6),
                            Expanded(child: Text(row['agent_name'] as String? ?? '—',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Text('${row['birds'] ?? 0} birds', style: const TextStyle(fontSize: 11, color: kTextSub)),
                            const SizedBox(width: 8),
                            Text(Fmt.amount((row['revenue'] as num?)?.toDouble() ?? 0),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary)),
                          ]));
                      }),
                    ])),
                  ],

                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Copy Report for WhatsApp'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366))),
                  const SizedBox(height: 20),
                ])),
  );

  Widget _hStat(String l, String v) => Column(children: [
    Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)),
  ]);

  Widget _row(String l, String v, [Color? c]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 12, color: kTextSub))),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c ?? kTextMain)),
    ]));
}
