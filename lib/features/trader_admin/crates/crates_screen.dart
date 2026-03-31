import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class CratesScreen extends ConsumerStatefulWidget {
  const CratesScreen({super.key});
  @override ConsumerState<CratesScreen> createState() => _S();
}
class _S extends ConsumerState<CratesScreen> {
  final _c = Supabase.instance.client;
  Map<String,dynamic>? _summary;
  bool _loading = true;
  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_crate_summary', params: {'p_trader_id': tid});
      if (mounted) setState(() { _summary = res != null ? Map<String,dynamic>.from(res as Map) : {}; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _setInventory() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final ctrl = TextEditingController(text: '${_summary?['total_crates'] ?? 0}');
    final result = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Set Total Crates'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Total Crates', suffixText: 'crates')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { final v = int.tryParse(ctrl.text); if (v != null && v >= 0) Navigator.pop(ctx, v); }, child: const Text('Set'))],
    ));
    ctrl.dispose();
    if (result == null) return;
    try {
      await _c.rpc('set_crate_inventory', params: {'p_trader_id': tid, 'p_total_crates': result});
      _load(); if (mounted) showSuccess(context, 'Inventory set ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _adjust(String entityType, String entityId, String entityName) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final adjCtrl = TextEditingController(); final notesCtrl = TextEditingController();
    final result = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Adjust: $entityName'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: adjCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adjustment (+ add / - remove)')),
        const SizedBox(height: 8),
        TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { final v = int.tryParse(adjCtrl.text); if (v != null) Navigator.pop(ctx, v); }, child: const Text('Adjust'))],
    ));
    final notes = notesCtrl.text.trim();
    adjCtrl.dispose(); notesCtrl.dispose();
    if (result == null) return;
    try {
      await _c.rpc('adjust_crate_balance', params: {'p_trader_id': tid, 'p_entity_type': entityType, 'p_entity_id': entityId, 'p_adjustment': result, 'p_notes': notes.isEmpty ? null : notes, 'p_adjusted_by': uid});
      _load(); if (mounted) showSuccess(context, 'Adjusted ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crate Management'), actions: [
      IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _setInventory, tooltip: 'Set Total Inventory'),
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: _loading ? const LoadingList() : _summary == null ? const EmptyState(icon: Icons.inventory_2_outlined, message: 'No crate data')
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
            GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.2,
              children: [
                KpiCard('Total', '${_summary!['total_crates'] ?? 0}', Icons.inventory_2_outlined, kPrimary),
                KpiCard('With Agents', '${_summary!['with_agents'] ?? 0}', Icons.delivery_dining, Colors.orange),
                KpiCard('With Retailers', '${_summary!['with_retailers'] ?? 0}', Icons.store_outlined, Colors.purple),
              ]),
            const SizedBox(height: 16),
            if ((_summary!['agent_balances'] as List?)?.isNotEmpty == true) ...[
              const SectionHeader('CRATES WITH AGENTS'),
              ...(_summary!['agent_balances'] as List).map((b) {
                final row = b as Map<String,dynamic>;
                return Container(margin: const EdgeInsets.only(bottom: 8), child: WhiteCard(padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(row['agent_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Text('${row['balance'] ?? 0} crates', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.orange)),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.tune_outlined, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                        onPressed: () => _adjust('agent', row['agent_id'] as String, row['agent_name'] as String)),
                  ])));
              }),
            ],
            if ((_summary!['retailer_balances'] as List?)?.isNotEmpty == true) ...[
              const SectionHeader('CRATES WITH RETAILERS'),
              ...(_summary!['retailer_balances'] as List).map((b) {
                final row = b as Map<String,dynamic>;
                return Container(margin: const EdgeInsets.only(bottom: 8), child: WhiteCard(padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(row['shop_name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Text('${row['balance'] ?? 0} crates', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.purple)),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.tune_outlined, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                        onPressed: () => _adjust('retailer', row['retailer_id'] as String, row['shop_name'] as String)),
                  ])));
              }),
            ],
          ])),
  );
}
