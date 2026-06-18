import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PRICING MANAGEMENT HUB — Phase 2 (Daily Rate UI removed)
// Tabs: Zone Rates · Customer Rates · Products · Zones · Assign
// Rate Cascade: Customer Rate → Zone Rate (Zone Rate is now the sole
// trader-facing base mechanism; the old Default/Daily Rate fallback still
// exists server-side in get_effective_rate_v4 as a silent safety net only —
// it is never shown or editable from this screen anymore).
// ═══════════════════════════════════════════════════════════════════════════════

class PricingHubScreen extends ConsumerStatefulWidget {
  const PricingHubScreen({super.key});

  @override
  ConsumerState<PricingHubScreen> createState() => _PricingHubScreenState();
}

class _PricingHubScreenState extends ConsumerState<PricingHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBgPage,
    appBar: AppBar(
      backgroundColor: kSurface,
      title: const Text('Pricing Management'),
      actions: [
        IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Zone Rate History',
            onPressed: () => context.push(R.zoneRateHistory)),
      ],
      bottom: TabBar(
        controller: _tab,
        labelColor: kNavy,
        unselectedLabelColor: kTextHint,
        indicatorColor: kGold,
        indicatorWeight: 3,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelStyle:
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Zone Rates'),
          Tab(text: 'Customer Rates'),
          Tab(text: 'Products'),
          Tab(text: 'Zones'),
          Tab(text: 'Assign'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tab,
      children: [
        _ZoneRatesTab(onGoToZones: () => _tab.animateTo(3)),
        const _CustomerRatesTab(),
        const _ProductsTab(),
        const _ZonesTab(),
        const _ZoneAssignTab(),
      ],
    ),
  );
}


// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

Widget _sectionHeader(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8, top: 4),
  child: Row(children: [
    Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: kNavy,
            letterSpacing: 0.3)),
    const SizedBox(width: 8),
    Expanded(child: Container(height: 1, color: kBorderLight)),
  ]),
);

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: ZONE RATES
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneRatesTab extends ConsumerStatefulWidget {
  const _ZoneRatesTab({required this.onGoToZones});

  final VoidCallback onGoToZones;

  @override
  ConsumerState<_ZoneRatesTab> createState() => _ZoneRatesTabState();
}

