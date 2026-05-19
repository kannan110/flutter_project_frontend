import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// =============================================================================
// SIMPLE MODE DASHBOARD — elder-friendly, large-text, workflow-oriented UI
//
// Used by AgentHomeScreen when uiMode == UiMode.simple.
// Receives all data from the parent's computed properties.
// =============================================================================

class SimpleDashboard extends StatelessWidget {
  const SimpleDashboard({
    super.key,
    required this.hasShift,
    required this.today,
    required this.reqBirds,
    required this.reqWeight,
    required this.orderCount,
    required this.availBirds,
    required this.availKg,
    required this.hasShortage,
    required this.shortBirds,
    required this.shortKg,
    required this.pendingList,
    required this.activeBatches,
    required this.onRefresh,
    required this.onGoToShiftOpen,
    required this.onGoToShiftClose,
    required this.onGoToBatchPickup,
    required this.onGoToDeliveries,
    required this.onGoToTransfers,
    required this.onGoToDeliveryComplete,
    required this.onGoToDcView,
    required this.onGoToAllDeliveries,
    this.onDeliveryCompleteItem,
    this.onTransferItem,
    this.onReassignItem,
  });

  final bool hasShift;
  final Map<String, dynamic>? today;
  final int reqBirds, orderCount, availBirds, shortBirds;
  final double reqWeight, availKg, shortKg;
  final bool hasShortage;
  final List pendingList;
  final List<Map<String, dynamic>> activeBatches;
  final VoidCallback onRefresh, onGoToShiftOpen, onGoToShiftClose;
  final VoidCallback onGoToBatchPickup, onGoToDeliveries, onGoToTransfers;
  final VoidCallback onGoToDeliveryComplete, onGoToDcView;
  final VoidCallback onGoToAllDeliveries;

  // Per-item callbacks
  final ValueChanged<String>? onDeliveryCompleteItem;
  final ValueChanged<String>? onTransferItem;
  final ValueChanged<Map<String, dynamic>>? onReassignItem;

  // ── Computed from today map ─────────────────────────────────────────────
  int get _doneCount =>
      (today?['delivered_count'] as num?)?.toInt() ?? 0;
  double get _cash =>
      (today?['cash_collected'] as num?)?.toDouble() ?? 0.0;

