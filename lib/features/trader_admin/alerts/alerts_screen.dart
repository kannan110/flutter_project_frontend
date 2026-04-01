import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

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
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      try { await _c.rpc('generate_alerts_v2', params: {'p_trader_id': tid}); } catch (_) {}
      // alerts: id,alert_type,severity,title,message,is_read,created_at
      final data = await _c.from('alerts').select('id,alert_type,severity,title,message,is_read,created_at').eq('trader_id', tid).eq('is_read', false).order('created_at', ascending: false).limit(50);
      if (mounted) setState(() { _alerts = List<Map<String,dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _dismiss(String id) async {
    await _c.from('alerts').update({'is_read': true}).eq('id', id);
    if (mounted) setState(() => _alerts.removeWhere((a) => a['id'] == id));
  }

  Color _color(String type) => switch(type) {
    'credit_limit' => Colors.red, 'payment_overdue' => Colors.orange,
    'stock_low' => Colors.amber, 'shift_not_closed' => Colors.blue,
    'mismatch' || 'cash_mismatch' => Colors.purple, _ => Colors.grey,
  };
  IconData _icon(String type) => switch(type) {
    'credit_limit' => Icons.credit_card_off_outlined, 'payment_overdue' => Icons.payment_outlined,
    'stock_low' => Icons.inventory_outlined, 'shift_not_closed' => Icons.schedule_outlined,
    _ => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [const Text('Alerts'), if (_alerts.isNotEmpty) ...[const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
            child: Text('${_alerts.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))]]),
      actions: [
        if (_alerts.isNotEmpty) TextButton(onPressed: () async {
          final tid = ref.read(appUserProvider).valueOrNull?.traderId;
          await _c.from('alerts').update({'is_read': true}).eq('trader_id', tid!).eq('is_read', false);
          if (mounted) setState(() => _alerts.clear());
        }, child: const Text('Dismiss All')),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ],
    ),
    body: _loading ? const LoadingList() : _alerts.isEmpty
        ? const EmptyState(icon: Icons.notifications_none_outlined, message: "You're all caught up!", sub: 'No active alerts')
        : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final a = _alerts[i];
              final type = a['alert_type'] as String? ?? 'info';
              final date = DateTime.tryParse(a['created_at'] as String? ?? '');
              final color = _color(type);
              return Dismissible(key: Key(a['id'] as String), direction: DismissDirection.endToStart,
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.check, color: Colors.green)),
                onDismissed: (_) => _dismiss(a['id'] as String),
                child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3), width: 1.2)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(_icon(type), color: color, size: 18)),
                    const SizedBox(width: 12),
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
}
