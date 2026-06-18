import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// =============================================================================
// SIMPLE MODE DASHBOARD — reference design match
// Color coding: Green=Active/Done, Blue=Batch/DC, Gold=Pending/Cash, Red=Alert
// Large text, big tap targets, Tamil language support
// =============================================================================

// ── Language helper ───────────────────────────────────────────────────────────
class _L {
  static bool tamil = false;
  static String t(String en, String ta) => tamil ? ta : en;
}

class SimpleDashboard extends StatefulWidget {
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
    this.onGoToPendingOrder,
    this.onGoToMyOrders,
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
  final VoidCallback? onGoToPendingOrder;
  final VoidCallback? onGoToMyOrders;
  final ValueChanged<String>? onDeliveryCompleteItem;
  final ValueChanged<String>? onTransferItem;
  final ValueChanged<Map<String, dynamic>>? onReassignItem;

  @override State<SimpleDashboard> createState() => _SimpleDashboardState();
}

class _SimpleDashboardState extends State<SimpleDashboard> {
  bool _tamil = false;

  // ── Computed ──────────────────────────────────────────────────────────────
  int    get _done  => (widget.today?['delivered_count'] as num?)?.toInt()    ?? 0;
  double get _cash  => (widget.today?['cash_collected']  as num?)?.toDouble() ?? 0.0;
  int    get _mort  => (widget.today?['mortality_birds'] as num?)?.toInt()    ?? 0;

  List<Map<String, dynamic>> get _actionable =>
      widget.pendingList
          .whereType<Map<String, dynamic>>()
          .where((d) => d['status'] == 'out_for_delivery')
          .toList();

