import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'report_pdf_generator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// P&L SCREEN
// UI ONLY — calls the existing get_pnl_statement RPC (Phase 4 backend).
// No accounting / profitability / cash-flow calculation lives in this file.
// Granularity (daily/weekly/monthly) is a display grouping the RPC already
// returns; this screen does not recompute or re-aggregate any figure.
// ─────────────────────────────────────────────────────────────────────────────

enum _Gran { daily, weekly, monthly }

extension _GranX on _Gran {
  String get label => switch (this) {
    _Gran.daily   => 'Daily',
    _Gran.weekly  => 'Weekly',
    _Gran.monthly => 'Monthly',
  };
  String get rpcValue => switch (this) {
    _Gran.daily   => 'daily',
    _Gran.weekly  => 'weekly',
    _Gran.monthly => 'monthly',
  };
}

enum _DatePreset { last7, last30, thisMonth, last90, custom }

extension _DatePresetX on _DatePreset {
  String get label => switch (this) {
    _DatePreset.last7     => 'Last 7',
    _DatePreset.last30    => 'Last 30',
    _DatePreset.thisMonth => 'This Month',
    _DatePreset.last90    => 'Last 90',
    _DatePreset.custom    => 'Custom',
  };
  (DateTime, DateTime) get range {
    final now = DateTime.now();
    return switch (this) {
      _DatePreset.last7     => (now.subtract(const Duration(days: 6)), now),
      _DatePreset.last30    => (now.subtract(const Duration(days: 29)), now),
      _DatePreset.thisMonth => (DateTime(now.year, now.month, 1), now),
      _DatePreset.last90    => (now.subtract(const Duration(days: 89)), now),
      _DatePreset.custom    => (now.subtract(const Duration(days: 29)), now),
    };
  }
}

class PnLScreen extends ConsumerStatefulWidget {
  const PnLScreen({super.key});
  @override
  ConsumerState<PnLScreen> createState() => _PnLScreenState();
}

class _PnLScreenState extends ConsumerState<PnLScreen> {
  final _c = Supabase.instance.client;

