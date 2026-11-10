import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../shared/widgets/web/web.dart';
import 'package:rooster_trader/core/util/number_input.dart';

class DayClosureScreen extends ConsumerStatefulWidget {
  const DayClosureScreen({super.key});
  @override ConsumerState<DayClosureScreen> createState() => _S();
}

class _S extends ConsumerState<DayClosureScreen> {
  final _c = Supabase.instance.client;

  Map<String,dynamic>? _status;
  List<Map<String,dynamic>> _shifts = [];
  bool _loading = true, _submitting = false;

  DateTime _date = DateTime.now();
  String get _dateStr => _date.toIso8601String().split('T')[0];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      // Get day closure status
      final st = await _c.rpc('get_day_closure_status', params: {'p_trader_id': tid, 'p_date': _dateStr});

      // ✅ Get ALL shifts for selected date with agent names
      final shifts = await _c.from('delivery_shifts')
          .select('id,status,shift_start_at,shift_end_at,total_orders,total_cash_collected,total_expenses,total_birds_delivered,shift_approval_status,odometer_start,odometer_end,delivery_agents(id,name,vehicle_no)') // U10 FIX: added birds, approval status
          .eq('trader_id', tid)
          .gte('shift_start_at', '$_dateStr 00:00:00')
          .lt('shift_start_at', '${_nextDay()} 00:00:00')
          .order('shift_start_at');