  // ── Pending deliveries — only those that are out_for_delivery ──────────
  List<Map<String, dynamic>> get _actionableDeliveries =>
      pendingList.whereType<Map<String, dynamic>>().where((d) =>
          d['status'] == 'out_for_delivery').toList();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _ShiftCard(
            hasShift: hasShift,
            doneCount: _doneCount,
            cash: _cash,
            orderCount: orderCount,
            onOpen: onGoToShiftOpen,
            onClose: onGoToShiftClose,
          ),
          const SizedBox(height: 16),
          _StockCard(
            availBirds: availBirds,
            availKg: availKg,
            reqBirds: reqBirds,
            reqWeight: reqWeight,
            hasShortage: hasShortage,
            shortBirds: shortBirds,
            shortKg: shortKg,
            onPickup: hasShortage ? onGoToBatchPickup : null,
            onTransfer: hasShortage ? onGoToTransfers : null,
          ),
          const SizedBox(height: 16),
          _WorkflowGrid(
            hasShift: hasShift,
            hasShortage: hasShortage,
            hasBatches: activeBatches.isNotEmpty,
            onPickup: onGoToBatchPickup,
            onDeliveries: onGoToDeliveries,
            onComplete: onGoToDeliveryComplete,
            onClose: onGoToShiftClose,
            onDcView: onGoToDcView,
            hasActionableDeliveries: _actionableDeliveries.isNotEmpty,
          ),
          const SizedBox(height: 16),
          if (pendingList.isNotEmpty) ...[
            _PendingSection(
              deliveries: pendingList,
              onCompleteItem: onDeliveryCompleteItem,
              onViewAll: onGoToAllDeliveries,
              onTransferItem: onTransferItem,
              onReassignItem: onReassignItem,
            ),
            const SizedBox(height: 16),
          ],
          if (activeBatches.isNotEmpty) ...[
            _BatchSection(
              batches: activeBatches,
              onPickup: onGoToBatchPickup,
              onDcView: onGoToDcView,
            ),
            const SizedBox(height: 16),
          ],
          if (pendingList.isEmpty && activeBatches.isEmpty)
            _EmptyStateCard(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1: SHIFT STATUS — Hero card
// ═══════════════════════════════════════════════════════════════════════════
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.hasShift,
    required this.doneCount,
    required this.cash,
    required this.orderCount,
    required this.onOpen,
    required this.onClose,
  });

  final bool hasShift;
  final int doneCount, orderCount;
  final double cash;
  final VoidCallback onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final Color bg1 = hasShift ? const Color(0xFF1B5E20) : const Color(0xFF455A64);
    final Color bg2 = hasShift ? const Color(0xFF2E7D32) : const Color(0xFF546E7A);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [bg1, bg2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status row
        Row(children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: hasShift ? const Color(0xFF69F0AE) : Colors.grey.shade400,
              shape: BoxShape.circle,
              boxShadow: hasShift
                  ? [BoxShadow(color: const Color(0xFF69F0AE).withValues(alpha: 0.6), blurRadius: 10)]
                  : [],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              hasShift ? 'SHIFT OPENED' : 'NO SHIFT',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ),
          Text(hasShift ? '🟢' : '🔴', style: const TextStyle(fontSize: 28)),
        ]),
        const SizedBox(height: 24),

        // Shift timer or empty prompt
        Text(
          hasShift ? 'Your shift is active — keep delivering!' : 'Start your shift to begin deliveries',
          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 20),

        // Big action button
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: hasShift ? onClose : onOpen,
            icon: Icon(hasShift ? Icons.lock_outline : Icons.play_arrow_rounded, size: 26),
            label: Text(
              hasShift ? 'CLOSE SHIFT' : 'OPEN SHIFT',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: hasShift ? const Color(0xFF1B5E20) : kPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 3 big KPIs
        Row(children: [
          _kpiBubble('✅', 'Done', '$doneCount'),
          const SizedBox(width: 8),
          _kpiBubble('💰', 'Cash', Fmt.amount(cash)),
          const SizedBox(width: 8),
          _kpiBubble('📋', 'Pending', '$orderCount'),
        ]),
      ]),
    );
  }

  Widget _kpiBubble(String emoji, String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
            textAlign: TextAlign.center),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2: STOCK STATUS — simple, visual
