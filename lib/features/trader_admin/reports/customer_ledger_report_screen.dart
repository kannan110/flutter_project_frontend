import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rooster_trader/features/trader_admin/reports/report_pdf_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/filters/filter_bar.dart';
import 'customer_ledger_row_builder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOMER LEDGER REPORT  (Reports → Ledger → Customer Ledger)  — Phase 1
//
// Data source: get_retailer_statement() RPC only — the same RPC the
// Retailer Statement screen uses. No new query, no duplicated balance math;
// this screen only adds report-style filters (date preset incl. Yesterday,
// Delivery Agent, Retailer) on top of it and renders the classic ERP ledger
// grid instead of the mobile timeline.
//
// Phase 1 scope: Generate Report, Export PDF, Share PDF for ONE customer at
// a time. Half Sheet / Full Sheet / Print-All-Customers are Phase 2.
// ─────────────────────────────────────────────────────────────────────────────

enum _DatePreset { today, yesterday, thisWeek, thisMonth, custom }

extension _DatePresetX on _DatePreset {
  String get label => switch (this) {
    _DatePreset.today => 'Today',
    _DatePreset.yesterday => 'Yesterday',
    _DatePreset.thisWeek => 'This Week',
    _DatePreset.thisMonth => 'This Month',
    _DatePreset.custom => 'Custom',
  };
}

class CustomerLedgerReportScreen extends ConsumerStatefulWidget {
  const CustomerLedgerReportScreen({super.key});
  @override
  ConsumerState<CustomerLedgerReportScreen> createState() => _S();
}

class _S extends ConsumerState<CustomerLedgerReportScreen> {
  final _c = Supabase.instance.client;

  // ── Date filter ────────────────────────────────────────────────────────
  _DatePreset _preset = _DatePreset.thisMonth;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  // ── Agent filter ───────────────────────────────────────────────────────
  String _agentMode = 'all'; // 'all' | 'individual'
  String? _agentId;
  String? _agentName;
  List<Map<String, dynamic>> _agents = [];

  // ── Customer filter ────────────────────────────────────────────────────
  String _customerMode = 'all'; // 'all' | 'individual'
  String? _retailerId;
  List<Map<String, dynamic>> _retailers = [];

  bool _refLoading = true;
  bool _loading = false;
  bool _pdfBusy = false;
  Map<String, dynamic>? _data;
  String? _error;

  Map<String, dynamic> get _header => (_data?['header'] as Map?)?.cast<String, dynamic>() ?? {};
  double get _opening => (_data?['opening_balance'] as num?)?.toDouble() ?? 0;
  double get _closing => (_data?['closing_balance'] as num?)?.toDouble() ?? 0;
  List<LedgerPrintRow> get _printRows => _data == null ? [] : CustomerLedgerRowBuilder.build(_data!);