  String t(String en, String ta) => _tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      color: const Color(0xFF1B6CA8),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 110),
        children: [
          // Top spacing for transparent AppBar
          const SizedBox(height: 44),

          // ── Lang toggle ─────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(() => _tamil = !_tamil),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: kNavy,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kGoldLight.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _tamil ? 'EN' : 'தமிழ்',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: kGoldLight),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── 1. Shift status card ─────────────────────────────────────────
          _ShiftCard(
            hasShift: widget.hasShift,
            done:     _done,
            cash:     _cash,
            pending:  widget.orderCount,
            mort:     _mort,
            onOpen:   widget.onGoToShiftOpen,
            onClose:  widget.onGoToShiftClose,
            onPendingOrder: widget.onGoToPendingOrder,
            tamil:    _tamil,
          ),
          const SizedBox(height: 14),

          // ── 2. Active batch card ─────────────────────────────────────────
          if (widget.activeBatches.isNotEmpty)
            _BatchCard(
              batch:     widget.activeBatches.first,
              reqBirds:  widget.reqBirds,
              reqWeight: widget.reqWeight,
              availBirds: widget.availBirds,
              availKg:   widget.availKg,
              onPickup:  widget.onGoToBatchPickup,
              onViewDCs: widget.onGoToDcView,
              tamil:     _tamil,
            )
          else if (widget.hasShift)
            _NoBatchCard(onPickup: widget.onGoToBatchPickup, tamil: _tamil),

          const SizedBox(height: 14),

          // ── 3. Next delivery card ────────────────────────────────────────
          if (_actionable.isNotEmpty)
            _NextDeliveryCard(
              delivery:   _actionable.first,
              allCount:   _actionable.length,
              onComplete: widget.onDeliveryCompleteItem,
              onTransfer: widget.onTransferItem,
              onReassign: widget.onReassignItem,
              onViewAll:  widget.onGoToAllDeliveries,
              tamil:      _tamil,
            )
          else if (widget.pendingList.isNotEmpty)
            _PendingListCard(
              list:      widget.pendingList,
              onViewAll: widget.onGoToAllDeliveries,
              tamil:     _tamil,
            ),

          const SizedBox(height: 14),

          // ── 4. Manage business grid ──────────────────────────────────────
          _ManageGrid(
            hasShift:   widget.hasShift,
            hasBatches: widget.activeBatches.isNotEmpty,
            onInstantOrder: widget.onGoToDeliveryComplete,
            onDeliveries:   widget.onGoToDeliveries,
            onTransfer:     widget.onGoToTransfers,
            onDcView:       widget.onGoToDcView,
            onPickup:       widget.onGoToBatchPickup,
            onMyOrders:     widget.onGoToMyOrders,
            tamil:          _tamil,
          ),
          const SizedBox(height: 14),

          // ── 5. Performance snapshot ──────────────────────────────────────
          if (widget.today != null)
            _PerfSnap(today: widget.today!, tamil: _tamil),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. SHIFT CARD — green when open, dark when no shift
// ═════════════════════════════════════════════════════════════════════════════
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.hasShift,
    required this.done,
    required this.cash,
    required this.pending,
    required this.mort,
    required this.onOpen,
    required this.onClose,
    this.onPendingOrder,
    required this.tamil,
  });
  final bool hasShift;
  final int done, pending, mort;
  final double cash;
  final VoidCallback onOpen, onClose;
  final VoidCallback? onPendingOrder;
  final bool tamil;

  String t(String en, String ta) => tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    final bg = hasShift ? const Color(0xFF1A7A3C) : const Color(0xFF374151);
    final dot = hasShift ? const Color(0xFF86EFAC) : const Color(0xFF9CA3AF);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kRadiusHero),
        boxShadow: [BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(
            hasShift
                ? t('● SHIFT OPENED', '● ஷிஃப்ட் திறந்தது')
                : t('NO ACTIVE SHIFT', 'ஷிஃப்ட் இல்லை'),
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900,
                letterSpacing: 0.3),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          hasShift
              ? t('You are on duty now.', 'நீங்கள் இப்போது பணியில் உள்ளீர்கள்.')
              : t('Tap below to start your shift.', 'ஷிஃப்ட் தொடங்க கீழே அழுத்தவும்.'),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 18),
        // KPI strip — 4 items: Done / Cash / Pending / Mortality
        Row(children: [
          _kpi(t('Done', 'முடி'),    '\$done',            const Color(0xFFBBF7D0)),
          _kpi(t('Cash', 'பணம்'),    Fmt.amount(cash),    const Color(0xFFFCD34D)),
          _kpi(t('Pending', 'மீதம்'),'\$pending',
              pending > 0 ? const Color(0xFFFCD34D) : const Color(0xFFBBF7D0)),
          _kpi(t('Mortality', 'இறப்பு'), '\$mort',
              mort > 0 ? const Color(0xFFFCA5A5) : Colors.white70),
        ]),
        const SizedBox(height: 18),
        // Action button
        GestureDetector(
          onTap: hasShift ? onClose : onOpen,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(kRadiusCard),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(
                hasShift ? Icons.lock_outline_rounded : Icons.play_circle_outline_rounded,
                color: bg, size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                hasShift
                    ? t('CLOSE SHIFT', 'ஷிஃப்ட் முடி')
                    : t('OPEN SHIFT', 'ஷிஃப்ட் தொடங்கு'),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: bg, letterSpacing: 0.5),
              ),
            ]),
          ),
        ),
        // Pre-shift order entry — small secondary action, only before a
        // shift is open. Deliberately subordinate to OPEN SHIFT above —
        // most agents open their shift first; this is for the agent who
        // wants to log a retailer's order on the way to the farm.
        if (!hasShift && onPendingOrder != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onPendingOrder,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: Colors.white38),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.pending_actions_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  t('Create Order (Pending Approval)',
                      'ஆர்டர் உருவாக்கு (ஒப்புதலுக்கு)'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _kpi(String label, String value, Color c) => Expanded(child: Column(children: [
    Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kRadiusInner),
      ),
      child: Text(value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c),
          textAlign: TextAlign.center,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    const SizedBox(height: 4),
    Text(label,
        style: const TextStyle(fontSize: 9, color: Colors.white60,
            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
  ]));
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. BATCH CARD — dark navy, vehicle prominent, capacity bar
// ═════════════════════════════════════════════════════════════════════════════
class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.reqBirds,
    required this.reqWeight,
    required this.availBirds,
    required this.availKg,
    required this.onPickup,
    required this.onViewDCs,
    required this.tamil,
  });
  final Map<String, dynamic> batch;
  final int reqBirds, availBirds;
  final double reqWeight, availKg;
  final VoidCallback onPickup, onViewDCs;
  final bool tamil;

  String t(String en, String ta) => tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    final vehicle  = batch['vehicle_no'] as String? ?? '—';
    final status   = batch['status']     as String? ?? 'assigned';
    final pct      = reqBirds > 0 ? (availBirds / reqBirds).clamp(0.0, 1.0) : 0.0;
    final pctTxt   = '${(pct * 100).toStringAsFixed(0)}% ${t("CAPACITY", "கொள்ளளவு")}';
    final remBirds = (reqBirds - availBirds).clamp(0, 999999);
    final remKg    = (reqWeight - availKg).clamp(0.0, 999999.0);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2B4B),
        borderRadius: BorderRadius.circular(kRadiusHero),
        boxShadow: [BoxShadow(
            color: const Color(0xFF1B2B4B).withValues(alpha: 0.4),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row — vehicle + main batch badge
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusInner),
            ),
            child: const Icon(Icons.local_shipping_rounded,
                color: Color(0xFF93C5FD), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(vehicle,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 0.5))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(kRadiusChip),
              border: Border.all(color: kGoldLight.withValues(alpha: 0.5)),
            ),
            child: Text(t('MAIN BATCH', 'முதல் பேட்ச்'),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900,
                    color: kGoldLight, letterSpacing: 0.5)),
          ),
        ]),
        const SizedBox(height: 12),
        // Capacity bar
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(pctTxt,
              style: const TextStyle(fontSize: 10, color: Colors.white60,
                  fontWeight: FontWeight.w700)),
          Text('${remBirds > 0 ? "$remBirds birds" : t("FULL", "நிரம்பியது")} ${t("REMAINING", "மீதம்")}',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: remBirds > 0 ? kGoldLight : const Color(0xFF86EFAC))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value:           pct,
            minHeight:       8,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(
                pct >= 1.0 ? const Color(0xFF86EFAC) : kGoldLight),
          ),
        ),
        const SizedBox(height: 14),
        // Birds / In stock
        Row(children: [
          Expanded(child: _statBox(
              t('REQUIRED', 'தேவை'), '$reqBirds birds',
              '${reqWeight.toStringAsFixed(1)} kg',
              const Color(0xFF93C5FD))),
          const SizedBox(width: 10),
          Expanded(child: _statBox(
              t('IN STOCK', 'கையிருப்பு'), '$availBirds birds',
              '${availKg.toStringAsFixed(1)} kg',
              availBirds >= reqBirds
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFFCD34D))),
        ]),
        const SizedBox(height: 14),
        // Action buttons
        Row(children: [
          Expanded(child: _actionBtn(
            icon:  Icons.agriculture_rounded,
            label: t('PICKUP', 'பிக்அப்'),
            bg:    const Color(0xFF1A7A3C),
            onTap: onPickup,
          )),
          const SizedBox(width: 10),
          Expanded(child: _actionBtn(
            icon:  Icons.receipt_long_rounded,
            label: t('VIEW DCS', 'DC பார்'),
            bg:    const Color(0xFF1B6CA8),
            onTap: onViewDCs,
          )),
        ]),
      ]),
    );
  }

  Widget _statBox(String label, String v1, String v2, Color c) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(kRadiusInner),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.white60,
          fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(v1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c)),
      Text(v2, style: TextStyle(fontSize: 11, color: c.withValues(alpha: 0.8))),
    ]),
  );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color bg,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(kRadiusCard)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
      ]),
    ),
  );
}

