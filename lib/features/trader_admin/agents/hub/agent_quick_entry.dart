import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/util/weight_calc.dart';
import '../../../../shared/widgets/common/horizontalscroll_wheel.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AGENT QUICK ENTRY (multi-product)  — formerly "Simple Entry"
//
// Fast proxy-entry path for when a delivery agent is absent/unable to enter
// their own data. This is NOT a new delivery process — it is the exact same
// Order → Order Items → Delivery → Stock validation → Stock movement →
// Delivered → Approval → Invoice → Ledger → Reports pipeline as every other
// order in the app. The only difference is faster data entry.
//
// UI pattern reused verbatim from CreateOrderScreen (create_order_screen.dart):
//   • Favourite/recent customer chips + search-sheet fallback
//   • Horizontal product chips — tapping a chip IS the add action (no
//     separate "+ Add Product" button)
//   • Only the actively-edited product shows an expanded quantity card;
//     every other added product collapses into a compact one-line row
//   • Large, icon-prefixed quantity fields
//
// Flow (ONE atomic creation, then ONE completion call — unchanged from the
// validated design; this file is a UI-only change):
//   agent_create_instant_order_multi  → order + all order_items + batch + delivery
//   complete_delivery                 → stock deduction, status='delivered',
//                                        approval_status stays 'pending'
// Then the existing Approvals screen / approve_delivery_and_order handles
// rate resolution, invoice, and ledger — completely untouched.
//
// Zero business logic here. Quantities entered are the FINAL DELIVERED
// quantities (not "expected" / "ordered" then adjusted later).
// ─────────────────────────────────────────────────────────────────────────────

class AgentQuickEntrySheet extends ConsumerStatefulWidget {
  const AgentQuickEntrySheet({
    super.key,
    required this.agentId,
    required this.agentName,
    required this.batchId,
    required this.batchDate,
    required this.onDone,
    required this.onRecoveryNeeded,
  });

  final String agentId;
  final String agentName;

  // ★ NEW (Batch Date): the active batch, resolved once by Agent Hub before
  // this sheet ever opens (creating it via a date picker if none existed).
  // The backend derives every business date from batchId server-side —
  // batchDate here is display-only, never sent back as a date calculation.
  final String batchId;
  final DateTime batchDate;

  final VoidCallback onDone;

  /// Called when the order/delivery was created successfully but
  /// complete_delivery failed. The sheet has already been popped by the
  /// time this fires, so the caller should navigate using its OWN stable
  /// context (the Hub screen's), not the sheet's — which is being torn down.
  final void Function(String deliveryId) onRecoveryNeeded;

  @override
  ConsumerState<AgentQuickEntrySheet> createState() =>
      _AgentQuickEntrySheetState();
}
/// Allows at most ONE decimal point. If an edit would add a second one,
/// the edit is rejected (field keeps its previous text) and [onInvalid] fires.
class SingleDecimalFormatter extends TextInputFormatter {
  SingleDecimalFormatter({this.onInvalid});
  final VoidCallback? onInvalid;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if ('.'.allMatches(newValue.text).length > 1) {
      onInvalid?.call();
      return oldValue;
    }
    return newValue;
  }
}
class _QuickLine {
  Map<String, dynamic>? product;
  final birdsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  // Customer Rate & Bill Preview — same fields/semantics as CreateOrderScreen's
  // _OrderLine, populated by the same get_effective_rate_v4 RPC (see
  // _fetchRate below). Read-only preview only; no new pricing logic.
  double? suggestRate;
  String? rateSource;
  String? rateSourceLabel;
  String? rateZoneId;
  String? rateZoneName;
  double? baseRate;
  String? pricingType;
  double? adjustmentValue;

  int get birds => int.tryParse(birdsCtrl.text.trim()) ?? 0;
  // Scenario 1 fix: preserves a blank Bird Count field as NULL (distinct
  // from a typed 0) so the sheet-level total can tell "no lines had a count
  // entered" apart from "some lines summed to zero."
  int? get birdsToRecord => int.tryParse(birdsCtrl.text.trim());
  double get weight => double.tryParse(weightCtrl.text.trim()) ?? 0;
  double get estimatedBill => weight * (suggestRate ?? 0);

  void dispose() {
    birdsCtrl.dispose();
    weightCtrl.dispose();
  }
}

class _AgentQuickEntrySheetState extends ConsumerState<AgentQuickEntrySheet> {
  final _c = Supabase.instance.client;
  // ★ Order Remarks — optional, customer-facing, one per order (not
  // per-line, so it lives here on the sheet's state, not on _QuickLine).
  // Quick Entry had no remarks/notes input at all before this.
  final remarksCtrl = TextEditingController();

  // ★ Optional Box Count / Gross / Empty Weight — sheet-level (one
  // physical weighing per delivery, not per product line, per the
  // approved architecture). Blank by default; when both Gross and Empty
  // are filled, the live Net Weight preview uses the shared WeightCalc,
  // and — only when there is exactly ONE line — auto-fills that line's
  // weightCtrl (still manually editable afterward). With 2+ lines this
  // stays informational only; per-line weight entry is unchanged, exactly
  // as today.
  final boxCountCtrl = TextEditingController();
  final grossWeightCtrl = TextEditingController();
  final emptyWeightCtrl = TextEditingController();
  bool _showWeightDetails = false;

