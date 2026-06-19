import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/session_provider.dart';
import '../reports/report_pdf_generator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SUPPLIER ACCOUNT STATEMENT
//
// Mirrors RetailerStatementScreen's transaction-timeline pattern.
// Source: supplier_ledger only, via get_supplier_statement() RPC (Phase 4
// backend — no new calculation here).
//
// DEVIATION FROM RETAILER STATEMENT: retailer statement PDF/share uses a
// dedicated Edge Function (generate-retailer-statement-pdf). Building an
// equivalent function for suppliers is backend work and out of scope for
// this UI-only phase, so export here uses the existing generic
// ReportPdfGenerator (in-app PDF, already used by Reports Hub) instead.
// ─────────────────────────────────────────────────────────────────────────────

enum _Preset { today, last7, last30, thisMonth, lastMonth, custom }

extension _PresetLabel on _Preset {
  String get label => switch (this) {
    _Preset.today     => 'Today',
    _Preset.last7     => 'Last 7',
    _Preset.last30    => 'Last 30',
    _Preset.thisMonth => 'This Month',
    _Preset.lastMonth => 'Last Month',
    _Preset.custom    => 'Custom',
  };
}

class _TxConfig {
  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  const _TxConfig(this.label, this.icon, this.iconBg, this.iconFg);
}

_TxConfig _txConfig(String reason, String entryType, String paymentMode) {
  final m = paymentMode.toUpperCase();
  if (entryType == 'debit' && reason == 'purchase') {
    return const _TxConfig('Purchase (DC)', Icons.local_shipping_outlined,
        Color(0xFFE3F2FD), Color(0xFF0D47A1));
  }
  if (entryType == 'credit' && reason == 'payment') {
    return _TxConfig('Payment Made${m.isNotEmpty ? " ($m)" : ""}',
        Icons.payments_outlined, const Color(0xFFE8F5E9), const Color(0xFF1B5E20));
  }
  return const _TxConfig('Adjustment', Icons.swap_horiz_outlined,
      Color(0xFFF5F5F5), Color(0xFF424242));
}

// ─────────────────────────────────────────────────────────────────────────────
class SupplierStatementScreen extends ConsumerStatefulWidget {
  const SupplierStatementScreen({super.key, required this.farmId});
  final String farmId;

