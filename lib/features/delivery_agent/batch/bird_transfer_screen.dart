import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class BirdTransferScreen extends ConsumerStatefulWidget {
  const BirdTransferScreen({super.key, required this.batchId});

  final String batchId;

  @override
  ConsumerState<BirdTransferScreen> createState() => _S();
}

class _S extends ConsumerState<BirdTransferScreen> {
  final _c = Supabase.instance.client;

  Map<String, dynamic>? _batch;
  List<Map<String, dynamic>> _deliveries = []; // transferable deliveries
  List<Map<String, dynamic>> _agents = []; // all other active agents
  List<String> _selectedDeliveryIds = []; // which orders to transfer
  Map<String, dynamic>? _toAgent;

  final _birdsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = true, _submitting = false;

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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;

      // Load batch details
      final b = await _c
          .from('delivery_batches')
          .select('*,delivery_agents(id,name,vehicle_no)')
          .eq('id', widget.batchId)
          .maybeSingle();

      // Load non-delivered deliveries in this batch
      final d = await _c
          .from('deliveries')
          .select('id,status,pickup_bird_count,'
              'orders(id,estimated_birds,total_quantity,retailers(shop_name,address))')
          .eq('batch_id', widget.batchId)
          .inFilter('status', ['assigned', 'picked_up', 'out_for_delivery']);

      // Load other active agents in same trader
      final a = await _c
          .from('delivery_agents')
          .select('id,name,vehicle_no,phone')
          .eq('trader_id', user?.traderId ?? '')
          .eq('is_active', true)
          .neq('id', b?['delivery_agent_id'] ?? '')
          .order('name');