// ═══════════════════════════════════════════════════════════════════════════
class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.availBirds, required this.availKg,
    required this.reqBirds, required this.reqWeight,
    required this.hasShortage, required this.shortBirds, required this.shortKg,
    this.onPickup, this.onTransfer,
  });

  final int availBirds, reqBirds, shortBirds;
  final double availKg, reqWeight, shortKg;
  final bool hasShortage;
  final VoidCallback? onPickup, onTransfer;

  @override
  Widget build(BuildContext context) {
    if (reqBirds == 0 && availBirds == 0) {
      return _simpleCard(
        icon: '📋',
        title: 'No Orders Today',
        subtitle: 'Waiting for orders from admin',
        color: kTextHint,
      );
    }

    final bool sufficient = !hasShortage;
    final String emoji = sufficient ? '✅' : '⚠️';
    final String statusText = sufficient ? 'Stock is Sufficient' : 'Not Enough Stock!';
    final Color statusColor = sufficient ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final Color cardColor = sufficient ? const Color(0xFFF1F8E9) : const Color(0xFFFFEBEE);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status header
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(statusText,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: statusColor)),
          ),
          if (sufficient) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('OK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)),
            ),
          ],
        ]),
        const SizedBox(height: 16),

        // Numbers — large, clear
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Available Birds', style: TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('$availBirds',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: kTextMain)),
              Text('${availKg.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 15, color: kTextSub)),
            ]),
          ),
          if (reqBirds > 0) ...[
            Container(width: 1, height: 60, color: kBorder),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Required', style: TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('$reqBirds',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: statusColor)),
                Text('${reqWeight.toStringAsFixed(1)} kg',
                    style: const TextStyle(fontSize: 15, color: kTextSub)),
              ]),
            ),
          ],
        ]),

        // Shortage action buttons
        if (hasShortage && onPickup != null) ...[
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: onPickup,
                  icon: const Icon(Icons.agriculture, size: 22),
                  label: const Text('🚛 Pickup from Farm',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            if (onTransfer != null) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: onTransfer,
                  icon: const Icon(Icons.swap_horiz, size: 20, color: Colors.purple),
                  label: const Text('🔄 Transfer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.purple)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.purple, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ]),
          if (shortBirds > 0) ...[
            const SizedBox(height: 8),
            Text('Shortage: $shortBirds birds (${shortKg.toStringAsFixed(1)} kg)',
                style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w700)),
          ],
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3: WORKFLOW GRID — 4 big tappable cards (2 columns × 2 rows)
// ═══════════════════════════════════════════════════════════════════════════
class _WorkflowGrid extends StatelessWidget {
  const _WorkflowGrid({
    required this.hasShift,
    required this.hasShortage,
    required this.hasBatches,
    required this.onPickup,
    required this.onDeliveries,
    required this.onComplete,
    required this.onClose,
    required this.onDcView,
    required this.hasActionableDeliveries,
  });

  final bool hasShift, hasShortage, hasBatches, hasActionableDeliveries;
  final VoidCallback onPickup, onDeliveries, onComplete, onClose, onDcView;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text('WHAT WOULD YOU LIKE TO DO?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
      ),
      Row(children: [
        Expanded(child: _actionCard(
          emoji: '🚛',
          title: 'Farm Pickup',
          subtitle: 'Pick birds from farm',
          color: const Color(0xFF2E7D32),
          onTap: hasBatches ? onPickup : null,
          disabledReason: !hasBatches ? 'No active batch' : null,
          highlighted: hasShortage,
        )),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(
          emoji: '📦',
          title: 'Deliveries',
          subtitle: 'View all deliveries',
          color: const Color(0xFF1565C0),
          onTap: onDeliveries,
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _actionCard(
          emoji: '✅',
          title: 'Complete Delivery',
          subtitle: hasActionableDeliveries ? 'Pending delivery' : 'Mark delivery done',
          color: const Color(0xFFE65100),
          onTap: hasActionableDeliveries ? onComplete : onDeliveries,
          disabledReason: null,
          highlighted: hasActionableDeliveries,
        )),
        const SizedBox(width: 10),
        Expanded(child: _actionCard(
          emoji: '🛵',
          title: hasShift ? 'Close Shift' : 'Open Shift',
          subtitle: hasShift ? 'End your shift' : 'Start your shift',
          color: hasShift ? kPrimary : const Color(0xFF2E7D32),
          onTap: hasShift ? onClose : null,
          disabledReason: !hasShift ? 'No active shift' : null,
          highlighted: hasShift,
        )),
      ]),
    ]);
  }

  Widget _actionCard({
    required String emoji, required String title, required String subtitle,
    required Color color, VoidCallback? onTap, String? disabledReason, bool highlighted = false,
  }) {
    final bool disabled = onTap == null;
    final Color bgColor = disabled ? Colors.grey.shade100 : (highlighted ? color.withValues(alpha: 0.12) : Colors.white);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: disabled ? Colors.grey.shade200 : color.withValues(alpha: highlighted ? 0.8 : 0.2),
            width: highlighted ? 2.5 : 1.5,
          ),
          boxShadow: disabled ? null : [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: disabled ? kTextHint : kTextMain,
                )),
            const SizedBox(height: 4),
            Text(disabledReason ?? subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: disabled ? kTextHint : kTextSub,
                  fontWeight: FontWeight.w500,
                )),
            if (highlighted && !disabled) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text('ACTION NEEDED',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4: PENDING DELIVERIES — simplified big-list
// ═══════════════════════════════════════════════════════════════════════════
class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.deliveries,
    required this.onCompleteItem,
    required this.onViewAll,
    this.onTransferItem,
    this.onReassignItem,
  });

  final List deliveries;
  final ValueChanged<String>? onCompleteItem;
  final VoidCallback onViewAll;
  final ValueChanged<String>? onTransferItem;
  final ValueChanged<Map<String, dynamic>>? onReassignItem;

  @override
  Widget build(BuildContext context) {
    final items = deliveries.take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('📋 PENDING DELIVERIES',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
        if (deliveries.length > 3)
          TextButton(onPressed: onViewAll, child: Text('View All ${deliveries.length}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 6),
      ...items.map((raw) {
        final d = (raw as Map).cast<String, dynamic>();
        final shopName = d['shop_name'] as String? ?? '--';
        final birds = (d['estimated_birds'] as num?)?.toInt() ?? 0;
        final wt = (d['total_quantity'] as num?)?.toDouble() ?? 0.0;
        final isOfd = d['status'] == 'out_for_delivery';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isOfd ? Colors.blue.shade300 : kBorder, width: isOfd ? 2 : 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header: shop name + status
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('🏪', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(shopName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('$birds birds · ${wt.toStringAsFixed(1)} kg',
                      style: const TextStyle(fontSize: 14, color: kTextSub)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),

            // Action buttons — Complete, Transfer, Reassign
            Row(children: [
              if (isOfd && onCompleteItem != null)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => onCompleteItem!(d['id'] as String),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Complete Delivery',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(Icons.schedule, size: 18, color: Colors.grey.shade400),
                      label: Text(d['status'] as String? ?? 'Pending',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                ),
              // Transfer button — per delivery, uses delivery's batch_id
              if (d['batch_id'] != null && onTransferItem != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => onTransferItem!(d['batch_id'] as String),
                      icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.purple),
                      label: const Text('Transfer',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.purple)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.purple, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
              // Reassign button — per delivery
              if (onReassignItem != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => onReassignItem!(d),
                      icon: const Icon(Icons.person_pin_circle_outlined, size: 18, color: Colors.brown),
                      label: const Text('Reassign',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.brown)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.brown, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ]),
        );
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 5: ACTIVE BATCH — simplified
// ═══════════════════════════════════════════════════════════════════════════
class _BatchSection extends StatelessWidget {
  const _BatchSection({
    required this.batches,
    required this.onPickup,
    required this.onDcView,
  });

  final List<Map<String, dynamic>> batches;
  final VoidCallback onPickup, onDcView;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🚛 ACTIVE BATCHES',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextHint, letterSpacing: 0.8)),
      const SizedBox(height: 6),
      ...batches.map((b) {
        final deliveries = (b['deliveries'] as List? ?? []).cast<Map<String, dynamic>>();
        final done = deliveries.where((d) => d['status'] == 'delivered').length;
        final total = deliveries.length;
        final vehicleNo = b['vehicle_no'] as String? ?? 'Vehicle';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🚛', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(vehicleNo,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('$done of $total deliveries done',
                      style: const TextStyle(fontSize: 13, color: kTextSub)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${total > 0 ? (done / total * 100).toStringAsFixed(0) : 0}%',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPrimary)),
              ),
            ]),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total > 0 ? done / total : 0,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                    done == total ? Colors.green : kPrimary),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onPickup,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Pickup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDcView,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View DCs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ]),
        );
      }),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════
class _EmptyStateCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: [
        const Text('📭', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        const Text('No deliveries or batches yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextSub),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Waiting for admin to assign work',
            style: TextStyle(fontSize: 14, color: kTextHint),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── Shared helper ─────────────────────────────────────────────────────────
Widget _simpleCard({
  required String icon, required String title, required String subtitle, Color color = kTextHint,
}) {
  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kBorder),
    ),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextSub), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(fontSize: 14, color: kTextHint), textAlign: TextAlign.center),
    ]),
  );
}