  @override
  ConsumerState<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends ConsumerState<SupplierStatementScreen> {
  final _c = Supabase.instance.client;

  _Preset _preset = _Preset.last30;
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();
  bool _loading = false;
  bool _pdfBusy = false;

  Map<String, dynamic> _data = {};

  Map<String, dynamic> get _header => (_data['header'] as Map?)?.cast<String, dynamic>() ?? {};
  double get _opening => (_data['opening_balance'] as num?)?.toDouble() ?? 0;
  double get _closing => (_data['closing_balance'] as num?)?.toDouble() ?? 0;
  Map<String, dynamic> get _summary => (_data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
  List<Map<String, dynamic>> get _rows => List<Map<String, dynamic>>.from(
      (_data['rows'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()) ?? []);

  @override
  void initState() {
    super.initState();
    _applyPreset(_Preset.last30);
  }

  void _applyPreset(_Preset p) {
    final now = DateTime.now();
    late DateTime from, to;
    switch (p) {
      case _Preset.today:
        from = to = now;
      case _Preset.last7:
        from = now.subtract(const Duration(days: 6));
        to = now;
      case _Preset.last30:
        from = now.subtract(const Duration(days: 29));
        to = now;
      case _Preset.thisMonth:
        from = DateTime(now.year, now.month, 1);
        to = now;
      case _Preset.lastMonth:
        from = DateTime(now.year, now.month - 1, 1);
        to = DateTime(now.year, now.month, 0);
      case _Preset.custom:
        return;
    }
    setState(() {
      _preset = p;
      _from = from;
      _to = to;
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: kNavy)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _Preset.custom;
      _from = picked.start;
      _to = picked.end;
    });
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _data = {};
    });
    try {
      final res = await _c.rpc('get_supplier_statement', params: {
        'p_farm_id': widget.farmId,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
      }).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _data = (res as Map?)?.cast<String, dynamic>() ?? {};
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.toString().replaceAll('Exception: ', ''), error: true);
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_data.isEmpty) {
      _snack('Load the statement first', error: true);
      return;
    }
    setState(() => _pdfBusy = true);
    final user = ref.read(appUserProvider).valueOrNull;
    final farmName = _header['farmer_name'] as String? ?? 'Supplier';
    try {
      // Reuse the existing generic PDF generator (already used by Reports Hub).
      // No new Edge Function — UI only.
      await ReportPdfGenerator.generateAndShow(
        context: context,
        reportData: {'report': 'supplier_statement', ..._data},
        reportLabel: 'Statement — $farmName',
        companyName: user?.companyName ?? (_header['company_name'] as String? ?? 'DSR Chicken'),
        fromDate: _from,
        toDate: _to,
      );
    } catch (e) {
      _snack('PDF Error: ${e.toString().replaceAll("Exception:", "").trim()}', error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: _appBar(),
    body: Column(children: [
      _presetBar(),
      Expanded(child: _body()),
    ]),
  );

  PreferredSizeWidget _appBar() {
    final name = _header['farmer_name'] as String? ?? 'Statement';
    return AppBar(
      backgroundColor: kNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : null,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          const Text('Supplier Statement', style: TextStyle(fontSize: 11, color: Color(0xFFB4C6F4))),
        ],
      ),
      actions: [
        if (_pdfBusy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          )
        else
          IconButton(icon: const Icon(Icons.picture_as_pdf_outlined), tooltip: 'Export PDF', onPressed: _exportPdf),
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
      ],
    );
  }

  Widget _presetBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                    children: _Preset.values.map((p) {
                      final sel = _preset == p;
                      return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                              onTap: () => p == _Preset.custom ? _pickCustomRange() : _applyPreset(p),
                              child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: sel ? kNavy : kBgPage,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: sel ? kNavy : kBorderLight)),
                                  child: Text(p.label,
                                      style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : kTextSub)))));
                    }).toList()))),
        const SizedBox(width: 4),
        Text('${DateFormat('d MMM').format(_from)}–${DateFormat('d MMM').format(_to)}',
            style: const TextStyle(fontSize: 10, color: kTextHint), overflow: TextOverflow.ellipsis),
      ]));

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kNavy, strokeWidth: 2));
    if (_data.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: kTextHint.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Select a date range to load statement', style: TextStyle(color: kTextHint, fontSize: 13)),
          ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kNavy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          _heroCard(),
          const SizedBox(height: 12),
          _summaryGrid(),
          const SizedBox(height: 16),
          _sectionLabel('TRANSACTIONS'),
          const SizedBox(height: 8),
          _openingTile(),
          ..._rows.map(_transactionTile),
          _closingTile(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6));

  // ── Hero card (navy gradient) ────────────────────────────────────────────
  Widget _heroCard() {
    final h = _header;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(kRadiusHero),
        boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(h['company_name'] as String? ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFFB4C6F4))),
        const SizedBox(height: 6),
        Text(h['farmer_name'] as String? ?? '—',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        if (h['farm_name'] != null)
          Text(h['farm_name'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFFB4C6F4))),
        if (h['farm_location'] != null)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(h['farm_location'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFFB4C6F4)))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CLOSING BALANCE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFB4C6F4), letterSpacing: 0.6)),
                const SizedBox(height: 4),
                Text(Fmt.amount(_closing),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _closing > 0 ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC))),
                Text(_closing > 0 ? 'payable to supplier' : 'settled',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFB4C6F4))),
              ])),
          if (h['credit_days'] != null)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('${h['credit_days']} day credit',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
      ]),
    );
  }

  Widget _summaryGrid() {
    final s = _summary;
    final purchases = (s['total_purchases'] as num?)?.toDouble() ?? 0;
    final payments = (s['total_payments'] as num?)?.toDouble() ?? 0;
    return Row(children: [
      Expanded(child: _statCard('Total Purchases', Fmt.amount(purchases), Colors.blue, Icons.local_shipping_outlined)),
      const SizedBox(width: 8),
      Expanded(child: _statCard('Total Paid', Fmt.amount(payments), Colors.green, Icons.payments_outlined)),
    ]);
  }

  Widget _statCard(String label, String value, Color c, IconData icon) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: kTextSub), maxLines: 1),
      ]));

  Widget _openingTile() => _tile(
    date: _from,
    icon: Icons.account_balance_outlined,
    iconBg: const Color(0xFFE3F2FD),
    iconFg: const Color(0xFF0D47A1),
    label: 'Opening Balance',
    refNo: null,
    metaText: null,
    isDebit: _opening >= 0,
    amount: _opening.abs(),
    balance: _opening,
    isFirst: true,
    isLast: _rows.isEmpty,
    highlighted: true,
  );

  Widget _closingTile() => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _tile(
        date: _to,
        icon: Icons.flag_outlined,
        iconBg: _closing > 0 ? const Color(0xFFFFF3F3) : const Color(0xFFF1FFF5),
        iconFg: _closing > 0 ? Colors.red.shade700 : Colors.green.shade700,
        label: 'Closing Balance',
        refNo: null,
        metaText: null,
        isDebit: _closing >= 0,
        amount: _closing.abs(),
        balance: _closing,
        isFirst: false,
        isLast: true,
        highlighted: true,
      ));

  Widget _transactionTile(Map<String, dynamic> row) {
    final reason = row['reason'] as String? ?? '';
    final entryType = row['entry_type'] as String? ?? 'debit';
    final paymentMode = row['payment_mode'] as String? ?? '';
    final cfg = _txConfig(reason, entryType, paymentMode);
    final isDebit = entryType == 'debit';
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final balance = (row['running_balance'] as num?)?.toDouble() ?? 0;
    final dateStr = row['entry_date'] as String?;
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final refNo = row['ref_number'] as String?;

    final parts = <String>[];
    final birds = row['birds'] as num?;
    final wt = row['weight_kg'] as num?;
    final rate = row['rate_per_kg'] as num?;
    if (birds != null) parts.add('${birds.toInt()} birds');
    if (wt != null) parts.add('${wt.toStringAsFixed(2)} kg');
    if (rate != null) parts.add('₹${rate.toStringAsFixed(0)}/kg');

    return _tile(
      date: date ?? DateTime.now(),
      icon: cfg.icon,
      iconBg: cfg.iconBg,
      iconFg: cfg.iconFg,
      label: cfg.label,
      refNo: refNo,
      metaText: parts.isEmpty ? null : parts.join(' · '),
      isDebit: isDebit,
      amount: amount,
      balance: balance,
      isFirst: false,
      isLast: false,
    );
  }

  Widget _tile({
    required DateTime date,
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required String label,
    required String? refNo,
    required String? metaText,
    required bool isDebit,
    required double amount,
    required double balance,
    required bool isFirst,
    required bool isLast,
    bool highlighted = false,
  }) {
    final amtColor = isDebit ? Colors.red.shade700 : Colors.green.shade700;
    final balColor = balance > 0 ? Colors.red.shade700 : Colors.green.shade700;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: 40,
            child: Column(mainAxisSize: MainAxisSize.max, children: [
              Expanded(child: Center(child: Container(width: 2, color: isFirst ? Colors.transparent : kBorderLight))),
              Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: iconBg, shape: BoxShape.circle, border: highlighted ? Border.all(color: iconFg, width: 2) : null),
                  child: Icon(icon, size: 15, color: iconFg)),
              Expanded(child: Center(child: Container(width: 2, color: isLast ? Colors.transparent : kBorderLight))),
            ])),
        const SizedBox(width: 8),
        Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: highlighted ? (balance > 0 ? const Color(0xFFFFF3F3) : const Color(0xFFF1FFF5)) : kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: highlighted ? (balance > 0 ? Colors.red.shade200 : Colors.green.shade200) : kBorderLight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 13, fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700, color: kTextMain))),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 70),
                      child: Text('${isDebit ? "+" : "−"} ${Fmt.amount(amount)}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: amtColor),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 2, children: [
                  Text(DateFormat('d MMM yyyy').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                  if (refNo != null && refNo.isNotEmpty)
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: kBorderLight.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                        child: Text(refNo, style: const TextStyle(fontSize: 10, color: kTextSub, fontWeight: FontWeight.w600))),
                  if (metaText != null) Text(metaText, style: const TextStyle(fontSize: 10, color: kTextHint)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Text('Balance: ', style: TextStyle(fontSize: 10, color: kTextHint)),
                  Text(Fmt.amount(balance),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: balColor), overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Text(balance > 0 ? 'payable' : 'settled', style: TextStyle(fontSize: 9, color: balColor)),
                ]),
              ]),
            )),
      ]),
    );
  }
}