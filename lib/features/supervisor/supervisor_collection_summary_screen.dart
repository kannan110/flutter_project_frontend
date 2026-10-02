import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/app_theme.dart';

class SupervisorCollectionSummaryScreen extends ConsumerStatefulWidget {
  const SupervisorCollectionSummaryScreen({super.key});
  @override ConsumerState<SupervisorCollectionSummaryScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorCollectionSummaryScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true;
  bool _isToday = true;
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  double _cash = 0, _upi = 0, _bank = 0;
  int _count = 0;
  int _customers = 0;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    if (mounted) setState(() => _loading = true);
    try {
      final r = await _c.from('ledger_entries')
          .select('amount,payment_mode,retailer_id')
          .eq('recorded_by', uid).eq('entry_type', 'credit').eq('source_type', 'payment')
          .gte('entry_date', DateFormat('yyyy-MM-dd').format(_from))
          .lte('entry_date', DateFormat('yyyy-MM-dd').format(_to));
      final list = List<Map<String, dynamic>>.from(r as List? ?? []);
      double cash = 0, upi = 0, bank = 0;
      for (final p in list) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0;
        switch (p['payment_mode']) {
          case 'cash': cash += amt; break;
          case 'upi':  upi  += amt; break;
          case 'bank': bank += amt; break;
        }
      }
      if (mounted) setState(() {
        _cash = cash; _upi = upi; _bank = bank;
        _count = list.length;
        _customers = list.map((p) => p['retailer_id']).toSet().length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  void _setToday() { setState(() { _isToday = true; _from = DateTime.now(); _to = DateTime.now(); }); _load(); }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to));
    if (range != null) { setState(() { _isToday = false; _from = range.start; _to = range.end; }); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final total = _cash + _upi + _bank;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(backgroundColor: kSurface, title: const Text('Collection Summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: _setToday,
                style: OutlinedButton.styleFrom(
                    backgroundColor: _isToday ? kNavy : null,
                    foregroundColor: _isToday ? Colors.white : kNavy,
                    side: const BorderSide(color: kNavy)),
                child: const Text('Today'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined, size: 16),
                style: OutlinedButton.styleFrom(
                    backgroundColor: !_isToday ? kNavy : null,
                    foregroundColor: !_isToday ? Colors.white : kNavy,
                    side: const BorderSide(color: kNavy)),
                label: Text(_isToday ? 'Date Range' : '${DateFormat('d MMM').format(_from)}–${DateFormat('d MMM').format(_to)}'))),
          ]),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(kRadiusHero),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TOTAL COLLECTED', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: 6),
              Text(Fmt.amount(total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 4),
              Text('$_count payments · $_customers customers', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 16),
          _modeRow('Cash', _cash, Icons.money_outlined, Colors.green.shade700),
          _modeRow('UPI', _upi, Icons.qr_code_outlined, Colors.blue.shade700),
          _modeRow('Bank', _bank, Icons.account_balance_outlined, Colors.purple.shade700),
        ]),
      ),
    );
  }

  Widget _modeRow(String label, double amt, IconData icon, Color color) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(Fmt.amount(amt), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
      ]));
}