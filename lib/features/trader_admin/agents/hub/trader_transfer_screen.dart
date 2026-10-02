import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'entry_mode_selector.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER TRANSFER SCREEN
//
// Trader-assisted version of bird_transfer_screen.dart.
// Identical business logic, same RPC (transfer_birds), same validations.
// Differences from agent screen:
//   • p_actor_type = 'trader', p_actor_id = trader userId
//   • EntryModeSelector shown at top
//   • BackdateField for actual_at
//   • Launched from hub with fromAgentId, fromAgentName, batchId pre-filled
//
// The RPC handles atomically:
//   • stock_ledger transferred_out / transferred_in
//   • delivery_assignment_history rows
//   • bird_transfers record
//   • operation_log entry
// ─────────────────────────────────────────────────────────────────────────────

class TraderTransferScreen extends ConsumerStatefulWidget {
  const TraderTransferScreen({
    super.key,
    required this.fromAgentId,
    required this.fromAgentName,
    required this.batchId,
  });

  final String fromAgentId;
  final String fromAgentName;
  final String batchId;

  @override
  ConsumerState<TraderTransferScreen> createState() =>
      _TraderTransferScreenState();
}

class _TraderTransferScreenState
    extends ConsumerState<TraderTransferScreen> {
  final _c           = Supabase.instance.client;
  final _birdsCtrl   = TextEditingController();
  final _weightCtrl  = TextEditingController();
  final _reasonCtrl  = TextEditingController();

  String    _entryMode = 'called';
  DateTime? _actualAt;

  // State
  bool _loading    = true;
  bool _submitting = false;

  Map<String, dynamic>?         _batch;
  List<Map<String, dynamic>>    _deliveries  = [];
  List<Map<String, dynamic>>    _toAgents    = [];
  Map<String, dynamic>?         _toAgent;
  List<String>                  _selectedDeliveryIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _birdsCtrl.dispose();
    _weightCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // Retries a transient network failure (e.g. "Connection reset by peer" —
  // a real, common mobile-network blip, not a logic bug) a few times with
  // a short backoff before giving up. Only retries genuinely transient
  // conditions (timeouts, connection resets, socket errors) — a real
  // server-side error (e.g. a 4xx from Postgrest) fails immediately
  // rather than retrying something that will never succeed.
  Future<T> _withRetry<T>(Future<T> Function() fn, {int retries = 2}) async {
    var attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final transient = msg.contains('connection reset') ||
            msg.contains('connection closed') ||
            msg.contains('socketexception') ||
            msg.contains('timeout') ||
            msg.contains('failed host lookup');
        attempt++;
        if (!transient || attempt > retries) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;

      // ★ FIX (Transfer Birds "Connection reset by peer" audit): these
      // three independent queries used to run strictly sequentially,
      // each unprotected — a single transient network blip on any one of
      // them (most commonly the last, "Transfer To" agents, simply
      // because it's the one waiting longest in the chain) threw the raw
      // exception straight into the UI and aborted the whole screen, even
      // though the other two queries may have already succeeded. Now:
      // (a) each query gets its own retry for transient failures, and
      // (b) they run in parallel via Future.wait — both shortens the
      // total round-trip (less time exposed to a mid-flight reset) and
      // means a failure in one no longer has to abort work already done
      // by the others before Future.wait itself reports the failure.
      final results = await Future.wait<dynamic>([
        _withRetry(() => _c
            .from('delivery_batches')
            .select('*,delivery_agents(id,name,vehicle_no)')
            .eq('id', widget.batchId)
            .maybeSingle()),
        _withRetry(() => _c
            .from('deliveries')
            .select(
            'id,status,pickup_bird_count,'
                'orders(id,estimated_birds,total_quantity,'
                'retailers(shop_name,address))')
            .eq('batch_id', widget.batchId)
            .inFilter(
            'status', ['assigned', 'picked_up', 'out_for_delivery'])),
        _withRetry(() => _c
            .from('delivery_agents')
            .select('id,name,vehicle_no,phone')
            .eq('trader_id', user?.traderId ?? '')
            .eq('is_active', true)
            .neq('id', widget.fromAgentId)
            .order('name')),
      ]);

      if (!mounted) return;

      final b = results[0] as Map<String, dynamic>?;
      final deliveries = List<Map<String, dynamic>>.from(results[1] as List? ?? []);
      final a = results[2] as List? ?? [];

      // Pre-fill totals from batch deliveries
      final totalBirds = deliveries.fold<int>(
          0,
              (s, d) =>
          s +
              (((d['orders'] as Map?)?['estimated_birds'] as num?)
                  ?.toInt() ??
                  0));
      final totalWeight = deliveries.fold<double>(
          0,
              (s, d) =>
          s +
              (((d['orders'] as Map?)?['total_quantity'] as num?)
                  ?.toDouble() ??
                  0));

      setState(() {
        _batch       = b;
        _deliveries  = deliveries;
        _toAgents    = List<Map<String, dynamic>>.from(a);
        _loading     = false;
        if (totalBirds > 0 && _birdsCtrl.text.isEmpty) {
          _birdsCtrl.text = '$totalBirds';
        }
        if (totalWeight > 0 && _weightCtrl.text.isEmpty) {
          _weightCtrl.text = totalWeight.toStringAsFixed(1);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        // Friendly message for the common transient case (what the
        // screenshot showed — a raw "ClientConnection reset by peer,
        // uri=https://...supabase.co/..." dump is not actionable for a
        // trader); anything else still surfaces its real message so a
        // genuine bug isn't hidden behind a generic string.
        final raw = e.toString();
        final friendly = raw.toLowerCase().contains('connection reset') ||
            raw.toLowerCase().contains('socketexception') ||
            raw.toLowerCase().contains('timeout')
            ? 'Couldn\'t load transfer data — connection issue. Tap ↻ to retry.'
            : raw.replaceAll('Exception: ', '');
        showError(context, friendly);
      }
    }
  }

  Future<void> _submit() async {
    if (_toAgent == null) {
      showError(context, 'Select the agent to transfer to');
      return;
    }
    final birds  = int.tryParse(_birdsCtrl.text.trim())    ?? 0;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (birds  <= 0) { showError(context, 'Enter bird count'); return; }
    if (weight <= 0) { showError(context, 'Enter weight');     return; }

    final user = ref.read(appUserProvider).valueOrNull;
    if (user?.traderId == null) return;

    final ok = await confirmDialog(
      context,
      title: 'Confirm Transfer',
      message: 'Transfer $birds birds (${weight.toStringAsFixed(1)} kg)\n'
          'From: ${widget.fromAgentName}\n'
          'To: ${_toAgent!['name']}\n\n'
          '${_selectedDeliveryIds.isNotEmpty ? '${_selectedDeliveryIds.length} order(s) will be reassigned.' : 'Stock transfer only — no order reassignment.'}'
          '${_reasonCtrl.text.trim().isNotEmpty ? '\n\nReason: ${_reasonCtrl.text.trim()}' : ''}',
      confirmText: 'Transfer',
      confirmColor: Colors.teal,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      final res = await _c.rpc('transfer_birds', params: {
        'p_from_agent_id': widget.fromAgentId,
        'p_to_agent_id':   _toAgent!['id'],
        'p_from_batch_id': widget.batchId,
        'p_delivery_ids':  _selectedDeliveryIds.isEmpty
            ? <String>[] : _selectedDeliveryIds,
        'p_bird_count':    birds,
        'p_weight_kg':     weight,
        'p_reason':        _reasonCtrl.text.trim().isEmpty
            ? null : _reasonCtrl.text.trim(),
        'p_initiated_by':  user!.userId,
        // Trader actor params
        'p_actor_type':    'trader',
        'p_actor_id':      user.userId,
        'p_entry_mode':    _entryMode,
        if (_actualAt != null)
          'p_actual_at':   _actualAt!.toIso8601String(),
      });

      if (!mounted) return;
      final result = res as Map<String, dynamic>;
      showSuccess(
        context,
        '✅ Transfer complete!\n'
            '$birds birds → ${_toAgent!['name']}\n'
            'Transfer ID: ${(result['transfer_id'] as String).substring(0, 8)}…',
      );
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) {
        showError(context,
            e.toString()
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', '')
                .replaceAll(')', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Transfer Birds',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('From: ${widget.fromAgentName}',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const LoadingList()
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── Entry mode ─────────────────────────────────────────────
          _card(
            title: 'How Did Agent Report?',
            icon: Icons.support_agent_rounded,
            iconColor: Colors.orange,
            child: EntryModeSelector(
              value: _entryMode,
              onChanged: (v) => setState(() => _entryMode = v),
            ),
          ),
          const SizedBox(height: 12),

          // ── Backdate ────────────────────────────────────────────────
          BackdateField(
            value: _actualAt,
            onChanged: (v) => setState(() => _actualAt = v),
          ),
          const SizedBox(height: 12),

          // ── From agent info ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.swap_horiz_rounded,
                  color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FROM (Current Agent)',
                          style: TextStyle(
                              fontSize: 10, color: Colors.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      Text(widget.fromAgentName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(
                          'Vehicle: '
                              '${(_batch?['delivery_agents'] as Map?)?['vehicle_no'] ?? '—'}'
                              ' · ${_deliveries.length} orders in batch',
                          style: const TextStyle(
                              fontSize: 11, color: kTextSub)),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Select deliveries to transfer ──────────────────────────
          if (_deliveries.isNotEmpty) ...[
            _card(
              title: 'Select Orders to Transfer (optional)',
              icon: Icons.list_alt_rounded,
              iconColor: Colors.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Leave unselected for stock-only transfer.',
                    style: TextStyle(
                        fontSize: 11, color: kTextHint),
                  ),
                  const SizedBox(height: 10),
                  // Select all toggle
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_selectedDeliveryIds.length ==
                          _deliveries.length) {
                        _selectedDeliveryIds.clear();
                      } else {
                        _selectedDeliveryIds = _deliveries
                            .map((d) => d['id'] as String)
                            .toList();
                      }
                    }),
                    child: Row(children: [
                      Checkbox(
                        value: _selectedDeliveryIds.length ==
                            _deliveries.length,
                        tristate:
                        _selectedDeliveryIds.isNotEmpty &&
                            _selectedDeliveryIds.length <
                                _deliveries.length,
                        onChanged: (_) => setState(() {
                          if (_selectedDeliveryIds.length ==
                              _deliveries.length) {
                            _selectedDeliveryIds.clear();
                          } else {
                            _selectedDeliveryIds = _deliveries
                                .map((d) => d['id'] as String)
                                .toList();
                          }
                        }),
                      ),
                      const Text('Select All',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  ..._deliveries.map((d) {
                    final id  = d['id'] as String;
                    final o   = (d['orders'] as Map?)?.cast<String, dynamic>();
                    final r   = (o?['retailers'] as Map?)?.cast<String, dynamic>();
                    final shop   = r?['shop_name'] as String? ?? '—';
                    final birds  = (o?['estimated_birds'] as num?)?.toInt()    ?? 0;
                    final weight = (o?['total_quantity']  as num?)?.toDouble() ?? 0;
                    final sel    = _selectedDeliveryIds.contains(id);

                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) _selectedDeliveryIds.remove(id);
                        else     _selectedDeliveryIds.add(id);
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel
                              ? Colors.teal.withValues(alpha: 0.07)
                              : Colors.white,
                          borderRadius:
                          BorderRadius.circular(kRadiusInner),
                          border: Border.all(
                            color: sel ? Colors.teal : kBorderLight,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Checkbox(
                            value: sel,
                            activeColor: Colors.teal,
                            onChanged: (_) => setState(() {
                              if (sel) _selectedDeliveryIds.remove(id);
                              else     _selectedDeliveryIds.add(id);
                            }),
                          ),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(shop,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      '$birds birds · '
                                          '${weight.toStringAsFixed(1)} kg',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: kTextHint)),
                                ]),
                          ),
                          StatusBadge(
                              d['status'] as String? ?? 'assigned',
                              SC.order(d['status'] as String? ??
                                  'assigned')),
                        ]),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Transfer to agent ───────────────────────────────────────
          _card(
            title: 'Transfer To',
            icon: Icons.person_outlined,
            iconColor: Colors.teal,
            child: _toAgents.isEmpty
                ? const Text(
              'No other active agents found.',
              style: TextStyle(
                  color: kTextHint, fontSize: 12),
            )
                : Column(
              children: _toAgents.map((a) {
                final sel = _toAgent?['id'] == a['id'];
                return GestureDetector(
                  onTap: () => setState(() =>
                  _toAgent = sel ? null : a),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.teal.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius:
                      BorderRadius.circular(kRadiusInner),
                      border: Border.all(
                        color: sel ? Colors.teal : kBorderLight,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                        Colors.teal.withValues(alpha: 0.12),
                        child: Text(
                          (a['name'] as String)[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(a['name'] as String,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  a['vehicle_no'] as String? ?? '—',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: kTextHint)),
                            ]),
                      ),
                      if (sel)
                        const Icon(Icons.check_circle,
                            color: Colors.teal, size: 20),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Birds and weight ────────────────────────────────────────
          const SectionHeader('TRANSFER QUANTITY'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _birdsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Birds *', suffixText: 'birds'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Weight (kg) *', suffixText: 'kg'),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Reason ──────────────────────────────────────────────────
          TextField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              alignLabelWithHint: true,
              hintText:
              'e.g. Agent vehicle breakdown, area split…',
            ),
          ),
          const SizedBox(height: 24),

          // ── Submit ──────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.compare_arrows_rounded, size: 20),
            label: Text(
              _toAgent == null
                  ? 'Select target agent above'
                  : 'Transfer to ${_toAgent!['name']}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(kRadiusBtn)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 14),
              child,
            ]),
      );
}