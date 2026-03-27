import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

class CratesScreen extends ConsumerStatefulWidget {
  const CratesScreen({super.key});

  @override
  ConsumerState<CratesScreen> createState() => _CratesScreenState();
}

class _CratesScreenState extends ConsumerState<CratesScreen> {
  List<Map<String, dynamic>> _agentBalances = [];
  List<Map<String, dynamic>> _retailerBalances = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final traderId = ref.read(appUserProvider).valueOrNull?.traderId;
    if (traderId == null) {
      setState(() => _loading = false);
      return;
    }

    final a = List<Map<String, dynamic>>.from(await Supabase.instance.client
        .from('crate_agent_balance')
        .select('*, delivery_agents(id,name)')
        .eq('trader_id', traderId)
        .order('crates_held', ascending: false));
    final r = List<Map<String, dynamic>>.from(await Supabase.instance.client
        .from('crate_retailer_balance')
        .select('*, retailers(id,shop_name)')
        .eq('trader_id', traderId)
        .order('crates_held', ascending: false));

    if (mounted)
      setState(() {
        _agentBalances = a;
        _retailerBalances = r;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Crates')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalAtAgents = _agentBalances.fold<int>(
        0, (s, r) => s + ((r['crates_held'] as int?) ?? 0));
    final totalAtRetailers = _retailerBalances.fold<int>(
        0, (s, r) => s + ((r['crates_held'] as int?) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crate Tracking'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Summary row
          Row(children: [
            Expanded(
                child: _SummaryCard('At Agents', totalAtAgents.toString(),
                    Icons.person_outline, Colors.orange)),
            const SizedBox(width: 10),
            Expanded(
                child: _SummaryCard('At Retailers', totalAtRetailers.toString(),
                    Icons.store_outlined, Colors.blue)),
          ]),
          const SizedBox(height: 20),

          // Agent balances
          const SectionHeader('AGENT BALANCES'),
          if (_agentBalances.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No agent crate records',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
            ),
          ..._agentBalances.map((b) {
            final held = (b['crates_held'] as int?) ?? 0;
            final agent = b['delivery_agents'] as Map<String, dynamic>?;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: held > 10
                        ? Colors.orange.shade200
                        : const Color(0xFFEEEEEE)),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(agent?['name'] as String? ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500))),
                Text('$held crates',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: held > 10 ? Colors.orange : AppTheme.primary)),
              ]),
            );
          }),

          const SizedBox(height: 16),
          const SectionHeader('RETAILER BALANCES'),
          if (_retailerBalances.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No retailer crate records',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
            ),
          ..._retailerBalances.map((b) {
            final held = (b['crates_held'] as int?) ?? 0;
            final retailer = b['retailers'] as Map<String, dynamic>?;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: held > 5
                        ? Colors.blue.shade200
                        : const Color(0xFFEEEEEE)),
              ),
              child: Row(children: [
                const Icon(Icons.store_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(retailer?['shop_name'] as String? ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500))),
                Text('$held crates',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: held > 5 ? Colors.blue : AppTheme.primary)),
              ]),
            );
          }),
        ]),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.label, this.value, this.icon, this.color);

  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              const Border.fromBorderSide(BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        ]),
      );
}