  int? get _boxCount => int.tryParse(boxCountCtrl.text.trim());
  double? get _grossWeight => double.tryParse(grossWeightCtrl.text.trim());
  double? get _emptyWeight => double.tryParse(emptyWeightCtrl.text.trim());
  double? get _computedNetWeight =>
      (_grossWeight != null && _emptyWeight != null)
          ? WeightCalc.net(_grossWeight!, _emptyWeight!)
          : null;

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _recentRetailers = [];
  Set<String> _favouriteIds = {};
  List<Map<String, dynamic>> _products = [];

  // productId -> {available_birds, available_kg} — fetched once per session;
  // complete_delivery is always the authoritative, final check regardless.
  Map<String, Map<String, num>> _stockByProduct = {};

  // In-House Stock Preview — trader's stock POINT (agent_id=NULL), distinct
  // from _stockByProduct above (the agent's own carried stock). Populated
  // once at load via the same canonical get_available_stock RPC the
  // Dashboard uses, then read per-product client-side — no extra network
  // call on every Product/Source change, matching "do not affect performance".
  Map<String, Map<String, num>> _inHouseStockByProduct = {};
  // The active batch's source (farm / shop_collection / inhouse_stock),
  // resolved once at load — determines whether the In-House Stock Preview
  // applies to this Quick Entry session at all.
  String? _batchSourceType;

  Map<String, dynamic>? _selRetailer;
  final List<_QuickLine> _lines = [];
  int _activeIdx = -1; // index into _lines currently shown expanded

  String _entryMode = 'called';
  String _payMode = 'credit';
  bool _loading = true;
  bool _submitting = false;
  String? _err;

  final _customerScrollCtrl = ScrollController();
  final _productScrollCtrl = ScrollController();

