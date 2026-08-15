import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'report_dataset.dart';
import 'report_pdf_generator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Supervisor Report — standalone screen (not a ReportsHubScreen/_kR tab).
// Deliberately NOT wired into the shared ReportTableBlock/ReportActionsBar:
// that widget's Excel button is an existing stub across ~20 other reports
// ("Excel export — coming soon") and fixing it there would mean touching
// a widget every other report depends on for a change this task doesn't
// require. Screen view here is bespoke (plain table — the six columns
// don't need Card view). PDF reuses ReportPdfGenerator.generateFromData
// SetAndShow — the SAME underlying generator every other report's PDF
// button already calls, just invoked directly instead of through the
// wrapper widget. Excel is real CSV (opens natively in Excel/Sheets, zero
// new dependency), delivered via the same Printing.sharePdf bytes-out
// primitive already used elsewhere in this app for non-preview downloads.
// ─────────────────────────────────────────────────────────────────────────────

class SupervisorReportScreen extends ConsumerStatefulWidget {
  const SupervisorReportScreen({super.key});
  @override ConsumerState<SupervisorReportScreen> createState() => _S();
}

class _S extends ConsumerState<SupervisorReportScreen> {
  final _c = Supabase.instance.client;
  bool _loading = true, _loadingFilters = true, _busy = false;

