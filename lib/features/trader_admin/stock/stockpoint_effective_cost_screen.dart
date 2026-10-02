// ─────────────────────────────────────────────────────────────────────────────
// StockPointEffectiveCostScreen — Stock Point Management.
//
// Pure presentation layer over the already-frozen backend, per the current
// production phase: this screen NEVER computes a cost itself. It only:
//   - reads fn_stock_point_effective_cost() for "what's effective today",
//   - reads stock_point_effective_cost directly for the read-only history,
//   - calls record_stock_point_effective_cost_v1() to save — which ALWAYS
//     inserts a new row, never updates one, matching the backend's
//     append-only guarantee exactly.
//
// No business logic lives here. If today's cost already exists, it's shown
// with Edit; if not, the most recent prior confirmation is pre-filled as a
// suggestion (editable) or, if there's no history at all, the field is left
// empty and the trader must enter it — this mirrors the backend's own
// fallback exactly, it does not reimplement it.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class StockPointEffectiveCostScreen extends ConsumerStatefulWidget {
  const StockPointEffectiveCostScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  final String productId;
  final String productName;

  @override
  ConsumerState<StockPointEffectiveCostScreen> createState() => _StockPointEffectiveCostScreenState();
}

class _StockPointEffectiveCostScreenState extends ConsumerState<StockPointEffectiveCostScreen> {
  final _c = Supabase.instance.client;
  final _costCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  double? _todaysConfirmedCost;   // a row already exists with effective_from == today
  double? _suggestedCost;         // no row for today, but a prior one exists
  List<Map<String, dynamic>> _history = [];
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    if (tid == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Full history — via a SECURITY DEFINER RPC (explicit p_trader_id
      // filter enforced server-side), matching how every other Stock Point
      // table is read in this app. This table has RLS disabled, same as
      // every sibling Stock Point table — a raw client-side .from() read
      // would not be safely scoped to this trader.
      final historyRes = await _c.rpc('get_stock_point_effective_cost_history_v1', params: {
        'p_trader_id': tid,
        'p_product_id': widget.productId,
      }).timeout(const Duration(seconds: 15));
      final history = List<Map<String, dynamic>>.from(historyRes as List? ?? []);

      // What's effective today — via the same backend function every
      // report/dashboard already uses, not a client-side re-derivation.
      final todayCostRes = await _c.rpc('fn_stock_point_effective_cost', params: {
        'p_trader_id': tid,
        'p_product_id': widget.productId,
        'p_as_of_date': today,
      }).timeout(const Duration(seconds: 15));

      final hasRowForToday = history.isNotEmpty && history.first['effective_from'] == today;

      if (!mounted) return;
      setState(() {
        _history = history;
        if (hasRowForToday) {
          _todaysConfirmedCost = (todayCostRes as num?)?.toDouble();
          _suggestedCost = null;
          _costCtrl.text = _todaysConfirmedCost?.toStringAsFixed(2) ?? '';
        } else {
          _todaysConfirmedCost = null;
          _suggestedCost = (todayCostRes as num?)?.toDouble();
          _costCtrl.text = _suggestedCost?.toStringAsFixed(2) ?? '';
          _editing = true; // nothing confirmed today yet — go straight to the input
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceAll('Exception:', '').trim(); });
    }
  }

  Future<void> _save() async {
    final tid = ref.read(appUserProvider).valueOrNull?.traderId;
    final uid = ref.read(appUserProvider).valueOrNull?.userId;
    if (tid == null) return;
    final cost = double.tryParse(_costCtrl.text.trim());
    if (cost == null || cost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid cost greater than zero.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _c.rpc('record_stock_point_effective_cost_v1', params: {
        'p_trader_id': tid,
        'p_product_id': widget.productId,
        'p_cost_per_kg': cost,
        'p_confirmed_by': uid,
        if (_reasonCtrl.text.trim().isNotEmpty) 'p_reason': _reasonCtrl.text.trim(),
      }).timeout(const Duration(seconds: 15));
      _reasonCtrl.clear();
      if (mounted) setState(() => _editing = false);
      await _load(); // reload from the backend — never trust the local value
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Effective Stock Point Cost saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save: ${e.toString().replaceAll('Exception:', '').trim()}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: Text('Stock Point Cost — ${widget.productName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
      bottomNavigationBar: const SizedBox(height: kBottomNavClearance),
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
          : RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, kBottomNavClearance),
      children: [
        _currentCostCard(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('COST HISTORY', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
        ),
        _historyList(),
      ],
    );
  }

  Widget _currentCostCard() {
    final hasToday = _todaysConfirmedCost != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: kBorderLight),
        boxShadow: kCardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.today_outlined, size: 16, color: kTextHint),
          const SizedBox(width: 6),
          const Text('TODAY\'S EFFECTIVE STOCK POINT COST',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),

        if (!_editing) ...[
          // Confirmed for today — show it, offer Edit.
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${_todaysConfirmedCost!.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kNavy)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('/kg', style: TextStyle(fontSize: 13, color: kTextSub)),
            ),
          ]),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
              SizedBox(width: 4),
              Text('Confirmed for today', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
        ] else ...[
          // No confirmation for today yet — editable field, pre-filled
          // with the last confirmed cost if one exists.
          if (_suggestedCost != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No cost confirmed today — showing your last confirmed cost (₹${_suggestedCost!.toStringAsFixed(2)}/kg) as a suggestion. Accept it as-is or change it below.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: kTextHint),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    'No prior cost on record for this product — enter today\'s working cost.',
                    style: TextStyle(fontSize: 12, color: kTextSub))),
              ]),
            ),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cost per kg (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonCtrl,
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'e.g. supplier bill pending, using last known rate',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
            if (_todaysConfirmedCost != null) ...[
              const SizedBox(width: 10),
              TextButton(
                onPressed: _saving ? null : () => setState(() {
                  _editing = false;
                  _costCtrl.text = _todaysConfirmedCost!.toStringAsFixed(2);
                }),
                child: const Text('Cancel'),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _historyList() {
    if (_history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: kBorderLight)),
        child: Center(child: Text('No confirmations recorded yet.', style: TextStyle(fontSize: 13, color: kTextSub))),
      );
    }
    final currentUserId = ref.read(appUserProvider).valueOrNull?.userId;
    return Column(
      children: _history.map((row) {
        final confirmedBy = row['confirmed_by'] as String?;
        final confirmedByLabel = confirmedBy == null
            ? '—'
            : (confirmedBy == currentUserId ? 'You' : '${confirmedBy.substring(0, 8)}…');
        final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderLight)),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fd(row['effective_from']), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text('Confirmed by $confirmedByLabel', style: TextStyle(fontSize: 11, color: kTextSub)),
                if ((row['reason'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(row['reason'] as String, style: TextStyle(fontSize: 11, color: kTextHint, fontStyle: FontStyle.italic)),
                  ),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${((row['effective_cost_per_kg'] as num).toDouble()).toStringAsFixed(2)}/kg',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                if (createdAt != null)
                  Text(DateFormat('d MMM, h:mm a').format(createdAt),
                      style: TextStyle(fontSize: 10.5, color: kTextHint)),
              ]),
            ),
          ]),
        );
      }).toList(),
    );
  }

  String _fd(dynamic d) {
    final dt = DateTime.tryParse(d?.toString() ?? '');
    if (dt == null) return '—';
    return DateFormat('d MMM yyyy').format(dt);
  }
}