  bool get _canGenerate => _customerMode == 'individual' && _retailerId != null;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final agents = await _c
          .from('delivery_agents')
          .select('id,name,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .order('name');
      final retailers = await _c
          .from('retailers')
          .select('id,shop_name,owner_name,phone')
          .eq('trader_id', tid)
          .eq('is_active', true)
          .order('shop_name');
      if (mounted) {
        setState(() {
          _agents = List<Map<String, dynamic>>.from(agents);
          _retailers = List<Map<String, dynamic>>.from(retailers);
          _refLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _refLoading = false);
    }
  }

  // ── Date preset handling ───────────────────────────────────────────────
  void _applyPreset(_DatePreset p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime from, to;
    switch (p) {
      case _DatePreset.today:
        from = today;
        to = today;
      case _DatePreset.yesterday:
        from = today.subtract(const Duration(days: 1));
        to = from;
      case _DatePreset.thisWeek:
        from = today.subtract(Duration(days: today.weekday - 1)); // Monday start
        to = today;
      case _DatePreset.thisMonth:
        from = DateTime(now.year, now.month, 1);
        to = today;
      case _DatePreset.custom:
        return; // handled by _pickCustomRange
    }
    setState(() {
      _preset = p;
      _from = from;
      _to = to;
    });
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
      _preset = _DatePreset.custom;
      _from = picked.start;
      _to = picked.end;
    });
  }

  // ── Agent picker ───────────────────────────────────────────────────────
  Future<void> _pickAgent() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PickerSheet(
        title: 'Select Delivery Agent',
        items: _agents,
        labelOf: (a) => a['name'] as String? ?? '—',
        subtitleOf: (a) => a['phone'] as String?,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _agentId = picked['id'] as String;
        _agentName = picked['name'] as String?;
      });
    }
  }

  // ── Customer picker ────────────────────────────────────────────────────
  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PickerSheet(
        title: 'Select Customer',
        items: _retailers,
        labelOf: (r) => r['shop_name'] as String? ?? '—',
        subtitleOf: (r) => r['owner_name'] as String?,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _retailerId = picked['id'] as String;
        _data = null; // require re-generate for the newly picked customer
      });
    }
  }

  // ── Generate ───────────────────────────────────────────────────────────
  Future<void> _generate() async {
    if (!_canGenerate) return;
    if (mounted) setState(() { _loading = true; _error = null; _data = null; });
    try {
      final res = await _c.rpc('get_retailer_statement', params: {
        'p_retailer_id': _retailerId,
        'p_from_date': DateFormat('yyyy-MM-dd').format(_from),
        'p_to_date': DateFormat('yyyy-MM-dd').format(_to),
        if (_agentMode == 'individual' && _agentId != null) 'p_agent_id': _agentId,
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
        _error = e.toString().replaceAll('Exception: ', '');
        showError(context, _error!);
      }
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────
  Future<void> _downloadPdf() async {
    if (_data == null) return;
    setState(() => _pdfBusy = true);
    try {
      final company = ref.read(appUserProvider).valueOrNull?.companyName ?? 'DSR Chicken';
      await ReportPdfGenerator.generateCustomerLedgerReportAndShow(
        context: context,
        data: _data!,
        companyName: company,
        fromDate: _from,
        toDate: _to,
        agentFilterName: _agentMode == 'individual' ? _agentName : null,
      );
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _sharePdf() async {
    if (_data == null) return;
    setState(() => _pdfBusy = true);
    try {
      final company = ref.read(appUserProvider).valueOrNull?.companyName ?? 'DSR Chicken';
      await ReportPdfGenerator.shareCustomerLedgerReport(
        data: _data!,
        companyName: company,
        fromDate: _from,
        toDate: _to,
        agentFilterName: _agentMode == 'individual' ? _agentName : null,
      );
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Customer Ledger'),
      ),
      body: _refLoading
          ? const LoadingList()
          : ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          _filterPanel(),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: kNavy)),
            )
          else if (_data != null)
            _reportBody()
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'No report generated yet',
                sub: _customerMode == 'all'
                    ? 'Select an individual customer, then tap Generate Report.'
                    : 'Choose a customer and date range, then tap Generate Report.',
              ),
            ),
        ],
      ),
    );
  }

  // ── Filter panel ───────────────────────────────────────────────────────
  Widget _filterPanel() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DATE RANGE', style: kTypeSectionTitle),
        const SizedBox(height: 8),
        FilterBar<_DatePreset>(
          options: _DatePreset.values,
          selected: _preset,
          onSelected: (p) => p == _DatePreset.custom ? _pickCustomRange() : _applyPreset(p),
          labelBuilder: (p) => p.label,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 4),
        Text(
          '${DateFormat('d MMM yyyy').format(_from)}  →  ${DateFormat('d MMM yyyy').format(_to)}',
          style: kTypeCaption,
        ),
        const SizedBox(height: 16),

        const Text('DELIVERY AGENT', style: kTypeSectionTitle),
        const SizedBox(height: 8),
        FilterBar<String>(
          options: const ['all', 'individual'],
          selected: _agentMode,
          onSelected: (m) => setState(() => _agentMode = m),
          labelBuilder: (m) => m == 'all' ? 'All Agents' : 'Individual Agent',
          padding: EdgeInsets.zero,
        ),
        if (_agentMode == 'individual') ...[
          const SizedBox(height: 8),
          _pickerField(
            label: _agentName ?? 'Select agent…',
            filled: _agentId != null,
            onTap: _pickAgent,
          ),
        ],
        const SizedBox(height: 16),

        const Text('CUSTOMER', style: kTypeSectionTitle),
        const SizedBox(height: 8),
        FilterBar<String>(
          options: const ['all', 'individual'],
          selected: _customerMode,
          onSelected: (m) => setState(() {
            _customerMode = m;
            if (m == 'all') { _retailerId = null; _data = null; }
          }),
          labelBuilder: (m) => m == 'all' ? 'All Customers' : 'Individual Customer',
          padding: EdgeInsets.zero,
        ),
        if (_customerMode == 'individual') ...[
          const SizedBox(height: 8),
          _pickerField(
            label: _retailerId == null
                ? 'Select customer…'
                : (_retailers.firstWhere((r) => r['id'] == _retailerId,
                orElse: () => const {})['shop_name'] as String? ?? 'Selected'),
            filled: _retailerId != null,
            onTap: _pickCustomer,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Batch generation for all customers arrives in a future update — pick an individual customer to generate a report now.',
              style: kTypeCaption.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _canGenerate && !_loading ? _generate : null,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Generate Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kNavy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: kBorder,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _pickerField({required String label, required bool filled, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kBgPage,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorder),
        ),
        child: Row(children: [
          const Icon(Icons.search, size: 18, color: kTextHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                    color: filled ? kTextMain : kTextHint)),
          ),
          const Icon(Icons.chevron_right, size: 18, color: kTextHint),
        ]),
      ),
    );
  }

  // ── Report body — plain ERP ledger grid ───────────────────────────────
  Widget _reportBody() {
    final rows = _printRows;
    final retailerName = _header['retailer_name'] as String? ?? '—';
    final retailerPhone = _header['retailer_phone'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Plain statement header — no colors, large readable text ──────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(kRadiusCard),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customer Ledger Statement',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kTextMain)),
            const SizedBox(height: 12),
            _plainRow('Customer', retailerName),
            if (retailerPhone != null) _plainRow('Mobile', retailerPhone),
            _plainRow('Period',
                '${DateFormat('dd-MMM-yyyy').format(_from)}  to  ${DateFormat('dd-MMM-yyyy').format(_to)}'),
            if (_agentMode == 'individual' && _agentName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing entries handled by $_agentName only. Balance reflects the full account across all agents.',
                  style: kTypeCaption.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Ledger grid ────────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _LedgerTable(rows: rows, opening: _opening, closing: _closing),
        ),
        const SizedBox(height: 20),

        // ── Actions ────────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pdfBusy ? null : _downloadPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Export PDF'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kNavy,
                side: const BorderSide(color: kNavy),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pdfBusy ? null : _sharePdf,
              icon: _pdfBusy
                  ? const SizedBox(width: 15, height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.share_outlined, size: 18, color: Colors.white),
              label: Text(_pdfBusy ? 'Preparing…' : 'Share PDF',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _plainRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 76, child: Text('$label :', style: const TextStyle(fontSize: 14, color: kTextSub))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain))),
    ]),
  );
}