class _ZoneRatesTabState extends ConsumerState<_ZoneRatesTab> {
  final _c = Supabase.instance.client;
  Map<String, dynamic> _dash = {};
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  String? _selZoneId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _c.rpc('get_pricing_dashboard', params: {'p_trader_id': tid}),
        _c.rpc('get_zones',
            params: {'p_trader_id': tid, 'p_active_only': true}),
      ]);
      if (!mounted) return;
      final zones = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      setState(() {
        _dash = Map<String, dynamic>.from(results[0] as Map? ?? {});
        _zones = zones;
        _selZoneId ??= zones.isNotEmpty ? zones.first['id'] as String? : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setZoneRate(Map<String, dynamic> zone,
      Map<String, dynamic> product, double? currentRate) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final rateCtrl =
    TextEditingController(text: currentRate?.toStringAsFixed(2) ?? '');
    DateTime selectedDate = DateTime.now();

    final result = await showModalBottomSheet<double>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(
                      'Zone Rate — ${zone['zone_name']} · ${product['product_name']}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kNavy)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final p = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate:
                          DateTime.now().add(const Duration(days: 30)));
                      if (p != null) ss(() => selectedDate = p);
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                            color: kNavy.withValues(alpha: 0.05),
                            borderRadius:
                            BorderRadius.circular(kRadiusInner),
                            border: Border.all(
                                color: kNavy.withValues(alpha: 0.2))),
                        child: Row(children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 18, color: kNavy),
                          const SizedBox(width: 10),
                          Text(
                              'Effective: ${DateFormat('d MMM y').format(selectedDate)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: kNavy)),
                          const Spacer(),
                          const Text('Tap to change',
                              style: TextStyle(
                                  fontSize: 11, color: kTextHint)),
                        ])),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rateCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kNavy),
                    decoration: InputDecoration(
                        labelText: 'Rate for ${zone['zone_name']} (₹/kg)',
                        prefixText: '₹ ',
                        suffixText: '/kg'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    onPressed: () {
                      final v = double.tryParse(rateCtrl.text.trim());
                      if (v != null && v > 0)
                        Navigator.of(ctx, rootNavigator: true).pop(v);
                    },
                    child: Text(currentRate == null
                        ? 'Set Zone Rate'
                        : 'Update Zone Rate'),
                  ),
                ]),
          )),
    );
    rateCtrl.dispose();
    if (result == null || !mounted) return;
    try {
      await _c.rpc('set_zone_rate', params: {
        'p_trader_id': tid,
        'p_zone_id': zone['id'],
        'p_product_id': product['product_id'],
        'p_rate_per_kg': result,
        'p_effective_date': DateFormat('yyyy-MM-dd').format(selectedDate),
      });
      if (mounted) {
        showSuccess(context,
            '${zone['zone_name']} · ${product['product_name']} → ${Fmt.amount(result)}/kg ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingList();
    if (_zones.isEmpty) {
      return EmptyState(
        icon: Icons.map_outlined,
        message: 'No Zones Created',
        sub:
        'Create zones in the Zones tab, then come back to set rates per zone.',
        actionLabel: 'Go to Zones',
        onAction: widget.onGoToZones,
      );
    }

    // get_pricing_dashboard's 'default_rates' key is just the product
    // catalogue (every active product), with optional daily-rate fields
    // attached that we no longer read here — Zone Rate is the only
    // trader-facing rate. Kept as-is to avoid touching the RPC contract.
    final products =
    List<Map<String, dynamic>>.from(_dash['default_rates'] as List? ?? []);
    final zoneRatesRaw =
    List<Map<String, dynamic>>.from(_dash['zone_rates'] as List? ?? []);
    final rateMap = <String, Map<String, dynamic>>{};
    for (final zr in zoneRatesRaw) {
      rateMap['${zr['zone_id']}__${zr['product_id']}'] = zr;
    }

    final selZone = _zones.firstWhere(
          (z) => z['id'] == _selZoneId,
      orElse: () => _zones.first,
    );

    return Column(children: [
      // Zone selector
      Container(
        color: kSurface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: _zones.map((z) {
              final isSel = z['id'] == _selZoneId;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selZoneId = z['id'] as String?),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        gradient: isSel
                            ? const LinearGradient(colors: [kNavy, kNavyMid])
                            : null,
                        color: isSel ? null : kBgGrey,
                        borderRadius: BorderRadius.circular(kRadiusChip),
                        border:
                        Border.all(color: isSel ? kNavyMid : kBorderLight)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text((z['zone_code'] as String? ?? '?').substring(0, 3),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: isSel ? kGoldLight : kTextHint,
                              letterSpacing: 0.5)),
                      const SizedBox(width: 6),
                      Text(z['zone_name'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isSel ? Colors.white : kNavy)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const Divider(height: 1),

      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          color: kNavy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Zone banner
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [kNavy, kNavyMid],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(kRadiusInner)),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined,
                      color: kGoldLight, size: 18),
                  const SizedBox(width: 8),
                  Text('${selZone['zone_name']} (${selZone['zone_code']})',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const Spacer(),
                  Text('${selZone['retailer_count'] ?? 0} retailers',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFB4C6F4))),
                ]),
              ),

              Container(
                decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight),
                    boxShadow: kCardShadow),
                child: Column(
                    children: products.asMap().entries.map((e) {
                      final i = e.key;
                      final p = e.value;
                      final key = '${selZone['id']}__${p['product_id']}';
                      final zr = rateMap[key];
                      final zoneRate = (zr?['rate_per_kg'] as num?)?.toDouble();
                      final zoneEffDate = zr?['effective_date'] as String?;
                      final isLast = i == products.length - 1;

                      return Container(
                        decoration: isLast
                            ? null
                            : const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: kBorderLight))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                          title: Text(p['product_name'] as String? ?? '—',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: kNavy)),
                          subtitle: zoneEffDate != null
                              ? Text(
                              'As of ${DateFormat('d MMM y').format(DateTime.parse(zoneEffDate))}',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextHint))
                              : null,
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (zoneRate != null)
                              Text('${Fmt.amount(zoneRate)}/kg',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: kNavy))
                            else
                              TextButton(
                                  onPressed: () =>
                                      _setZoneRate(selZone, p, zoneRate),
                                  child: const Text('No rate set — Set Rate',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w800))),
                            IconButton(
                              icon: Icon(
                                  zoneRate != null
                                      ? Icons.edit_outlined
                                      : Icons.add_circle_outline,
                                  size: 18,
                                  color: zoneRate != null ? kTextSub : kNavy),
                              onPressed: () => _setZoneRate(selZone, p, zoneRate),
                            ),
                          ]),
                        ),
                      );
                    }).toList()),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: CUSTOMER SPECIAL RATES
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerRatesTab extends ConsumerStatefulWidget {
  const _CustomerRatesTab();

  @override
  ConsumerState<_CustomerRatesTab> createState() => _CustomerRatesTabState();
}