  _Gran _gran = _Gran.daily;
  _DatePreset _preset = _DatePreset.last30;
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> get _summary =>
      (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
  List<Map<String, dynamic>> get _buckets => List<Map<String, dynamic>>.from(
      (_data?['buckets'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()) ?? []);

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _c.rpc('get_pnl_statement', params: {
        'p_trader_id': tid,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
        'p_granularity': _gran.rpcValue,
      }).timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _data = (res as Map?)?.cast<String, dynamic>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: kNavy)),
        child: child!,
      ),
    );
    if (r != null && mounted) {
      setState(() {
        _preset = _DatePreset.custom;
        _from = r.start;
        _to = r.end;
      });
      _load();
    }
  }

  Future<void> _exportPdf() async {
    if (_data == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Load the report first')));
      return;
    }
    final user = ref.read(appUserProvider).valueOrNull;
    final company = user?.companyName ?? 'DSR Chicken';
    try {
      await ReportPdfGenerator.generateAndShow(
        context: context,
        reportData: _data!,
        reportLabel: 'P&L (${_gran.label})',
        companyName: company,
        fromDate: _from,
        toDate: _to,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF Error: ${e.toString().replaceAll("Exception:", "").trim()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Profit & Loss', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text('${DateFormat("d MMM").format(_from)} – ${DateFormat("d MMM yyyy").format(_to)}',
              style: const TextStyle(fontSize: 12, color: kTextSub)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 22),
              onPressed: _exportPdf,
              tooltip: 'Export PDF'),
        ],
      ),
      body: Column(children: [
        _buildGranBar(),
        _buildDateBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kNavy, strokeWidth: 2.5))
              : _error != null
              ? _buildError()
              : _data == null
              ? const SizedBox.shrink()
              : _buildBody(),
        ),
      ]),
    );
  }

  Widget _buildGranBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
          children: _Gran.values
              .map((g) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                  onTap: () {
                    setState(() => _gran = g);
                    _load();
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: _gran == g ? kNavy : kBgGrey,
                          borderRadius: BorderRadius.circular(kRadiusChip)),
                      child: Text(g.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _gran == g ? Colors.white : kTextSub))))))
              .toList()));

  Widget _buildDateBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(children: [
        Expanded(
            child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: _DatePreset.values
                    .where((p) => p != _DatePreset.custom)
                    .map((p) => GestureDetector(
                    onTap: () {
                      final (f, t) = p.range;
                      setState(() {
                        _preset = p;
                        _from = f;
                        _to = t;
                      });
                      _load();
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                            color: _preset == p ? kNavy : kBgGrey,
                            borderRadius: BorderRadius.circular(kRadiusChip)),
                        child: Text(p.label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _preset == p ? Colors.white : kTextSub)))))
                    .toList())),
        GestureDetector(
            onTap: _pickCustomRange,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: _preset == _DatePreset.custom ? kNavy : kBgGrey,
                    borderRadius: BorderRadius.circular(kRadiusChip)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.date_range_outlined,
                      size: 12, color: _preset == _DatePreset.custom ? Colors.white : kTextSub),
                  const SizedBox(width: 4),
                  Text('Custom',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _preset == _DatePreset.custom ? Colors.white : kTextSub)),
                ]))),
      ]));

  Widget _buildError() => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: kErrorBg, borderRadius: BorderRadius.circular(kRadiusCard)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 12),
                Text(_error ?? 'Error loading P&L', textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]))));

  Widget _buildBody() {
    final s = _summary;
    final pendingCount = _i(s, 'lines_cost_pending');
    final costPending = pendingCount > 0;

    final revenue = _d(s, 'revenue');
    final cogs = _dn(s, 'cogs');
    final grossProfit = _dn(s, 'gross_profit');
    final netProfit = _dn(s, 'net_profit');
    final mortality = _d(s, 'mortality_loss_amount');
    final shrinkage = _d(s, 'shrinkage_loss_amount');
    final tripExp = _d(s, 'trip_expenses');
    final fixedExp = _d(s, 'fixed_expenses');
    final totalExp = _d(s, 'total_expenses');

    return SingleChildScrollView(
        child: Column(children: [
          if (costPending)
            _banner(
                '$pendingCount line${pendingCount == 1 ? '' : 's'} not yet costed — Gross/Net Profit shown as "Pending" until batch costing completes.',
                Colors.orange),
          Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight),
                  boxShadow: kCardShadow),
              child: Column(children: [
                _hdr('Profit & Loss', Icons.trending_up_outlined, kSuccess),
                _plRow('Revenue', revenue, Colors.green, '+'),
                _plRow('Cost of Goods (COGS)', cogs!, Colors.blue, '-'),
                _plRow('Mortality Loss', mortality, Colors.red, '-'),
                _plRow('Shrinkage Loss', shrinkage, const Color(0xFF6A1B9A), '-'),
                _plRow('Trip Expenses', tripExp, Colors.orange, '-'),
                _plRow('Fixed Expenses', fixedExp, Colors.brown, '-'),
                Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: netProfit == null
                            ? Colors.orange.shade50
                            : netProfit >= 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15))),
                    child: Row(children: [
                      Expanded(
                          child: Text('= Net Profit',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: netProfit == null
                                      ? Colors.orange.shade800
                                      : netProfit >= 0
                                      ? Colors.green
                                      : Colors.red))),
                      Text(
                          netProfit == null ? 'Pending' : Fmt.amount(netProfit),
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: netProfit == null
                                  ? Colors.orange.shade800
                                  : netProfit >= 0
                                  ? Colors.green
                                  : Colors.red)),
                    ])),
              ])),
          _kpiGrid([
            _kpi('Revenue', Fmt.amount(revenue), const Color(0xFF1565C0), Icons.currency_rupee),
            _kpi('Gross Profit', grossProfit == null ? 'Pending' : Fmt.amount(grossProfit),
                grossProfit == null ? Colors.orange : (grossProfit >= 0 ? kSuccess : kError),
                Icons.calculate_outlined),
          ]),
          _kpiGrid([
            _kpi2('Total Expenses', Fmt.amount(totalExp), Colors.orange, Icons.receipt_long_outlined),
            _kpi2('Mortality', Fmt.amount(mortality), Colors.red, Icons.health_and_safety_outlined),
            _kpi2('Shrinkage', Fmt.amount(shrinkage), const Color(0xFF6A1B9A), Icons.compress_outlined),
          ]),
          _sec('${_gran.label.toUpperCase()} BREAKDOWN'),
          _tbl(
              ['Period', 'Revenue', 'COGS', 'Gross Profit', 'Net Profit'],
              _buckets.map((b) {
                final gp = _dn(b, 'gross_profit');
                final np = _dn(b, 'net_profit');
                final pend = _i(b, 'lines_cost_pending') > 0;
                return [
                  _fd(b['period_start']),
                  Fmt.amount(_d(b, 'revenue')),
                  pend ? 'Pending' : Fmt.amount(_dn(b, 'cogs') ?? 0),
                  gp == null ? 'Pending' : Fmt.amount(gp),
                  np == null ? 'Pending' : Fmt.amount(np),
                ];
              }).toList(),
              hi: [3, 4]),
          const SizedBox(height: 24),
        ]));
  }

  // ── helpers (display-only; no calculation) ──────────────────────────────
  double _d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
  double? _dn(Map m, String k) => (m[k] as num?)?.toDouble();
  int _i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
  String _fd(dynamic v) {
    if (v == null) return '—';
    try {
      return DateFormat('d MMM yy').format(DateTime.parse(v.toString()));
    } catch (_) {
      return v.toString();
    }
  }

  Widget _banner(String text, Color c) => Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: c),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600))),
      ]));

  Widget _hdr(String title, IconData icon, Color c) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.07),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusCard))),
      child: Row(children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c)),
      ]));

  Widget _plRow(String label, double value, Color c, String sign) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
      child: Row(children: [
        Container(width: 4, height: 20, color: c, margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: c, fontWeight: FontWeight.w600))),
        Text('$sign ${Fmt.amount(value)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ]));

  Widget _kpiGrid(List<Widget> cards) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(children: cards.expand((c) => [c, const SizedBox(width: 8)]).toList()..removeLast()));

  Widget _kpi(String label, String value, Color c, IconData icon) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: c.withValues(alpha: 0.25)),
              boxShadow: kCardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: kTextSub), maxLines: 1),
          ])));

  Widget _kpi2(String label, String value, Color c, IconData icon) => Expanded(
      child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(kRadiusCard)),
          child: Column(children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
            Text(label, style: const TextStyle(fontSize: 9, color: kTextSub), textAlign: TextAlign.center, maxLines: 1),
          ])));

  Widget _sec(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child:
      Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kNavy, letterSpacing: 0.6)));

  Widget _tbl(List<String> heads, List<List<String>> rows, {List<int> hi = const []}) => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 40,
              dataRowMinHeight: 38,
              dataRowMaxHeight: 44,
              headingRowColor: WidgetStateProperty.all(kNavy),
              columns: heads
                  .asMap()
                  .entries
                  .map((e) => DataColumn(
                  label: Text(e.value,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: hi.contains(e.key) ? kGoldLight : const Color(0xFFB4C6F4)))))
                  .toList(),
              rows: rows
                  .asMap()
                  .entries
                  .map((re) => DataRow(
                  color: WidgetStateProperty.resolveWith((s) => re.key.isOdd ? Colors.grey.shade50 : Colors.white),
                  cells: re.value
                      .asMap()
                      .entries
                      .map((ce) => DataCell(Text(ce.value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: hi.contains(ce.key) ? FontWeight.w800 : FontWeight.w500,
                          color: hi.contains(ce.key) ? kNavy : kTextMain))))
                      .toList()))
                  .toList())));
}