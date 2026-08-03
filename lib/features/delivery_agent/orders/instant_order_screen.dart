import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Instant Order Screen — Delivery Agent (v3 — multi-product)
//
// IMPORTANT ARCHITECTURE NOTE — read before touching this file further:
// agent_create_instant_order takes a single p_product_id and creates ONE
// order + ONE delivery per call (confirmed: every call site in this codebase,
// including the trader-assisted version in agent_assistance_hub_screen.dart,
// passes exactly one product). There is no bulk/array variant. Since backend
// logic must stay unchanged, "multiple products" here means the agent adds
// several product lines in one screen, and on submit this calls the RPC
// once per line, sequentially, for the same retailer — which creates that
// many SEPARATE orders and SEPARATE deliveries, not one delivery carrying
// several line items. That's a real operational consequence (the agent will
// see N delivery tasks, not 1), not just a UI detail — flagging it plainly
// rather than papering over it.
//
// PRESERVED EXACTLY FROM v1/v2 (no other business logic changes):
//   • Retailer required, each line's Product required, Weight required,
//     Birds optional
//   • Pricing stays hidden from the agent — no rate field, no total shown,
//     p_rate_per_kg is never sent (RPC defaults it to NULL); the selling
//     rate is resolved later at Trader Approval via get_effective_rate_v4
//   • agent_create_instant_order RPC call and all its params, unchanged
//   • Shift-gating: an open delivery_shifts row is required before this
//     form is usable at all
//   • No average weight is ever assumed or displayed anywhere
//
// WHAT'S NEW IN v3:
//   • Multiple product lines, added by tapping product chips (same product
//     tapped twice reopens that line instead of duplicating it)
//   • Sequential submission, one RPC call per line. If a call fails partway
//     through, earlier successful calls are NOT rolled back (no compensating
//     RPC exists) — the error message says exactly how many succeeded before
//     the failure so the agent isn't left guessing.
//   • Navigation after submit: if exactly one line was submitted (the
//     original single-product case), behaviour is identical to before —
//     straight to that delivery. If multiple lines were submitted, goes to
//     the agent's Deliveries list instead, since there's no longer one
//     single delivery to land on.
// ─────────────────────────────────────────────────────────────────────────────

class _AgentLine {
  Map<String, dynamic>? product;
  final birds = TextEditingController();
  final weight = TextEditingController();

  int get b => int.tryParse(birds.text.trim()) ?? 0;
  double get kg => double.tryParse(weight.text.trim()) ?? 0;

  void dispose() {
    birds.dispose();
    weight.dispose();
  }
}

class InstantOrderScreen extends ConsumerStatefulWidget {
  const InstantOrderScreen({super.key});
  @override
  ConsumerState<InstantOrderScreen> createState() => _S();
}

class _S extends ConsumerState<InstantOrderScreen> {
  final _c = Supabase.instance.client;
  final _notesCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _localMessengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _loading = true;
  bool _submitting = false;
  bool _hasShift = false;

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _selRetailer;
  String _payMode = 'cash';
  String? _err;