// Pricing type definitions — UI display metadata
class _PricingTypeDef {
  const _PricingTypeDef(this.type, this.label, this.icon, this.color,
      this.inputLabel, this.hint, this.needsRate, this.needsAdjustment);

  final String type;
  final String label;
  final IconData icon;
  final Color color;
  final String inputLabel;
  final String hint;
  final bool needsRate; // needs rate_per_kg field
  final bool needsAdjustment; // needs adjustment_value field
}

const _kPricingTypes = [
  _PricingTypeDef('fixed', 'Fixed Rate', Icons.push_pin_outlined,
      Color(0xFF0369A1), 'Final Rate (₹/kg)', 'e.g. 138', true, false),
  _PricingTypeDef('contract', 'Contract Rate', Icons.assignment_outlined,
      Color(0xFF7C3AED), 'Contract Rate (₹/kg)', 'e.g. 136', true, false),
  _PricingTypeDef('flat_discount', 'Flat Discount', Icons.remove_circle_outline,
      Color(0xFF059669), 'Discount Amount (₹)', 'e.g. 2', false, true),
  _PricingTypeDef('flat_premium', 'Flat Premium', Icons.add_circle_outline,
      Color(0xFFB45309), 'Premium Amount (₹)', 'e.g. 3', false, true),
  _PricingTypeDef('pct_discount', 'Percentage Discount', Icons.percent_outlined,
      Color(0xFF0D9488), 'Discount (%)', 'e.g. 1.5', false, true),
  _PricingTypeDef(
      'pct_premium',
      'Percentage Premium',
      Icons.trending_up_outlined,
      Color(0xFFDC6803),
      'Premium (%)',
      'e.g. 2',
      false,
      true),
];

_PricingTypeDef _pricingTypeDef(String? type) => _kPricingTypes
    .firstWhere((t) => t.type == type, orElse: () => _kPricingTypes[0]);