      if (!mounted) return;
      final deliveries = List<Map<String, dynamic>>.from(d as List? ?? []);
      setState(() {
        _batch = b;
        _deliveries = deliveries;
        _agents = List<Map<String, dynamic>>.from(a as List? ?? []);
        // Pre-fill totals
        final totalBirds = deliveries.fold(
            0,
            (s, d) =>
                s +
                (((d['orders'] as Map?)?['estimated_birds'] as num?)?.toInt() ??
                    0));
        final totalWeight = deliveries.fold(
            0.0,
            (s, d) =>
                s +
                (((d['orders'] as Map?)?['total_quantity'] as num?)
                        ?.toDouble() ??
                    0));
        if (_birdsCtrl.text.isEmpty && totalBirds > 0)
          _birdsCtrl.text = '$totalBirds';
        if (_weightCtrl.text.isEmpty && totalWeight > 0)
          _weightCtrl.text = totalWeight.toStringAsFixed(1);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _submit() async {
    if (_toAgent == null) {
      showError(context, 'Select the agent to transfer to');
      return;
    }
    if (_birdsCtrl.text.isEmpty) {
      showError(context, 'Enter bird count');
      return;
    }
    if (_weightCtrl.text.isEmpty) {
      showError(context, 'Enter weight');
      return;
    }

    final birds = int.tryParse(_birdsCtrl.text.trim()) ?? 0;
    final weight = double.tryParse(_weightCtrl.text.trim()) ?? 0;
    if (birds <= 0) {
      showError(context, 'Bird count must be > 0');
      return;
    }
    if (weight <= 0) {
      showError(context, 'Weight must be > 0');
      return;
    }

    final ok = await confirmDialog(context,
        title: 'Confirm Transfer',
        message: 'Transfer $birds birds (${weight.toStringAsFixed(1)} kg) to '
            '${_toAgent!['name']}?\n\n'
            '${_selectedDeliveryIds.isNotEmpty ? '${_selectedDeliveryIds.length} order(s) will be reassigned.' : 'No orders reassigned — stock transfer only.'}',
        confirmText: 'Transfer',
        confirmColor: kPrimary);
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      final user = ref.read(appUserProvider).valueOrNull;
      final fromAgentId = _batch?['delivery_agent_id'] as String?;

      final res = await _c.rpc('transfer_birds', params: {
        'p_from_agent_id': fromAgentId,
        'p_to_agent_id': _toAgent!['id'],
        'p_from_batch_id': widget.batchId,
        'p_delivery_ids':
            _selectedDeliveryIds.isEmpty ? [] : _selectedDeliveryIds,
        'p_bird_count': birds,
        'p_weight_kg': weight,
        'p_reason':
            _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        'p_initiated_by': user?.userId,
      });

      if (!mounted) return;
      final result = res as Map<String, dynamic>;
      showSuccess(
          context,
          '✅ Transfer complete!\n'
          '$birds birds → ${_toAgent!['name']}\n'
          'Transfer ID: ${(result['transfer_id'] as String).substring(0, 8)}...');
      if (context.canPop())
        context.pop();
      else
        context.go(R.agentHome);
    } catch (e) {
      if (mounted)
        showError(
            context,
            e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return Scaffold(
          appBar: AppBar(title: const Text('Transfer Birds')),
          body: const LoadingList());

    final fromAgent = _batch?['delivery_agents'] as Map<String, dynamic>?;
    final batchBirds = _deliveries.fold(
        0,
        (s, d) =>
            s +
            (((d['orders'] as Map?)?['estimated_birds'] as num?)?.toInt() ??
                0));

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop())
                  context.pop();
                else
                  context.go(R.agentHome);
              }),
          title: const Text('Transfer Birds'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
          ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── From agent info ──────────────────────────────────────
        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [
              const Icon(Icons.swap_horiz, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('FROM (Current Agent)',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8)),
                    Text(fromAgent?['name'] as String? ?? '—',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                        'Vehicle: ${fromAgent?['vehicle_no'] ?? '—'} · $batchBirds birds in batch',
                        style: const TextStyle(fontSize: 11, color: kTextSub)),
                  ])),
            ])),
        const SizedBox(height: 12),

        // ── Select destination agent ─────────────────────────────
        const SectionHeader('TRANSFER TO AGENT'),
        if (_agents.isEmpty)
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: const Text(
                  'No other active agents found. Ask admin to create agents first.',
                  style: TextStyle(color: Colors.red, fontSize: 12)))
        else
          ..._agents.map((a) {
            final selected = _toAgent?['id'] == a['id'];
            return GestureDetector(
                onTap: () => setState(() => _toAgent = selected ? null : a),
                child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: selected
                            ? kPrimary.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected ? kPrimary : kBorder,
                            width: selected ? 2 : 1)),
                    child: Row(children: [
                      CircleAvatar(
                          radius: 20,
                          backgroundColor: kPrimary.withValues(alpha: 0.15),
                          child: Text((a['name'] as String)[0].toUpperCase(),
                              style: const TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.w800))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(a['name'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(
                                '${a['vehicle_no'] ?? '—'}  ${a['phone'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextSub)),
                          ])),
                      if (selected)
                        const Icon(Icons.check_circle,
                            color: kPrimary, size: 22),
                    ])));
          }),
        const SizedBox(height: 14),

        // ── Select orders to transfer ────────────────────────────
        if (_deliveries.isNotEmpty) ...[
          Row(children: [
            const Expanded(child: SectionHeader('SELECT ORDERS TO TRANSFER')),
            TextButton(
                onPressed: () => setState(() {
                      if (_selectedDeliveryIds.length == _deliveries.length) {
                        _selectedDeliveryIds.clear();
                      } else {
                        _selectedDeliveryIds =
                            _deliveries.map((d) => d['id'] as String).toList();
                      }
                    }),
                child: Text(
                    _selectedDeliveryIds.length == _deliveries.length
                        ? 'Deselect All'
                        : 'Select All',
                    style: const TextStyle(fontSize: 12))),
          ]),
          ..._deliveries.map((d) {
            final o = d['orders'] as Map<String, dynamic>?;
            final r = o?['retailers'] as Map<String, dynamic>?;
            final birds = (o?['estimated_birds'] as num?)?.toInt() ?? 0;
            final weight = (o?['total_quantity'] as num?)?.toDouble() ?? 0;
            final dId = d['id'] as String;
            final checked = _selectedDeliveryIds.contains(dId);
            return GestureDetector(
                onTap: () => setState(() {
                      if (checked)
                        _selectedDeliveryIds.remove(dId);
                      else
                        _selectedDeliveryIds.add(dId);
                    }),
                child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: checked ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: checked ? Colors.green : kBorder)),
                    child: Row(children: [
                      Icon(
                          checked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: checked ? Colors.green : kTextHint,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(r?['shop_name'] as String? ?? '—',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(
                                '$birds birds · ${weight.toStringAsFixed(1)} kg · ${r?['address'] ?? '—'}',
                                style: const TextStyle(
                                    fontSize: 11, color: kTextSub)),
                          ])),
                      StatusBadge(d['status'] as String,
                          SC.order(d['status'] as String),
                          small: true),
                    ])));
          }),
          const SizedBox(height: 6),
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  _selectedDeliveryIds.isEmpty
                      ? '💡 No orders selected — only stock will transfer. Agent B takes care of their own orders.'
                      : '✅ ${_selectedDeliveryIds.length} order(s) will be reassigned to ${_toAgent?['name'] ?? 'the selected agent'}.',
                  style: const TextStyle(fontSize: 11, color: Colors.blue))),
          const SizedBox(height: 14),
        ],

        // ── Transfer quantity ────────────────────────────────────
        const SectionHeader('TRANSFER QUANTITY'),
        Row(children: [
          Expanded(
              child: TextFormField(
                  controller: _birdsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Birds *',
                      suffixText: 'birds',
                      prefixIcon: Icon(Icons.set_meal_outlined,
                          size: 18, color: kPrimary)))),
          const SizedBox(width: 12),
          Expanded(
              child: TextFormField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Weight (kg) *',
                      suffixText: 'kg',
                      prefixIcon: Icon(Icons.balance_outlined,
                          size: 18, color: kPrimary)))),
        ]),
        const SizedBox(height: 10),
        TextFormField(
            controller: _reasonCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Reason for transfer (optional)',
                hintText: 'e.g. Urgent delivery request in the area',
                prefixIcon:
                    Icon(Icons.notes_outlined, size: 18, color: kPrimary))),
        const SizedBox(height: 24),

        // ── Info banner ──────────────────────────────────────────
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200)),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What happens after transfer:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.brown)),
                  SizedBox(height: 4),
                  Text(
                      '• Birds deducted from your stock, added to Agent B\n'
                      '• Selected orders reassigned to Agent B\n'
                      '• Transfer recorded in transaction history for both agents\n'
                      '• Trader admin can see full transfer trail',
                      style: TextStyle(
                          fontSize: 11, color: Colors.brown, height: 1.5)),
                ])),
        const SizedBox(height: 20),

        // ── Submit ───────────────────────────────────────────────
        ElevatedButton.icon(
            onPressed: (_submitting || _toAgent == null) ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz, size: 20),
            label: Text(
                _toAgent == null
                    ? 'Select an agent first'
                    : 'Transfer to ${_toAgent!['name']}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52))),
        const SizedBox(height: 20),
      ]),
    );
  }
}