// No batch card
class _NoBatchCard extends StatelessWidget {
  const _NoBatchCard({required this.onPickup, required this.tamil});
  final VoidCallback onPickup;
  final bool tamil;
  String t(String en, String ta) => tamil ? ta : en;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight),
      boxShadow: kCardShadow,
    ),
    child: Column(children: [
      const Icon(Icons.inbox_outlined, size: 40, color: kTextHint),
      const SizedBox(height: 8),
      Text(t('No batch assigned yet', 'பேட்ச் இல்லை'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kTextSub)),
      const SizedBox(height: 4),
      Text(t('Ask admin to assign a batch', 'அட்மினிடம் கேளுங்கள்'),
          style: const TextStyle(fontSize: 12, color: kTextHint)),
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. NEXT DELIVERY CARD — white, shop name large, COMPLETE button prominent
// ═════════════════════════════════════════════════════════════════════════════
class _NextDeliveryCard extends StatelessWidget {
  const _NextDeliveryCard({
    required this.delivery,
    required this.allCount,
    required this.onComplete,
    required this.onTransfer,
    required this.onReassign,
    required this.onViewAll,
    required this.tamil,
  });
  final Map<String, dynamic> delivery;
  final int allCount;
  final ValueChanged<String>? onComplete;
  final ValueChanged<String>? onTransfer;
  final ValueChanged<Map<String, dynamic>>? onReassign;
  final VoidCallback onViewAll;
  final bool tamil;

  String t(String en, String ta) => tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    final shop   = delivery['shop_name']      as String? ?? '—';
    final addr   = delivery['address']        as String? ?? '';
    final birds  = (delivery['estimated_birds'] as num?)?.toInt()    ?? 0;
    final weight = (delivery['total_quantity']  as num?)?.toDouble() ?? 0;
    final id     = delivery['id']             as String? ?? '';
    final batchId= delivery['batch_id']       as String?;

    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusHero),
        border: Border.all(color: const Color(0xFF1B6CA8).withValues(alpha: 0.35), width: 1.5),
        boxShadow: kCardShadow,
      ),
      child: Column(children: [
        // ACTIVE DELIVERY header
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(kRadiusHero)),
          ),
          child: Row(children: [
            const Icon(Icons.local_shipping_rounded,
                color: Color(0xFF1B6CA8), size: 16),
            const SizedBox(width: 6),
            Text(t('ACTIVE DELIVERY', 'டெலிவரி'),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900,
                    color: Color(0xFF1B6CA8), letterSpacing: 0.6)),
            const Spacer(),
            if (allCount > 1)
              GestureDetector(
                onTap: onViewAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B6CA8),
                    borderRadius: BorderRadius.circular(kRadiusChip),
                  ),
                  child: Text('${t("NEXT PRIORITY", "அடுத்தது")} ${allCount > 1 ? "1 OF $allCount" : ""}',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
          ]),
        ),
        // Shop info
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(kRadiusChip),
                ),
                child: const Icon(Icons.store_rounded,
                    color: Color(0xFF1B6CA8), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900, color: kNavy),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (addr.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 12, color: kTextHint),
                    const SizedBox(width: 3),
                    Expanded(child: Text(addr,
                        style: const TextStyle(fontSize: 12, color: kTextHint),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
              ])),
            ]),
            const SizedBox(height: 16),
            // Deliver birds / weight
            Row(children: [
              _delivStat(t('DELIVER BIRDS', 'கோழி'), '$birds ${t("QTY", "எண்")}',
                  const Color(0xFF1B6CA8)),
              const SizedBox(width: 12),
              _delivStat(t('TARGET WEIGHT', 'எடை'), '${weight.toStringAsFixed(1)} KG',
                  kGold),
            ]),
            const SizedBox(height: 18),
            // COMPLETE button
            GestureDetector(
              onTap: id.isNotEmpty ? () => onComplete?.call(id) : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A7A3C),
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF1A7A3C).withValues(alpha: 0.4),
                      blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(t('COMPLETE', 'முடித்தது'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 0.5)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Transfer + Reassign
            Row(children: [
              if (batchId != null)
                Expanded(child: _ghostBtn(
                  icon: Icons.swap_horiz_rounded,
                  label: t('TRANSFER', 'மாற்று'),
                  color: Colors.purple,
                  onTap: () => onTransfer?.call(batchId),
                )),
              if (batchId != null) const SizedBox(width: 10),
              Expanded(child: _ghostBtn(
                icon:  Icons.person_pin_circle_outlined,
                label: t('REASSIGN', 'மாற்றவும்'),
                color: Colors.brown,
                onTap: () => onReassign?.call(delivery),
              )),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ]),
    );
  }

  Widget _delivStat(String label, String value, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(kRadiusInner),
      border: Border.all(color: c.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w800,
          color: c, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900, color: c)),
    ]),
  ));

  Widget _ghostBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ]),
    ),
  );
}