  static const _entryModes = {
    'called': '📞 Called',
    'whatsapp': '💬 WhatsApp',
    'present': '🧑 Present',
    'estimated': '📊 Estimated',
  };
  static const _payModes = {
    'credit': 'Credit',
    'cash': 'Cash',
    'upi': 'UPI',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-fill Delivered Weight only when the user finishes editing
    // Gross/Empty Weight (focus lost) — see _applyNetWeightAutoFill.
    _grossFocusNode.addListener(() {
      if (!_grossFocusNode.hasFocus) _applyNetWeightAutoFill();
    });
    _emptyFocusNode.addListener(() {
      if (!_emptyFocusNode.hasFocus) _applyNetWeightAutoFill();
    });
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _customerScrollCtrl.dispose();
    _productScrollCtrl.dispose();
    remarksCtrl.dispose();
    boxCountCtrl.dispose();
    grossWeightCtrl.dispose();
    emptyWeightCtrl.dispose();
    _grossFocusNode.dispose();
    _emptyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
      // ★ NEW: current open shift id, so Available Stock reflects the
      // current batch/shift rather than the agent's lifetime stock_ledger.
      String? currentShiftId;
      try {
        final s = await _c
            .from('delivery_shifts')
            .select('id')
            .eq('delivery_agent_id', widget.agentId)
            .eq('status', 'open')
            .maybeSingle()
            .timeout(const Duration(seconds: 8));
        currentShiftId = s?['id'] as String?;
      } catch (_) {}

      final results = await Future.wait<dynamic>([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', tid)
            .eq('is_active', true)
            .order('shop_name'),
        // Trader-enabled products only — SAME RPC CreateOrderScreen uses,
        // same ordering (category, sort_order, name). No shared-function
        // changes: this RPC doesn't return parent_product_id (Create Order
        // never needed it), so it's fetched separately below and merged
        // client-side, scoped only to Quick Entry.
        _c.rpc('get_trader_enabled_products', params: {'p_trader_id': tid}),
        // Read-only, used purely to compute "recent" and "favourite" chips —
        // identical approach to CreateOrderScreen.
        _c
            .from('orders')
            .select('retailer_id,created_at')
            .eq('trader_id', tid)
            .order('created_at', ascending: false)
            .limit(150),
        // One call for ALL products' stock for this agent — used for the
        // family-pooled availability display (see _familyStockFor below).
        _c.rpc('get_available_stock', params: {
          'p_trader_id': tid,
          'p_agent_id': widget.agentId,
          'p_shift_id': currentShiftId,
        }),
        // In-House Stock Preview: same canonical RPC, agent_id=NULL so it
        // resolves the trader's stock POINT balance instead of this
        // agent's own carried stock — identical call shape to how the
        // Dashboard/batch DC screens already show in-house availability.
        _c.rpc('get_available_stock', params: {
          'p_trader_id': tid,
          'p_agent_id': null,
          'p_shift_id': null,
        }),
        // The active batch's source (farm / shop_collection / inhouse_stock)
        // — determines whether the In-House Stock Preview applies.
        _c.from('delivery_batches').select('source_type').eq('id', widget.batchId).maybeSingle(),
      ]);

      if (!mounted) return;

      final retailers = List<Map<String, dynamic>>.from(results[0] as List);
      final enabledProducts =
      List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      final history = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      final stockRows = List<Map<String, dynamic>>.from(results[3] as List? ?? []);
      final inHouseStockRows = List<Map<String, dynamic>>.from(results[4] as List? ?? []);
      final batchRow = results[5] as Map<String, dynamic>?;

      // Quick-Entry-only supplement: parent_product_id for family-pooled
      // stock grouping, scoped strictly to the trader-enabled product IDs
      // just returned — not the whole catalog, and not a change to the
      // shared RPC or to Create Order's data shape.
      Map<String, String?> parentByProductId = {};
      final enabledIds = enabledProducts.map((p) => p['id'] as String).toList();
      if (enabledIds.isNotEmpty) {
        final parentRows = await _c
            .from('master_products')
            .select('id,parent_product_id')
            .inFilter('id', enabledIds);
        parentByProductId = {
          for (final row in List<Map<String, dynamic>>.from(parentRows as List))
            row['id'] as String: row['parent_product_id'] as String?,
        };
      }
      final products = enabledProducts
          .map((p) => {...p, 'parent_product_id': parentByProductId[p['id']]})
          .toList();

      if (!mounted) return;

      final byId = {for (final r in retailers) r['id'] as String: r};
      final seenOrder = <String>[];
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

      final stockMap = <String, Map<String, num>>{
        for (final row in stockRows)
          row['product_id'] as String: {
            'available_birds': (row['available_birds'] as num?) ?? 0,
            'available_kg': (row['available_kg'] as num?) ?? 0,
          }
      };
      final inHouseStockMap = <String, Map<String, num>>{
        for (final row in inHouseStockRows)
          row['product_id'] as String: {
            'in_house_birds': (row['in_house_birds'] as num?) ?? 0,
            'in_house_kg': (row['in_house_kg'] as num?) ?? 0,
          }
      };

      setState(() {
        _retailers = retailers;
        _recentRetailers = recent;
        _favouriteIds = favIds;
        _products = products;
        _stockByProduct = stockMap;
        _inHouseStockByProduct = inHouseStockMap;
        _batchSourceType = batchRow?['source_type'] as String?;
        _loading = false;
      });

      // Default product selection — only on the initial load, before the
      // user has tapped anything. Never overrides a manual selection: this
      // only fires once, right after data loads, while _lines is still empty.
      if (_lines.isEmpty && products.isNotEmpty) {
        final broiler = products.where(
                (p) => (p['name'] as String? ?? '').trim().toLowerCase() == 'broiler');
        _tapProduct(broiler.isNotEmpty ? broiler.first : products.first);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Family helpers ───────────────────────────────────────────────────────
  // Mirrors the DB's own family grouping (COALESCE(parent_product_id, id)),
  // matching exactly how complete_delivery's family-pooled shortage check
  // groups products — so the UI never shows a false warning that ignores
  // sibling stock, and never hides a real shortage the DB would catch.
  String _familyRootId(Map<String, dynamic> product) =>
      (product['parent_product_id'] as String?) ?? product['id'] as String;

  String _familyRootName(String rootId) {
    final root = _products.where((p) => p['id'] == rootId);
    return root.isNotEmpty ? root.first['name'] as String : '';
  }

  /// Family-pooled required vs. available birds for [product]'s family,
  /// counting every active line in that family (not just this one line) and
  /// every sibling product's stock (not just this exact product's stock).
  ({int requiredBirds, int availableBirds, num availableKg}) _familyStockFor(
      Map<String, dynamic> product) {
    final root = _familyRootId(product);
    final familyProductIds =
    _products.where((p) => _familyRootId(p) == root).map((p) => p['id'] as String).toSet();

    final requiredBirds = _lines
        .where((l) => l.product != null && familyProductIds.contains(l.product!['id']))
        .fold<int>(0, (s, l) => s + l.birds);

    final availableBirds = familyProductIds.fold<int>(
        0, (s, pid) => s + ((_stockByProduct[pid]?['available_birds'] ?? 0).toInt()));
    final availableKg = familyProductIds.fold<num>(
        0, (s, pid) => s + (_stockByProduct[pid]?['available_kg'] ?? 0));

    return (requiredBirds: requiredBirds, availableBirds: availableBirds, availableKg: availableKg);
  }

  // ── Customer selection ───────────────────────────────────────────────────
  void _selectRetailer(Map<String, dynamic> r) {
    setState(() => _selRetailer = r);
    // Customer Rate & Bill Preview: refresh every line now that a customer
    // (and therefore a Zone) is known.
    for (int i = 0; i < _lines.length; i++) {
      _fetchRate(i);
    }
  }

  // Customer Rate & Bill Preview — same RPC, same params, same cascade
  // (Zone → Customer Pricing → Product Rate) as CreateOrderScreen's own
  // _fetchRate. No pricing logic is reimplemented here; this only calls the
  // existing get_effective_rate_v4 RPC and stores exactly what it returns.
  Future<void> _fetchRate(int idx) async {
    final line = _lines[idx];
    if (_selRetailer == null || line.product == null) return;
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final kg = line.weight;
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
      if (mounted && rate > 0) {
        setState(() {
          line.suggestRate = rate;
          line.baseRate = (row['base_rate'] as num?)?.toDouble();
          line.rateSource = row['rate_source'] as String? ?? 'default_rate';
          line.rateSourceLabel = row['rate_label'] as String?;
          line.pricingType = row['pricing_type'] as String? ?? 'none';
          line.adjustmentValue = (row['adjustment_value'] as num?)?.toDouble() ?? 0;
          line.rateZoneId = row['zone_id'] as String?;
          line.rateZoneName = row['zone_name'] as String?;
        });
      }
    } catch (_) {}
  }

  String _rateSourceLabel(_QuickLine line) {
    if (line.rateSourceLabel != null && line.rateSourceLabel!.trim().isNotEmpty) {
      return line.rateSourceLabel!;
    }
    return line.rateSource ?? 'Default rate';
  }

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
              borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search customer name',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (q) => setSheet(() {
                  final ql = q.trim().toLowerCase();
                  filtered = ql.isEmpty
                      ? List.from(_retailers)
                      : _retailers
                      .where((r) =>
                      (r['shop_name'] as String? ?? '').toLowerCase().contains(ql))
                      .toList();
                }),
              ),
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
                      },
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Product chip is the ONLY add action — tap adds/reopens, never duplicates ──
  void _tapProduct(Map<String, dynamic> product) {
    final existingIdx = _lines.indexWhere((l) => l.product?['id'] == product['id']);
    if (existingIdx != -1) {
      setState(() => _activeIdx = existingIdx);
      return;
    }
    setState(() {
      _lines.add(_QuickLine()..product = product);
      _activeIdx = _lines.length - 1;
    });
    _fetchRate(_lines.length - 1);
  }

  void _removeLine(int idx) {
    final removed = _lines[idx];
    setState(() {
      _lines.removeAt(idx);
      if (_activeIdx >= _lines.length) _activeIdx = _lines.length - 1;
    });
    removed.dispose();
  }

  double get _totalWeight => _lines.fold(0.0, (s, l) => s + l.weight);
  int get _totalBirds => _lines.fold(0, (s, l) => s + l.birds);
  // Scenario 1 fix: null only when every line's Bird Count is blank; if at
  // least one line has a value, sum with blank lines treated as 0 — same
  // rule as the single-delivery screens, applied across lines.
  int? get _totalBirdsToRecord {
    final anyEntered = _lines.any((l) => l.birdsCtrl.text.trim().isNotEmpty);
    return anyEntered ? _totalBirds : null;
  }

  // ★ NEW: Possible-duplicate confirmation dialog — never blocks, just warns.
  Future<bool?> _showDuplicateOrderDialog(Map<String, dynamic> d) {
    final createdAt = DateTime.tryParse(d['created_at'] as String? ?? '');
    final timeStr = createdAt != null
        ? DateFormat('dd MMM, hh:mm a').format(createdAt.toLocal())
        : '—';
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        title: const Row(children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Possible Duplicate Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A similar order was created recently.',
                style: TextStyle(fontSize: 13, color: kTextSub, height: 1.4)),
            const SizedBox(height: 12),
            _dupRow('Order No', '${d['order_no']}'),
            _dupRow('Retailer', '${d['retailer_name']}'),
            _dupRow('Time', timeStr),
            _dupRow('Product(s)', (d['products'] as String? ?? '').isEmpty ? '—' : '${d['products']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(false),
            child: const Text('Cancel', style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(c, rootNavigator: true).pop(true),
            child: const Text('Create New Order', style: TextStyle(color: kNavy, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _dupRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: kTextHint))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );

  Future<void> _submit() async {
    setState(() => _err = null);

    if (_selRetailer == null) {
      setState(() => _err = 'Select a customer');
      return;
    }
    final activeLines = _lines.where((l) => l.product != null).toList();
    if (activeLines.isEmpty) {
      setState(() => _err = 'Tap a product to add it');
      return;
    }
    for (final l in activeLines) {
      if (l.weight <= 0) {
        setState(() => _err = 'Enter delivered weight for ${l.product!['name']}');
        return;
      }
      // ★ FIX (Close Shift "0 birds / weight" audit): a BLANK Bird Count
      // is a legitimate, existing, supported workflow — it means "not
      // counted yet," recorded as NULL and flagged as "unconfirmed" at
      // shift-approval time (see approve_shift's own
      // unconfirmed_delivery_count handling) so the agent can fill it in
      // later. That is NOT what this blocks. This blocks the different,
      // invalid case: the agent explicitly TYPED "0" into Bird Count
      // while a real, nonzero Weight was also entered — a nonsensical
      // combination (weight without any birds) that previously reached
      // complete_delivery as a real, recorded zero (not the unconfirmed
      // NULL), silently inflating every downstream total that summed
      // delivered weight.
      if (l.birdsCtrl.text.trim().isNotEmpty && l.birds <= 0) {
        setState(() => _err =
        '${l.product!['name']}: Bird Count can\'t be 0 when Weight is entered. '
            'Leave Bird Count blank if it genuinely hasn\'t been counted yet, '
            'or enter the real count.');
        return;
      }
    }

    // Defensive re-check: every selected product must still be trader-
    // enabled at submit time. Chips only ever come from the trader-enabled
    // list, so this only matters if the trader disabled a product mid-
    // session (long-open sheet) — cheap, in-memory check, no extra RPC.
    final enabledIds = _products.map((p) => p['id']).toSet();
    final disabled = activeLines.where((l) => !enabledIds.contains(l.product!['id'])).toList();
    if (disabled.isNotEmpty) {
      setState(() => _err =
      '${disabled.first.product!['name']} is no longer enabled for this trader. Remove it and retry.');
      return;
    }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user == null) return;

    final itemSummary = activeLines
        .map((l) =>
    '${l.product!['name']}: ${l.birds > 0 ? '${l.birds} birds, ' : ''}${l.weight.toStringAsFixed(1)} kg')
        .join('\n');

    final ok = await confirmDialog(
      context,
      title: 'Complete Delivery',
      message: '${_selRetailer!['shop_name']}\n\n$itemSummary\n\n'
          'Payment: ${_payModes[_payMode]}\n'
          'Acting on behalf of ${widget.agentName}.',
      confirmText: 'Complete',
      confirmColor: kNavy,
    );
    if (!ok || !mounted) return;

    // ★ NEW (duplicate-order audit): warn, never block.
    try {
      final totalBirds = activeLines.fold<int>(0, (s, l) => s + l.birds);
      final dup = await _c.rpc('check_duplicate_order', params: {
        'p_trader_id': ref.read(appUserProvider).valueOrNull?.traderId,
        'p_retailer_id': _selRetailer!['id'],
        'p_product_id': activeLines.first.product!['id'],
        'p_estimated_birds': totalBirds,
      });
      final d = (dup as Map?)?.cast<String, dynamic>();
      if (d?['is_duplicate'] == true) {
        final proceed = await _showDuplicateOrderDialog(d!);
        if (proceed != true) return;
      }
    } catch (_) {
      // Pre-check failing should never block order creation.
    }

    setState(() => _submitting = true);

    // ── Step 1: atomic creation (order + all order_items + batch + delivery) ──
    Map<String, dynamic> createRes;
    try {
      final res = await _c.rpc('agent_create_instant_order_multi', params: {
        'p_agent_id': widget.agentId,
        'p_retailer_id': _selRetailer!['id'],
        'p_items': activeLines
            .map((l) => {
          'product_id': l.product!['id'],
          'birds': l.birds > 0 ? l.birds : null,
          'weight_kg': l.weight,
        })
            .toList(),
        'p_payment_mode': _payMode,
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
        // ★ NEW (Batch Date): the active batch is the single source of
        // truth for the business date — no date is computed or sent from
        // Flutter. The backend looks up batch_date from this batchId.
        'p_batch_id': widget.batchId,
        if (remarksCtrl.text.trim().isNotEmpty) 'p_remarks': remarksCtrl.text.trim(),
      });
      createRes = Map<String, dynamic>.from(res as Map);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _err = _cleanError(e);
        });
      }
      return; // Nothing was created — atomic RPC rolled back entirely.
    }

    final deliveryId = createRes['delivery_id'] as String;
    final totalBirds = (createRes['total_birds'] as num?)?.toInt() ?? _totalBirdsToRecord;
    final totalWeight = (createRes['total_weight'] as num?)?.toDouble() ?? _totalWeight;

    // ── Step 2: complete the delivery (stock deduction, status=delivered) ──
    try {
      await _c.rpc('complete_delivery', params: {
        'p_delivery_id': deliveryId,
        'p_birds_delivered': totalBirds,
        'p_delivered_total_weight': totalWeight,
        'p_payment_mode': _payMode,
        'p_collected_amount': 0,
        'p_mortality_birds': 0,
        'p_returned_birds': 0,
        'p_returned_weight': 0,
        'p_shrinkage_kg': 0,
        'p_rejected_birds': 0,
        'p_crates_dropped': 0,
        'p_crates_collected': 0,
        'p_crates_returned': 0,
        'p_is_partial': false,
        'p_remaining_action': 'same',
        'p_actor_type': 'trader',
        'p_actor_id': user.userId,
        'p_entry_mode': _entryMode,
        // Optional Box Count / Gross / Empty Weight — pure passthrough
        // storage (see complete_delivery's own comment on these params).
        // Omitted/null when the trader never touched these fields, which
        // is the existing flow, unchanged.
        if (_boxCount != null) 'p_box_count': _boxCount,
        if (_grossWeight != null) 'p_gross_weight_kg': _grossWeight,
        if (_emptyWeight != null) 'p_empty_weight_kg': _emptyWeight,
      });

      if (mounted) {
        showSuccess(
            context,
            '✅ Delivery completed for ${widget.agentName}\n'
                '${_selRetailer!['shop_name']} — ${activeLines.length} product(s)');
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
      }
    } catch (e) {
      // ── Recovery: order + delivery + all order_items DID get created
      //    successfully (step 1 committed). Only completion failed — most
      //    likely insufficient stock discovered at this later, authoritative
      //    check. Do not lose the order: hand off to the Hub, which will
      //    navigate to the full Record Delivery screen for this exact
      //    delivery using ITS OWN context (this sheet's context is about to
      //    be torn down by the pop below). ────────────────────────────────
      if (mounted) {
        setState(() => _submitting = false);
        await confirmDialog(
          context,
          title: 'Order created — delivery not completed',
          message: '${_selRetailer!['shop_name']}\'s order was created, but the '
              'delivery could not be completed:\n\n${_cleanError(e)}\n\n'
              'Finish it from Record Delivery.',
          confirmText: 'Open Record Delivery',
          confirmColor: Colors.orange,
        );
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDone();
        widget.onRecoveryNeeded(deliveryId);
      }
      return;
    }

    if (mounted) setState(() => _submitting = false);
  }
    void _showDecimalWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Please type a valid weight. Only one decimal point is allowed (e.g. 75.3)'),
        duration: Duration(seconds: 2),
      ));
  }
  String _cleanError(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('PostgrestException(message: ', '')
      .replaceAll(')', '');

  String _placeholderEmojiFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('country')) return '🦃';
    if (n.contains('duck')) return '🦆';
    if (n.contains('layer') || n.contains('egg')) return '🥚';
    if (n.contains('quail')) return '🐦';
    if (n.contains('turkey')) return '🦃';
    return '🐔';
  }

  Color _colorFor(String name) {
    final colors = [kNavy, const Color(0xFF185FA5), const Color(0xFF993C1D), Colors.teal];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration:
                BoxDecoration(color: kBorderLight, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: kNavy, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quick Entry',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text('For ${widget.agentName}',
                          style: const TextStyle(fontSize: 12, color: kTextHint)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ★ NEW (Batch Date): prominent, always-visible — every order
            // created in this sheet inherits this exact date, decided by
            // the backend from widget.batchId. Highlighted when backdated
            // so it's never mistaken for today's entry.
            Builder(builder: (_) {
              final isToday = DateUtils.isSameDay(widget.batchDate, DateTime.now());
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (isToday ? kNavy : Colors.orange).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: isToday ? kNavy.withValues(alpha: 0.2) : Colors.orangeAccent),
                ),
                child: Row(children: [
                  Icon(Icons.event_outlined, size: 16, color: isToday ? kNavy : Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Text(
                    'Batch Date: ${DateFormat('dd MMM yyyy').format(widget.batchDate)}'
                        '${isToday ? '' : '  •  Backdated entry'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isToday ? kNavy : Colors.orange.shade800,
                    ),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 8),

            _customerSection(),
            const SizedBox(height: 18),

            _productSection(),
            const SizedBox(height: 8),

            ..._lines.asMap().entries.map((e) => e.key == _activeIdx
                ? _activeProductCard(e.key)
                : _collapsedProductRow(e.key)),

            if (_totalBirds > 0 || _totalWeight > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(kRadiusInner),
                ),
                child: Text(
                  'Total: $_totalBirds birds · ${_totalWeight.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: kNavy),
                ),
              ),
            ],
            const SizedBox(height: 16),

            _weightDetailsSection(),
            const SizedBox(height: 16),

            _secondaryOptionsRow(),
            const SizedBox(height: 12),
            TextField(
              controller: remarksCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Remarks (optional)',
                alignLabelWithHint: true,
                filled: true,
                fillColor: kBgPage,
                prefixIcon: const Icon(Icons.notes_outlined, size: 16, color: kTextHint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 18),

            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kErrorBg,
                    borderRadius: BorderRadius.circular(kRadiusInner),
                  ),
                  child:
                  Text(_err!, style: const TextStyle(fontSize: 12, color: kError)),
                ),
              ),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy,
                  shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusBtn)),
                ),
                child: _submitting
                    ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Complete Delivery',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Customer: favourite/recent chips + search fallback (reused pattern) ──
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('CUSTOMER'),
        const SizedBox(height: 6),
        // Search moved to the top — tap opens the same search sheet as
        // before; recent/favourite chips sit below for one-tap selection.
        GestureDetector(
          onTap: _openSearchSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kBgPage,
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: kBorderLight),
            ),
            child: const Row(children: [
              Icon(Icons.search, size: 18, color: kTextHint),
              SizedBox(width: 8),
              Text('Search customer…',
                  style: TextStyle(fontSize: 13, color: kTextHint)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        if (_retailers.isEmpty)
          const Text('No customers found.', style: TextStyle(color: kTextHint, fontSize: 12))
        else
          SizedBox(
            height: 82,
            child: HorizontalScrollWheel(
              controller: _customerScrollCtrl,
              child: ListView(
                controller: _customerScrollCtrl,
                scrollDirection: Axis.horizontal,
                children: chips.map(_customerChip).toList(),
              ),
            ),
          ),
        if (_selRetailer != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Selected: ${_selRetailer!['shop_name']}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
          ),
      ],
    );
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
                border: Border.all(color: selected ? kNavy : Colors.transparent, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(_initialsFor(name),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: _colorFor(name))),
            ),
            if (isFav)
              const Positioned(
                  top: -2, right: -2, child: Icon(Icons.star, size: 13, color: kGoldLight)),
          ]),
          const SizedBox(height: 4),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Products: chips ARE the add action; active card + collapsed rows ────
  Widget _productSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeader('PRODUCTS — TAP TO ADD'),
      const SizedBox(height: 6),
      if (_products.isEmpty)
        const Text('No products found.', style: TextStyle(color: kTextHint, fontSize: 12))
      else
        SizedBox(
          height: 88,
          child: HorizontalScrollWheel(
            controller: _productScrollCtrl,
            child: ListView(
              controller: _productScrollCtrl,
              scrollDirection: Axis.horizontal,
              children: _products.map(_productChip).toList(),
            ),
          ),
        ),
      if (_products.length > 5)
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('Swipe to see more →',
              style: TextStyle(fontSize: 10, color: kTextHint)),
        ),
    ],
  );

  Widget _productChip(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final selected = _lines.any((l) => l.product?['id'] == product['id']);
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
                color: selected ? kNavy.withValues(alpha: 0.10) : kBgPage,
                border: selected ? Border.all(color: kNavy, width: 2) : null,
              ),
              alignment: Alignment.center,
              child: Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 28, height: 1.0)),
            ),
            if (selected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(color: kNavy, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: selected ? kNavy : Colors.black87)),
        ]),
      ),
    );
  }

  // ── Active (expanded) product card — Birds + Delivered Weight, family-
  //    pooled stock display (never a false warning from exact-product alone) ──
  Widget _activeProductCard(int idx) {
    final line = _lines[idx];
    final product = line.product;
    if (product == null) return const SizedBox.shrink();
    final name = product['name'] as String;
    final family = _familyStockFor(product);
    final short = family.requiredBirds > family.availableBirds;
    final rootName = _familyRootName(_familyRootId(product));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          GestureDetector(
            onTap: () => _removeLine(idx),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration:
              BoxDecoration(color: Colors.red.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _compactField(
              label: 'Birds',
              controller: line.birdsCtrl,
              icon: Icons.egg_alt_outlined,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _compactField(
              label: 'Delivered Weight (kg)',
              controller: line.weightCtrl,
              icon: Icons.scale_outlined,
              decimal: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                SingleDecimalFormatter(onInvalid: _showDecimalWarning),
              ],
              onChanged: () {
                setState(() {});
                _fetchRate(idx);
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          rootName.isNotEmpty && rootName != name
              ? 'Available for $rootName group: ${family.availableBirds} birds · '
              '${family.availableKg.toStringAsFixed(1)} kg'
              : 'Available: ${family.availableBirds} birds · ${family.availableKg.toStringAsFixed(1)} kg',
          style: TextStyle(
            fontSize: 11,
            color: short ? kError : kTextHint,
            fontWeight: short ? FontWeight.w700 : FontWeight.normal,
          ),
        ),

        // In-House Stock Preview — only relevant when this batch's stock
        // came from the trader's own in-house stock point. Read-only,
        // reuses the same get_available_stock data already loaded for
        // every product at session start (no extra call per keystroke).
        if (_batchSourceType == 'inhouse_stock') ...[
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final inHouse = _inHouseStockByProduct[product['id']];
            final birds = (inHouse?['in_house_birds'] ?? 0).toInt();
            final kg = (inHouse?['in_house_kg'] ?? 0).toDouble();
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.circular(kRadiusInner),
                border: Border.all(color: kBorderLight),
              ),
              child: Row(children: [
                const Icon(Icons.home_work_outlined, size: 14, color: kTextHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('In-House Stock — $birds Birds · ${kg.toStringAsFixed(2)} Kg',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: kTextSub)),
                ),
              ]),
            );
          }),
        ],

        // Customer Rate & Bill Preview — same cascade/labels as Order
        // Creation (Zone → Customer Pricing → Product Rate), via the same
        // get_effective_rate_v4 RPC. Read-only preview only.
        if (_selRetailer != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(kRadiusInner),
              border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('Rate Source: ${_rateSourceLabel(line)}',
                      style: const TextStyle(fontSize: 11, color: kTextSub)),
                ),
                Text(
                  line.suggestRate != null
                      ? '₹${line.suggestRate!.toStringAsFixed(2)}/kg'
                      : '—',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Expanded(
                  child: Text('Estimated Bill', style: TextStyle(fontSize: 11, color: kTextSub)),
                ),
                Text(
                  line.suggestRate != null ? Fmt.amount(line.estimatedBill) : '—',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900, color: kNavy),
                ),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Collapsed row for every already-added product not currently active ───
  Widget _collapsedProductRow(int idx) {
    final line = _lines[idx];
    final product = line.product;
    if (product == null) return const SizedBox.shrink();
    final name = product['name'] as String;
    return GestureDetector(
      onTap: () => setState(() => _activeIdx = idx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
        ),
        child: Row(children: [
          Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$name — ${line.birds > 0 ? '${line.birds} birds · ' : ''}'
                '${line.weight.toStringAsFixed(1)} kg'),
          ),
          IconButton(
            onPressed: () => setState(() => _activeIdx = idx),
            icon: const Icon(Icons.edit_outlined, size: 18, color: kTextHint),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _removeLine(idx),
            icon: const Icon(Icons.close_rounded, size: 18, color: kTextHint),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
      ),
    );
  }

  Widget _compactField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required VoidCallback onChanged,
    bool decimal = false,
    FocusNode? focusNode,
    List<TextInputFormatter>? inputFormatters, 
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kTextHint)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          focusNode: focusNode,
          inputFormatters: inputFormatters,
          textAlign: TextAlign.center,
          keyboardType:
          decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: kBgPage,
            prefixIcon: Icon(icon, size: 14, color: kTextHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (_) => onChanged(),
        ),
      ]);

  // ── Optional Box Count / Gross / Empty Weight — sheet-level (one per
  // delivery), collapsed by default so the existing flow is visually
  // unchanged unless the trader opts in. Reuses the shared WeightCalc,
  // the same calculation batch_pickup_screen.dart's Delivery Challan
  // entry already uses. ─────────────────────────────────────────────────
  // Focus nodes for Gross/Empty Weight — the auto-fill into Delivered
  // Weight only fires on focus-LOSS (see below), never mid-keystroke.
  // Setting a DIFFERENT TextField's controller.text while the user is
  // actively typing in this field was causing the platform's keyboard/
  // text-input connection to reattach to whichever field's text just
  // changed — stealing focus away after a single character. The live
  // "Net = Gross − Empty" preview line still updates on every keystroke
  // (it's a plain Text rebuild, not a controller mutation, so it's safe).
  final FocusNode _grossFocusNode = FocusNode();
  final FocusNode _emptyFocusNode = FocusNode();

  void _onGrossEmptyChanged() {
    // Live preview text only — no controller mutation here.
    setState(() {});
  }

  void _applyNetWeightAutoFill() {
    final net = _computedNetWeight;
    if (net != null && _lines.length == 1) {
      setState(() {
        _lines[0].weightCtrl.text = net.toStringAsFixed(2);
        _fetchRate(0);
      });
    }
  }

  Widget _weightDetailsSection() {
    if (!_showWeightDetails) {
      return InkWell(
        onTap: () => setState(() => _showWeightDetails = true),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.add_circle_outline, size: 16, color: kTextHint),
            SizedBox(width: 6),
            Text('Add Box / Gross / Empty Weight (optional)',
                style: TextStyle(fontSize: 12, color: kTextHint, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }
    final net = _computedNetWeight;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kBgPage,
        borderRadius: BorderRadius.circular(kRadiusInner),
        border: Border.all(color: kBorderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Box / Gross / Empty Weight',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub)),
          const Spacer(),
          InkWell(
            onTap: () => setState(() {
              _showWeightDetails = false;
              boxCountCtrl.clear();
              grossWeightCtrl.clear();
              emptyWeightCtrl.clear();
            }),
            child: const Icon(Icons.close, size: 16, color: kTextHint),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: _compactField(
              label: 'Boxes',
              controller: boxCountCtrl,
              icon: Icons.inventory_2_outlined,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(
              label: 'Gross (kg)',
              controller: grossWeightCtrl,
              icon: Icons.scale_outlined,
              decimal: true,
              onChanged: _onGrossEmptyChanged,
              focusNode: _grossFocusNode,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _compactField(
              label: 'Empty (kg)',
              controller: emptyWeightCtrl,
              icon: Icons.remove_circle_outline,
              decimal: true,
              onChanged: _onGrossEmptyChanged,
              focusNode: _emptyFocusNode,
            ),
          ),
        ]),
        if (net != null) ...[
          const SizedBox(height: 8),
          Text(
            'Net = ${_grossWeight!.toStringAsFixed(2)} − ${_emptyWeight!.toStringAsFixed(2)} = ${net.toStringAsFixed(2)} kg'
                '${_lines.length == 1 ? ' (auto-filled into Delivered Weight below)' : _lines.length > 1 ? ' — split manually per product below' : ''}',
            style: const TextStyle(fontSize: 11, color: kNavy, fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    );
  }

  // ── Entry Mode + Payment Mode — compact, secondary, single row ──────────
  Widget _secondaryOptionsRow() {
    return Row(children: [
      Expanded(child: _secondaryPill(label: 'Reported', value: _entryModes[_entryMode]!, options: _entryModes, current: _entryMode, onSelect: (v) => setState(() => _entryMode = v))),
      const SizedBox(width: 10),
      Expanded(child: _secondaryPill(label: 'Payment', value: _payModes[_payMode]!, options: _payModes, current: _payMode, onSelect: (v) => setState(() => _payMode = v))),
    ]);
  }

  Widget _secondaryPill({
    required String label,
    required String value,
    required Map<String, String> options,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelect,
      itemBuilder: (_) => options.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kBgPage,
          borderRadius: BorderRadius.circular(kRadiusInner),
          border: Border.all(color: kBorderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 9, color: kTextHint)),
              Text(value,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kNavy)),
            ]),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: kTextHint),
        ]),
      ),
    );
  }
}