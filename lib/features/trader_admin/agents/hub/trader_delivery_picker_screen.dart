import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRADER DELIVERY PICKER
//
// Lists all out_for_delivery items for an agent.
// Tapping one navigates to TraderDeliveryScreen for that specific delivery.
// Used when an agent has multiple concurrent out_for_delivery items.
// ─────────────────────────────────────────────────────────────────────────────

class TraderDeliveryPickerScreen extends StatelessWidget {
  const TraderDeliveryPickerScreen({
    super.key,
    required this.agentId,
    required this.agentName,
    required this.pendingList,
  });

  final String agentId;
  final String agentName;
  final List<Map<String, dynamic>> pendingList;

  @override
  Widget build(BuildContext context) {
    // Filter to only out_for_delivery
    final ready = pendingList
        .where((d) => (d['status'] as String?) == 'out_for_delivery')
        .toList();

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
            const Text('Record Delivery',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: Colors.white)),
            Text('For: $agentName',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFB4C6F4))),
          ],
        ),
      ),
      body: ready.isEmpty
          ? Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_shipping_outlined,
              size: 64, color: kTextHint),
          const SizedBox(height: 16),
          const Text('No deliveries out for delivery',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: kTextSub)),
          const SizedBox(height: 8),
          const Text(
              'DC must be uploaded and batch started first.',
              style: TextStyle(fontSize: 13, color: kTextHint),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton(
              onPressed: () => context.canPop() ? context.pop() : null,
              child: const Text('← Back')),
        ]),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kNavy.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kNavy.withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: kNavy, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${ready.length} delivery(s) out for delivery. '
                      'Tap one to record.',
                  style: const TextStyle(
                      fontSize: 12, color: kNavy,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          ...ready.map((d) {
            final id     = d['id'] as String;
            final shop   = d['shop_name'] as String? ?? '—';
            final addr   = d['address'] as String?;
            final phone  = d['phone'] as String?;
            final birds  = (d['estimated_birds'] as num?)?.toInt() ?? 0;
            final weight = (d['total_quantity'] as num?)?.toDouble() ?? 0;

            return GestureDetector(
              onTap: () => context.push(
                R.agentAssistDeliveryPath(agentId, id),
                extra: {
                  'agentId':   agentId,
                  'agentName': agentName,
                },
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(color: kBorderLight),
                  boxShadow: kCardShadow,
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: kNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusInner),
                    ),
                    child: const Icon(Icons.store_outlined,
                        color: kNavy, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop, style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                        if (addr != null)
                          Text(addr, style: const TextStyle(
                              fontSize: 11, color: kTextHint),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (phone != null)
                          Text(phone, style: const TextStyle(
                              fontSize: 11, color: kTextHint)),
                        const SizedBox(height: 4),
                        Text(
                          '$birds birds · ${weight.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kNavy),
                        ),
                      ])),
                  const Icon(Icons.chevron_right,
                      color: kTextHint, size: 22),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}