// Pending but not OFD yet
class _PendingListCard extends StatelessWidget {
  const _PendingListCard({
    required this.list,
    required this.onViewAll,
    required this.tamil,
  });
  final List list;
  final VoidCallback onViewAll;
  final bool tamil;
  String t(String en, String ta) => tamil ? ta : en;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: kSurface, borderRadius: BorderRadius.circular(kRadiusCard),
      border: Border.all(color: kBorderLight), boxShadow: kCardShadow,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('PENDING DELIVERIES', 'மீதமுள்ள டெலிவரி'),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
              color: kNavy, letterSpacing: 0.5)),
      const SizedBox(height: 12),
      ...list.take(3).map((raw) {
        final d = (raw as Map).cast<String, dynamic>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(d['shop_name'] as String? ?? '—',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kNavy))),
            Text('${(d['estimated_birds'] as num?)?.toInt() ?? 0} ${t("birds", "கோழி")}',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ]),
        );
      }),
      if (list.length > 3) ...[
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onViewAll,
          child: Text('+${list.length - 3} ${t("more", "மேலும்")} →',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1B6CA8),
                  fontWeight: FontWeight.w700)),
        ),
      ],
    ]),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. MANAGE BUSINESS GRID — 3×2 color-coded actions
// ═════════════════════════════════════════════════════════════════════════════
class _ManageGrid extends StatelessWidget {
  const _ManageGrid({
    required this.hasShift,
    required this.hasBatches,
    required this.onInstantOrder,
    required this.onDeliveries,
    required this.onTransfer,
    required this.onDcView,
    required this.onPickup,
    this.onMyOrders,
    required this.tamil,
  });
  final bool hasShift, hasBatches;
  final VoidCallback onInstantOrder, onDeliveries, onTransfer, onDcView, onPickup;
  final VoidCallback? onMyOrders;
  final bool tamil;
  String t(String en, String ta) => tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    final items = [
      _GridItem(Icons.electric_bolt_rounded, t('INSTANT\nORDER', 'உடனடி\nஆர்டர்'),
          const Color(0xFFEA580C), const Color(0xFFFFF7ED),
          const Color(0xFFFED7AA), onInstantOrder),
      _GridItem(Icons.local_shipping_rounded, t('Deliveries', 'டெலிவரி'),
          const Color(0xFF1B6CA8), const Color(0xFFEFF6FF),
          const Color(0xFFBFDBFE), onDeliveries),
      _GridItem(Icons.swap_horiz_rounded, t('Transfer', 'மாற்று'),
          Colors.purple, const Color(0xFFFAF5FF),
          const Color(0xFFE9D5FF), onTransfer),
      _GridItem(Icons.receipt_long_rounded, t('View DCs', 'DC பார்'),
          const Color(0xFF0D9488), const Color(0xFFECFDF5),
          const Color(0xFF99F6E4), onDcView),
      _GridItem(Icons.currency_rupee_rounded, t('Expenses', 'செலவு'),
          const Color(0xFFD97706), const Color(0xFFFFFBEB),
          const Color(0xFFFDE68A), onInstantOrder),
      _GridItem(Icons.warning_amber_rounded, t('Mortality', 'இறப்பு'),
          kError, const Color(0xFFFEF2F2),
          const Color(0xFFFECACA), onDeliveries),
      if (onMyOrders != null)
        _GridItem(Icons.assignment_outlined, t('My\nOrders', 'என் ஆர்டர்கள்'),
            Colors.indigo, const Color(0xFFEEF2FF),
            const Color(0xFFC7D2FE), onMyOrders!),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('MANAGE BUSINESS', 'வணிகம் நிர்வகி'),
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900,
              color: kTextSub, letterSpacing: 0.7)),
      const SizedBox(height: 10),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.05,
        children: items.map((item) => _GridTile(item: item)).toList(),
      ),
    ]);
  }
}