class _CustomerRatesTabState extends ConsumerState<_CustomerRatesTab> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _c.rpc('get_pricing_dashboard', params: {'p_trader_id': tid}),
        _c
            .from('retailers')
            .select('id, shop_name')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c.rpc('get_product_catalogue'),
      ]);
      if (!mounted) return;
      final dash = Map<String, dynamic>.from(results[0] as Map? ?? {});
      setState(() {
        _rates = List<Map<String, dynamic>>.from(
            dash['customer_rates'] as List? ?? []);
        _retailers = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRate() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;

    Map<String, dynamic>? selR, selP;
    _PricingTypeDef selType = _kPricingTypes[0]; // default: fixed
    final rateCtrl = TextEditingController();
    final adjCtrl = TextEditingController();
    DateTime effDate = DateTime.now();
    DateTime? expDate;

    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            builder: (_, scroll) => Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20))),
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: ListView(controller: scroll, children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('Customer Pricing',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: kNavy)),
                const SizedBox(height: 4),
                const Text(
                    'Priority 1 — always wins over the zone rate',
                    style: TextStyle(fontSize: 12, color: kTextSub)),
                const SizedBox(height: 20),

                // ── Pricing type selector ──────────────────────────────────────
                const Text('PRICING TYPE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: kTextHint,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kPricingTypes.map((t) {
                    final isSel = selType.type == t.type;
                    return GestureDetector(
                      onTap: () {
                        ss(() {
                          selType = t;
                          rateCtrl.clear();
                          adjCtrl.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: isSel
                                ? t.color.withValues(alpha: 0.12)
                                : kBgGrey,
                            borderRadius:
                            BorderRadius.circular(kRadiusChip),
                            border: Border.all(
                                color: isSel
                                    ? t.color.withValues(alpha: 0.4)
                                    : kBorderLight,
                                width: isSel ? 1.5 : 0.5)),
                        child:
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.icon,
                              size: 14, color: isSel ? t.color : kTextHint),
                          const SizedBox(width: 6),
                          Text(t.label,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSel ? t.color : kTextHint)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                // Contextual helper
                _PricingTypeHelper(type: selType),
                const SizedBox(height: 16),

                // ── Customer + Product dropdowns ───────────────────────────────
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selR,
                  hint: const Text('Select Customer *'),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.store_outlined, size: 18)),
                  isExpanded: true,
                  items: _retailers
                      .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(r['shop_name'] as String? ?? '—',
                        overflow: TextOverflow.ellipsis),
                  ))
                      .toList(),
                  onChanged: (v) => ss(() => selR = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selP,
                  hint: const Text('Select Product *'),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.egg_alt_outlined, size: 18)),
                  isExpanded: true,
                  items: _products
                      .map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p['name'] as String? ?? '—'),
                  ))
                      .toList(),
                  onChanged: (v) => ss(() => selP = v),
                ),
                const SizedBox(height: 10),

                // ── Rate / adjustment input ────────────────────────────────────
                if (selType.needsRate)
                  TextFormField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kNavy),
                    decoration: InputDecoration(
                      labelText: selType.inputLabel,
                      prefixText: '₹ ',
                      suffixText: '/kg',
                      hintText: selType.hint,
                      helperText: selType.type == 'contract'
                          ? 'Set expiry date below for contract validity period'
                          : 'This is the final rate charged to this customer',
                    ),
                  ),
                if (selType.needsAdjustment)
                  TextFormField(
                    controller: adjCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kNavy),
                    decoration: InputDecoration(
                      labelText: selType.inputLabel,
                      prefixIcon: Icon(selType.icon,
                          size: 18, color: selType.color),
                      suffixText:
                      selType.type.startsWith('pct') ? '%' : '₹',
                      hintText: selType.hint,
                      helperText:
                      'Applied to the zone rate at order time',
                    ),
                  ),

                // ── Dates ─────────────────────────────────────────────────────
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final p = await showDatePicker(
                              context: ctx,
                              initialDate: effDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 1)),
                              lastDate:
                              DateTime.now().add(const Duration(days: 30)));
                          if (p != null) ss(() => effDate = p);
                        },
                        child: _dateTile('Effective From', effDate),
                      )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final p = await showDatePicker(
                              context: ctx,
                              initialDate: expDate ??
                                  effDate.add(const Duration(days: 30)),
                              firstDate: effDate,
                              lastDate: effDate.add(const Duration(days: 365)));
                          ss(() => expDate = p);
                        },
                        child: _dateTile('Expires On', expDate, optional: true),
                      )),
                ]),
                const SizedBox(height: 20),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: selType.color),
                  onPressed: () async {
                    if (selR == null || selP == null) {
                      showError(ctx, 'Select customer and product');
                      return;
                    }
                    double? rateVal, adjVal;
                    if (selType.needsRate) {
                      rateVal = double.tryParse(rateCtrl.text.trim());
                      if (rateVal == null || rateVal <= 0) {
                        showError(ctx, 'Enter a valid rate');
                        return;
                      }
                    }
                    if (selType.needsAdjustment) {
                      adjVal = double.tryParse(adjCtrl.text.trim());
                      if (adjVal == null || adjVal <= 0) {
                        showError(ctx, 'Enter a valid adjustment value');
                        return;
                      }
                    }
                    Navigator.of(ctx, rootNavigator: true).pop();
                    try {
                      await _c.rpc('set_customer_rate', params: {
                        'p_trader_id': tid,
                        'p_retailer_id': selR!['id'],
                        'p_product_id': selP!['id'],
                        'p_rate_per_kg': rateVal ?? 0,
                        'p_effective_date':
                        DateFormat('yyyy-MM-dd').format(effDate),
                        if (expDate != null)
                          'p_expiry_date':
                          DateFormat('yyyy-MM-dd').format(expDate!),
                        'p_pricing_type': selType.type,
                        'p_adjustment_value': adjVal ?? 0,
                      });
                      if (mounted) {
                        final desc = selType.needsAdjustment
                            ? '${selType.label}: ${adjVal}${selType.type.startsWith('pct') ? '%' : '₹'}'
                            : '${Fmt.amount(rateVal!)}/kg';
                        showSuccess(context,
                            '${selR!['shop_name']} · ${selP!['name']} → $desc ✓');
                        _load();
                      }
                    } catch (e) {
                      if (mounted) showError(context, e.toString());
                    }
                  },
                  child: Text('Set ${selType.label}'),
                ),
              ]),
            ),
          )),
    );
    rateCtrl.dispose();
    adjCtrl.dispose();
  }

  Widget _dateTile(String label, DateTime? date, {bool optional = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
            color: date != null ? kNavy.withValues(alpha: 0.05) : kBgGrey,
            borderRadius: BorderRadius.circular(kRadiusInner),
            border: Border.all(
                color: date != null
                    ? kNavy.withValues(alpha: 0.2)
                    : kBorderLight)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: kTextHint, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            date != null
                ? DateFormat('d MMM y').format(date)
                : (optional ? 'No expiry' : 'Tap to set'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: date != null ? kNavy : kTextHint),
          ),
        ]),
      );

  Future<void> _deactivate(Map<String, dynamic> rate) async {
    final confirm = await confirmDialog(context,
        title: 'Remove Special Rate?',
        message:
        '${rate['shop_name']} · ${rate['product_name']} will revert to the zone rate.',
        confirmText: 'Remove',
        confirmColor: kError);
    if (!confirm) return;
    try {
      await _c
          .from('retailer_rates')
          .update({'is_active': false}).eq('id', rate['id']);
      if (mounted) {
        showSuccess(context, 'Rate removed');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  /// Build the display label for the trailing rate cell
  String _rateDisplay(Map<String, dynamic> r) {
    final type = r['pricing_type'] as String? ?? 'fixed';
    final rate = (r['rate_per_kg'] as num?)?.toDouble() ?? 0;
    final adj = (r['adjustment_value'] as num?)?.toDouble() ?? 0;
    return switch (type) {
      'flat_discount' => '−${Fmt.amount(adj)}',
      'flat_premium' => '+${Fmt.amount(adj)}',
      'pct_discount' => '−$adj%',
      'pct_premium' => '+$adj%',
      _ => '${Fmt.amount(rate)}/kg',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingList();

    return RefreshIndicator(
      onRefresh: _load,
      color: kNavy,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: _addRate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Customer Pricing'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
          ),
          const SizedBox(height: 12),

          // 6-type legend strip
          _PricingTypeLegend(),
          const SizedBox(height: 16),

          if (_rates.isEmpty)
            const EmptyState(
              icon: Icons.person_pin_outlined,
              message: 'No Customer Pricing',
              sub:
              'Set fixed rates, cutting rates, premiums or contracts for specific customers.',
            )
          else
            Container(
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight),
                  boxShadow: kCardShadow),
              child: Column(
                children: _rates.asMap().entries.map((e) {
                  final i = e.key;
                  final r = e.value;
                  final isLast = i == _rates.length - 1;
                  final td = _pricingTypeDef(r['pricing_type'] as String?);
                  final expStr = r['expiry_date'] as String?;
                  final exp = expStr != null ? DateTime.tryParse(expStr) : null;
                  final expiringSoon =
                      exp != null && exp.difference(DateTime.now()).inDays <= 7;

                  return Container(
                    decoration: isLast
                        ? null
                        : const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: kBorderLight))),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: td.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(kRadiusChip)),
                        child: Icon(td.icon, size: 18, color: td.color),
                      ),
                      title: Text(
                        '${r['shop_name']} · ${r['product_name']}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: kNavy),
                      ),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(td.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: td.color,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              'From: ${DateFormat('d MMM y').format(DateTime.parse(r['effective_date'] as String))}',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextHint),
                            ),
                            if (exp != null)
                              Text(
                                'Expires: ${DateFormat('d MMM y').format(exp)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: expiringSoon
                                        ? Colors.orange
                                        : kTextHint,
                                    fontWeight: expiringSoon
                                        ? FontWeight.w700
                                        : FontWeight.normal),
                              ),
                          ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          _rateDisplay(r),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: td.color),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: kError),
                          onPressed: () => _deactivate(r),
                          tooltip: 'Remove',
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Helper: contextual description shown when a type chip is selected ────────
class _PricingTypeHelper extends StatelessWidget {
  const _PricingTypeHelper({required this.type});