  List<_AgentLine> _lines = [_AgentLine()];
  int _activeIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _localMessengerKey.currentState?.clearSnackBars();
    _notesCtrl.dispose();
    _scrollCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(appUserProvider).valueOrNull;
    final agentId = user?.agentId;
    final traderId = user?.traderId;
    if (agentId == null || traderId == null) {
      if (mounted) setState(() {
        _loading = false;
        _hasShift = false;
      });
      return;
    }
    try {
      final shift = await _c
          .from('delivery_shifts')
          .select('id')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();
      if (shift == null) {
        if (mounted) setState(() {
          _loading = false;
          _hasShift = false;
        });
        return;
      }
      final results = await Future.wait<dynamic>([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', traderId)
            .eq('is_active', true)
            .order('shop_name'),
        _c.from('master_products').select('id,name,unit').eq('is_active', true).order('name'),
      ]);
      if (!mounted) return;
      setState(() {
        _hasShift = true;
        _retailers = List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _hasShift = false;
      });
    }
  }

  int get _totalBirds => _lines.fold(0, (s, l) => s + l.b);
  double get _totalKg => _lines.fold(0.0, (s, l) => s + l.kg);

  void _tapProduct(Map<String, dynamic> product) {
    final existingIdx = _lines.indexWhere((l) => l.product?['id'] == product['id']);
    if (existingIdx != -1) {
      setState(() => _activeIdx = existingIdx);
      return;
    }
    final emptyIdx = _lines.indexWhere((l) => l.product == null);
    if (emptyIdx != -1) {
      setState(() {
        _lines[emptyIdx].product = product;
        _activeIdx = emptyIdx;
      });
    } else {
      setState(() {
        _lines.add(_AgentLine()..product = product);
        _activeIdx = _lines.length - 1;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      }
    });
  }

  void _removeLine(int idx) {
    final removed = _lines[idx];
    final wasOnlyLine = _lines.length == 1;
    setState(() {
      _lines.removeAt(idx);
      if (wasOnlyLine) _lines.add(_AgentLine());
      if (_activeIdx >= _lines.length) _activeIdx = _lines.length - 1;
      if (_activeIdx < 0) _activeIdx = 0;
    });
    removed.dispose();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2), content: Text('Product removed')));
  }

  // ★ NEW: Possible-duplicate confirmation dialog — never blocks, just
  // warns. Returns true if the trader/agent chooses to proceed anyway.
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
        title: Row(children: const [
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
      setState(() => _err = 'Select a retailer');
      return;
    }
    final validLines = _lines.where((l) => l.product != null).toList();
    if (validLines.isEmpty) {
      setState(() => _err = 'Select at least one product');
      return;
    }
    for (int i = 0; i < validLines.length; i++) {
      if (validLines[i].kg <= 0) {
        setState(() => _err = 'Enter weight for ${validLines[i].product!['name']}');
        return;
      }
    }

    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (agentId == null) return;

    // ★ NEW (duplicate-order audit): checked once for all lines before any
    // creation happens — if any line looks like a recent duplicate, the
    // trader/agent sees one warning up front rather than a mix of some
    // lines already created and others not. Never blocks; the check
    // failing silently is treated as "no duplicate" so submission is
    // never held up by it.
    if (traderId != null) {
      for (final line in validLines) {
        try {
          final dup = await _c.rpc('check_duplicate_order', params: {
            'p_trader_id': traderId,
            'p_retailer_id': _selRetailer!['id'],
            'p_product_id': line.product!['id'],
            'p_estimated_birds': line.b,
          });
          final d = (dup as Map?)?.cast<String, dynamic>();
          if (d?['is_duplicate'] == true) {
            final proceed = await _showDuplicateOrderDialog(d!);
            if (proceed != true) return;
            break; // one confirmation covers the whole batch
          }
        } catch (_) {
          // Pre-check failing should never block order creation.
        }
      }
    }

    if (mounted) setState(() => _submitting = true);
    final createdDeliveryIds = <String>[];
    String? retailerName;
    try {
      for (final line in validLines) {
        // p_rate_per_kg intentionally omitted — defaults to NULL in DB.
        // order_items created with rate_per_kg=NULL (same as normal orders).
        // approve_delivery_and_order resolves zone rate via get_effective_rate_v4.
        final res = await _c.rpc('agent_create_instant_order', params: {
          'p_agent_id': agentId,
          'p_retailer_id': _selRetailer!['id'],
          'p_product_id': line.product!['id'],
          'p_birds': line.b > 0 ? line.b : null,
          'p_weight_kg': line.kg,
          'p_payment_mode': _payMode,
          'p_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          'p_remarks': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        });
        final result = res as Map<String, dynamic>;
        retailerName = result['retailer_name'] as String? ?? retailerName;
        final deliveryId = result['delivery_id'] as String?;
        if (deliveryId != null) createdDeliveryIds.add(deliveryId);
      }

      if (!mounted) return;
      final n = validLines.length;
      showSuccess(context,
          n == 1
              ? 'Instant order created!\n$retailerName · ${validLines.first.kg.toStringAsFixed(2)} kg'
              : '$n instant orders created for $retailerName');

      if (createdDeliveryIds.length == 1) {
        context.push(R.deliveryDonePath(createdDeliveryIds.first));
      } else if (createdDeliveryIds.length > 1) {
        context.go(R.agentDeliveries);
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go(R.agentDeliveries);
      }
    } catch (e) {
      final msg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');
      if (mounted) setState(() {
        _err = createdDeliveryIds.isEmpty
            ? msg
            : '${createdDeliveryIds.length} of ${validLines.length} orders created before this failed: $msg';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI helpers ───────────────────────────────────────────────────────────
  static const _palette = [
    Color(0xFFEA580C), Color(0xFF0F6E56), Color(0xFF993C1D),
    Color(0xFF534AB7), Color(0xFF185FA5), kGoldLight,
  ];
  Color _colorFor(String seed) => _palette[seed.hashCode.abs() % _palette.length];

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  String _placeholderEmojiFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('country')) return '🦃';
    if (n.contains('duck')) return '🦆';
    if (n.contains('layer') || n.contains('egg')) return '🥚';
    if (n.contains('quail')) return '🐦';
    return '🐔';
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
      key: _localMessengerKey,
      child: Scaffold(
          backgroundColor: kBgPage,
          appBar: AppBar(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(R.agentHome);
                    }
                  }),
              title: const Text('Instant Order'),
              actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
          body: _loading
              ? const LoadingList()
              : !_hasShift
              ? _buildNoShift()
              : _buildForm()));

  Widget _buildNoShift() => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_clock_outlined, size: 64, color: kTextHint),
            const SizedBox(height: 16),
            const Text('Shift Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Open a shift first before creating instant orders.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kTextSub)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
                onPressed: () => context.go(R.shiftOpen),
                icon: const Icon(Icons.schedule),
                label: const Text('Open Shift')),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(R.agentHome);
                  }
                },
                child: const Text('Back to Home')),
          ])));

  Widget _buildForm() => Column(children: [
    Expanded(
        child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.2))),
                  child: Row(children: [
                    const Icon(Icons.electric_bolt, color: Color(0xFFEA580C), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Instant Order Mode',
                              style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEA580C), fontSize: 13)),
                          Text('Rate will be confirmed by trader at approval.',
                              style: TextStyle(fontSize: 11, color: kTextSub)),
                        ])),
                    Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Shift Active',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                  ])),

              if (_err != null)
                Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration:
                    BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(kRadiusCard)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: kError, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_err!, style: const TextStyle(color: kError, fontSize: 13))),
                    ])),

              const SectionHeader('Retailer'),
              const SizedBox(height: 6),
              _retailers.isEmpty
                  ? Container(
                  padding: const EdgeInsets.all(14),
                  decoration:
                  BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Text('No retailers found. Ask admin to add retailers.',
                      style: TextStyle(color: Colors.deepOrange)))
                  : SizedBox(
                  height: 82,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ..._retailers.map((r) => _retailerChip(r)),
                        _searchRetailerChip(),
                      ])),
              if (_selRetailer?['address'] != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: kTextSub),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(_selRetailer!['address'] as String,
                              style: const TextStyle(fontSize: 11, color: kTextSub))),
                    ])),
              const SizedBox(height: 18),

              Row(children: [
                const Expanded(child: SectionHeader('Products — tap to add')),
                TextButton.icon(
                    onPressed: () => setState(() {
                      _lines.add(_AgentLine());
                      _activeIdx = _lines.length - 1;
                    }),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Add Product', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEA580C),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32))),
              ]),
              const SizedBox(height: 6),
              _products.isEmpty
                  ? const SizedBox.shrink()
                  : SizedBox(
                  height: 88,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _products.map((p) => _productChip(p)).toList())),
              const SizedBox(height: 18),

              const SectionHeader('Order lines'),
              const SizedBox(height: 6),
              _activeLineCard(_activeIdx),
              _addedLinesList(),
              const SizedBox(height: 18),

              const SectionHeader('Payment mode'),
              const SizedBox(height: 8),
              Row(children: [
                _payChip('cash', 'Cash', Icons.payments_outlined),
                const SizedBox(width: 8),
                _payChip('upi', 'UPI', Icons.qr_code_2),
                const SizedBox(width: 8),
                _payChip('credit', 'Credit', Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                _payChip('bank', 'Bank', Icons.account_balance_outlined),
              ]),
              const SizedBox(height: 18),

              TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Remarks (optional)',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_outlined, size: 18, color: Color(0xFFEA580C)))),
              const SizedBox(height: 120),
            ])),
    _bottomBar(),
  ]);

  Widget _bottomBar() => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
          color: kSurface,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -2))
          ]),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              _summStat('Birds', '$_totalBirds'),
              _summStat('Weight', '${_totalKg.toStringAsFixed(1)} kg'),
              _summStat('Products', '${_lines.where((l) => l.product != null).length}'),
            ]),
            const SizedBox(height: 10),
            ElevatedButton.icon(
                onPressed: (_submitting || _selRetailer == null) ? null : _submit,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54), backgroundColor: const Color(0xFFEA580C)),
                icon: _submitting
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.electric_bolt, size: 20),
                label: Text(_submitting ? 'Creating...' : 'Create & Go to Delivery',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ])));

  Widget _summStat(String l, String v) => Expanded(
      child: Column(children: [
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        Text(l, style: const TextStyle(fontSize: 9, color: kTextSub, fontWeight: FontWeight.w700)),
      ]));

  Widget _retailerChip(Map<String, dynamic> r) {
    final selected = _selRetailer?['id'] == r['id'];
    final name = r['shop_name'] as String? ?? '';
    return GestureDetector(
        onTap: () => setState(() => _selRetailer = r),
        child: Container(
            width: 66,
            margin: const EdgeInsets.only(right: 8),
            child: Column(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colorFor(name).withValues(alpha: 0.15),
                      border: Border.all(color: selected ? const Color(0xFFEA580C) : Colors.transparent, width: 2)),
                  alignment: Alignment.center,
                  child: Text(_initialsFor(name),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _colorFor(name)))),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ])));
  }

  Widget _searchRetailerChip() => GestureDetector(
      onTap: _openRetailerSearch,
      child: Container(
          width: 66,
          margin: const EdgeInsets.only(right: 8),
          child: Column(children: [
            Container(
                width: 44,
                height: 44,
                decoration:
                BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBorderLight), color: kSurface),
                alignment: Alignment.center,
                child: const Icon(Icons.search, size: 20, color: kTextSub)),
            const SizedBox(height: 4),
            const Text('Search', style: TextStyle(fontSize: 10, color: kTextSub)),
          ])));

  Future<void> _openRetailerSearch() async {
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
                      color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusCard))),
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: 'Search retailer name or mobile', prefixIcon: Icon(Icons.search, size: 20)),
                        onChanged: (q) => setSheet(() {
                          final ql = q.trim().toLowerCase();
                          filtered = ql.isEmpty
                              ? List.from(_retailers)
                              : _retailers
                              .where((r) => (r['shop_name'] as String? ?? '').toLowerCase().contains(ql))
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
                                    setState(() => _selRetailer = r);
                                  });
                            })),
                  ])));
        }));
  }

  Widget _productChip(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final selected = _lines.any((l) => l.product?['id'] == product['id']);
    return GestureDetector(
        onTap: () => _tapProduct(product),
        child: Container(
            width: 68,
            margin: const EdgeInsets.only(right: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: selected ? const Color(0xFFEA580C).withValues(alpha: 0.10) : kBgPage,
                      border: selected ? Border.all(color: const Color(0xFFEA580C), width: 2) : null),
                  alignment: Alignment.center,
                  child: Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 28, height: 1.0))),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? const Color(0xFFEA580C) : Colors.black87)),
            ])));
  }

  Widget _activeLineCard(int idx) {
    final line = _lines[idx];
    final name = line.product?['name'] as String? ?? 'Select a product above';
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (line.product != null) ...[
              Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            if (line.product != null)
              GestureDetector(
                  onTap: () => _removeLine(idx),
                  child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), shape: BoxShape.circle),
                      child: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _compactField(
                    label: 'Weight (kg) *',
                    controller: line.weight,
                    icon: Icons.scale_outlined,
                    decimal: true,
                    onChanged: () => setState(() {}))),
            const SizedBox(width: 10),
            Expanded(
                child: _compactField(
                    label: 'Birds (optional)',
                    controller: line.birds,
                    icon: Icons.egg_alt_outlined,
                    onChanged: () => setState(() {}))),
          ]),
        ]));
  }

  Widget _addedLinesList() {
    final withProduct = _lines.where((l) => l.product != null).toList();
    if (withProduct.length <= 1) return const SizedBox.shrink();
    return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Added products (${withProduct.length})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub)),
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
                              color: isActive ? const Color(0xFFEA580C) : Colors.black87))),
                  Expanded(
                      flex: 3,
                      child: Text('${line.b > 0 ? '${line.b} birds · ' : ''}${line.kg.toStringAsFixed(0)} kg',
                          style: const TextStyle(fontSize: 11, color: kTextSub))),
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

  Widget _compactField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required VoidCallback onChanged,
    bool decimal = false,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: kTextSub)),
        const SizedBox(height: 4),
        TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            decoration: InputDecoration(
                filled: true,
                fillColor: kBgPage,
                prefixIcon: Icon(icon, size: 16, color: const Color(0xFFEA580C)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
            onChanged: (_) => onChanged()),
      ]);

  Widget _payChip(String value, String label, IconData icon) {
    final selected = _payMode == value;
    return Expanded(
        child: GestureDetector(
            onTap: () => setState(() => _payMode = value),
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: selected ? const Color(0xFFEA580C).withValues(alpha: 0.10) : kBgPage,
                    borderRadius: BorderRadius.circular(12),
                    border: selected ? Border.all(color: const Color(0xFFEA580C), width: 2) : null),
                child: Column(children: [
                  Icon(icon, size: 18, color: selected ? const Color(0xFFEA580C) : kTextSub),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? const Color(0xFFEA580C) : kTextSub)),
                ]))));
  }
}