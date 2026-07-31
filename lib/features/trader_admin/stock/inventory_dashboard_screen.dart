// ─────────────────────────────────────────────────────────────────────────────
// InventoryDashboardScreen — Stock Point Management, Phase 2.
//
// Today-scope only in this phase (see Phase 2 report: full date-range
// dashboard support — Yesterday/Last 7/30/Custom — remains a deferred
// decision; the Reports Hub's Stock Point reports already support
// arbitrary ranges via the existing date bar).
//
// Reads get_stock_point_dashboard_v1 directly (no repository/service layer,
// matching the rest of the app's established pattern of calling Supabase
// RPCs straight from the screen).
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class InventoryDashboardScreen extends ConsumerStatefulWidget {
  const InventoryDashboardScreen({super.key});

  @override
  ConsumerState<InventoryDashboardScreen> createState() => _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends ConsumerState<InventoryDashboardScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _c.rpc('get_stock_point_dashboard_v1', params: {'p_trader_id': tid})
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _data = (res as Map?)?.cast<String, dynamic>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _d(String k) => (_data?[k] as num?)?.toDouble() ?? 0;
  int _i(String k) => (_data?[k] as num?)?.toInt() ?? 0;
  Map<String, dynamic> _m(String k) => (_data?[k] as Map?)?.cast<String, dynamic>() ?? {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text('Inventory Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(icon: const Icon(Icons.menu_book_outlined), tooltip: 'Stock Point Reports',
              onPressed: () => context.push(R.reportsHub)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      ))
          : _data == null
          ? const Center(child: Text('No data'))
          : RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final todaysSales = _m('todays_sales');
    final returnStock = _m('return_stock');
    final pendingCount = _i('pending_cost_product_count');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (pendingCount > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(children: [
              Icon(Icons.hourglass_empty, color: Colors.orange.shade800, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(
                '$pendingCount product${pendingCount == 1 ? '' : 's'} have no confirmed cost yet — valuation shown below is Pending Cost, never assumed to be ₹0.',
                style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
              )),
            ]),
          ),

        // Row 1 — big numbers
        Row(children: [
          Expanded(child: _bigCard('Current Stock', '${_d("current_stock_kg").toStringAsFixed(0)} kg',
              Icons.inventory_2_outlined, kNavy)),
          const SizedBox(width: 10),
          Expanded(child: _bigCard('Bird Count', '${_i("bird_count")}',
              Icons.egg_outlined, kNavy)),
        ]),
        const SizedBox(height: 10),

        // Row 2 — valuation, navy/gold banner style matching Stock Adjustment screen
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00081E), Color(0xFF0A1F44)]),
            borderRadius: BorderRadius.circular(kRadiusCard),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(child: _goldStat('Inventory Value', Fmt.amount(_d('inventory_value')))),
              Expanded(child: _goldStat('Market Value', Fmt.amount(_d('market_value')))),
            ]),
          ]),
        ),
        const SizedBox(height: 10),

        // Row 3 — today's movement
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.1,
          children: [
            _statTile("Today's Sales", '${(todaysSales['kg'] as num?)?.toStringAsFixed(0) ?? 0} kg', Icons.point_of_sale_outlined, Colors.green),
            _statTile('Return Stock', '${(returnStock['kg'] as num?)?.toStringAsFixed(0) ?? 0} kg', Icons.assignment_return_outlined, Colors.teal),
            _statTile('Inventory Loss', Fmt.amount(_d('inventory_loss')), Icons.trending_down_outlined, Colors.red),
            _statTile('Market Loss', Fmt.amount(_d('market_loss')), Icons.storefront_outlined, Colors.deepOrange),
          ],
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statTile('Loss %', '${_d("loss_percent").toStringAsFixed(2)}%',
              Icons.percent_outlined, _d('loss_percent') > 2 ? Colors.red : Colors.green)),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            onTap: () => context.push(R.alerts),
            child: _statTile('Alerts', '${_i("unread_alerts")}', Icons.notifications_outlined,
                _i('unread_alerts') > 0 ? Colors.orange : Colors.grey),
          )),
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.push(R.reportsHub),
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('Daily Closing, History & Loss Analysis reports'),
        ),
      ],
    );
  }

  Widget _bigCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(fontSize: 12, color: kTextSub)),
    ]),
  );

  Widget _goldStat(String label, String value) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFE9C176), fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
  ]);

  Widget _statTile(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight), boxShadow: kCardShadow),
    child: Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
        Text(label, style: TextStyle(fontSize: 10.5, color: kTextSub), overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}