  final _PricingTypeDef type;

  String get _desc => switch (type.type) {
    'fixed' =>
    'Final rate charged regardless of zone. e.g. ₹138/kg always.',
    'contract' =>
    'Fixed rate with a set validity period. Set an expiry date below.',
    'flat_discount' =>
    'Zone rate minus a fixed ₹ amount. e.g. Zone ₹140 − ₹2 = ₹138.',
    'flat_premium' =>
    'Zone rate plus a fixed ₹ amount. e.g. Zone ₹140 + ₹3 = ₹143.',
    'pct_discount' =>
    'Zone rate minus a percentage. e.g. Zone ₹140 × 1.5% off = ₹137.90.',
    'pct_premium' =>
    'Zone rate plus a percentage. e.g. Zone ₹140 × 2% on = ₹142.80.',
    _ => '',
  };

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: type.color.withValues(alpha: 0.2))),
    child: Row(children: [
      Icon(type.icon, size: 14, color: type.color),
      const SizedBox(width: 8),
      Expanded(
          child: Text(_desc,
              style: TextStyle(
                  fontSize: 11,
                  color: type.color,
                  fontWeight: FontWeight.w500))),
    ]),
  );
}

// ── Legend: compact 3-column grid of all 6 types ─────────────────────────────
class _PricingTypeLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: kNavy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SUPPORTED PRICING TYPES',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: kTextHint,
              letterSpacing: 0.8)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 3.0,
        children: _kPricingTypes
            .map((t) => Container(
          decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(kRadiusChip)),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(t.icon, size: 12, color: t.color),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(t.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: t.color))),
              ]),
        ))
            .toList(),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3: PRODUCTS
