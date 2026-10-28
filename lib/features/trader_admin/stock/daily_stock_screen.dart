import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DAILY STOCK SCREEN
//
// Phase 8: Shows frozen end-of-day stock positions from daily_stock_snapshots.
// Replaces the live ledger scan for historical stock queries — positions here
// are immutable once snapped.
//
// Features:
//   • Date range selector (last 7 / last 30 / this month / custom)
//   • Range summary KPIs: total purchased, delivered, mortality, cash, expenses
//   • Daily rows: per-day card with opening → in → out → closing
//   • Per-agent breakdown expandable on each day card
//   • Missing dates banner: shows which dates lack a snapshot with "Snap Now"
//   • Retroactive snap: capture any past date's position from the ledger
//   • Manual snap: freeze today's position on demand
//
// Auto-snap note: No pg_cron in this project. Snapshots are triggered by:
//   (a) Trader tapping "Snap Now" for a specific date
//   (b) Trader tapping "Snap All Missing" to batch-backfill the date range
//   (c) Future: calling create_daily_snapshot inside approve_shift (Phase 9)
// ─────────────────────────────────────────────────────────────────────────────

class DailyStockScreen extends ConsumerStatefulWidget {
  const DailyStockScreen({super.key});

  @override
  ConsumerState<DailyStockScreen> createState() => _DailyStockScreenState();
}

class _DailyStockScreenState extends ConsumerState<DailyStockScreen> {
  final _c = Supabase.instance.client;

  _DatePreset _preset = _DatePreset.last7;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to   = DateTime.now();

  bool _loading    = false;
  bool _snapping   = false;
  Map<String, dynamic> _data = {};

