import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/layouts/responsive_layout.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/widgets/web/web.dart';

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
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_crate_summary', params: {'p_trader_id': tid});
      if (!mounted) return;
      if (mounted) setState(() { _summary = res != null ? Map<String,dynamic>.from(res as Map) : {}; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _setInventory() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final ctrl = TextEditingController(text: '${_summary?['total_crates'] ?? 0}');
    final result = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Set Total Crates'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          decoration: const InputDecoration(labelText: 'Total Crates', suffixText: 'crates')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { final v = int.tryParse(ctrl.text); if (v != null && v >= 0) Navigator.pop(ctx, v); }, child: const Text('Set'))],
    ));
    ctrl.dispose();
    if (result == null) return;
    try {
      await _c.rpc('set_crate_inventory', params: {'p_trader_id': tid, 'p_total_crates': result});
      _load();
      if (mounted) showSuccess(context, 'Crate inventory updated ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  Future<void> _adjust(String entityType, String entityId, String entityName) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    final adjCtrl = TextEditingController(); final notesCtrl = TextEditingController();
    final result = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Adjust Crates — $entityName'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: adjCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adjustment (+/-)', helperText: 'Positive = add, Negative = remove')),
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
      _load();
      if (mounted) showSuccess(context, 'Adjusted ✓');
    } catch (e) { if (mounted) showError(context, e.toString()); }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB (desktop) — KPIs, agent and retailer balances side by side.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildWeb() {
    final header = PageBreadcrumbsHeader(
      title: 'Crate Management',
      subtitle: 'Where every crate is — in stock, with agents, with retailers',
      crumbs: const [Crumb('Dashboard', R.dashboard), Crumb('Crates')],
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        WebIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh',
            onTap: _load),
        const SizedBox(width: 8),
        WebButton(label: 'Set Inventory', icon: Icons.settings_outlined,
            outlined: true, onPressed: _setInventory),
      ]),
    );
    if (_loading) {
      return WebPage(header: header, children: const [
        WebCard(child: WebTableState.loading()),
      ]);
    }
    if (_summary == null) {
      return WebPage(header: header, children: const [
        WebCard(child: WebTableState.empty(text: 'No crate data')),
      ]);
    }

    final agents = List<Map<String, dynamic>>.from(
        ((_summary!['agent_balances'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    final retailers = List<Map<String, dynamic>>.from(
        ((_summary!['retailer_balances'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
    final total = (_summary!['total_crates'] as num?)?.toInt() ?? 0;
    final withAgents = (_summary!['with_agents'] as num?)?.toInt() ?? 0;
    final withRetailers = (_summary!['with_retailers'] as num?)?.toInt() ?? 0;

    Widget balanceCard(String title, IconData icon, Color c,
        List<Map<String, dynamic>> rows, String nameKey, String idKey,
        String entity) => WebListCard(children: [
      WebCardHeader(title: title, icon: icon,
          subtitle: '${rows.length} holding crates'),
      WebDataTable<Map<String, dynamic>>(
        columns: const [
          WebColumn('Name', flex: 3),
          WebColumn('Crates', width: 130, align: TextAlign.right),
          WebColumn('Adjust', width: 90, align: TextAlign.center),
        ],
        rows: rows,
        paginate: true,
        rowsPerPage: 10,
        rowsPerPageOptions: const [10, 25, 50],
        dense: true,
        minWidth: 400,
        emptyText: 'None',
        cellBuilder: (r, col) {
          final name = r[nameKey] as String? ?? '—';
          return switch (col) {
            0 => Text(name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5,
                    fontWeight: FontWeight.w600, color: WebColors.text1)),
            1 => Text('${r['balance'] ?? 0} crates', style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: c)),
            _ => WebIconButton(
                icon: Icons.tune_outlined, tooltip: 'Adjust',
                size: 32, outlined: false,
                onTap: () => _adjust(entity, r[idKey] as String, name)),
          };
        },
      ),
    ]);

    return WebPage(header: header, children: [
      WebKpiRow(children: [
        WebKpiCard(label: 'Total Crates', value: '$total',
            icon: Icons.inventory_2_outlined, color: WebColors.navy),
        WebKpiCard(label: 'In Stock',
            value: '${total - withAgents - withRetailers}',
            sub: 'not with agents or retailers',
            icon: Icons.warehouse_outlined, color: WebColors.success),
        WebKpiCard(label: 'With Agents', value: '$withAgents',
            icon: Icons.delivery_dining, color: WebColors.warning),
        WebKpiCard(label: 'With Retailers', value: '$withRetailers',
            icon: Icons.store_outlined, color: const Color(0xFF7C3AED)),
      ]),
      const SizedBox(height: WebSpace.lg),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: balanceCard('With Agents', Icons.delivery_dining,
            WebColors.warning, agents, 'agent_name', 'agent_id', 'agent')),
        const SizedBox(width: WebSpace.lg),
        Expanded(child: balanceCard('With Retailers', Icons.store_outlined,
            const Color(0xFF7C3AED), retailers, 'shop_name', 'retailer_id',
            'retailer')),
      ]),
    ]);
  }

  Widget _buildScaffold(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(backgroundColor: kSurface, title: const Text('Crate Management'), actions: [
      IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _setInventory, tooltip: 'Set inventory'),
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: _loading ? const LoadingList() : _summary == null ? const EmptyState(icon: Icons.inventory_2_outlined, message: 'No crate data')
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavClearance), children: [
      GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.2, children: [
            KpiCard('Total', '${_summary!['total_crates'] ?? 0}', Icons.inventory_2_outlined, kPrimary),
            KpiCard('With Agents', '${_summary!['with_agents'] ?? 0}', Icons.delivery_dining, Colors.orange),
            KpiCard('With Retailers', '${_summary!['with_retailers'] ?? 0}', Icons.store_outlined, Colors.purple),
          ]),
      const SizedBox(height: 14),
      if ((_summary!['agent_balances'] as List?)?.isNotEmpty == true) ...[
        const SectionHeader('WITH AGENTS'),
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
        const SectionHeader('WITH RETAILERS'),
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
  @override
  Widget build(BuildContext context) => ResponsiveLayout(
    mobile:  (_) => _buildScaffold(context),
    desktop: (_) => _buildWeb(),
  );

}