class _GridItem {
  const _GridItem(this.icon, this.label, this.color, this.bg, this.border, this.onTap);
  final IconData icon;
  final String label;
  final Color color, bg, border;
  final VoidCallback onTap;
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.item});
  final _GridItem item;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: item.onTap,
    child: Container(
      decoration: BoxDecoration(
        color:        item.bg,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border:       Border.all(color: item.border),
        boxShadow:    kCardShadow,
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(kRadiusChip),
            boxShadow:    [BoxShadow(
                color: item.color.withValues(alpha: 0.2),
                blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Icon(item.icon, size: 22, color: item.color),
        ),
        const SizedBox(height: 8),
        Text(item.label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: item.color),
            textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. PERFORMANCE SNAPSHOT — 2×2 stats
// ═════════════════════════════════════════════════════════════════════════════
class _PerfSnap extends StatelessWidget {
  const _PerfSnap({required this.today, required this.tamil});
  final Map<String, dynamic> today;
  final bool tamil;
  String t(String en, String ta) => tamil ? ta : en;

  @override
  Widget build(BuildContext context) {
    final birds  = (today['delivered_birds']  as num?)?.toInt()    ?? 0;
    final weight = (today['delivered_weight'] as num?)?.toDouble() ?? 0;
    final cash   = (today['cash_collected']   as num?)?.toDouble() ?? 0;
    final loss   = (today['total_loss_kg']    as num?)?.toDouble() ?? 0;
    final lossPct= (weight + loss) > 0 ? (loss / (weight + loss) * 100) : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t("TODAY'S PERFORMANCE SNAPSHOT", 'இன்றைய செயல்திறன்'),
          style: const TextStyle(
              fontSize: 10, fontWeight: FontWeight.w900,
              color: kTextSub, letterSpacing: 0.6)),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: Border.all(color: kBorderLight),
          boxShadow: kCardShadow,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            _snap(Icons.egg_alt_rounded, '$birds ${t("birds", "கோழி")}',
                t('DELIVERED', 'டெலிவரி'), const Color(0xFF1A7A3C)),
            _div(),
            _snap(Icons.scale_rounded, '${weight.toStringAsFixed(1)} kg',
                t('WEIGHT', 'எடை'), const Color(0xFF1B6CA8)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _snap(Icons.currency_rupee_rounded, Fmt.amount(cash),
                t('COLLECTED', 'வசூல்'), const Color(0xFF1A7A3C)),
            _div(),
            _snap(Icons.compress_rounded, '${lossPct.toStringAsFixed(1)}%',
                t('SHRINKAGE', 'சரிவு'),
                lossPct >= 2 ? kError : kTextSub),
          ]),
        ]),
      ),
    ]);
  }

  Widget _snap(IconData icon, String value, String label, Color c) =>
      Expanded(child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kRadiusChip),
          ),
          child: Icon(icon, size: 18, color: c),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w900, color: c)),
          Text(label, style: const TextStyle(
              fontSize: 9, color: kTextHint, fontWeight: FontWeight.w700,
              letterSpacing: 0.4)),
        ]),
      ]));

  Widget _div() => Container(
      width: 1, height: 40, color: kBorderLight,
      margin: const EdgeInsets.symmetric(horizontal: 8));
}