import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/web/web.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});
  @override ConsumerState<AlertsScreen> createState() => _S();
}
class _S extends ConsumerState<AlertsScreen> {
  final _c = Supabase.instance.client;
  List<Map<String,dynamic>> _alerts = [];
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      try { await _c.rpc('generate_alerts_v2', params: {'p_trader_id': tid}); } catch (_) {}
      final data = await _c.from('alerts').select('id,alert_type,severity,title,message,is_read,created_at')
          .eq('trader_id', tid).eq('is_read', false).order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      if (mounted) setState(() { _alerts = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _dismiss(String id) async {
    await _c.from('alerts').update({'is_read': true}).eq('id', id);
    if (mounted) setState(() => _alerts.removeWhere((a) => a['id'] == id));
  }

  Color _color(String t) => switch(t) {
    'credit_limit' || 'payment_overdue' => Colors.red,
    'stock_low' => Colors.orange,
    'shift_not_closed' || 'cash_mismatch' => Colors.blue,
    'mismatch' => Colors.purple,
    'expense_overclaim' => Colors.orange,
    _ => Colors.grey,
  };
  IconData _icon(String t) => switch(t) {
    'credit_limit' => Icons.credit_card_off_outlined,
    'payment_overdue' => Icons.payment_outlined,
    'stock_low' => Icons.inventory_2_outlined,
    'shift_not_closed' => Icons.schedule_outlined,
    'cash_mismatch' => Icons.account_balance_outlined,
    'expense_overclaim' => Icons.receipt_long_outlined,
    _ => Icons.notifications_outlined,
  };

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — KPIs, severity tabs, alert list with dismiss.
  // ═══════════════════════════════════════════════════════════════════════
  int _webTab = 0; // 0 all · 1 critical · 2 other

  Future<void> _dismissAll(String? tid) async {
    await _c.from('alerts').update({'is_read': true})
        .eq('trader_id', tid!).eq('is_read', false);
    if (mounted) setState(() => _alerts.clear());
  }

  Widget _buildWeb(String? tid) {
    bool critical(Map<String, dynamic> a) => a['severity'] == 'critical';
    final crit = _alerts.where(critical).length;
    final rows = switch (_webTab) {
      1 => _alerts.where(critical).toList(),
      2 => _alerts.where((a) => !critical(a)).toList(),
      _ => _alerts,
    };
    final types = <String>{for (final a in _alerts) a['alert_type'] as String? ?? ''};

    return WebPage(
      header: PageBreadcrumbsHeader(
        title: 'Alerts',
        titleTrailing: _alerts.isEmpty ? null
            : WebLabel('${_alerts.length} unread', color: WebColors.error,
                dot: true),
        subtitle: 'Things that need your attention',
        crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Alerts')],
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
              onTap: _load),
          if (_alerts.isNotEmpty) ...[
            const SizedBox(width: 8),
            WebButton(label: 'Dismiss All', icon: Icons.done_all_rounded,
                outlined: true, onPressed: () => _dismissAll(tid)),
          ],
        ]),
      ),
      children: [
        WebKpiRow(children: [
          WebKpiCard(label: 'Unread Alerts', value: '${_alerts.length}',
              icon: Icons.notifications_active_outlined,
              color: WebColors.navy),
          WebKpiCard(label: 'Critical', value: '$crit',
              icon: Icons.error_outline_rounded, color: WebColors.error),
          WebKpiCard(label: 'Other', value: '${_alerts.length - crit}',
              icon: Icons.info_outline_rounded, color: WebColors.warning),
          WebKpiCard(label: 'Alert Types', value: '${types.length}',
              icon: Icons.category_outlined, color: WebColors.info),
        ]),
        const SizedBox(height: WebSpace.lg),
        WebListCard(children: [
          WebListTabs(
            tabs: [
              WebTab('All', count: _alerts.length),
              WebTab('Critical', count: crit, color: WebColors.error),
              WebTab('Other', count: _alerts.length - crit,
                  color: WebColors.warning),
            ],
            selected: _webTab,
            onChanged: (i) => setState(() => _webTab = i),
          ),
          if (_loading)
            const WebTableState.loading()
          else if (rows.isEmpty)
            const WebTableState.empty(text: "All clear! No alerts.")
          else
            for (final a in rows) _webAlertRow(a),
          const SizedBox(height: WebSpace.sm),
        ]),
      ],
    );
  }

  Widget _webAlertRow(Map<String, dynamic> a) {
    final type = a['alert_type'] as String? ?? '';
    final sev = a['severity'] as String? ?? 'info';
    final date = DateTime.tryParse(a['created_at'] as String? ?? '');
    final color = _color(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: sev == 'critical' ? WebColors.errorBg : null,
        border: const Border(bottom: BorderSide(color: WebColors.divider)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WebIconTile(icon: _icon(type), color: color, size: 40),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Flexible(child: Text(a['title'] as String? ?? type,
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w700, color: WebColors.text1))),
            const SizedBox(width: 8),
            WebLabel(sev[0].toUpperCase() + sev.substring(1),
                color: sev == 'critical' ? WebColors.error : color),
          ]),
          const SizedBox(height: 4),
          Text(a['message'] as String? ?? '—', style: WebText.bodySub),
        ])),
        const SizedBox(width: 16),
        if (date != null)
          Text(DateFormat('d MMM, h:mm a').format(date),
              style: WebText.caption),
        const SizedBox(width: 12),
        WebIconButton(icon: Icons.check_rounded, tooltip: 'Dismiss',
            size: 32, onTap: () => _dismiss(a['id'] as String)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final scaffold = Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Row(children: [
          const Text('Alerts'),
          if (_alerts.isNotEmpty) ...[const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                child: Text('${_alerts.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))],
        ]),
        actions: [
          if (_alerts.isNotEmpty) TextButton(onPressed: () => _dismissAll(tid),
              child: const Text('Dismiss All')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading ? const LoadingList() : _alerts.isEmpty
          ? const EmptyState(icon: Icons.notifications_none_outlined, message: "All clear! No alerts.", sub: "You're up to date")
          : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), itemCount: _alerts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final a = _alerts[i];
            final type  = a['alert_type'] as String? ?? '';
            final sev   = a['severity']   as String? ?? 'info';
            final date  = DateTime.tryParse(a['created_at'] as String? ?? '');
            final color = _color(type);
            return Dismissible(key: Key(a['id'] as String), direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.check, color: Colors.green)),
                onDismissed: (_) => _dismiss(a['id'] as String),
                child: Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sev == 'critical' ? Colors.red.shade300 : color.withValues(alpha: 0.3), width: sev == 'critical' ? 2 : 1)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: Icon(_icon(type), color: color, size: 18)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['title'] as String? ?? type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(a['message'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: kTextSub)),
                        if (date != null) Text(DateFormat('d MMM, h:mm a').format(date), style: const TextStyle(fontSize: 10, color: kTextHint)),
                      ])),
                      IconButton(icon: const Icon(Icons.close, size: 16, color: kTextHint), onPressed: () => _dismiss(a['id'] as String), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    ])));
          }),
    );
    return ResponsiveLayout(mobile: (_) => scaffold,
        desktop: (_) => _buildWeb(tid));
  }
}