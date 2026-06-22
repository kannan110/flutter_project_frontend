import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'report_pdf_generator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CASH FLOW SCREEN
// UI ONLY — calls the existing get_cash_flow_statement RPC (Phase 4 backend).
// Running balance, cash-in/out splits are computed server-side; this screen
// only displays the returned JSON.
// ─────────────────────────────────────────────────────────────────────────────

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

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});
  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  final _c = Supabase.instance.client;

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
  List<Map<String, dynamic>> get _daily => List<Map<String, dynamic>>.from(
      (_data?['daily'] as List?)?.map((e) => (e as Map).cast<String, dynamic>()) ?? []);

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _c.rpc('get_cash_flow_statement', params: {
        'p_trader_id': tid,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
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
        reportLabel: 'Cash Flow',
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
          const Text('Cash Flow', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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

  Widget _buildDateBar() => Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                Text(_error ?? 'Error loading cash flow', textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]))));

  Widget _buildBody() {
    final s = _summary;
    final cashIn = _d(s, 'total_cash_in');
    final cashOut = _d(s, 'total_cash_out');
    final net = _d(s, 'net_movement');
    final daily = _daily;
    final currentBalance = daily.isNotEmpty ? _d(daily.first, 'running_balance') : 0.0;

    return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: kBottomNavClearance),
        child: Column(children: [
          Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: kNavy.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CASH POSITION (MOVEMENT)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFB4C6F4), letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Text(Fmt.amount(currentBalance),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Net movement over selected period: ${net >= 0 ? "+" : ""}${Fmt.amount(net)}',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
              ])),
          _banner('Cash position shows movement within the selected range, not an absolute till balance.', Colors.orange),
          _kpiGrid([
            _kpi('Cash In', Fmt.amount(cashIn), kSuccess, Icons.arrow_downward_rounded),
            _kpi('Cash Out', Fmt.amount(cashOut), kError, Icons.arrow_upward_rounded),
          ]),
          _sec('DAILY CASH FLOW'),
          _tbl(
              ['Date', 'Cash In', 'Supplier Paid', 'Trip Exp', 'Fixed Exp', 'Net', 'Balance'],
              daily.map((d) {
                final netM = _d(d, 'net_movement');
                return [
                  _fd(d['date']),
                  Fmt.amount(_d(d, 'cash_in_total')),
                  Fmt.amount(_d(d, 'cash_out_supplier')),
                  Fmt.amount(_d(d, 'cash_out_trip')),
                  Fmt.amount(_d(d, 'cash_out_fixed')),
                  '${netM >= 0 ? "+" : ""}${Fmt.amount(netM)}',
                  Fmt.amount(_d(d, 'running_balance')),
                ];
              }).toList(),
              hi: [5, 6]),
          const SizedBox(height: 24),
        ]));
  }

  double _d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
  String _fd(dynamic v) {
    if (v == null) return '—';
    try {
      return DateFormat('d MMM yy').format(DateTime.parse(v.toString()));
    } catch (_) {
      return v.toString();
    }
  }

  Widget _banner(String text, Color c) => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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
              columnSpacing: 16,
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