  List<Map<String, dynamic>> _supervisors = [];
  List<Map<String, dynamic>> _retailers = [];
  String? _supervisorId, _retailerId, _paymentMode;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];

  @override void initState() { super.initState(); _loadFilters(); _load(); }

  Future<void> _loadFilters() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final sups = await _c.from('supervisor_profiles').select('id,name').eq('trader_id', tid).order('name');
      final rets = await _c.from('retailers').select('id,shop_name').eq('trader_id', tid).eq('is_active', true).order('shop_name').limit(5000);
      if (mounted) setState(() {
        _supervisors = List<Map<String, dynamic>>.from(sups as List? ?? []);
        _retailers = List<Map<String, dynamic>>.from(rets as List? ?? []);
        _loadingFilters = false;
      });
    } catch (_) { if (mounted) setState(() => _loadingFilters = false); }
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_supervisor_report', params: {
        'p_trader_id': tid,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
        if (_supervisorId != null) 'p_supervisor_id': _supervisorId,
        if (_retailerId != null) 'p_retailer_id': _retailerId,
        if (_paymentMode != null) 'p_payment_mode': _paymentMode,
      });
      final data = (res as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) setState(() {
        _summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
        _rows = List<Map<String, dynamic>>.from(data['rows'] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); showError(context, e.toString()); }
    }
  }

  double _n(String k) => (_summary[k] as num?)?.toDouble() ?? 0;
  int _i(String k) => (_summary[k] as num?)?.toInt() ?? 0;

  // ── Shared row-building — the ONE place Screen/PDF/Excel all read from,
  // so they can never disagree on formatting or column order. ────────────
  List<String> get _headers => const ['Date', 'Time', 'Retailer', 'Amount', 'Mode', 'Remarks'];

  List<List<String>> get _tableRows => _rows.map((r) {
    final date = DateTime.parse(r['entry_date'] as String);
    final createdAt = r['created_at'] != null ? DateTime.tryParse(r['created_at'] as String) : null;
    return [
      DateFormat('d MMM yyyy').format(date),
      createdAt != null ? DateFormat('h:mm a').format(createdAt.toLocal()) : '—',
      r['retailer_name'] as String? ?? '—',
      Fmt.amount((r['amount'] as num?)?.toDouble() ?? 0),
      (r['payment_mode'] as String? ?? '').toUpperCase(),
      r['description'] as String? ?? '',
    ];
  }).toList();

  ReportDataSet _buildDataSet() => ReportDataSet(
    title: 'Supervisor Report',
    fromDate: _from, toDate: _to,
    headers: _headers,
    rows: _tableRows,
    highlightColumns: const [3],
    summary: [
      ReportSummaryItem('Total Collected', Fmt.amount(_n('total_collected'))),
      ReportSummaryItem('Cash', Fmt.amount(_n('cash'))),
      ReportSummaryItem('UPI', Fmt.amount(_n('upi'))),
      ReportSummaryItem('Bank', Fmt.amount(_n('bank'))),
      ReportSummaryItem('Collections', '${_i('collections_count')}'),
      ReportSummaryItem('Retailers Visited', '${_i('retailers_visited')}'),
    ],
  );

  Future<void> _exportPdf() async {
    final company = ref.read(appUserProvider).valueOrNull?.companyName ?? 'Trader';
    if (mounted) setState(() => _busy = true);
    try {
      await ReportPdfGenerator.generateFromDataSetAndShow(context: context, dataSet: _buildDataSet(), companyName: company);
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  Future<void> _exportExcel() async {
    if (mounted) setState(() => _busy = true);
    try {
      final buf = StringBuffer();
      buf.writeln(_headers.map(_csvEscape).join(','));
      for (final row in _tableRows) {
        buf.writeln(row.map(_csvEscape).join(','));
      }
      final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
      final filename = 'SupervisorReport_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}.csv';
      // Same generic bytes-out-to-user primitive used elsewhere in this
      // app for non-PDF downloads (e.g. the bulk ledger ZIP) — works in
      // practice despite being labeled a "PDF" call, since delivery only
      // cares about bytes + filename.
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to));
    if (range != null) { setState(() { _from = range.start; _to = range.end; }); _load(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(title: const Text('Supervisor Report')),
      body: Column(children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.all(12),
          child: _loadingFilters
              ? const LinearProgressIndicator()
              : Column(children: [
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _supervisorId, isDense: true,
                decoration: const InputDecoration(labelText: 'Supervisor', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Supervisors')),
                  ..._supervisors.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String? ?? '—'))),
                ],
                onChanged: (v) { setState(() => _supervisorId = v); _load(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                value: _retailerId, isDense: true,
                decoration: const InputDecoration(labelText: 'Retailer', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Retailers')),
                  ..._retailers.map((r) => DropdownMenuItem(value: r['id'] as String, child: Text(r['shop_name'] as String? ?? '—'))),
                ],
                onChanged: (v) { setState(() => _retailerId = v); _load(); },
              )),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: _paymentMode, isDense: true,
                decoration: const InputDecoration(labelText: 'Payment Mode', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Modes')),
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                ],
                onChanged: (v) { setState(() => _paymentMode = v); _load(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: Text('${DateFormat('d MMM').format(_from)}–${DateFormat('d MMM').format(_to)}', style: const TextStyle(fontSize: 12)),
              )),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16), label: const Text('PDF', style: TextStyle(fontSize: 12)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _exportExcel,
                icon: const Icon(Icons.grid_on_outlined, size: 16), label: const Text('Excel', style: TextStyle(fontSize: 12)))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kNavy, kNavyMid], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(kRadiusHero),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('TOTAL COLLECTED', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  Text(Fmt.amount(_n('total_collected')), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('${_i('collections_count')} collections · ${_i('retailers_visited')} retailers visited', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _modeChip('Cash', _n('cash'), Colors.green.shade700)),
                const SizedBox(width: 8),
                Expanded(child: _modeChip('UPI', _n('upi'), Colors.blue.shade700)),
                const SizedBox(width: 8),
                Expanded(child: _modeChip('Bank', _n('bank'), Colors.purple.shade700)),
              ]),
              const SizedBox(height: 16),
              if (_rows.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 30), child: Center(child: Text('No collections in this range.', style: TextStyle(color: kTextHint)))),
              if (_rows.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(kBgPage),
                    columns: _headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))).toList(),
                    rows: _tableRows.map((r) => DataRow(cells: r.map((v) => DataCell(Text(v, style: const TextStyle(fontSize: 12)))).toList())).toList(),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _modeChip(String label, double amt, Color color) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard), border: Border.all(color: kBorderLight)),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(Fmt.amount(amt), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
      ]));
}