// ─────────────────────────────────────────────────────────────────────────────

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab();

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_trader_products', params: {
        'p_trader_id': tid,
        'p_active_only': true
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(res as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> p) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final enabled = p['is_enabled'] as bool? ?? false;
    try {
      await _c.rpc('manage_trader_product', params: {
        'p_trader_id': tid,
        'p_product_id': p['product_id'],
        'p_action': enabled ? 'disable' : 'enable',
      });
      if (mounted) {
        showSuccess(context, enabled ? 'Disabled' : 'Enabled ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in _products)
      grouped.putIfAbsent(p['category'] as String? ?? 'other', () => []).add(p);
    final labels = {
      'broiler': '🐔 Broiler',
      'country': '🐓 Country Chicken',
      'quail': '🥚 Quail'
    };
    return RefreshIndicator(
      onRefresh: _load,
      color: kNavy,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: kNavy.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(color: kNavy.withValues(alpha: 0.15))),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: kNavy),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Enable the products you trade. Only enabled products appear in order creation.',
                      style: TextStyle(
                          fontSize: 12,
                          color: kNavy,
                          fontWeight: FontWeight.w500)))
            ])),
        for (final cat in ['broiler', 'country', 'quail'])
          if ((grouped[cat] ?? []).isNotEmpty) ...[
            _sectionHeader(labels[cat] ?? cat),
            Container(
              decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight),
                  boxShadow: kCardShadow),
              child: Column(
                  children: (grouped[cat] ?? []).map((p) {
                    final enabled = p['is_enabled'] as bool? ?? false;
                    final isVariant = p['is_variant'] as bool? ?? false;
                    return ListTile(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: isVariant ? 4 : 8),
                      leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color:
                              enabled ? kNavy.withValues(alpha: 0.08) : kBgGrey,
                              borderRadius: BorderRadius.circular(kRadiusChip),
                              border: Border.all(
                                  color: enabled
                                      ? kNavy.withValues(alpha: 0.2)
                                      : kBorderLight)),
                          child: Icon(
                              isVariant
                                  ? Icons.subdirectory_arrow_right_rounded
                                  : Icons.egg_alt_rounded,
                              size: 18,
                              color: enabled ? kNavy : kTextHint)),
                      title: Text(
                          p['display_name'] as String? ??
                              p['name'] as String? ??
                              '—',
                          style: TextStyle(
                              fontSize: isVariant ? 13 : 15,
                              fontWeight:
                              isVariant ? FontWeight.w600 : FontWeight.w800,
                              color: enabled ? kNavy : kTextHint)),
                      subtitle: Text(
                          p['rate_unit'] == 'per_bird' ? 'Per bird' : 'Per kg',
                          style: TextStyle(
                              fontSize: 11, color: enabled ? kTextSub : kTextHint)),
                      trailing: Switch.adaptive(
                          value: enabled,
                          activeColor: kNavy,
                          onChanged: (_) => _toggle(p)),
                    );
                  }).toList()),
            ),
            const SizedBox(height: 8),
          ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4: ZONES
// ─────────────────────────────────────────────────────────────────────────────

class _ZonesTab extends ConsumerStatefulWidget {
  const _ZonesTab();

  @override
  ConsumerState<_ZonesTab> createState() => _ZonesTabState();
}

