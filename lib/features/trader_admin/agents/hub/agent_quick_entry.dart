import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/common/horizontalscroll_wheel.dart';

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
    required this.onDone,
    required this.onRecoveryNeeded,
  });

  final String agentId;
  final String agentName;
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

class _QuickLine {
  Map<String, dynamic>? product;
  final birdsCtrl = TextEditingController();
  final weightCtrl = TextEditingController();

  int get birds => int.tryParse(birdsCtrl.text.trim()) ?? 0;
  double get weight => double.tryParse(weightCtrl.text.trim()) ?? 0;

  void dispose() {
    birdsCtrl.dispose();
    weightCtrl.dispose();
  }
}

class _AgentQuickEntrySheetState extends ConsumerState<AgentQuickEntrySheet> {
  final _c = Supabase.instance.client;

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _recentRetailers = [];
  Set<String> _favouriteIds = {};
  List<Map<String, dynamic>> _products = [];

  // productId -> {available_birds, available_kg} — fetched once per session;
  // complete_delivery is always the authoritative, final check regardless.
  Map<String, Map<String, num>> _stockByProduct = {};

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
  }

  @override
  void dispose() {
    for (final l in _lines) l.dispose();
    _customerScrollCtrl.dispose();
    _productScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    try {
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
        }),
      ]);

      if (!mounted) return;

      final retailers = List<Map<String, dynamic>>.from(results[0] as List);
      final enabledProducts =
      List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      final history = List<Map<String, dynamic>>.from(results[2] as List? ?? []);
      final stockRows = List<Map<String, dynamic>>.from(results[3] as List? ?? []);

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

      setState(() {
        _retailers = retailers;
        _recentRetailers = recent;
        _favouriteIds = favIds;
        _products = products;
        _stockByProduct = stockMap;
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
  void _selectRetailer(Map<String, dynamic> r) => setState(() => _selRetailer = r);

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
    final totalBirds = (createRes['total_birds'] as num?)?.toInt() ?? _totalBirds;
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
            const SizedBox(height: 18),

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

            _secondaryOptionsRow(),
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
              onChanged: () => setState(() {}),
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
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kTextHint)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
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