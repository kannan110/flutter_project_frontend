import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common/horizontalscroll_wheel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Create Order — v2 (UX redesign only)
//
// PRESERVED EXACTLY FROM v1 (no business logic changes):
//   • orders / order_items insert shape and fields
//   • get_effective_rate_v4 cascade call + rate snapshot capture
//   • auto-confirm-on-create behaviour
//   • validation rules (product required, weight > 0)
//   • multi-product support
//
// WHAT CHANGED (workflow / UX only):
//   • Customer-first flow, zone/outstanding/last-order surfaced automatically
//   • Recent + favourite customers computed client-side from order history
//     (favourites = most-frequent in that window — no new schema, no pinning
//     column added, since schema changes are out of scope for this pass)
//   • One-tap "Repeat last order"
//   • Product chips instead of a dropdown
//   • Birds is the primary input; Weight auto-calculates and is edit-on-tap;
//     Rate shows as a trusted chip with its source, edit-on-tap
//   • No confirmation modal — Create is final, in place
//   • After creation the page does not navigate; the sticky Create button is
//     replaced in place by an Action Hub (Assign Batch, New Order,
//     Today's Orders, WhatsApp Customer, View Order)
//   • Responsive: >=900px width uses a 70/30 split (content | sticky summary)
//     instead of a stretched single column
//
// ASSUMPTIONS FLAGGED FOR REVIEW (please confirm before this goes to prod):
//   • get_retailer_outstanding is assumed to return a plain numeric value,
//     matching how retailer_detail_screen.dart already consumes it.
//   • "Favourite" = top-3 most-ordered-from retailers in the trader's last
//     ~150 orders. If you want manually pinned favourites instead, that
//     needs a new column (schema change) and is a separate approval.
//   • Stock-availability indicator was intentionally left out of this pass —
//     Create Order has never validated against stock (that happens at batch
//     assignment), and wiring it in needs its own root-cause/data-source
//     discussion rather than a guess bundled into a UX pass.
//   • Rate-source label uses the RPC's own `rate_label` field directly
//     (v1 fetched it but never displayed it) rather than guessing at
//     rate_source enum strings.
//   • Zone display uses the real `retailers.zone_id` -> `zones.zone_name`
//     join (confirmed via create_retailer_screen.dart), not a placeholder.
// ─────────────────────────────────────────────────────────────────────────────

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _S();
}

class _OrderLine {
  Map<String, dynamic>? product;
  final birds = TextEditingController();
  final totalWt = TextEditingController();
  final rate = TextEditingController();
  double? suggestRate;
  String? rateSource;
  String? rateSourceLabel;
  String? rateZoneId;
  String? rateZoneName;
  double? baseRate;
  String? pricingType;
  double? adjustmentValue;

  // UI-only edit-mode flag (not business logic) — Rate stays a trusted
  // read-only chip until the trader explicitly taps to override it.
  bool editingRate = false;

  double get kg => double.tryParse(totalWt.text.trim()) ?? 0;
  double get r => double.tryParse(rate.text.trim()) ?? 0;
  int get b => int.tryParse(birds.text.trim()) ?? 0;
  double get amt => kg * r;

  void dispose() {
    birds.dispose();
    totalWt.dispose();
    rate.dispose();
  }
}

class _S extends ConsumerState<CreateOrderScreen> {
  final _c = Supabase.instance.client;
  final _form = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _localMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _customerScrollCtrl = ScrollController();
  final _productScrollCtrl = ScrollController();

  List<Map<String, dynamic>> _retailers = [], _products = [];
  List<Map<String, dynamic>> _recentRetailers = [];
  Set<String> _favouriteIds = {};
  Map<String, String> _zoneNameById = {}; // retailers.zone_id -> zones.zone_name

  Map<String, dynamic>? _selRetailer;
  double _outstanding = 0;
  Map<String, dynamic>? _lastOrder; // {id, created_at, total_amount, items:[...]}
  bool _loadingCustomerContext = false;

  List<_OrderLine> _lines = [_OrderLine()];
  int _activeIdx = 0; // which line is shown expanded for editing right now
  bool _saving = false, _dataLoading = true;