  // Which day cards are expanded to show agent detail
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_daily_stock_history', params: {
        'p_trader_id': tid,
        'p_from':      DateFormat('yyyy-MM-dd').format(_from),
        'p_to':        DateFormat('yyyy-MM-dd').format(_to),
      }).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _data    = (res as Map?)?.cast<String, dynamic>() ?? {};
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _snapDate(DateTime date) async {
    final tid  = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid  = ref.read(appUserProvider).valueOrNull?.userId;
    if (tid == null) return;
    setState(() => _snapping = true);
    try {
      await _c.rpc('create_daily_snapshot', params: {
        'p_trader_id':  tid,
        'p_date':       DateFormat('yyyy-MM-dd').format(date),
        'p_snapped_by': uid,
      }).timeout(const Duration(seconds: 20));
      if (mounted) {
        showSuccess(context,
            '✅ Snapshot created for ${DateFormat('d MMM').format(date)}');
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _snapping = false);
    }
  }

  Future<void> _snapAllMissing() async {
    final missing = _missingDates;
    if (missing.isEmpty) return;

    final ok = await confirmDialog(
      context,
      title: 'Snap All Missing Dates',
      message: 'Create snapshots for ${missing.length} date(s)?\n\n'
          '${missing.take(5).map((d) => DateFormat('d MMM').format(d)).join(', ')}'
          '${missing.length > 5 ? ' …+${missing.length - 5} more' : ''}',
      confirmText: 'Snap All',
      confirmColor: kNavy,
    );
    if (!ok || !mounted) return;

    setState(() => _snapping = true);
    int done = 0;
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      final uid = ref.read(appUserProvider).valueOrNull?.userId;
      if (tid == null) return;

      for (final date in missing) {
        try {
          await _c.rpc('create_daily_snapshot', params: {
            'p_trader_id':  tid,
            'p_date':       DateFormat('yyyy-MM-dd').format(date),
            'p_snapped_by': uid,
          }).timeout(const Duration(seconds: 20));
          done++;
        } catch (_) {}
      }
      if (mounted) {
        showSuccess(context, '✅ $done snapshot(s) created');
        await _load();
      }
    } finally {
      if (mounted) setState(() => _snapping = false);
    }
  }

  // ── Derived state ───────────────────────────────────────────────────────────
  Map<String, dynamic> get _summary =>
      ((_data['range_summary'] as Map?)?.cast<String, dynamic>()) ?? {};

  List<Map<String, dynamic>> get _dailyRows =>
      List<Map<String, dynamic>>.from(
          (_data['daily_rows'] as List?)?.map((e) =>
              (e as Map).cast<String, dynamic>()) ?? []);

  List<DateTime> get _missingDates {
    final raw = _data['missing_dates'] as List? ?? [];
    return raw.map((d) {
      try { return DateTime.parse(d as String); } catch (_) { return null; }
    }).whereType<DateTime>().toList();
  }

  void _applyPreset(_DatePreset p) {
    final now = DateTime.now();
    setState(() {
      _preset = p;
      switch (p) {
        case _DatePreset.last7:
          _from = now.subtract(const Duration(days: 6)); _to = now;
        case _DatePreset.last30:
          _from = now.subtract(const Duration(days: 29)); _to = now;
        case _DatePreset.thisMonth:
          _from = DateTime(now.year, now.month, 1); _to = now;
        case _DatePreset.custom:
          break; // user picks via date pickers
      }
    });
    if (p != _DatePreset.custom) _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _DatePreset.custom;
      _from   = picked.start;
      _to     = picked.end;
    });
    _load();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily Stock Snapshots',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('Frozen end-of-day positions',
                style: TextStyle(fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
        actions: [
          if (_snapping)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              tooltip: 'Snap Today',
              onPressed: () => _snapDate(DateTime.now()),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(children: [
        _dateRangeBar(),
        Expanded(
          child: _loading
              ? const LoadingList()
              : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
              children: [
                // Missing dates banner
                if (_missingDates.isNotEmpty) ...[
                  _missingDatesBanner(),
                  const SizedBox(height: 12),
                ],

                // Range summary KPIs
                _summaryCard(),
                const SizedBox(height: 12),

                // Daily rows
                if (_dailyRows.isEmpty)
                  EmptyState(
                    icon: Icons.calendar_today_outlined,
                    message: 'No snapshots in this range',
                    sub: 'Tap the camera icon or "Snap All" to freeze daily positions.',
                    onAction: _missingDates.isNotEmpty
                        ? _snapAllMissing : null,
                    actionLabel: 'Snap All Missing',
                  )
                else
                  ..._dailyRows.map(_buildDayCard),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Date range bar ──────────────────────────────────────────────────────────
  Widget _dateRangeBar() {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        ..._DatePreset.values.map((p) {
          final sel = _preset == p;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => p == _DatePreset.custom
                  ? _pickCustomRange() : _applyPreset(p),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? kNavy : kBgPage,
                  borderRadius: BorderRadius.circular(kRadiusChip),
                  border: Border.all(
                      color: sel ? kNavy : kBorderLight),
                ),
                child: Text(p.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : kTextSub)),
              ),
            ),
          );
        }),
        const Spacer(),
        Text(
          '${DateFormat('d MMM').format(_from)} – '
              '${DateFormat('d MMM').format(_to)}',
          style: const TextStyle(fontSize: 10, color: kTextHint),
        ),
      ]),
    );
  }

  // ── Missing dates banner ────────────────────────────────────────────────────
  Widget _missingDatesBanner() {
    final m = _missingDates;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(
            '${m.length} date(s) without snapshots',
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: Colors.orange),
          )),
          if (!_snapping)
            TextButton(
              onPressed: _snapAllMissing,
              style: TextButton.styleFrom(
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  minimumSize: Size.zero),
              child: const Text('Snap All',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6, runSpacing: 4,
          children: m.take(7).map((d) => GestureDetector(
            onTap: _snapping ? null : () => _snapDate(d),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusChip),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${DateFormat('d MMM').format(d)} +'  ,
                style: const TextStyle(
                    fontSize: 10, color: Colors.orange,
                    fontWeight: FontWeight.w700),
              ),
            ),
          )).toList(),
        ),
      ]),
    );
  }

  // ── Range summary card ──────────────────────────────────────────────────────
  Widget _summaryCard() {
    final purchased = (_summary['total_purchased_birds'] as num?)?.toInt() ?? 0;
    final delivered = (_summary['total_delivered_birds'] as num?)?.toInt() ?? 0;
    final mortality = (_summary['total_mortality_birds'] as num?)?.toInt() ?? 0;
    final cash      = (_summary['total_cash']            as num?)?.toDouble() ?? 0;
    final expenses  = (_summary['total_expenses']        as num?)?.toDouble() ?? 0;
    final closing   = (_summary['latest_closing_birds']  as num?)?.toInt() ?? 0;
    final days      = (_summary['days_snapped']          as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00081E), Color(0xFF0A1F44)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kRadiusCard),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('RANGE SUMMARY',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                  color: Color(0xFFB4C6F4), letterSpacing: 0.8))),
          Text('$days day(s) snapped',
              style: const TextStyle(fontSize: 10, color: Color(0xFF7B94C8))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _heroKpi('Purchased', '$purchased birds', Colors.blue),
          _heroKpi('Delivered', '$delivered birds', Colors.green),
          _heroKpi('Mortality', '$mortality birds', Colors.red),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _heroKpi('Cash', Fmt.amount(cash), Colors.green),
          _heroKpi('Expenses', Fmt.amount(expenses), Colors.orange),
          _heroKpi('Now in Stock', '$closing birds', const Color(0xFFE9C176)),
        ]),
      ]),
    );
  }

  Widget _heroKpi(String label, String value, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w900, color: color),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 9,
            color: Color(0xFF7B94C8)),
            textAlign: TextAlign.center),
      ]));

  // ── Day card ────────────────────────────────────────────────────────────────
  Widget _buildDayCard(Map<String, dynamic> row) {
    final id          = row['id'] as String? ?? '';
    final dateStr     = row['snapshot_date'] as String? ?? '';
    final date        = DateTime.tryParse(dateStr);
    final isRetro     = row['is_retroactive'] as bool? ?? false;
    final openBirds   = (row['opening_birds']        as num?)?.toInt() ?? 0;
    final purchased   = (row['purchased_birds']      as num?)?.toInt() ?? 0;
    final transIn     = (row['transferred_in_birds'] as num?)?.toInt() ?? 0;
    final delivered   = (row['delivered_birds']      as num?)?.toInt() ?? 0;
    final mortality   = (row['mortality_birds']      as num?)?.toInt() ?? 0;
    final transOut    = (row['transferred_out_birds']as num?)?.toInt() ?? 0;
    final returned    = (row['returned_birds']       as num?)?.toInt() ?? 0;
    final closingB    = (row['closing_birds']        as num?)?.toInt() ?? 0;
    final closingKg   = (row['closing_kg']           as num?)?.toDouble() ?? 0;
    final cash        = (row['total_cash']           as num?)?.toDouble() ?? 0;
    final expenses    = (row['total_expenses']       as num?)?.toDouble() ?? 0;
    final product     = row['product_name'] as String? ?? 'Broiler';
    final agents      = (row['agents'] as List? ?? [])
        .map((a) => (a as Map).cast<String, dynamic>()).toList();
    final expanded    = _expandedIds.contains(id);

    final dateLabel = date != null
        ? DateFormat('EEE, d MMM').format(date) : dateStr;
    final isToday = date != null &&
        DateFormat('yyyy-MM-dd').format(date) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: isToday
              ? kNavy.withValues(alpha: 0.4) : kBorderLight,
          width: isToday ? 1.5 : 1,
        ),
        boxShadow: kCardShadow,
      ),
      child: Column(children: [
        // Header row
        InkWell(
          onTap: agents.isNotEmpty
              ? () => setState(() {
            if (expanded) {
              _expandedIds.remove(id);
            } else {
              _expandedIds.add(id);
            }
          })
              : null,
          borderRadius: BorderRadius.vertical(
              top: const Radius.circular(kRadiusCard),
              bottom: Radius.circular(expanded ? 0 : kRadiusCard)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                // Date + badge
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(dateLabel,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isToday ? kNavy : kTextMain)),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: kNavy.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('TODAY',
                                style: TextStyle(fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: kNavy)),
                          ),
                        ],
                        if (isRetro) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('RETROACTIVE',
                                style: TextStyle(fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.purple)),
                          ),
                        ],
                      ]),
                      Text(product,
                          style: const TextStyle(
                              fontSize: 11, color: kTextHint)),
                    ])),
                // Closing position pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: closingB > 0
                        ? kNavy.withValues(alpha: 0.08)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child: Column(children: [
                    Text('$closingB birds',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900,
                            color: closingB > 0 ? kNavy : kTextHint)),
                    Text('${closingKg.toStringAsFixed(1)} kg',
                        style: const TextStyle(
                            fontSize: 9, color: kTextHint)),
                    const Text('CLOSING',
                        style: TextStyle(fontSize: 8,
                            color: kTextHint, letterSpacing: 0.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              // Flow row: opening → in → out → closing
              _flowRow(openBirds, purchased, transIn, delivered,
                  mortality, transOut, returned, closingB, cash, expenses),
            ]),
          ),
        ),

        // Agent detail expansion
        if (expanded && agents.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('BY AGENT',
                      style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: kTextHint, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  ...agents.map((a) => _agentRow(a)),
                ]),
          ),
        ],
      ]),
    );
  }

  Widget _flowRow(int open, int purch, int tIn, int deliv, int mort,
      int tOut, int ret, int closing, double cash, double expenses) {
    return Row(children: [
      _flowChip('Open',    '$open',    Colors.grey),
      _arrow(),
      if (purch > 0) ...[
        _flowChip('+Purch', '+$purch', Colors.blue),
        _arrow(),
      ],
      if (tIn > 0) ...[
        _flowChip('+Trans', '+$tIn', Colors.teal),
        _arrow(),
      ],
      _flowChip('−Deliv', '−$deliv', kNavy),
      if (mort > 0) ...[
        _arrow(),
        _flowChip('−Mort', '−$mort', Colors.red),
      ],
      if (tOut > 0) ...[
        _arrow(),
        _flowChip('−Out', '−$tOut', Colors.indigo),
      ],
      _arrow(),
      _flowChip('Close', '$closing', closing > 0 ? Colors.green : Colors.grey),
      const Spacer(),
      if (cash > 0)
        Text(Fmt.amount(cash),
            style: const TextStyle(fontSize: 10,
                color: Colors.green, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _flowChip(String label, String value, Color color) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(
            fontSize: 8, color: kTextHint)),
      ]);

  Widget _arrow() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 3),
    child: Text('→', style: TextStyle(fontSize: 10, color: kBorderLight)),
  );

  Widget _agentRow(Map<String, dynamic> a) {
    final name    = a['agent_name']      as String? ?? '—';
    final purch   = (a['purchased_birds'] as num?)?.toInt() ?? 0;
    final deliv   = (a['delivered_birds'] as num?)?.toInt() ?? 0;
    final mort    = (a['mortality_birds'] as num?)?.toInt() ?? 0;
    final closing = (a['closing_birds']   as num?)?.toInt() ?? 0;
    final closKg  = (a['closing_kg']      as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        CircleAvatar(radius: 14,
            backgroundColor: kNavy.withValues(alpha: 0.08),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800, color: kNavy))),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700))),
        if (purch > 0) _agentStat('DC', '+$purch', Colors.blue),
        _agentStat('Del', '−$deliv', kNavy),
        if (mort > 0) _agentStat('Mort', '−$mort', Colors.red),
        _agentStat('Close', '$closing birds\n${closKg.toStringAsFixed(1)} kg',
            closing > 0 ? Colors.green : kTextHint),
      ]),
    );
  }

  Widget _agentStat(String label, String value, Color color) =>
      Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(kRadiusInner),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: TextStyle(fontSize: 10,
              fontWeight: FontWeight.w800, color: color),
              textAlign: TextAlign.center),
          Text(label, style: const TextStyle(
              fontSize: 8, color: kTextHint),
              textAlign: TextAlign.center),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
enum _DatePreset { last7, last30, thisMonth, custom }

extension _DatePresetX on _DatePreset {
  String get label => switch (this) {
    _DatePreset.last7     => 'Last 7',
    _DatePreset.last30    => 'Last 30',
    _DatePreset.thisMonth => 'This Month',
    _DatePreset.custom    => 'Custom',
  };
}