// ── Plain ERP ledger grid ─────────────────────────────────────────────────
class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.rows, required this.opening, required this.closing});
  final List<LedgerPrintRow> rows;
  final double opening;
  final double closing;

  static const _colWidths = <double>[64, 70, 60, 160, 60, 60, 95, 95, 105];
  static const _headers = ['Date', 'Ref No', 'Type', 'Product / Description', 'Kg', 'Rate', 'Sale', 'Payment', 'Balance'];

  TextStyle get _headStyle => const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kTextMain);
  TextStyle get _cellStyle => const TextStyle(fontSize: 13, color: kTextMain);
  TextStyle get _cellSubStyle => const TextStyle(fontSize: 13, color: kTextSub);

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? '' : DateFormat('dd-MMM').format(d);
  }

  Widget _cell(int i, Widget child) => Container(
    width: _colWidths[i],
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    alignment: i >= 4 ? Alignment.centerRight : Alignment.centerLeft,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final totalWidth = _colWidths.fold(0.0, (a, b) => a + b);
    return Container(
      width: totalWidth,
      decoration: BoxDecoration(border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        // Header row
        Container(
          decoration: const BoxDecoration(
              color: kBgPage, border: Border(bottom: BorderSide(color: kBorder, width: 1.2))),
          child: Row(children: List.generate(
              _headers.length, (i) => _cell(i, Text(_headers[i], style: _headStyle)))),
        ),
        // Opening balance
        _plainLine(
          date: '', ref: 'OPEN', type: 'Opening', desc: 'Opening Balance',
          kg: null, rate: null, sale: null, payment: null, balance: opening, bold: true,
        ),
        // Transactions
        for (final r in rows)
          _plainLine(
            date: r.date == null ? '' : _fmtDate(r.date),
            ref: r.refNo ?? '',
            type: r.type ?? '',
            desc: r.description,
            kg: r.kg, rate: r.rate, sale: r.saleAmt, payment: r.paymentAmt, balance: r.balance,
          ),
        // Closing balance
        _plainLine(
          date: '', ref: '', type: '', desc: 'Closing Balance',
          kg: null, rate: null, sale: null, payment: null, balance: closing, bold: true, topBorder: true,
        ),
      ]),
    );
  }

  Widget _plainLine({
    required String date,
    required String ref,
    required String type,
    required String desc,
    required double? kg,
    required double? rate,
    required double? sale,
    required double? payment,
    required double balance,
    bool bold = false,
    bool topBorder = false,
  }) {
    final style = bold ? _cellStyle.copyWith(fontWeight: FontWeight.w800) : _cellStyle;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kBorder.withValues(alpha: 0.4), width: 0.6),
          top: topBorder ? const BorderSide(color: kBorder, width: 1.2) : BorderSide.none,
        ),
      ),
      child: Row(children: [
        _cell(0, Text(date, style: _cellSubStyle)),
        _cell(1, Text(ref, style: _cellSubStyle)),
        _cell(2, Text(type, style: _cellSubStyle)),
        _cell(3, Text(desc, style: style, overflow: TextOverflow.ellipsis, maxLines: 1)),
        _cell(4, Text(kg == null ? '' : kg.toStringAsFixed(2), style: _cellStyle)),
        _cell(5, Text(rate == null ? '' : rate.toStringAsFixed(0), style: _cellStyle)),
        _cell(6, Text(sale == null ? '' : Fmt.plainAmount(sale), style: _cellStyle)),
        _cell(7, Text(payment == null ? '' : Fmt.plainAmount(payment), style: _cellStyle)),
        _cell(8, Text(Fmt.plainAmount(balance), style: style)),
      ]),
    );
  }
}

// ── Reusable search-and-pick bottom sheet ─────────────────────────────────
class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.items, required this.labelOf, this.subtitleOf});
  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) labelOf;
  final String? Function(Map<String, dynamic>)? subtitleOf;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items.where((i) => widget.labelOf(i).toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search…',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: kBgPage,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorderLight)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matches', style: TextStyle(color: kTextHint)))
                : ListView.separated(
              controller: scrollCtrl,
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = filtered[i];
                final sub = widget.subtitleOf?.call(item);
                return ListTile(
                  title: Text(widget.labelOf(item), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: sub == null ? null : Text(sub),
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(item),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}