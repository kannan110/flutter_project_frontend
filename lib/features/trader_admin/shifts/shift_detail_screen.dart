import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class ShiftDetailScreen extends ConsumerStatefulWidget {
  const ShiftDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends ConsumerState<ShiftDetailScreen> {
  Map<String, dynamic>? _shift;
  List<Map<String, dynamic>> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Supabase.instance.client
        .from('delivery_shifts')
        .select('*, delivery_agents(id,name,phone)')
        .eq('id', widget.id)
        .maybeSingle();
    final e = List<Map<String, dynamic>>.from(await Supabase.instance.client
        .from('delivery_expenses')
        .select('*')
        .eq('shift_id', widget.id)
        .order('created_at'));
    if (mounted)
      setState(() {
        _shift = s;
        _expenses = e;
        _loading = false;
      });
  }

  Future<void> _approve() async {
    await Supabase.instance.client
        .from('delivery_shifts')
        .update({'shift_approval_status': 'approved'}).eq('id', widget.id);
    if (mounted) {
      showSuccess(context, 'Shift approved');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_shift == null)
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('Not found')));

    final agent = _shift!['delivery_agents'] as Map<String, dynamic>?;
    final status = _shift!['status'] as String? ?? 'open';
    final approval = _shift!['shift_approval_status'] as String? ?? 'pending';
    final isClosed = status == 'closed';

    final openingBirds = _shift!['opening_bird_count'] as int? ?? 0;
    final closingBirds = _shift!['closing_bird_count'] as int? ?? 0;
    final totalBirds = _shift!['total_birds_delivered'] as int? ?? 0;
    final totalWt = (_shift!['total_weight_kg'] as num?)?.toDouble() ?? 0;
    final mortality = _shift!['total_mortality'] as int? ?? 0;
    final cash = (_shift!['total_cash_collected'] as num?)?.toDouble() ?? 0;
    final expenses = (_shift!['total_expenses'] as num?)?.toDouble() ?? 0;
    final odomStart = _shift!['odometer_start'];
    final odomEnd = _shift!['odometer_end'];
    final startAt =
        DateTime.tryParse(_shift!['shift_start_at'] as String? ?? '') ??
            DateTime.now();
    final closedAt = isClosed && _shift!['closed_at'] != null
        ? DateTime.tryParse(_shift!['closed_at'] as String)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Shift Detail')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: const Border.fromBorderSide(
                BorderSide(color: Color(0xFFEEEEEE))),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StatusBadge(status, StatusColors.shift(status)),
              const SizedBox(width: 8),
              StatusBadge(approval, StatusColors.approval(approval)),
            ]),
            const SizedBox(height: 12),
            Text(agent?['name'] as String? ?? 'Unknown',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            InfoRow('Started', DateFormat('d MMM y, HH:mm').format(startAt)),
            if (closedAt != null)
              InfoRow('Closed', DateFormat('d MMM y, HH:mm').format(closedAt)),
            InfoRow('Opening Birds', openingBirds.toString()),
            if (isClosed) ...[
              InfoRow('Closing Birds', closingBirds.toString()),
              InfoRow('Delivered',
                  '$totalBirds birds · ${totalWt.toStringAsFixed(2)} kg'),
              InfoRow('Mortality', mortality.toString()),
              InfoRow('Cash Collected', 'Rs.${cash.toStringAsFixed(2)}',
                  valueColor: Colors.green),
              InfoRow('Expenses', 'Rs.${expenses.toStringAsFixed(2)}',
                  valueColor: Colors.red),
              if (odomStart != null)
                InfoRow('Odometer', '$odomStart -> ${odomEnd ?? 'N/A'} km'),
            ],
          ]),
        ),

        // Expenses
        if (_expenses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader('EXPENSES'),
          ..._expenses.map((e) {
            final amt = (e['amount'] as num).toDouble();
            return ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_outlined, size: 18),
              title: Text(e['expense_type'] as String? ?? 'Other',
                  style: const TextStyle(fontSize: 13)),
              subtitle: e['notes'] != null
                  ? Text(e['notes'] as String,
                      style: const TextStyle(fontSize: 11))
                  : null,
              trailing: Text('Rs.${amt.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.red)),
            );
          }),
        ],

        // Approve button
        if (isClosed && approval == 'pending') ...[
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _approve,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Approve Shift'),
          ),
        ],
      ]),
    );
  }
}