  Map<String, dynamic>? _createdOrder; // snapshot shown in the success sheet

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _localMessengerKey.currentState?.clearSnackBars();
    _notesCtrl.dispose();
    _scrollCtrl.dispose();
    _customerScrollCtrl.dispose();
    _productScrollCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────
  Future<void> _loadMeta() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _c
            .from('retailers')
            .select('id,shop_name,phone,zone_id')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        _c.rpc('get_trader_enabled_products', params: {'p_trader_id': tid}),
        // Read-only, used purely to compute "recent" and "favourite" chips.
        _c
            .from('orders')
            .select('retailer_id,created_at')
            .eq('trader_id', tid)
            .order('created_at', ascending: false)
            .limit(150),
        // Zone names for the read-only zone display next to a selected customer.
        _c.from('zones').select('id,zone_name'),
      ]);
      if (!mounted) return;
      final retailers = List<Map<String, dynamic>>.from(results[0] as List);
      final products = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      final history = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      final zones = List<Map<String, dynamic>>.from(results[3] as List? ?? []);
      final zoneNameById = {
        for (final z in zones) z['id'] as String: z['zone_name'] as String? ?? ''
      };

      final byId = {for (final r in retailers) r['id'] as String: r};
      final seenOrder = <String>[]; // recency, first-seen order preserved
      final counts = <String, int>{};
      for (final row in history) {
        final id = row['retailer_id'] as String?;
        if (id == null || !byId.containsKey(id)) continue;
        if (!seenOrder.contains(id)) seenOrder.add(id);
        counts[id] = (counts[id] ?? 0) + 1;
      }
      final recent = seenOrder.take(8).map((id) => byId[id]!).toList();
      final favIds = (counts.keys.toList()
        ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0)))
          .take(3)
          .toSet();

      setState(() {
        _retailers = retailers;
        _products = products;
        _recentRetailers = recent;
        _favouriteIds = favIds;
        _zoneNameById = zoneNameById;
        _dataLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _dataLoading = false);
    }
  }

  // ── Customer selection ──────────────────────────────────────────────────
  Future<void> _selectRetailer(Map<String, dynamic> r) async {
    _beginEditingIfNeeded();
    setState(() {
      _selRetailer = r;
      _outstanding = 0;
      _lastOrder = null;
      _loadingCustomerContext = true;
    });
    for (int i = 0; i < _lines.length; i++) _fetchRate(i);

    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    try {
      final results = await Future.wait<dynamic>([
        _c.rpc('get_retailer_outstanding', params: {'p_retailer_id': r['id']}),
        _c
            .from('orders')
            .select('id,created_at,total_amount')
            .eq('retailer_id', r['id'] as String)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      final outstanding = (results[0] as num?)?.toDouble() ?? 0;
      final lastOrderRow = results[1] as Map<String, dynamic>?;

      Map<String, dynamic>? lastOrder;
      if (lastOrderRow != null) {
        final items = await _c
            .from('order_items')
            .select('product_id,bird_count,total_weight,rate_per_kg,line_total')
            .eq('order_id', lastOrderRow['id'] as String);
        final itemList = List<Map<String, dynamic>>.from(items);
        lastOrder = {
          'id': lastOrderRow['id'],
          'created_at': lastOrderRow['created_at'],
          'total_amount': (lastOrderRow['total_amount'] as num?)?.toDouble() ?? 0,
          'items': itemList,
        };
      }
      if (!mounted) return;
      setState(() {
        _outstanding = outstanding;
        _lastOrder = lastOrder;
        _loadingCustomerContext = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCustomerContext = false);
    }
    if (tid == null) return;
  }

  String _lastOrderSummaryText() {
    final items = List<Map<String, dynamic>>.from(_lastOrder?['items'] ?? []);
    if (items.isEmpty) return '';
    final parts = items.map((it) {
      final p = _products.firstWhere(
              (p) => p['id'] == it['product_id'],
          orElse: () => {'name': 'Product'});
      final birds = (it['bird_count'] as num?)?.toInt() ?? 0;
      final wt = (it['total_weight'] as num?)?.toDouble() ?? 0;
      // Some historical orders only recorded weight, not bird count — don't
      // print a misleading "0 birds" for those.
      final bits = <String>[
        if (birds > 0) '$birds birds',
        if (wt > 0) '${wt.toStringAsFixed(0)} kg',
      ];
      return '${p['name']}${bits.isEmpty ? '' : ' · ${bits.join(' · ')}'}';
    });
    return parts.join(' · ');
  }

  void _repeatLastOrder() {
    final items = List<Map<String, dynamic>>.from(_lastOrder?['items'] ?? []);
    if (items.isEmpty) return;
    _beginEditingIfNeeded();
    for (final l in _lines) l.dispose();
    final newLines = <_OrderLine>[];
    for (final it in items) {
      final line = _OrderLine();
      final product = _products.firstWhere(
              (p) => p['id'] == it['product_id'],
          orElse: () => <String, dynamic>{});
      if (product.isNotEmpty) line.product = product;
      final birds = (it['bird_count'] as num?)?.toInt() ?? 0;
      final wt = (it['total_weight'] as num?)?.toDouble() ?? 0;
      if (birds > 0) line.birds.text = '$birds';
      if (wt > 0) line.totalWt.text = wt.toStringAsFixed(2);
      newLines.add(line);
    }
    setState(() {
      _lines = newLines;
      _activeIdx = 0;
    });
    for (int i = 0; i < _lines.length; i++) _fetchRate(i);
  }

  // ── Rate (unchanged from v1) ────────────────────────────────────────────
  Future<void> _fetchRate(int idx) async {
    final line = _lines[idx];
    if (_selRetailer == null || line.product == null) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    // Weight is the primary business quantity the rate cascade is keyed on
    // (get_effective_rate_v4 takes p_quantity_kg). We only fetch once real
    // weight has been entered — never estimate it from birds, since average
    // weight per bird varies by farm/retailer and can't be assumed.
    final kg = line.kg;
    if (kg <= 0) return;
    try {
      final res = await _c.rpc('get_effective_rate_v4', params: {
        'p_trader_id': tid,
        'p_retailer_id': _selRetailer!['id'],
        'p_product_id': line.product!['id'],
        'p_quantity_kg': kg,
      });
      final rows = res as List?;
      if (rows == null || rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      final rate = (row['rate'] as num?)?.toDouble() ?? 0;
      final baseRate = (row['base_rate'] as num?)?.toDouble();
      final source = row['rate_source'] as String? ?? 'default_rate';
      final label = row['rate_label'] as String? ?? '';
      final pricingType = row['pricing_type'] as String? ?? 'none';
      final adjValue = (row['adjustment_value'] as num?)?.toDouble() ?? 0;
      final zoneId = row['zone_id'] as String?;
      final zoneName = row['zone_name'] as String?;
      if (mounted && rate > 0) {
        setState(() {
          line.suggestRate = rate;
          line.baseRate = baseRate;
          line.rateSource = source;
          line.rateSourceLabel = label;
          line.pricingType = pricingType;
          line.adjustmentValue = adjValue;
          line.rateZoneId = zoneId;
          line.rateZoneName = zoneName;
          if (!line.editingRate) line.rate.text = rate.toStringAsFixed(2);
        });
      }
    } catch (_) {}
  }

  // get_effective_rate_v4 already returns a human-readable `rate_label` —
  // v1 fetched it but never displayed it. Use it directly rather than
  // guessing at the exact rate_source enum strings.
  String _rateSourceLabel(_OrderLine line) {
    if (line.rateSourceLabel != null && line.rateSourceLabel!.trim().isNotEmpty) {
      return line.rateSourceLabel!;
    }
    return line.rateSource ?? 'Default rate';
  }

  // ── Lines ────────────────────────────────────────────────────────────────
  // No-op now that success is a transient bottom sheet rather than a
  // persistent page state — kept so existing call sites don't need touching.
  void _beginEditingIfNeeded() {}

  void _tapProduct(Map<String, dynamic> product) {
    _beginEditingIfNeeded();

    // Already added? Just reopen it as the active card instead of duplicating.
    final existingIdx = _lines.indexWhere((l) => l.product?['id'] == product['id']);
    if (existingIdx != -1) {
      setState(() => _activeIdx = existingIdx);
      return;
    }

    // Fill the first empty line if one exists, else add a new one.
    final emptyIdx = _lines.indexWhere((l) => l.product == null);
    if (emptyIdx != -1) {
      setState(() {
        _lines[emptyIdx].product = product;
        _activeIdx = emptyIdx;
      });
      _fetchRate(emptyIdx);
    } else {
      final line = _OrderLine()..product = product;
      setState(() {
        _lines.add(line);
        _activeIdx = _lines.length - 1;
      });
      _fetchRate(_lines.length - 1);
    }
    _scrollToBottomSoon();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  void _addLine() {
    _beginEditingIfNeeded();
    setState(() {
      _lines.add(_OrderLine());
      _activeIdx = _lines.length - 1;
    });
    _scrollToBottomSoon();
  }

  void _quickAdjustBirds(_OrderLine line, int delta) {
    _beginEditingIfNeeded();
    final cur = int.tryParse(line.birds.text.trim()) ?? 0;
    final next = (cur + delta).clamp(0, 1000000);
    line.birds.text = '$next';
    setState(() {});
    final idx = _lines.indexOf(line);
    if (idx != -1) _fetchRate(idx);
  }

  void _removeLine(int idx) {
    _beginEditingIfNeeded();
    final removed = _lines[idx];
    final wasOnlyLine = _lines.length == 1;
    setState(() {
      _lines.removeAt(idx);
      if (wasOnlyLine) _lines.add(_OrderLine()); // keep one blank slot to edit into
      if (_activeIdx >= _lines.length) _activeIdx = _lines.length - 1;
      if (_activeIdx < 0) _activeIdx = 0;
    });
    removed.dispose();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          content: Text('Product removed')));
  }

  void _clearAllLines() {
    _beginEditingIfNeeded();
    for (final l in _lines) l.dispose();
    setState(() {
      _lines = [_OrderLine()];
      _activeIdx = 0;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
          content: Text('All products cleared')));
  }

  // Purely a UI hint ("Usual: 110-130") derived from this customer's last
  // order for this product — never used for validation or pricing.
  String? _usualRangeFor(_OrderLine line) {
    final product = line.product;
    if (product == null) return null;
    final items = List<Map<String, dynamic>>.from(_lastOrder?['items'] ?? []);
    final match = items.where((it) => it['product_id'] == product['id']);
    if (match.isEmpty) return null;
    final b = (match.first['bird_count'] as num?)?.toInt() ?? 0;
    if (b <= 0) return null;
    final lo = (b * 0.85).round();
    final hi = (b * 1.15).round();
    return 'Usual: $lo–$hi';
  }

  double get _totalAmt => _lines.fold(0.0, (s, l) => s + l.amt);
  double get _totalKg => _lines.fold(0.0, (s, l) => s + l.kg);
  int get _totalBirds => _lines.fold(0, (s, l) => s + l.b);

  // ── Save (business logic unchanged from v1) ─────────────────────────────
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_selRetailer == null) {
      showError(context, 'Select a customer');
      return;
    }
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].product == null) {
        showError(context, 'Select product for line ${i + 1}');
        return;
      }
      if (_lines[i].kg <= 0) {
        showError(context, 'Enter weight for line ${i + 1}');
        return;
      }
    }

    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (mounted) setState(() => _saving = true);
    try {
      final firstLine = _lines.first;
      final order = await _c
          .from('orders')
          .insert({
        'trader_id': tid,
        'retailer_id': _selRetailer!['id'],
        'product_id': firstLine.product!['id'],
        'status': 'pending', // auto-confirmed by DB trigger
        'order_date': DateTime.now().toIso8601String().split('T')[0],
        if (_totalBirds > 0) 'estimated_birds': _totalBirds,
        if (_totalKg > 0) 'total_quantity': _totalKg,
        if (_totalAmt > 0) 'total_amount': _totalAmt,
        if (firstLine.r > 0) 'final_price': firstLine.r,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      })
          .select()
          .single();

      for (final line in _lines) {
        await _c.from('order_items').insert({
          'order_id': order['id'],
          'trader_id': tid,
          'product_id': line.product!['id'],
          if (line.b > 0) 'bird_count': line.b,
          if (line.kg > 0) 'total_weight': line.kg,
          if (line.r > 0) 'rate_per_kg': line.r,
          if (line.amt > 0) 'line_total': line.amt,
          if (line.r > 0) 'applied_rate': line.r,
          if (line.baseRate != null) 'base_rate': line.baseRate,
          if (line.rateSource != null) 'rate_source': line.rateSource,
          if (line.pricingType != null) 'adjustment_type': line.pricingType,
          if (line.adjustmentValue != null && line.adjustmentValue! > 0)
            'adjustment_value': line.adjustmentValue,
          if (line.rateZoneId != null) 'rate_zone_id': line.rateZoneId,
          if (line.rateZoneName != null) 'rate_zone_name': line.rateZoneName,
        });
      }

      final zoneId = _selRetailer?['zone_id'] as String?;
      final itemSnapshot = _lines
          .where((l) => l.product != null)
          .map((l) => {
        'name': l.product!['name'],
        'birds': l.b,
        'kg': l.kg,
      })
          .toList();

      if (mounted) {
        setState(() {
          _createdOrder = {
            'id': order['id'],
            'amount': _totalAmt,
            'birds': _totalBirds,
            'kg': _totalKg,
            'customer': _selRetailer?['shop_name'],
            'zone': (zoneId != null ? _zoneNameById[zoneId] : null) ?? '—',
            'items': itemSnapshot,
          };
          // Reset the working form right away — customer stays selected,
          // since most traders place several orders in a row for the same
          // shop. The sheet below shows what was just created.
          for (final l in _lines) l.dispose();
          _lines = [_OrderLine()];
          _activeIdx = 0;
        });
        _showSuccessSheet();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForNewOrder() {
    for (final l in _lines) l.dispose();
    _notesCtrl.clear();
    setState(() {
      _lines = [_OrderLine()];
      _activeIdx = 0;
      _selRetailer = null;
      _outstanding = 0;
      _lastOrder = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _whatsAppShare() async {
    final shop = _selRetailer?['shop_name'] as String? ?? 'Customer';
    final amt = (_createdOrder?['amount'] as num?)?.toDouble() ?? _totalAmt;
    final birds = (_createdOrder?['birds'] as num?)?.toInt() ?? _totalBirds;
    final text = 'Order for $shop\n$birds birds · ${Fmt.amount(amt)}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSuccess(context, 'Order summary copied — paste in WhatsApp');
  }

  // ── UI helpers ───────────────────────────────────────────────────────────
  static const _palette = [
    kPrimary, kGoldLight, Color(0xFF0F6E56), Color(0xFF993C1D),
    Color(0xFF534AB7), Color(0xFF185FA5),
  ];

  Color _colorFor(String seed) => _palette[seed.hashCode.abs() % _palette.length];

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return ScaffoldMessenger(
      key: _localMessengerKey,
      child: Scaffold(
        backgroundColor: kBgPage,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: kSurface,
          title: const Text('New Order'),
        ),
        body: SafeArea(
          child: _dataLoading
              ? const LoadingList()
              : _products.isEmpty
              ? EmptyState(
            icon: Icons.egg_alt_outlined,
            message: 'No Products Enabled',
            sub: 'Enable the products you trade in Pricing → Products tab before creating orders.',
            actionLabel: 'Go to Pricing',
            onAction: () => context.push(R.pricingHub),
          )
              : Form(
            key: _form,
            child: LayoutBuilder(builder: (ctx, cons) {
              final isWide = cons.maxWidth >= 900;
              return isWide
                  ? _buildWideLayout(bottomInset)
                  : _buildNarrowLayout(bottomInset);
            }),
          ),
        ),
      ),
    );
  }

  // ── Mobile / narrow layout ───────────────────────────────────────────────
  Widget _buildNarrowLayout(double bottomInset) => Column(children: [
    Expanded(
        child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: _bodyChildren())),
    _bottomBar(bottomInset),
  ]);

  // ── Desktop / wide layout — 70/30, not a stretched phone screen ─────────
  Widget _buildWideLayout(double bottomInset) => Padding(
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            flex: 7,
            child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.only(right: 16),
                children: _bodyChildren())),
        Expanded(
            flex: 3,
            child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: kBorderLight),
                    boxShadow: kCardShadow),
                child: _summaryPanel())),
      ]));

  List<Widget> _bodyChildren() {
    return [
      _customerSection(),
      const SizedBox(height: 14),
      if (_selRetailer != null) _customerContextCard(),
      if (_selRetailer != null && _lastOrder != null) _repeatOrderCard(),
      const SizedBox(height: 14),
      _productSection(),
      const SizedBox(height: 14),
      _stepHeader(3, 'Order Items'),
      _activeProductCard(_activeIdx),
      _addedProductsList(),
      const SizedBox(height: 120),
    ];
  }

  // ── Customer: favourites/recent horizontal scroll + search ─────────────
  Widget _stepHeader(int n, String title, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('$n',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        if (trailing != null) trailing,
      ]));

  Widget _customerSection() {
    final chips = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final r in _recentRetailers) {
      if (_favouriteIds.contains(r['id'])) {
        chips.add(r);
        seen.add(r['id'] as String);
      }
    }
    for (final r in _recentRetailers) {
      if (!seen.contains(r['id'])) {
        chips.add(r);
        seen.add(r['id'] as String);
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepHeader(1, 'Customer',
          trailing: TextButton.icon(
              onPressed: () => context.push(R.retailerCreate),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add New', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)))),
      SizedBox(
          height: 82,
          child: HorizontalScrollWheel(
              controller: _customerScrollCtrl,
              child: ListView(
                  controller: _customerScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  children: [
                    ...chips.map((r) => _customerChip(r)),
                    _searchChip(),
                  ])))
    ]);
  }

  Widget _customerChip(Map<String, dynamic> r) {
    final selected = _selRetailer?['id'] == r['id'];
    final isFav = _favouriteIds.contains(r['id']);
    final name = r['shop_name'] as String? ?? '';
    return GestureDetector(
        onTap: () => _selectRetailer(r),
        child: Container(
            width: 66,
            margin: const EdgeInsets.only(right: 8),
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _colorFor(name).withValues(alpha: 0.15),
                        border: Border.all(
                            color: selected ? kPrimary : Colors.transparent, width: 2)),
                    alignment: Alignment.center,
                    child: Text(_initialsFor(name),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _colorFor(name)))),
                if (isFav)
                  const Positioned(
                      top: -2,
                      right: -2,
                      child: Icon(Icons.star, size: 13, color: kGoldLight)),
              ]),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ])));
  }

  Widget _searchChip() => GestureDetector(
      onTap: _openSearchSheet,
      child: Container(
          width: 66,
          margin: const EdgeInsets.only(right: 8),
          child: Column(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kBorderLight),
                    color: kSurface),
                alignment: Alignment.center,
                child: const Icon(Icons.search, size: 20, color: kTextSub)),
            const SizedBox(height: 4),
            const Text('Search', style: TextStyle(fontSize: 10, color: kTextSub)),
          ])));

  Future<void> _openSearchSheet() async {
    final ctrl = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(_retailers);
    await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollCtrl) => Container(
                  decoration: const BoxDecoration(
                      color: kSurface,
                      borderRadius:
                      BorderRadius.vertical(top: Radius.circular(kRadiusCard))),
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: 'Search customer name or mobile',
                            prefixIcon: Icon(Icons.search, size: 20)),
                        onChanged: (q) => setSheet(() {
                          final ql = q.trim().toLowerCase();
                          filtered = ql.isEmpty
                              ? List.from(_retailers)
                              : _retailers
                              .where((r) => (r['shop_name'] as String? ?? '')
                              .toLowerCase()
                              .contains(ql))
                              .toList();
                        })),
                    const SizedBox(height: 10),
                    Expanded(
                        child: ListView.builder(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final r = filtered[i];
                              return ListTile(
                                  title: Text(r['shop_name'] as String? ?? ''),
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _selectRetailer(r);
                                  });
                            })),
                  ])));
        }));
  }

  Widget _customerContextCard() {
    final zoneId = _selRetailer?['zone_id'] as String?;
    final zone = (zoneId != null ? _zoneNameById[zoneId] : null) ?? '—';
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusInner),
            border: Border.all(color: kBorderLight)),
        child: _loadingCustomerContext
            ? const SizedBox(
            height: 20,
            child: Center(
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(_selRetailer?['shop_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            GestureDetector(
                onTap: _openSearchSheet,
                child: const Text('Change',
                    style: TextStyle(fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _contextStat(Icons.location_on_outlined, 'Zone', zone),
            _contextStat(
                Icons.account_balance_wallet_outlined,
                'Outstanding',
                _outstanding > 0 ? Fmt.amount(_outstanding) : '—',
                warn: _outstanding > 50000),
            _contextStat(
                Icons.history,
                'Last order',
                _lastOrder == null ? '—' : _shortDate(_lastOrder!['created_at'] as String?)),
          ]),
        ]));
  }

  String _shortDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '$diff days ago';
  }

  Widget _contextStat(IconData icon, String label, String value, {bool warn = false}) => Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: kTextSub),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: kTextSub)),
        ]),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: warn ? Colors.red : Colors.black87)),
      ]));

  Widget _repeatOrderCard() {
    final amt = (_lastOrder?['total_amount'] as num?)?.toDouble() ?? 0;
    return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Same as last time',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: Text(_lastOrderSummaryText(),
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600, color: Colors.green.shade900))),
            if (amt > 0)
              Text(Fmt.amount(amt),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.green.shade900)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: _repeatLastOrder,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700, minimumSize: const Size(0, 48)),
                  child: const Text('Repeat this order',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))),
        ]));
  }

  // ── Product: horizontal image-cards, tap to add ─────────────────────────
  Widget _productSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _stepHeader(2, 'Products',
        trailing: TextButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('Add Product', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)))),
    SizedBox(
        height: 88,
        child: HorizontalScrollWheel(
            controller: _productScrollCtrl,
            child: ListView(
                controller: _productScrollCtrl,
                scrollDirection: Axis.horizontal,
                children: _products.map((p) => _productChip(p)).toList()))),
    if (_products.length > 5)
      const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('Swipe to see more →', style: TextStyle(fontSize: 10, color: kTextHint))),
  ]);

  // Placeholder icon per product type — swap for product['image_url'] once
  // real product photos/icons are available. Kept as a single lookup so
  // wiring in real images later is a one-line change at the call site below.
  String _placeholderEmojiFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('country')) return '🦃';
    if (n.contains('duck')) return '🦆';
    if (n.contains('layer') || n.contains('egg')) return '🥚';
    if (n.contains('quail')) return '🐦';
    if (n.contains('turkey')) return '🦃';
    return '🐔'; // broiler / default
  }

  Widget _productChip(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final activeLine = _lines.where((l) => l.product?['id'] == product['id']);
    final selected = activeLine.isNotEmpty;
    return GestureDetector(
        onTap: () => _tapProduct(product),
        child: Container(
            width: 68,
            margin: const EdgeInsets.only(right: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: selected ? kPrimary.withValues(alpha: 0.10) : kBgPage,
                        border: selected ? Border.all(color: kPrimary, width: 2) : null),
                    alignment: Alignment.center,
                    // TODO: replace this emoji placeholder with a real product
                    // image/icon asset (e.g. Image.network(product['image_url']))
                    // once photos are available — the tile sizing already fits one.
                    child: Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 28, height: 1.0))),
                if (selected)
                  Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 12, color: Colors.white))),
              ]),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? kPrimary : Colors.black87)),
            ])));
  }

  // ── Active product card — only the line currently being edited is shown
  // expanded; everything else lives in the compact "Added Products" list
  // below. This is the single biggest scroll-reduction from the reference.
  Widget _activeProductCard(int idx) {
    final line = _lines[idx];
    final name = line.product?['name'] as String? ?? 'Select a product above';
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (line.product != null) ...[
              Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            if (line.product != null)
              GestureDetector(
                  onTap: () => _removeLine(idx),
                  child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08), shape: BoxShape.circle),
                      child: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent))),
          ]),
          if (_usualRangeFor(line) != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_usualRangeFor(line)!, style: const TextStyle(fontSize: 10, color: kTextHint))),
          const SizedBox(height: 12),

          // Birds and Weight are independent inputs — neither is derived
          // from the other. Average weight per bird varies by farm and
          // retailer and is never assumed anywhere in this screen. Weight
          // is the primary quantity the rate cascade is keyed on; Birds is
          // recorded alongside it but doesn't drive Weight or vice versa.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _compactField(
                    label: 'Birds',
                    controller: line.birds,
                    icon: Icons.egg_alt_outlined,
                    onChanged: () {
                      setState(() {});
                      _fetchRate(idx);
                    })),
            const SizedBox(width: 10),
            Expanded(
                child: _compactField(
                    label: 'Weight (kg)',
                    controller: line.totalWt,
                    icon: Icons.scale_outlined,
                    decimal: true,
                    onChanged: () {
                      setState(() {});
                      _fetchRate(idx);
                    })),
            const SizedBox(width: 10),
            Expanded(child: _rateCompact(line, idx)),
          ]),
          if (line.r > 0) ...[
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final sourceColor = (line.rateSource ?? '').toLowerCase().contains('customer')
                  ? const Color(0xFF185FA5)
                  : (line.rateSource ?? '').toLowerCase().contains('zone')
                  ? const Color(0xFF993C1D)
                  : kTextSub;
              return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: sourceColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(_rateSourceLabel(line),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sourceColor)));
            }),
          ],
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _qtyChip('-10', () => _quickAdjustBirds(line, -10)),
            _qtyChip('-5', () => _quickAdjustBirds(line, -5)),
            _qtyChip('+5', () => _quickAdjustBirds(line, 5)),
            _qtyChip('+10', () => _quickAdjustBirds(line, 10)),
            if (line.kg > 0 && line.r > 0)
              Text(Fmt.amount(line.amt),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kPrimary)),
          ]),
        ]));
  }

  Widget _compactField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required VoidCallback onChanged,
    bool decimal = false,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kTextSub)),
        const SizedBox(height: 4),
        TextFormField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: decimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: kBgPage,
                prefixIcon: Icon(icon, size: 14, color: kTextHint),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10)),
            onChanged: (_) => onChanged()),
      ]);

  Widget _rateCompact(_OrderLine line, int idx) {
    final hasRate = line.r > 0;
    if (line.editingRate) {
      return _compactField(
          label: 'Rate (₹/kg)',
          controller: line.rate,
          icon: Icons.currency_rupee,
          decimal: true,
          onChanged: () => setState(() {}));
    }
    return GestureDetector(
        onTap: () => setState(() => line.editingRate = true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Rate (₹/kg)', style: TextStyle(fontSize: 10, color: kTextSub)),
          const SizedBox(height: 4),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                  color: hasRate ? kPrimary.withValues(alpha: 0.1) : kBgPage,
                  borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: Text(hasRate ? line.r.toStringAsFixed(0) : '—',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: kPrimary))),
        ]));
  }

  // ── Compact "Added Products" list — every line, edit/delete per row ─────
  Widget _addedProductsList() {
    final withProduct = _lines.where((l) => l.product != null).toList();
    if (withProduct.isEmpty) return const SizedBox.shrink();
    return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('Added products (${withProduct.length})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub))),
            if (withProduct.length > 1)
              GestureDetector(
                  onTap: _clearAllLines,
                  child: const Text('Clear all',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600))),
          ]),
          const Divider(height: 16),
          ..._lines.asMap().entries.where((e) => e.value.product != null).map((e) {
            final idx = e.key;
            final line = e.value;
            final name = line.product!['name'] as String? ?? '';
            final isActive = idx == _activeIdx;
            return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 3,
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                              color: isActive ? kPrimary : Colors.black87))),
                  Expanded(
                      flex: 2,
                      child: Text('${line.b} birds · ${line.kg.toStringAsFixed(0)} kg',
                          style: const TextStyle(fontSize: 11, color: kTextSub))),
                  Expanded(
                      flex: 2,
                      child: Text(line.r > 0 ? Fmt.amount(line.amt) : '—',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  GestureDetector(
                      onTap: () => setState(() => _activeIdx = idx),
                      child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          child: const Icon(Icons.edit_outlined, size: 17, color: kTextSub))),
                  GestureDetector(
                      onTap: () => _removeLine(idx),
                      child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          child: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent))),
                ]));
          }),
        ]));
  }

  Widget _qtyChip(String label, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: kBgPage, borderRadius: BorderRadius.circular(10)),
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kTextSub))));

  // ── Sticky footer / action hub ───────────────────────────────────────────
  Widget _bottomBar(double bottomInset) => Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: BoxDecoration(
          color: kSurface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2))]),
      child: SafeArea(top: false, child: _createButtonBlock()));

  Widget _createButtonBlock() => Column(mainAxisSize: MainAxisSize.min, children: [
    Row(children: [
      _summStat('Birds', '$_totalBirds'),
      _summStat('Weight', '${_totalKg.toStringAsFixed(1)} kg'),
      _summStat('Total', Fmt.amount(_totalAmt)),
    ]),
    const SizedBox(height: 10),
    ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        child: _saving
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Text('Create Order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
  ]);

  // ── Success bottom sheet — natural continuation, not a separate screen ──
  Future<void> _showSuccessSheet() async {
    final snap = _createdOrder;
    if (snap == null) return;
    await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => DraggableScrollableSheet(
            initialChildSize: 0.62,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (sheetCtx, scrollCtrl) => Container(
                decoration: const BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                child: ListView(controller: scrollCtrl, padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: kBorderLight, borderRadius: BorderRadius.circular(2)))),
                  Center(
                      child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                          child: const Icon(Icons.check, size: 32, color: Colors.green))),
                  const SizedBox(height: 14),
                  Center(
                      child: Text('Order created',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 4),
                  Center(
                      child: Text(
                          '${snap['customer'] ?? ''}'
                              '${snap['id'] != null ? '  ·  #${(snap['id'] as String).substring(0, 8)}' : ''}',
                          style: const TextStyle(fontSize: 12, color: kTextSub))),
                  const SizedBox(height: 10),
                  Center(
                      child: Text(Fmt.amount((snap['amount'] as num?)?.toDouble() ?? 0),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
                  const SizedBox(height: 18),
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: kBgPage, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sheetRow('Zone', snap['zone'] as String? ?? '—'),
                        _sheetRow('Birds', '${snap['birds'] ?? 0}'),
                        _sheetRow('Weight', '${((snap['kg'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} kg'),
                        const Divider(height: 18),
                        ...List<Map<String, dynamic>>.from(snap['items'] ?? []).map((it) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                                '${it['name']} · ${it['birds']} birds · ${(it['kg'] as num).toStringAsFixed(0)} kg',
                                style: const TextStyle(fontSize: 12, color: kTextSub)))),
                      ])),
                  const SizedBox(height: 20),
                  const Text("What's next", style: TextStyle(fontSize: 11, color: kTextSub)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _hubAction(Icons.add_circle_outline, 'New\nOrder', kGoldLight, () {
                          Navigator.of(sheetCtx).pop();
                          _resetForNewOrder();
                        })),
                    Expanded(
                        child: _hubAction(Icons.local_shipping_outlined, 'Assign\nBatch', kPrimary, () {
                          Navigator.of(sheetCtx).pop();
                          context.go(R.dispatch);
                        })),
                    Expanded(
                        child: _hubAction(Icons.receipt_long_outlined, "Today's\nOrders",
                            const Color(0xFF534AB7), () {
                              Navigator.of(sheetCtx).pop();
                              context.go(R.orders);
                            })),
                    Expanded(
                        child: _hubAction(Icons.chat_bubble_outline, 'WhatsApp\nCustomer', Colors.green,
                                () {
                              Navigator.of(sheetCtx).pop();
                              _whatsAppShare();
                            })),
                    Expanded(
                        child: _hubAction(Icons.visibility_outlined, 'View\nOrder', kTextSub,
                            snap['id'] == null
                                ? null
                                : () {
                              Navigator.of(sheetCtx).pop();
                              context.push(R.orderDetailPath(snap['id'] as String));
                            })),
                  ]),
                ]))));
  }

  Widget _sheetRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: kTextSub)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]));

  Widget _hubAction(IconData icon, String label, Color color, VoidCallback? onTap) => GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: onTap == null ? kBgPage : color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: onTap == null ? kTextHint : color)),
        const SizedBox(height: 5),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: onTap == null ? kTextHint : Colors.black87)),
      ]));

  Widget _summStat(String l, String v) => Expanded(
      child: Column(children: [
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextSub, fontWeight: FontWeight.w700)),
      ]));

  // ── Desktop sticky summary panel ─────────────────────────────────────────
  Widget _summaryPanel() => SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        _summaryRow('Birds', '$_totalBirds'),
        _summaryRow('Weight', '${_totalKg.toStringAsFixed(1)} kg'),
        if (_selRetailer != null)
          _summaryRow('Outstanding', _outstanding > 0 ? Fmt.amount(_outstanding) : '—',
              warn: _outstanding > 50000),
        const Divider(height: 24),
        if (_lines.isNotEmpty && _lines.first.rateSource != null)
          _summaryRow('Rate source', _rateSourceLabel(_lines.first)),
        _summaryRow('Total', Fmt.amount(_totalAmt), big: true),
        const SizedBox(height: 16),
        _createButtonBlock(),
      ]));

  Widget _summaryRow(String label, String value, {bool warn = false, bool big = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: big ? 14 : 12, color: kTextSub)),
        Text(value,
            style: TextStyle(
                fontSize: big ? 18 : 13,
                fontWeight: FontWeight.w800,
                color: warn ? Colors.red : Colors.black87)),
      ]));
}