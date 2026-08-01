// ─────────────────────────────────────────────────────────────────────────────
// InventoryDashboardScreen — Stock Point Management.
//
// Built as an operational control panel, not a KPI card grid: the trader
// should read today's Stock Point condition top-to-bottom in one glance,
// in the fixed hierarchy below (approved order — do not reorder without
// re-confirming, since this order is deliberate: flow first because it
// explains *why* today's stock is what it is, alerts near the end because
// they're the "anything need my attention" check after the numbers already
// make sense).
//
//   1. Today's Stock Flow   (Opening + Return − Loaded − Shrinkage −
//                             Mortality ± Manual = Current)
//   2. Stock Point Status   (Birds, Weight, Purchase Value, Today's Market
//                             Value, Average Cost, Today's Market Rate)
//   3. Today's Loss         (Shrinkage / Mortality / Theft, Inventory Loss,
//                             Market Loss, Loss %)
//   4. Alerts               (only actionable Stock Point conditions —
//                             Pending Purchase Cost, High Shrinkage,
//                             Negative Stock, Stock Verification Pending)
//   5. Quick Actions         (Inventory Ledger / Daily Closing / Return
//                             Stock Ledger / Loss Analysis / Print)
//
// Today-scope only (no date range on this screen — see Phase 2 report for
// the deferred date-range dashboard decision). No backend logic changes —
// this file only reads get_stock_point_dashboard_v1 and renders it.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../reports/reports_hub_screen.dart';

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

  // ★ Product selection — one chip per active product, no "All Products"
  // option (per requirement). Defaults to Broiler by name if present,
  // otherwise the first active product alphabetically.
  List<Map<String, dynamic>> _products = [];
  String? _selectedProductId;
  bool _loadingProducts = true;

  @override
  void initState() {
    super.initState();
    _loadProductsThenDashboard();
  }

  Future<void> _loadProductsThenDashboard() async {
    try {
      // ★ FIX: master_products also stores product VARIANTS as full rows
      // (e.g. "Broiler Big/Medium/Small" nested under "Broiler" via
      // parent_product_id). Only top-level products belong on this chip
      // selector — variants were showing up as extra chips before,
      // pushing Broiler out of view. parent_product_id IS NULL is the
      // exact same top-level filter already used elsewhere in the app.
      final res = await _c.from('master_products')
          .select('id,name')
          .eq('is_active', true)
          .filter('parent_product_id', 'is', null)
          .order('name')
          .timeout(const Duration(seconds: 15));
      final products = List<Map<String, dynamic>>.from(res as List? ?? []);
      // ★ FIX: Broiler must always appear first if enabled — sort
      // explicitly rather than relying on alphabetical luck.
      products.sort((a, b) {
        final an = (a['name'] as String? ?? '').toLowerCase();
        final bn = (b['name'] as String? ?? '').toLowerCase();
        if (an == 'broiler') return -1;
        if (bn == 'broiler') return 1;
        return an.compareTo(bn);
      });
      if (!mounted) return;
      final defaultId = products.isNotEmpty ? products.first['id'] as String? : null;
      setState(() {
        _products = products;
        _selectedProductId = defaultId;
        _loadingProducts = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadingProducts = false; _error = e.toString().replaceAll('Exception:', '').trim(); });
    }
    await _load();
  }

  void _selectProduct(String productId) {
    if (productId == _selectedProductId) return;
    setState(() => _selectedProductId = productId);
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || _selectedProductId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _c.rpc('get_stock_point_dashboard_v1', params: {
        'p_trader_id': tid,
        'p_product_id': _selectedProductId,
      }).timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _data = (res as Map?)?.cast<String, dynamic>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _d(String k) => (_data?[k] as num?)?.toDouble() ?? 0;
  int _i(String k) => (_data?[k] as num?)?.toInt() ?? 0;
  double? _dn(String k) => (_data?[k] as num?)?.toDouble();
  Map<String, dynamic> _m(String k) => (_data?[k] as Map?)?.cast<String, dynamic>() ?? {};
  bool _b(String k) => _data?[k] == true;

  void _openReport(String key) {
    // Matches report_home_screen.dart's exact navigation call (the "Reports"
    // screen's own category list) — showChipPicker:false gives the focused
    // single-report view, not the older full chip-picker/browse mode.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReportsHubScreen(
        initialReportKey: key,
        showChipPicker: false,
        initialProductId: _selectedProductId,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text('Inventory Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      // ★ Scroll fix: this shell's TraderShell Scaffold uses extendBody:true
      // (the glass bottom nav floats over content by design), so every
      // screen must reserve its own clearance — matching the exact
      // established pattern already used in stock_screen.dart, not a new
      // padding value invented for this screen.
      bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
      body: Column(children: [
        _productChipSelector(),
        Expanded(
          child: _loading || _loadingProducts
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
              : (_data == null || _selectedProductId == null)
              ? const Center(child: Text('No active products found'))
              : RefreshIndicator(onRefresh: _load, child: _buildBody()),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT SELECTION — one chip per active product, no "All Products".
  // Selecting a chip refreshes the entire dashboard for that product only.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _productChipSelector() {
    if (_loadingProducts) {
      return const SizedBox(height: 52, child: Center(child: SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_products.isEmpty) return const SizedBox.shrink();
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = _products[i];
            final id = p['id'] as String;
            final name = p['name'] as String? ?? '—';
            final selected = id == _selectedProductId;
            return ChoiceChip(
              label: Text(name, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : kTextMain)),
              selected: selected,
              onSelected: (_) => _selectProduct(id),
              selectedColor: kNavy,
              backgroundColor: kBgGrey,
              showCheckmark: false,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    final selectedName = _products.firstWhere(
          (p) => p['id'] == _selectedProductId, orElse: () => const {},
    )['name'] as String? ?? '';

    return ListView(
      // ★ Scroll fix: kBottomNavClearance (the same constant, same value,
      // already used in stock_screen.dart) instead of a plain 20px bottom
      // pad — this is what actually keeps Quick Actions fully visible
      // above the floating glass nav bar on every screen size.
      padding: const EdgeInsets.fromLTRB(12, 8, 12, kBottomNavClearance),
      children: [
        if (selectedName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: kTextHint),
              const SizedBox(width: 6),
              Text('Showing: $selectedName', style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kTextSub)),
            ]),
          ),
        _sectionLabel('TODAY\'S STOCK FLOW'),
        _stockFlowCard(),
        const SizedBox(height: 14),

        _sectionLabel('STOCK POINT STATUS'),
        _stockPointStatusCard(),
        const SizedBox(height: 14),

        _sectionLabel('TODAY\'S LOSS'),
        _todaysLossCard(),
        const SizedBox(height: 14),

        _sectionLabel('ALERTS'),
        _alertsCard(),
        const SizedBox(height: 14),

        _sectionLabel('QUICK ACTIONS'),
        _quickActionsRow(),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(text, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight),
      boxShadow: kCardShadow,
    ),
    child: child,
  );

  // ═══════════════════════════════════════════════════════════════════════
  // 1. TODAY'S STOCK FLOW — a single-glance equation, not separate cards.
  // Maps to: opening_stock.kg, return_stock.kg, loaded.kg, shrinkage_kg,
  // mortality.kg, manual_adjustment_kg, current_stock_kg (all from
  // get_stock_point_dashboard_v1, unchanged backend).
  // ═══════════════════════════════════════════════════════════════════════
  Widget _stockFlowCard() {
    final opening = (_m('opening_stock')['kg'] as num?)?.toDouble() ?? 0;
    final returnKg = (_m('return_stock')['kg'] as num?)?.toDouble() ?? 0;
    final loadedKg = (_m('loaded')['kg'] as num?)?.toDouble() ?? 0;
    final shrinkageKg = _d('shrinkage_kg');
    final mortalityKg = (_m('mortality')['kg'] as num?)?.toDouble() ?? 0;
    final manualKg = _d('manual_adjustment_kg');
    final currentKg = _d('current_stock_kg');

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 6, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _flowChip('Opening', '${opening.toStringAsFixed(0)} kg', kBgGrey, kTextMain),
          _flowArrow(),
          _flowChip('Return', '+${returnKg.toStringAsFixed(0)} kg', const Color(0xFFE0F5F0), const Color(0xFF00695C)),
          _flowArrow(),
          _flowChip('Loaded', '−${loadedKg.toStringAsFixed(0)} kg', const Color(0xFFFFF0E0), const Color(0xFFB25E00)),
          _flowArrow(),
          _flowChip('Shrinkage', '−${shrinkageKg.toStringAsFixed(1)} kg', const Color(0xFFF3E5F5), const Color(0xFF6A1B9A)),
          _flowArrow(),
          _flowChip('Mortality', '−${mortalityKg.toStringAsFixed(1)} kg', const Color(0xFFFDE7E7), const Color(0xFFC62828)),
          _flowArrow(),
          _flowChip('Manual', '${manualKg >= 0 ? '+' : ''}${manualKg.toStringAsFixed(1)} kg', const Color(0xFFE3EAFD), const Color(0xFF1A4FBF)),
          _flowArrow(),
          _flowChip('Current', '${currentKg.toStringAsFixed(1)} kg', kNavy, Colors.white, bold: true),
        ],
      ),
    ]));
  }

  Widget _flowChip(String label, String value, Color bg, Color fg, {bool bold = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
          color: fg.withValues(alpha: bold ? 0.75 : 0.7))),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w800, color: fg)),
    ]),
  );

  Widget _flowArrow() => Icon(Icons.chevron_right, size: 16, color: kTextHint.withValues(alpha: 0.6));

  // ═══════════════════════════════════════════════════════════════════════
  // 2. STOCK POINT STATUS — business-friendly labels ("Purchase Value",
  // "Today's Market Value"), Average Cost / Today's Market Rate as small
  // per-kg context under the totals, not their own cards.
  // Maps to: bird_count, current_stock_kg, inventory_value, market_value,
  // avg_cost_per_kg, market_rate_per_kg.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _stockPointStatusCard() {
    final avgCost = _dn('avg_cost_per_kg');
    final marketRate = _dn('market_rate_per_kg');
    final currentKg = _d('current_stock_kg');
    // ★ FIX: Purchase Value is now always DERIVED as current_stock_kg ×
    // avg_cost_per_kg on the client, rather than trusting a separately
    // transmitted total — this guarantees the "Purchase Value = Current
    // Stock KG × Average Cost" identity holds by construction, not by
    // coincidence, even if the backend's own field were ever to drift.
    final purchaseValue = avgCost == null ? null : currentKg * avgCost;
    final basisLabel = switch (_data?['avg_cost_basis']) {
      'traced_purchase_entry' => 'Traced Purchase Cost',
      'existing_average_cost' || 'rollout_seed_average_cost' => 'Existing Average Cost',
      'current_mwac' => 'MWAC',
      _ => null,
    };
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _statBlock('Current Birds', '${_i("bird_count")}', kTextMain)),
        Container(width: 1, height: 34, color: kBorderLight),
        Expanded(child: _statBlock('Current Weight', '${currentKg.toStringAsFixed(1)} kg', kTextMain)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kNavy, kNavyMid]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(child: _goldStat('Purchase Value',
              purchaseValue == null ? 'Pending Cost' : Fmt.amount(purchaseValue))),
          Container(width: 1, height: 32, color: Colors.white24),
          Expanded(child: _goldStat("Today's Market Value", Fmt.amount(_d('market_value')))),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.calculate_outlined, size: 14, color: kTextHint),
        const SizedBox(width: 6),
        Expanded(child: Text(
          avgCost == null
              ? 'Average Cost: Pending'
              : 'Average Cost: ₹${avgCost.toStringAsFixed(2)}/kg',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: avgCost == null ? Colors.orange.shade800 : kTextSub),
        )),
        Expanded(child: Text(
          marketRate == null
              ? "Today's Market Rate: —"
              : "Today's Market Rate: ₹${marketRate.toStringAsFixed(2)}/kg",
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextSub),
        )),
      ]),
      if (basisLabel != null) ...[
        const SizedBox(height: 4),
        Text('Source: $basisLabel', style: TextStyle(fontSize: 10.5, color: kTextHint.withValues(alpha: 0.9))),
      ],
    ]));
  }

  Widget _statBlock(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: const TextStyle(fontSize: 11.5, color: kTextSub)),
    ],
  );

  Widget _goldStat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11.5, color: kGoldLight, fontWeight: FontWeight.w600)),
    const SizedBox(height: 3),
    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
  ]);

  // ═══════════════════════════════════════════════════════════════════════
  // 3. TODAY'S LOSS — Shrinkage/Mortality/Theft as small inline figures,
  // Inventory Loss / Market Loss / Loss % as the primary (red) figures.
  // Maps to: shrinkage_kg, mortality.kg, theft_kg, inventory_loss,
  // market_loss, loss_percent.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _todaysLossCard() {
    final lossPct = _d('loss_percent');
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _lossMini('Shrinkage', '${_d("shrinkage_kg").toStringAsFixed(1)} kg')),
        Expanded(child: _lossMini('Mortality', '${(_m("mortality")["kg"] as num?)?.toStringAsFixed(1) ?? "0.0"} kg')),
        Expanded(child: _lossMini('Theft', '${_d("theft_kg").toStringAsFixed(1)} kg')),
      ]),
      const Divider(height: 20),
      Row(children: [
        Expanded(child: _statBlock('Inventory Loss', Fmt.amount(_d('inventory_loss')), Colors.red.shade700)),
        Expanded(child: _statBlock('Market Loss', Fmt.amount(_d('market_loss')), Colors.deepOrange.shade700)),
        Expanded(child: _statBlock('Loss %', '${lossPct.toStringAsFixed(2)}%',
            lossPct > 2 ? Colors.red.shade700 : kTextMain)),
      ]),
    ]));
  }

  Widget _lossMini(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(fontSize: 10.5, color: kTextSub)),
  ]);

  // ═══════════════════════════════════════════════════════════════════════
  // 4. ALERTS — only actionable Stock Point conditions. Return Stock
  // Pending was explicitly removed (operational/shift concept, not a
  // Stock Point KPI). Every threshold is read from the backend's own
  // configured-or-null fields — nothing here is a hardcoded assumption;
  // an alert that depends on an unconfigured threshold (high_shrinkage,
  // physical_verification_required) simply won't fire, exactly matching
  // the backend's null-safe design.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _alertsCard() {
    final alerts = <(IconData, Color, String)>[];

    final pendingCostCount = _i('pending_cost_product_count');
    if (pendingCostCount > 0) {
      alerts.add((Icons.hourglass_empty, Colors.orange,
      'Pending Purchase Cost — $pendingCostCount product${pendingCostCount == 1 ? '' : 's'} awaiting confirmed cost'));
    }
    if (_b('high_shrinkage')) {
      final t = _dn('shrinkage_alert_threshold_pct');
      alerts.add((Icons.trending_down, Colors.deepOrange,
      'High Shrinkage — today\'s shrinkage is above your ${t?.toStringAsFixed(1) ?? '—'}% threshold'));
    }
    if (_b('negative_stock_detected')) {
      alerts.add((Icons.error_outline, Colors.red,
      'Negative Stock detected — recorded outflows exceed inflows for a product. Needs review.'));
    }
    if (_data?['physical_verification_required'] == true) {
      final lastDate = _data?['last_physical_verification_date'] as String?;
      alerts.add((Icons.fact_check_outlined, Colors.orange,
      lastDate == null
          ? 'Stock Verification Pending — no physical count on record yet'
          : 'Stock Verification Pending — last verified $lastDate'));
    }

    if (alerts.isEmpty) {
      return _card(child: Row(children: const [
        Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
        SizedBox(width: 8),
        Text('All clear — nothing needs attention right now.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextMain)),
      ]));
    }

    return _card(child: Column(
      children: alerts.map((a) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(a.$1, color: a.$2, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(a.$3, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: a.$2))),
        ]),
      )).toList(),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. QUICK ACTIONS — deep-links directly into the existing Reports Hub
  // (ReportsHubScreen already accepts initialReportKey — reused as-is, no
  // new navigation/printing engine). "Print" opens Daily Closing Report,
  // where the existing Print/PDF button in the report toolbar is already
  // one tap away — this dashboard does not generate PDFs itself, to avoid
  // duplicating the report_pdf_generator.dart logic that already lives in
  // reports_hub_screen.dart.
  // ═══════════════════════════════════════════════════════════════════════
  Widget _quickActionsRow() {
    final actions = [
      (Icons.menu_book_outlined, 'Ledger', 'inventory_ledger'),
      (Icons.today_outlined, 'Daily Closing', 'daily_closing_report'),
      (Icons.assignment_return_outlined, 'Return Ledger', 'return_stock_ledger'),
      (Icons.trending_down_outlined, 'Loss Analysis', 'loss_analysis'),
      (Icons.print_outlined, 'Print', 'daily_closing_report'),
    ];
    // ★ FIX: was 78px with a 2-line label at 10.5px — overflowed by ~2px on
    // longer labels ("Return Ledger", "Loss Analysis") on some devices.
    // 92px + smaller icon/text gives consistent headroom for any 2-word
    // label wrapping to 2 lines, on any common Android screen density.
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = actions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(kRadiusCard),
            onTap: () => _openReport(a.$3),
            child: Container(
              width: 86,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: kBorderLight),
                boxShadow: kCardShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.$1, size: 18, color: const Color(0xFF8D6E00)),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(a.$2, textAlign: TextAlign.center,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextMain, height: 1.15)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}