class _ZonesTabState extends ConsumerState<_ZonesTab> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  static const _presets = [
    {'name': 'Coimbatore', 'code': 'CBE'},
    {'name': 'Tiruppur', 'code': 'TPR'},
    {'name': 'Pollachi', 'code': 'PLH'},
    {'name': 'Salem', 'code': 'SLM'},
    {'name': 'Erode', 'code': 'ERD'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final res = await _c.rpc('get_zones', params: {
        'p_trader_id': tid,
        'p_active_only': false
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _zones = List<Map<String, dynamic>>.from(res as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showZoneForm({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final nc =
    TextEditingController(text: existing?['zone_name'] as String? ?? '');
    final cc =
    TextEditingController(text: existing?['zone_code'] as String? ?? '');
    final dc =
    TextEditingController(text: existing?['description'] as String? ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text(isEdit ? 'Edit Zone' : 'Add Zone',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: kNavy)),
                  const SizedBox(height: 16),
                  if (!isEdit) ...[
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _presets
                            .where((p) => _zones
                            .every((z) => z['zone_code'] != p['code']))
                            .map((p) => ActionChip(
                          label: Text(p['name']!,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          backgroundColor:
                          kNavy.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: kNavy.withValues(alpha: 0.2)),
                          onPressed: () {
                            nc.text = p['name']!;
                            cc.text = p['code']!;
                            ss(() {});
                          },
                        ))
                            .toList()),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                      controller: nc,
                      decoration: const InputDecoration(
                          labelText: 'Zone Name *',
                          prefixIcon: Icon(Icons.location_city_outlined,
                              size: 20))),
                  const SizedBox(height: 10),
                  TextFormField(
                      controller: cc,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 5,
                      decoration: const InputDecoration(
                          labelText: 'Zone Code *',
                          counterText: '',
                          prefixIcon: Icon(Icons.tag_rounded, size: 20))),
                  const SizedBox(height: 10),
                  TextFormField(
                      controller: dc,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          alignLabelWithHint: true)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52)),
                    onPressed: () async {
                      final name = nc.text.trim();
                      final code = cc.text.trim().toUpperCase();
                      if (name.isEmpty || code.isEmpty) {
                        showError(context, 'Name and code required');
                        return;
                      }
                      Navigator.of(ctx, rootNavigator: true).pop();
                      try {
                        await _c.rpc('manage_zone', params: {
                          'p_action': isEdit ? 'update' : 'create',
                          'p_trader_id': tid,
                          if (isEdit) 'p_zone_id': existing!['id'],
                          'p_zone_name': name,
                          'p_zone_code': code,
                          if (dc.text.trim().isNotEmpty)
                            'p_description': dc.text.trim(),
                        });
                        if (mounted) {
                          showSuccess(
                              context,
                              isEdit
                                  ? 'Zone updated ✓'
                                  : 'Zone "$name" created ✓');
                          _load();
                        }
                      } catch (e) {
                        if (mounted) showError(context, e.toString());
                      }
                    },
                    child: Text(isEdit ? 'Save Changes' : 'Create Zone'),
                  ),
                ]),
          )),
    );
  }

  Future<void> _toggle(Map<String, dynamic> zone) async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    final isActive = zone['is_active'] as bool? ?? true;
    final confirm = await confirmDialog(context,
        title: isActive ? 'Disable Zone?' : 'Enable Zone?',
        message: isActive
            ? 'Zone rates will stop applying to retailers in this zone.'
            : 'Enable to use in rate assignments.',
        confirmText: isActive ? 'Disable' : 'Enable',
        confirmColor: isActive ? kError : kSuccess);
    if (!confirm) return;
    try {
      await _c.rpc('manage_zone', params: {
        'p_action': 'toggle',
        'p_trader_id': tid,
        'p_zone_id': zone['id']
      });
      if (mounted) {
        showSuccess(context, isActive ? 'Zone disabled' : 'Zone enabled ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingList();
    return RefreshIndicator(
      onRefresh: _load,
      color: kNavy,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: kGoldBg.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(color: kGold.withValues(alpha: 0.3))),
            child: const Row(children: [
              Icon(Icons.map_outlined, size: 16, color: kWarning),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Zones let you set different selling rates per delivery area.',
                      style: TextStyle(
                          fontSize: 12,
                          color: kWarning,
                          fontWeight: FontWeight.w500)))
            ])),
        if (_zones.isEmpty)
          EmptyState(
              icon: Icons.map_outlined,
              message: 'No Zones Yet',
              sub: 'Add delivery zones like Coimbatore, Tiruppur, Pollachi.',
              actionLabel: 'Add First Zone',
              onAction: () => _showZoneForm())
        else ...[
          for (final z in _zones) ...[
            _ZoneCard(
                zone: z,
                onEdit: () => _showZoneForm(existing: z),
                onToggle: () => _toggle(z)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => _showZoneForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Zone'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48))),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 5: ZONE ASSIGNMENT
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneAssignTab extends ConsumerStatefulWidget {
  const _ZoneAssignTab();

  @override
  ConsumerState<_ZoneAssignTab> createState() => _ZoneAssignTabState();
}

class _ZoneAssignTabState extends ConsumerState<_ZoneAssignTab> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _retailers = [], _zones = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null || !mounted) return;
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _c
            .from('retailers')
            .select('id, shop_name, city, zone_id, zones(zone_name, zone_code)')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c.rpc('get_zones',
            params: {'p_trader_id': tid, 'p_active_only': true}),
      ]);
      if (!mounted) return;
      setState(() {
        _retailers = List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _zones = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> retailer, String? zoneId) async {
    try {
      await _c.rpc('assign_retailer_zone',
          params: {'p_retailer_id': retailer['id'], 'p_zone_id': zoneId});
      if (mounted) {
        showSuccess(
            context, zoneId == null ? 'Zone removed' : 'Zone assigned ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _retailers;
    final q = _search.toLowerCase();
    return _retailers
        .where((r) =>
    (r['shop_name'] as String? ?? '').toLowerCase().contains(q) ||
        (r['city'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingList();
    if (_zones.isEmpty) {
      return const EmptyState(
          icon: Icons.map_outlined,
          message: 'No Active Zones',
          sub: 'Create zones in the Zones tab first.');
    }
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: AppSearchBar(
              controller: _searchCtrl,
              hint: 'Search retailers…',
              onChanged: (v) => setState(() => _search = v),
              onClear: () => setState(() {
                _search = '';
                _searchCtrl.clear();
              }))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${_retailers.where((r) => r['zone_id'] != null).length} / ${_retailers.length} assigned',
                style: const TextStyle(
                    fontSize: 12,
                    color: kTextSub,
                    fontWeight: FontWeight.w600))),
      ),
      Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: kNavy,
            child: _filtered.isEmpty
                ? const EmptyState(
                icon: Icons.store_outlined, message: 'No retailers found')
                : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = _filtered[i];
                  final zoneId = r['zone_id'] as String?;
                  final zoneInfo = r['zones'] as Map<String, dynamic>?;
                  final code = (zoneInfo?['zone_code'] as String? ?? '—');
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(kRadiusCard),
                        border: Border.all(
                            color: zoneId != null
                                ? kNavy.withValues(alpha: 0.15)
                                : kBorderLight),
                        boxShadow: kCardShadow),
                    child: Row(children: [
                      Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              gradient: zoneId != null
                                  ? const LinearGradient(
                                  colors: [kNavy, kNavyMid])
                                  : null,
                              color: zoneId == null ? kBgGrey : null,
                              borderRadius: BorderRadius.circular(kRadiusChip)),
                          child: Center(
                              child: Text(
                                  code.length >= 3
                                      ? code.substring(0, 3)
                                      : code,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: zoneId != null
                                          ? kGoldLight
                                          : kTextHint,
                                      letterSpacing: 0.3)))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['shop_name'] as String? ?? '—',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: kNavy)),
                                Text(
                                    zoneInfo?['zone_name'] != null
                                        ? 'Zone: ${zoneInfo!['zone_name']}'
                                        : 'No zone assigned',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                        zoneId != null ? kTextSub : kTextHint)),
                              ])),
                      DropdownButton<String?>(
                        value: zoneId,
                        hint: const Text('Zone',
                            style: TextStyle(fontSize: 12, color: kTextHint)),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No Zone',
                                  style: TextStyle(
                                      fontSize: 12, color: kTextHint))),
                          ..._zones.map((z) => DropdownMenuItem<String?>(
                            value: z['id'] as String?,
                            child: Text(z['zone_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          )),
                        ],
                        onChanged: (v) => _assign(r, v),
                      ),
                    ]),
                  );
                }),
          )),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED CARD WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneCard extends StatelessWidget {
  const _ZoneCard(
      {required this.zone, required this.onEdit, required this.onToggle});

  final Map<String, dynamic> zone;
  final VoidCallback onEdit, onToggle;

  @override
  Widget build(BuildContext context) {
    final isActive = zone['is_active'] as bool? ?? true;
    final count = (zone['retailer_count'] as num?)?.toInt() ?? 0;
    return Container(
      decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
          boxShadow: isActive ? kCardShadow : null),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                gradient: isActive
                    ? const LinearGradient(colors: [kNavy, kNavyMid])
                    : null,
                color: isActive ? null : kBgGrey,
                borderRadius: BorderRadius.circular(kRadiusChip)),
            child: Center(
                child: Text(
                    (zone['zone_code'] as String? ?? '?')
                        .substring(0, 3)
                        .toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: isActive ? kGoldLight : kTextHint,
                        letterSpacing: 0.5)))),
        title: Text(zone['zone_name'] as String? ?? '—',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isActive ? kNavy : kTextHint)),
        subtitle: Text(
            count > 0
                ? '$count retailer${count > 1 ? 's' : ''}'
                : 'No retailers',
            style: TextStyle(
                fontSize: 11, color: isActive ? kTextSub : kTextHint)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: kTextSub),
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
          IconButton(
              icon: Icon(
                  isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                  size: 24,
                  color: isActive ? kNavy : kTextHint),
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
        ]),
      ),
    );
  }
}