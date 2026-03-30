import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class AgentDeliveriesScreen extends ConsumerStatefulWidget {
  const AgentDeliveriesScreen({super.key});
  @override
  ConsumerState<AgentDeliveriesScreen> createState() => _State();
}

class _State extends ConsumerState<AgentDeliveriesScreen> {
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final agentId = ref.read(appUserProvider).valueOrNull?.agentId;
    if (agentId == null) { setState(() => _loading = false); return; }
    final d = List<Map<String, dynamic>>.from(
      await Supabase.instance.client.from('deliveries')
          .select('*, orders(*, retailers(id,shop_name,owner_name,phone,address,latitude,longitude))')
          .eq('delivery_agent_id', agentId)
          .inFilter('status', ['out_for_delivery', 'assigned', 'picked_up'])
          .order('assigned_at'));
    if (mounted) setState(() { _deliveries = d; _loading = false; });
  }

  Future<void> _call(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _navigate(double? lat, double? lng, String name) async {
    if (lat == null || lng == null) { showError(context, 'Location not available'); return; }
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$name');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('My Deliveries (${_deliveries.length})'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: _loading
        ? const LoadingList()
        : _deliveries.isEmpty
            ? const EmptyState(icon: Icons.delivery_dining_outlined, message: 'No deliveries assigned', sub: 'Check back after batch pickup')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _deliveries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = _deliveries[i];
                    final order    = d['orders'] as Map<String, dynamic>?;
                    final retailer = order?['retailers'] as Map<String, dynamic>?;
                    final phone    = retailer?['phone'] as String?;
                    final lat      = (retailer?['latitude'] as num?)?.toDouble();
                    final lng      = (retailer?['longitude'] as num?)?.toDouble();
                    final status   = d['status'] as String? ?? 'assigned';
                    final isDone   = status == 'delivered';
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDone ? Colors.grey.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDone ? Colors.grey.shade200 : const Color(0xFFEEEEEE)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(retailer?['shop_name'] ?? '—',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                  color: isDone ? Colors.grey : null))),
                          StatusBadge(status.replaceAll('_', ' '), StatusColors.order(status)),
                        ]),
                        if (retailer?['owner_name'] != null) ...[
                          const SizedBox(height: 2),
                          Text(retailer!['owner_name'] as String, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                        ],
                        if (retailer?['address'] != null) ...[
                          const SizedBox(height: 2),
                          Text(retailer!['address'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD))),
                        ],
                        if ((order?['total_quantity'] as num?) != null) ...[
                          const SizedBox(height: 4),
                          Text('${(order!['total_quantity'] as num).toStringAsFixed(1)} kg · ${(d['expected_bird_count'] ?? order['estimated_birds'] ?? 0)} birds',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
                        ],
                        if (!isDone) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            if (phone != null) ...[
                              _IconAction(Icons.call_outlined, 'Call', Colors.green, () => _call(phone)),
                              const SizedBox(width: 8),
                            ],
                            _IconAction(Icons.navigation_outlined, 'Navigate', Colors.blue, () => _navigate(lat, lng, retailer?['shop_name'] ?? '')),
                            const SizedBox(width: 8),
                            Expanded(child: SizedBox(height: 36,
                              child: ElevatedButton(
                                onPressed: () => context.go(Routes.agentDeliveryDonePath(d['id'] as String)),
                                style: ElevatedButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                                child: const Text('Complete', style: TextStyle(fontSize: 13)),
                              ),
                            )),
                          ]),
                        ],
                      ]),
                    );
                  },
                ),
              ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction(this.icon, this.label, this.color, this.onTap);
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}