      if (mounted) {
        setState(() {
        _status = st != null ? Map<String,dynamic>.from(((st as Map?)?.cast<String,dynamic>()) ?? {}) : {};
        _shifts = List<Map<String,dynamic>>.from(shifts);
        _loading = false;
      });
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _nextDay() {
    final next = _date.add(const Duration(days: 1));
    return next.toIso8601String().split('T')[0];
  }

  // ── Close single shift (admin force-close) ─────────────────────────
  Future<void> _closeShift(Map<String,dynamic> shift) async {
    final agent = shift['delivery_agents'] as Map<String,dynamic>?;
    final odoCtrl    = TextEditingController();
    final birdsCtrl  = TextEditingController(text: '0');
    final weightCtrl = TextEditingController(text: '0');
    final expCtrl    = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context, useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Close Shift — ${agent?['name'] ?? '—'}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Start odometer: ${shift['odometer_start'] ?? '—'} km',
              style: const TextStyle(fontSize: 12, color: kTextSub)),
          const SizedBox(height: 12),
          TextField(controller: odoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'End odometer (km)', suffixText: 'km')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: birdsCtrl, inputFormatters: birdsInputFormatters, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unsold birds'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: weightCtrl, inputFormatters: kgInputFormatters, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unsold kg'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: expCtrl, inputFormatters: moneyInputFormatters, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Expenses (₹)', prefixText: '₹')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true), child: const Text('Close Shift')),
        ],
      ),
    ) ?? false;

    if (!confirmed) { odoCtrl.dispose(); birdsCtrl.dispose(); weightCtrl.dispose(); expCtrl.dispose(); return; }

    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final odo     = double.tryParse(odoCtrl.text.trim());
    final birds   = int.tryParse(birdsCtrl.text.trim()) ?? 0;
    final weight  = double.tryParse(weightCtrl.text.trim()) ?? 0;
    final exp     = double.tryParse(expCtrl.text.trim()) ?? 0;
    odoCtrl.dispose(); birdsCtrl.dispose(); weightCtrl.dispose(); expCtrl.dispose();

    try {
      await _c.rpc('admin_close_shift', params: {
        'p_shift_id':       shift['id'],
        'p_odometer_end':   odo,
        'p_closing_birds':  birds,
        'p_closing_weight': weight,
        'p_total_expenses': exp,
        'p_closed_by':      uid,
      });
      _load();
      if (mounted) showSuccess(context, '${agent?['name'] ?? 'Shift'} closed ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  // ── Run cross-check ────────────────────────────────────────────────
  Future<void> _runCheck() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (mounted) setState(() => _submitting = true);
    try {
      await _c.rpc('run_cross_check', params: {'p_trader_id': tid, 'p_date': _dateStr, 'p_run_by': uid});
      _load();
      if (mounted) showSuccess(context, 'Cross-check complete ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  // ── Close the whole day ────────────────────────────────────────────
  Future<void> _closeDay() async {
    final openCount = _shifts.where((s) => s['status'] == 'open').length;
    if (openCount > 0) {
      final ok = await confirmDialog(context,
          title: 'Open Shifts Remaining',
          message: '$openCount shift(s) are still open.\nClose all shifts before closing the day.',
          confirmText: 'Force Close Day Anyway',
          confirmColor: Colors.orange);
      if (!ok) return;
    } else {
      final ok = await confirmDialog(context,
          title: 'Close Day — $_dateStr',
          message: 'This will mark today as closed for reconciliation.\nYou can still create orders if needed.',
          confirmText: 'Close Day',
          confirmColor: kError);
      if (!ok) return;
    }

    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (mounted) setState(() => _submitting = true);
    try {
      final res = await _c.rpc('initiate_day_closure',
          params: {'p_trader_id': tid, 'p_date': _dateStr, 'p_closed_by': uid});
      _load();
      if (mounted) {
        final locked = res?['locked'] as bool? ?? false;
        showSuccess(context, locked ? 'Day locked ✓' : 'Day closure initiated (some checks pending)');
      }
    } catch (e) { if (mounted) showError(context, e.toString()); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  Widget _buildScaffold(BuildContext context) {
    final isClosed = _status?['status'] == 'closed' || _status?['status'] == 'locked';
    final openShifts   = _shifts.where((s) => s['status'] == 'open').length;
    final closedShifts = _shifts.where((s) => s['status'] == 'closed').length;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Close Day'),
        actions: [
          // Date picker
          TextButton.icon(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now());
              if (d != null) { if (mounted) setState(() { _date = d; _status = null; _shifts = []; }); _load(); }
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(DateFormat('d MMM').format(_date)),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingList() : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isClosed
                  ? [const Color(0xFF047857), Colors.green.shade600]
                  : [kNavy, kNavyMid],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(isClosed ? Icons.lock : Icons.lock_open_outlined, color: Colors.white, size: 28),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM y').format(_date),
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(isClosed ? 'DAY IS CLOSED & LOCKED' : 'DAY IS OPEN',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('$openShifts open · $closedShifts closed shift(s)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Checklist ─────────────────────────────────────────────
        if (_status != null) WhiteCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('DAY CHECKLIST'),
          _check('All shifts closed',    openShifts == 0),
          _check('Cash reconciled',      _status!['cash_reconciled'] as bool? ?? false),
          _check('No pending approvals', (_status!['pending_approvals_today'] as int? ?? 0) == 0),
          _check('No pending returns',   (_status!['pending_returns_today']   as int? ?? 0) == 0),
          _check('Cross-check passed',   _status!['cross_check_passed']  as bool? ?? false),
          if ((_status!['total_revenue'] as num? ?? 0) > 0) ...[
            const Divider(height: 16),
            InfoRow('Total Revenue', Fmt.amount((_status!['total_revenue'] as num?)?.toDouble() ?? 0)),
            InfoRow('Cash Collected', Fmt.amount((_status!['total_cash_collected'] as num?)?.toDouble() ?? 0)),
            InfoRow('Total Orders', '${_status!['total_orders'] ?? 0}'),
          ],
        ])),
        const SizedBox(height: 14),

        // ── Shift list by agent ────────────────────────────────────
        const SectionHeader('TODAY\'S SHIFTS BY AGENT'),
        if (_shifts.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: const Text('No shifts started today.', style: TextStyle(color: kTextHint, fontSize: 13)),
          )
        else ..._shifts.map((shift) {
          final agent  = shift['delivery_agents'] as Map<String,dynamic>?;
          final status = shift['status'] as String? ?? 'open';
          final isOpen = status == 'open';
          final startAt = DateTime.tryParse(shift['shift_start_at'] as String? ?? '');
          final endAt   = shift['shift_end_at'] != null ? DateTime.tryParse(shift['shift_end_at'] as String) : null;
          final cash        = (shift['total_cash_collected'] as num?)?.toDouble() ?? 0;
          final expenses    = (shift['total_expenses'] as num?)?.toDouble() ?? 0;
          final netCash     = (cash - expenses).clamp(0.0, double.infinity);
          final orders      = shift['total_orders'] as int? ?? 0;
          final birds       = (shift['total_birds_delivered'] as num?)?.toInt() ?? 0;
          final approvalSt  = shift['shift_approval_status'] as String? ?? 'pending';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isOpen ? Colors.orange.shade300 : Colors.green.shade200, width: isOpen ? 1.5 : 1),
            ),
            child: Column(children: [
              // Header
              Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: isOpen ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delivery_dining, color: isOpen ? Colors.orange : Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(agent?['name'] as String? ?? '—',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(agent?['vehicle_no'] as String? ?? '',
                      style: const TextStyle(fontSize: 11, color: kTextHint)),
                ])),
                StatusBadge(status, isOpen ? Colors.orange : Colors.green),
              ])),

              // U10 FIX: Richer stats row — show cash, expenses, net, birds, approval
              Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 0), child: Column(children: [
                // Row 1: timing + order count
                Row(children: [
                  _mini('Start', startAt != null ? DateFormat('h:mm a').format(startAt) : '—'),
                  _mini('End',   endAt   != null ? DateFormat('h:mm a').format(endAt)   : '—'),
                  _mini('Orders', '$orders'),
                  _mini('Birds', birds > 0 ? '$birds' : '—'),
                ]),
                const SizedBox(height: 8),
                // Row 2: financial summary — the key numbers trader checks at day closure
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      _mini('Cash Collected', Fmt.amount(cash), color: Colors.green),
                      _vDivider(),
                      _mini('Expenses',       Fmt.amount(expenses), color: expenses > 0 ? Colors.red : kTextHint),
                      _vDivider(),
                      _mini('Net to Hand',    Fmt.amount(netCash), color: kPrimary, bold: true),
                    ])),
                // Approval status badge for closed shifts
                if (!isOpen) Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Row(children: [
                      Icon(
                          approvalSt == 'approved' ? Icons.verified_outlined : Icons.pending_outlined,
                          size: 13,
                          color: approvalSt == 'approved' ? Colors.green : Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                          approvalSt == 'approved' ? 'Shift approved ✓' : 'Pending shift approval',
                          style: TextStyle(fontSize: 11,
                              color: approvalSt == 'approved' ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.w600)),
                    ])),
              ])),

              // Open shift — show Close button
              if (isOpen && !isClosed) Container(
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.lock_outline, color: Colors.orange, size: 20),
                  title: const Text('Shift still open — close it',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange)),
                  trailing: ElevatedButton(
                    onPressed: () => _closeShift(shift),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        minimumSize: const Size(80, 34)),
                    child: const Text('Close', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),

              // Closed shift — show green tick
              if (!isOpen) Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 6),
                  Text('Shift closed ✓', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          );
        }),

        const SizedBox(height: 14),

        // ── Actions ────────────────────────────────────────────────
        if (!isClosed) ...[
          if (openShifts == 0) ...[
            OutlinedButton.icon(
              onPressed: _submitting ? null : _runCheck,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Run Cross-Check'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _closeDay,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline, size: 18),
              label: const Text('Close & Lock Day'),
              style: ElevatedButton.styleFrom(backgroundColor: kError),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text('$openShifts shift(s) still open. Close all shifts above before closing the day.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade800))),
              ]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _closeDay,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Force Close Day'),
              style: OutlinedButton.styleFrom(foregroundColor: kError, side: const BorderSide(color: kError)),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
            child: const Row(children: [
              Icon(Icons.lock, color: Colors.green, size: 22),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Day is locked ✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green)),
                Text('No new records can be created for this day.', style: TextStyle(fontSize: 12, color: Colors.green)),
              ])),
            ]),
          ),
        ],
        const SizedBox(height: 20),
      ])),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — status + checklist, shifts table, close-day actions.
  // Same actions and the same show/hide rules as the mobile layout.
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date,
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now());
    if (d != null) {
      if (mounted) setState(() { _date = d; _status = null; _shifts = []; });
      _load();
    }
  }

  Widget _buildWeb() {
    final isClosed = _status?['status'] == 'closed' || _status?['status'] == 'locked';
    final openShifts   = _shifts.where((s) => s['status'] == 'open').length;
    final closedShifts = _shifts.where((s) => s['status'] == 'closed').length;

    final header = PageBreadcrumbsHeader(
      title: 'Close Day',
      titleTrailing: _status == null ? null : WebLabel(
          isClosed ? 'Closed & Locked' : 'Open',
          color: isClosed ? WebColors.success : WebColors.warning, dot: true),
      subtitle: DateFormat('EEEE, d MMMM y').format(_date),
      crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Day Closure')],
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        WebButton(
          label: DateFormat('d MMM y').format(_date),
          icon: Icons.calendar_today_outlined,
          outlined: true,
          onPressed: _pickDate,
        ),
        const SizedBox(width: 8),
        WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
            onTap: _load),
      ]),
    );

    if (_loading) {
      return WebPage(header: header, children: const [
        WebCard(child: WebTableState.loading()),
      ]);
    }

    // ── Status hero ─────────────────────────────────────────────────────
    final hero = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: isClosed
                ? [const Color(0xFF047857), WebColors.success]
                : [WebColors.navy, WebColors.navyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(WebRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          WebIconTile(icon: isClosed ? Icons.lock : Icons.lock_open_outlined,
              color: Colors.white, size: 48),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('EEEE, d MMMM y').format(_date),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(isClosed ? 'Day is closed & locked' : 'Day is open',
                style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ])),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          _heroStat('Open shifts', '$openShifts'),
          _heroStat('Closed shifts', '$closedShifts'),
          _heroStat('Revenue', Fmt.amount(
              (_status?['total_revenue'] as num?)?.toDouble() ?? 0)),
          _heroStat('Cash Collected', Fmt.amount(
              (_status?['total_cash_collected'] as num?)?.toDouble() ?? 0)),
          _heroStat('Orders', '${_status?['total_orders'] ?? 0}'),
        ]),
      ]),
    );

    // ── Checklist ───────────────────────────────────────────────────────
    final checks = <(String, bool)>[
      ('All shifts closed', openShifts == 0),
      ('Cash reconciled', _status?['cash_reconciled'] as bool? ?? false),
      ('No pending approvals',
          (_status?['pending_approvals_today'] as int? ?? 0) == 0),
      ('No pending returns',
          (_status?['pending_returns_today'] as int? ?? 0) == 0),
      ('Cross-check passed', _status?['cross_check_passed'] as bool? ?? false),
    ];
    final done = checks.where((c) => c.$2).length;
    final checklist = WebSectionCard(
      title: 'Day Checklist',
      subtitle: '$done of ${checks.length} complete',
      icon: Icons.checklist_rounded,
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done / checks.length, minHeight: 6,
            backgroundColor: WebColors.divider,
            valueColor: AlwaysStoppedAnimation(
                done == checks.length ? WebColors.success : WebColors.warning),
          ),
        ),
        const SizedBox(height: 12),
        for (final c in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(c.$2 ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
                  size: 20,
                  color: c.$2 ? WebColors.success : WebColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(c.$1, style: TextStyle(fontSize: 13.5,
                  fontWeight: c.$2 ? FontWeight.w500 : FontWeight.w700,
                  color: c.$2 ? WebColors.text1 : WebColors.warning))),
            ]),
          ),
      ]),
    );

    // ── Shifts table ────────────────────────────────────────────────────
    final shiftsCard = WebListCard(children: [
      WebCardHeader(
        title: "Today's Shifts by Agent",
        subtitle: '${_shifts.length} shift${_shifts.length == 1 ? '' : 's'}',
        icon: Icons.delivery_dining,
      ),
      WebDataTable<Map<String, dynamic>>(
        columns: const [
          WebColumn('Agent', flex: 3),
          WebColumn('Vehicle', width: 130),
          WebColumn('Start', width: 95),
          WebColumn('End', width: 95),
          WebColumn('Orders', width: 85, align: TextAlign.right),
          WebColumn('Birds', width: 85, align: TextAlign.right),
          WebColumn('Cash', width: 120, align: TextAlign.right),
          WebColumn('Expenses', width: 110, align: TextAlign.right),
          WebColumn('Net to Hand', width: 130, align: TextAlign.right),
          WebColumn('Status', width: 180),
          WebColumn('Action', width: 110, align: TextAlign.center),
        ],
        rows: _shifts,
        paginate: true,
        dense: true,
        emptyText: 'No shifts started today.',
        cellBuilder: (shift, col) {
          final agent = shift['delivery_agents'] as Map<String, dynamic>?;
          final status = shift['status'] as String? ?? 'open';
          final isOpen = status == 'open';
          final cash = (shift['total_cash_collected'] as num?)?.toDouble() ?? 0;
          final exp = (shift['total_expenses'] as num?)?.toDouble() ?? 0;
          switch (col) {
            case 0:
              final name = agent?['name'] as String? ?? '—';
              return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: WebColors.text1));
            case 1:
              return Text(agent?['vehicle_no'] as String? ?? '—',
                  style: const TextStyle(fontSize: 13, color: WebColors.text2));
            case 2:
              final s = DateTime.tryParse(shift['shift_start_at'] as String? ?? '');
              return Text(s != null ? DateFormat('h:mm a').format(s) : '—',
                  style: const TextStyle(fontSize: 13, color: WebColors.text2));
            case 3:
              final e = shift['shift_end_at'] != null
                  ? DateTime.tryParse(shift['shift_end_at'] as String) : null;
              return Text(e != null ? DateFormat('h:mm a').format(e) : 'Running',
                  style: TextStyle(fontSize: 13,
                      color: e != null ? WebColors.text2 : WebColors.warning));
            case 4:
              return Text('${shift['total_orders'] ?? 0}',
                  style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
            case 5:
              final b = (shift['total_birds_delivered'] as num?)?.toInt() ?? 0;
              return Text(b > 0 ? '$b' : '—',
                  style: const TextStyle(fontSize: 13.5, color: WebColors.text2));
            case 6:
              return Text(Fmt.amount(cash), style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: WebColors.success));
            case 7:
              return Text(Fmt.amount(exp), style: TextStyle(fontSize: 13.5,
                  color: exp > 0 ? WebColors.error : WebColors.text3));
            case 8:
              return Text(Fmt.amount((cash - exp).clamp(0.0, double.infinity)),
                  style: const TextStyle(fontSize: 13.5,
                      fontWeight: FontWeight.w800, color: WebColors.navy));
            case 9:
              final appr = shift['shift_approval_status'] as String? ?? 'pending';
              return Row(mainAxisSize: MainAxisSize.min, children: [
                WebLabel(isOpen ? 'Open' : 'Closed ✓',
                    color: isOpen ? WebColors.warning : WebColors.success,
                    dot: true),
                if (!isOpen) ...[
                  const SizedBox(width: 6),
                  Text(appr == 'approved' ? '· Approved ✓'
                      : '· Pending',
                      style: TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: appr == 'approved'
                              ? WebColors.success : WebColors.warning)),
                ],
              ]);
            default:
              return isOpen && !isClosed
                  ? WebButton(label: 'Close', icon: Icons.lock_outline,
                      color: WebColors.warning,
                      onPressed: () => _closeShift(shift))
                  : const Text('—', style: WebText.caption);
          }
        },
      ),
      const SizedBox(height: WebSpace.md),
    ]);

    // ── Actions ─────────────────────────────────────────────────────────
    final Widget actions;
    if (isClosed) {
      actions = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WebColors.successBg,
          borderRadius: BorderRadius.circular(WebRadius.card),
          border: Border.all(color: WebColors.success.withValues(alpha: 0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.lock, color: WebColors.success, size: 22),
          SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Day is locked ✓', style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: WebColors.success)),
            Text('No new records can be created for this day.',
                style: TextStyle(fontSize: 12.5, color: WebColors.success)),
          ])),
        ]),
      );
    } else {
      actions = WebCard(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: openShifts == 0
              ? const Text('All shifts are closed. Run the cross-check, then '
                  'close and lock the day.', style: WebText.bodySub)
              : Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: WebColors.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                      '$openShifts shift(s) still open. Close all shifts '
                      'above before closing the day.',
                      style: const TextStyle(fontSize: 13.5,
                          color: WebColors.warning))),
                ])),
          const SizedBox(width: 16),
          if (openShifts == 0) ...[
            WebButton(
              label: 'Run Cross-Check',
              icon: Icons.fact_check_outlined,
              outlined: true,
              onPressed: _submitting ? null : _runCheck,
            ),
            const SizedBox(width: 10),
            WebButton(
              label: 'Close & Lock Day',
              icon: Icons.lock_outline,
              color: WebColors.error,
              onPressed: _submitting ? null : _closeDay,
            ),
          ] else
            WebButton(
              label: 'Force Close Day',
              icon: Icons.lock_outline,
              outlined: true,
              color: WebColors.error,
              onPressed: _submitting ? null : _closeDay,
            ),
        ]),
      );
    }

    return WebPage(header: header, children: [
      if (_status != null)
        WebKpiRow(children: [hero, checklist])
      else
        hero,
      const SizedBox(height: WebSpace.lg),
      shiftsCard,
      const SizedBox(height: WebSpace.lg),
      actions,
    ]);
  }

  Widget _heroStat(String label, String value) => Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 18,
        fontWeight: FontWeight.w800, color: Colors.white)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
  ]));

  Widget _check(String label, bool ok) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(ok ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 18, color: ok ? Colors.green : Colors.orange),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: ok ? kTextMain : Colors.orange, fontWeight: ok ? FontWeight.normal : FontWeight.w600)),
    ]),
  );

  Widget _mini(String label, String value, {Color? color, bool bold = false}) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(fontSize: 12,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            color: color ?? kTextMain), textAlign: TextAlign.center),
        Text(label, style: const TextStyle(fontSize: 10, color: kTextHint), textAlign: TextAlign.center),
      ]));

  Widget _vDivider() => Container(
      width: 1, height: 28, color: kBorder,
      margin: const EdgeInsets.symmetric(horizontal: 4));
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildWeb(),
  );

}