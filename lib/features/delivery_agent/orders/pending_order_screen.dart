import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pending Order Screen — Delivery Agent (v2 — same redesign as Instant Order,
// multi-product support added)
//
// Pre-shift order entry. Available only when NO shift is open — if one is,
// point the agent to Instant Order instead (unchanged gate logic). Does NOT
// touch deliveries / delivery_batches / stock_ledger — order only, exactly
// like a retailer-placed order. Once a trader approves it (existing Order
// Detail screen action), it becomes a normal 'confirmed' order and flows
// through dispatch/batch assignment like any other order.
//
// ARCHITECTURE NOTE (same constraint as Instant Order): agent_create_pending_
// order takes a single p_product_id and creates ONE order per call — no bulk
// variant exists. Multiple product lines here means the RPC is called once
// per line, sequentially, for the same retailer, creating that many SEPARATE
// pending orders (each independently approved/rejected by the trader), not
// one order with several line items.
//
// PRESERVED EXACTLY (no business logic changes):
//   • Retailer required; Product OPTIONAL per line (unlike Instant Order,
//     where product is required) — a line can be a generic weight-only entry
//   • Weight required per line, Birds optional per line
//   • Rate per line is an OPTIONAL agent estimate only — never fetched from
//     get_effective_rate_v4 or any pricing hierarchy; the trader sets the
//     real rate at approval. No "system rate" chip belongs on this screen.
//   • agent_create_pending_order RPC call and all its params, unchanged
//   • Inverted shift gate (available only pre-shift)
//   • Stays on this screen after submitting and refreshes "My Submitted
//     Orders" rather than navigating away — preserved exactly
//
// WHAT CHANGED (workflow / UX only), matching Instant Order's redesign:
//   • Retailer/Product pickers → horizontal chips instead of dropdowns
//   • Removed the confirmation dialog — the Order Summary card already
//     shows what will be submitted, and this action only creates a PENDING
//     order (no dispatch, no stock, no live delivery) so there's even less
//     at stake here than on Instant Order for skipping the modal
//   • Removed the "Avg: X g/bird" derived-ratio line, consistent with the
//     rule that no average weight should be displayed anywhere
//   • Multiple product lines, same tap-to-add / reopen-existing pattern
// ─────────────────────────────────────────────────────────────────────────────

class _AgentPendingLine {
  Map<String, dynamic>? product;
  final birds = TextEditingController();
  final weight = TextEditingController();
  final rate = TextEditingController();

  int get b => int.tryParse(birds.text.trim()) ?? 0;
  double get kg => double.tryParse(weight.text.trim()) ?? 0;
  double get r => double.tryParse(rate.text.trim()) ?? 0;
  double get total => kg * r;

  void dispose() {
    birds.dispose();
    weight.dispose();
    rate.dispose();
  }
}

class PendingOrderScreen extends ConsumerStatefulWidget {
  const PendingOrderScreen({super.key});

  @override
  ConsumerState<PendingOrderScreen> createState() => _S();
}

class _S extends ConsumerState<PendingOrderScreen> {
  final _c = Supabase.instance.client;
  final _notesCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _localMessengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _loading = true;
  bool _submitting = false;
  bool _hasOpenShift = false; // if true, this screen is NOT available

  List<Map<String, dynamic>> _retailers = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _myOrders = [];
  Map<String, dynamic>? _selRetailer;
  String? _err;

  List<_AgentPendingLine> _lines = [_AgentPendingLine()];
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
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // INVERTED gate vs InstantOrderScreen: this screen is for BEFORE shift
      // open. If a shift IS open, the agent should use Instant Order instead.
      final shift = await _c
          .from('delivery_shifts')
          .select('id')
          .eq('delivery_agent_id', agentId)
          .eq('status', 'open')
          .maybeSingle();
      final results = await Future.wait<dynamic>([
        _c
            .from('retailers')
            .select('id,shop_name,phone,address')
            .eq('trader_id', traderId)
            .eq('is_active', true)
            .order('shop_name'),
        _c.from('master_products').select('id,name,unit').eq('is_active', true).order('name'),
      ]);
      List<Map<String, dynamic>> myOrders = [];
      try {
        final mine = await _c
            .from('orders')
            .select('id,status,total_quantity,estimated_birds,final_price,'
            'total_amount,order_date,retailers(shop_name)')
            .eq('created_by_agent_id', agentId)
            .inFilter('status', ['pending', 'confirmed']).order('created_at', ascending: false);
        myOrders = List<Map<String, dynamic>>.from(mine as List? ?? []);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _hasOpenShift = shift != null;
        _retailers = List<Map<String, dynamic>>.from(results[0] as List? ?? []);
        _products = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
        _myOrders = myOrders;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalBirds => _lines.fold(0, (s, l) => s + l.b);
  double get _totalKg => _lines.fold(0.0, (s, l) => s + l.kg);
  double get _totalEst => _lines.fold(0.0, (s, l) => s + l.total);

  void _tapProduct(Map<String, dynamic> product) {
    final existingIdx = _lines.indexWhere((l) => l.product?['id'] == product['id']);
    if (existingIdx != -1) {
      setState(() => _activeIdx = existingIdx);
      return;
    }
    final emptyIdx = _lines.indexWhere((l) => l.product == null && l.kg <= 0 && l.b <= 0);
    if (emptyIdx != -1) {
      setState(() {
        _lines[emptyIdx].product = product;
        _activeIdx = emptyIdx;
      });
    } else {
      setState(() {
        _lines.add(_AgentPendingLine()..product = product);
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
      if (wasOnlyLine) _lines.add(_AgentPendingLine());
      if (_activeIdx >= _lines.length) _activeIdx = _lines.length - 1;
      if (_activeIdx < 0) _activeIdx = 0;
    });
    removed.dispose();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2), content: Text('Line removed')));
  }

  Future<void> _submit() async {
    setState(() => _err = null);
    if (_selRetailer == null) {
      setState(() => _err = 'Select a retailer');
      return;
    }
    final validLines = _lines.where((l) => l.kg > 0).toList();
    if (validLines.isEmpty) {
      setState(() => _err = 'Enter weight for at least one line');
      return;
    }

    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) return;

    if (mounted) setState(() => _submitting = true);
    var created = 0;
    String? retailerName;
    try {
      for (final line in validLines) {
        final res = await _c.rpc('agent_create_pending_order', params: {
          'p_agent_id': agentId,
          'p_retailer_id': _selRetailer!['id'],
          'p_product_id': line.product?['id'],
          'p_birds': line.b > 0 ? line.b : null,
          'p_weight_kg': line.kg,
          'p_rate_per_kg': line.r > 0 ? line.r : null,
          'p_notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        });
        final result = res as Map<String, dynamic>;
        retailerName = result['retailer_name'] as String? ?? retailerName;
        created++;
      }

      if (!mounted) return;
      showSuccess(context,
          created == 1
              ? 'Order submitted for approval!\n$retailerName — ${validLines.first.kg.toStringAsFixed(1)} kg'
              : '$created orders submitted for approval for $retailerName');

      // Stay on this screen and refresh — the agent should see their orders
      // appear in "My Submitted Orders" immediately, not navigate away blind.
      for (final l in _lines) l.dispose();
      _notesCtrl.clear();
      setState(() {
        _lines = [_AgentPendingLine()];
        _activeIdx = 0;
        _selRetailer = null;
      });
      _load();
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    } catch (e) {
      final msg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('PostgrestException(message: ', '')
          .replaceAll(')', '');
      if (mounted) setState(() {
        _err = created == 0 ? msg : '$created of ${validLines.length} orders submitted before this failed: $msg';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI helpers ───────────────────────────────────────────────────────────
  static const _palette = [
    kPrimary, Color(0xFF0F6E56), Color(0xFF993C1D), Color(0xFF534AB7), Color(0xFF185FA5), kGoldLight,
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
              backgroundColor: kPrimary,
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
              title: const Text('Create Order (Pending Approval)'),
              actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
          body: _loading
              ? const LoadingList()
              : _hasOpenShift
              ? _buildShiftOpenBlock()
              : _buildForm()));

  Widget _buildShiftOpenBlock() => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.electric_bolt, size: 64, color: kTextHint),
            const SizedBox(height: 16),
            const Text('Shift Already Open', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Use Instant Order for orders during an active shift.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kTextSub)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
                onPressed: () => context.go(R.instantOrder),
                icon: const Icon(Icons.electric_bolt),
                label: const Text('Go to Instant Order')),
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
        child: ListView(controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          if (_myOrders.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                    onTap: () => context.push(R.agentMyOrders),
                    child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(kRadiusCard),
                            border: Border.all(color: kPrimary.withValues(alpha: 0.2))),
                        child: Row(children: [
                          const Icon(Icons.receipt_long_outlined, size: 20, color: kPrimary),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${_myOrders.length} order${_myOrders.length == 1 ? '' : 's'} submitted',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kPrimary)),
                                const Text('Tap to track status', style: TextStyle(fontSize: 11, color: kTextSub)),
                              ])),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: kPrimary),
                        ])))),
          Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: Colors.orange.shade200)),
              child: Row(children: [
                const Icon(Icons.pending_actions_outlined, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pending Approval Mode',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.orange, fontSize: 13)),
                      Text('Trader must approve before this order is dispatched.',
                          style: TextStyle(fontSize: 11, color: kTextSub)),
                    ])),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                    child: const Text('No Shift',
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
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
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
            const Expanded(child: SectionHeader('Products — tap to add (optional)')),
            TextButton.icon(
                onPressed: () => setState(() {
                  _lines.add(_AgentPendingLine());
                  _activeIdx = _lines.length - 1;
                }),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Line', style: TextStyle(fontSize: 12)),
                style:
                TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32))),
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
          TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined, size: 18, color: kPrimary))),
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
              _summStat('Est. Total', _totalEst > 0 ? Fmt.amount(_totalEst) : '—'),
            ]),
            const SizedBox(height: 10),
            ElevatedButton.icon(
                onPressed: (_submitting || _selRetailer == null) ? null : _submit,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 54), backgroundColor: kPrimary),
                icon: _submitting
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.send_outlined, size: 20),
                label: Text(_submitting ? 'Submitting...' : 'Submit for Approval',
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
                      border: Border.all(color: selected ? kPrimary : Colors.transparent, width: 2)),
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
                      color: selected ? kPrimary.withValues(alpha: 0.10) : kBgPage,
                      border: selected ? Border.all(color: kPrimary, width: 2) : null),
                  alignment: Alignment.center,
                  child: Text(_placeholderEmojiFor(name), style: const TextStyle(fontSize: 28, height: 1.0))),
              const SizedBox(height: 6),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: selected ? kPrimary : Colors.black87)),
            ])));
  }

  Widget _activeLineCard(int idx) {
    final line = _lines[idx];
    final name = line.product?['name'] as String? ?? 'No product (weight only)';
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
            Expanded(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: line.product == null ? kTextSub : Colors.black87))),
            if (_lines.length > 1)
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
          const SizedBox(height: 10),
          _compactField(
              label: 'Est. rate ₹/kg (optional — trader sets final)',
              controller: line.rate,
              icon: Icons.currency_rupee,
              decimal: true,
              onChanged: () => setState(() {})),
          if (line.total > 0)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Est. ${Fmt.amount(line.total)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPrimary)))),
        ]));
  }

  Widget _addedLinesList() {
    final withContent = _lines.where((l) => l.product != null || l.kg > 0).toList();
    if (withContent.length <= 1) return const SizedBox.shrink();
    return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order lines (${withContent.length})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSub)),
          const Divider(height: 16),
          ..._lines.asMap().entries.where((e) => e.value.product != null || e.value.kg > 0).map((e) {
            final idx = e.key;
            final line = e.value;
            final name = line.product?['name'] as String? ?? 'No product';
            final isActive = idx == _activeIdx;
            return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Text(line.product != null ? _placeholderEmojiFor(name) : '⚖️', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                      flex: 3,
                      child: Text(name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                              color: isActive ? kPrimary : Colors.black87))),
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
                prefixIcon: Icon(icon, size: 16, color: kPrimary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
            onChanged: (_) => onChanged()),
      ]);
}