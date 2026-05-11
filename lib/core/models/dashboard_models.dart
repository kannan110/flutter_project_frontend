
class StockPosition {
  final String productId;
  final String productName;
  final int totalInBirds;
  final double totalInKg;
  final int totalOutBirds;
  final double totalOutKg;
  final int availableBirds;
  final double availableKg;
  final int mortalityBirds;
  final int returnedBirds;
  final int todayPurchased;
  final int todayDelivered;

  const StockPosition({
    required this.productId, required this.productName,
    required this.totalInBirds, required this.totalInKg,
    required this.totalOutBirds, required this.totalOutKg,
    required this.availableBirds, required this.availableKg,
    required this.mortalityBirds, required this.returnedBirds,
    required this.todayPurchased, required this.todayDelivered,
  });

  factory StockPosition.fromMap(Map<String,dynamic> m) => StockPosition(
    productId:      m['product_id']   as String? ?? '',
    productName:    m['product_name'] as String? ?? '—',
    totalInBirds:   (m['total_in_birds']  as num?)?.toInt() ?? 0,
    totalInKg:      (m['total_in_kg']     as num?)?.toDouble() ?? 0,
    totalOutBirds:  (m['total_out_birds'] as num?)?.toInt() ?? 0,
    totalOutKg:     (m['total_out_kg']    as num?)?.toDouble() ?? 0,
    availableBirds: (m['available_birds'] as num?)?.toInt() ?? 0,
    availableKg:    (m['available_kg']    as num?)?.toDouble() ?? 0,
    mortalityBirds: (m['mortality_birds'] as num?)?.toInt() ?? 0,
    returnedBirds:  (m['returned_birds']  as num?)?.toInt() ?? 0,
    todayPurchased: (m['today_purchased'] as num?)?.toInt() ?? 0,
    todayDelivered: (m['today_delivered'] as num?)?.toInt() ?? 0,
  );

  bool get hasLowStock => availableBirds < 100 && totalInBirds > 0;
  bool get isNegative  => availableBirds < 0;
}

// ── Per-agent stock position for dashboard reconciliation section ─────────────
class AgentStockStatus {
  final String agentId;
  final String agentName;
  final String? vehicleNo;
  final bool hasOpenShift;
  final int pendingDeliveries;
  final int liveStockBirds;
  final double liveStockKg;
  final int todayDcBirds;
  final double todayDcKg;
  final int todayDeliveredBirds;

  const AgentStockStatus({
    required this.agentId, required this.agentName, this.vehicleNo,
    required this.hasOpenShift, required this.pendingDeliveries,
    required this.liveStockBirds, required this.liveStockKg,
    required this.todayDcBirds, required this.todayDcKg,
    required this.todayDeliveredBirds,
  });

  factory AgentStockStatus.fromMap(Map<String,dynamic> m) => AgentStockStatus(
    agentId:            m['agent_id'] as String? ?? '',
    agentName:          m['agent_name'] as String? ?? '—',
    vehicleNo:          m['vehicle_no'] as String?,
    hasOpenShift:       m['has_open_shift'] as bool? ?? false,
    pendingDeliveries:  (m['pending_deliveries'] as num?)?.toInt() ?? 0,
    liveStockBirds:     (m['live_stock_birds']   as num?)?.toInt() ?? 0,
    liveStockKg:        (m['live_stock_kg']      as num?)?.toDouble() ?? 0,
    todayDcBirds:       (m['today_dc_birds']     as num?)?.toInt() ?? 0,
    todayDcKg:          (m['today_dc_kg']        as num?)?.toDouble() ?? 0,
    todayDeliveredBirds:(m['today_delivered_birds'] as num?)?.toInt() ?? 0,
  );

  // Stock is reconciled when shift is closed and all deliveries done
  bool get needsAttention => liveStockBirds > 0 || pendingDeliveries > 0;
}

class DashboardData {
  final int pendingOrders;
  final int activeDeliveries;
  final int todayDelivered;
  final int pendingApprovals;
  final int pendingReturns;
  final double todayRevenue;
  final double totalOutstanding;
  final double todayCollected;
  final double todayCashCollected;
  final double todayUpiCollected;

  // ── LIVE STOCK (cumulative all-time from stock_ledger) ─────────────────────
  // stockBirds  = ALL-TIME total IN (label: "Total Purchased")
  // remainingBirds = LIVE balance right now = IN - OUT
  final int stockBirds;
  final double stockKg;
  final int remainingBirds;
  final double remainingKg;
  final int deliveredBirds;   // stock_ledger delivered, today_delivered field
  final int returnedBirds;    // all-time returned_in
  final int mortalityBirds;   // all-time mortality

  final int todayReturnsBirds;
  final double todayReturnsKg;

  // ── TODAY DC (from delivery_challans — correct, not double-counted) ────────
  final int todayDcCount;
  final int todayDcBirds;
  final double todayDcWeight; // SUM(challans.net_weight) — authoritative

  // ── TODAY values from stock_ledger (SOURCE OF TRUTH) ─────────────────────
  // These replace the old today_dc_weight_total (which was double-counted)
  final int todayPurchasedBirds;    // stock_ledger movement_type=purchased, entry_date=today
  final double todayPurchasedKg;
  final int todayDeliveredBirdsLedger; // stock_ledger movement_type=delivered, entry_date=today
  final double todayDeliveredKgLedger;
  final int todayTransferredInBirds;
  final int todayTransferredOutBirds;
  final int todayMortalityBirdsLedger;

  // ── LOSS (only from APPROVED shifts — real reconciled loss) ───────────────
  // todayHighLossCount: from batch_loss_summary (approved shifts only)
  // todayApprovedLossKg: from batch_loss_summary (shift-approved, batch-level loss)
  // todayPendingShifts: how many shifts today are not yet approved
  final int todayHighLossCount;
  final double todayTotalLossKg;    // approved loss only (from batch_loss_summary)
  final double todayApprovedLossKg; // alias for clarity
  final int todayPendingShifts;     // shifts pending approval today

  // DEPRECATED — kept to avoid compile errors; always 0 from new DB function
  final double todayDcWeightTotal;  // was double-counted; now always 0
  final int todayMortalityBirds;

  // ── Operational ───────────────────────────────────────────────────────────
  final int activeAgents;
  final int openShifts;
  final int activeBatches;
  final int totalRetailers;
  final int unreadAlerts;
  final String dayStatus;
  final bool allClear;

  // ── Per-agent reconciliation status (new) ────────────────────────────────
  final List<AgentStockStatus> agentStatus;

  const DashboardData({
    this.pendingOrders=0, this.activeDeliveries=0, this.todayDelivered=0,
    this.pendingApprovals=0, this.pendingReturns=0,
    this.todayRevenue=0, this.totalOutstanding=0, this.todayCollected=0,
    this.todayCashCollected=0, this.todayUpiCollected=0,
    this.stockBirds=0, this.stockKg=0, this.remainingBirds=0, this.remainingKg=0,
    this.deliveredBirds=0, this.returnedBirds=0, this.mortalityBirds=0,
    this.todayReturnsBirds=0, this.todayReturnsKg=0,
    this.todayDcCount=0, this.todayDcBirds=0, this.todayDcWeight=0,
    this.todayPurchasedBirds=0, this.todayPurchasedKg=0,
    this.todayDeliveredBirdsLedger=0, this.todayDeliveredKgLedger=0,
    this.todayTransferredInBirds=0, this.todayTransferredOutBirds=0,
    this.todayMortalityBirdsLedger=0,
    this.activeAgents=0, this.openShifts=0, this.activeBatches=0,
    this.totalRetailers=0, this.unreadAlerts=0,
    this.dayStatus='open', this.allClear=false,
    this.todayHighLossCount=0, this.todayTotalLossKg=0,
    this.todayApprovedLossKg=0, this.todayPendingShifts=0,
    this.todayDcWeightTotal=0, this.todayMortalityBirds=0,
    this.agentStatus=const [],
  });

  factory DashboardData.fromMap(Map<String,dynamic> m) => DashboardData(
    pendingOrders:     (m['pending_orders']      as num?)?.toInt() ?? 0,
    activeDeliveries:  (m['active_deliveries']   as num?)?.toInt() ?? 0,
    todayDelivered:    (m['today_delivered']      as num?)?.toInt() ?? 0,
    pendingApprovals:  (m['pending_approvals']    as num?)?.toInt() ?? 0,
    pendingReturns:    (m['pending_returns']      as num?)?.toInt() ?? 0,
    todayRevenue:      (m['today_revenue']        as num?)?.toDouble() ?? 0,
    totalOutstanding:  (m['total_outstanding']    as num?)?.toDouble() ?? 0,
    todayCollected:    (m['today_collected']      as num?)?.toDouble() ?? 0,
    todayCashCollected:(m['today_cash_collected'] as num?)?.toDouble() ?? 0,
    todayUpiCollected: (m['today_upi_collected']  as num?)?.toDouble() ?? 0,
    stockBirds:        (m['stock_birds']          as num?)?.toInt() ?? 0,
    stockKg:           (m['stock_kg']             as num?)?.toDouble() ?? 0,
    remainingBirds:    (m['remaining_birds']      as num?)?.toInt() ?? 0,
    remainingKg:       (m['remaining_kg']         as num?)?.toDouble() ?? 0,
    deliveredBirds:    (m['delivered_birds']      as num?)?.toInt() ?? 0,
    returnedBirds:     (m['returned_birds']       as num?)?.toInt() ?? 0,
    mortalityBirds:    (m['mortality_birds']      as num?)?.toInt() ?? 0,
    todayReturnsBirds: (m['today_returns_birds']  as num?)?.toInt() ?? 0,
    todayReturnsKg:    (m['today_returns_kg']     as num?)?.toDouble() ?? 0,
    todayDcCount:      (m['today_dc_count']       as num?)?.toInt() ?? 0,
    todayDcBirds:      (m['today_dc_birds']       as num?)?.toInt() ?? 0,
    todayDcWeight:     (m['today_dc_weight']      as num?)?.toDouble() ?? 0,
    // New ledger-based today fields
    todayPurchasedBirds:       (m['today_purchased_birds']        as num?)?.toInt() ?? 0,
    todayPurchasedKg:          (m['today_purchased_kg']           as num?)?.toDouble() ?? 0,
    todayDeliveredBirdsLedger: (m['today_delivered_birds']        as num?)?.toInt() ?? 0,
    todayDeliveredKgLedger:    (m['today_delivered_kg']           as num?)?.toDouble() ?? 0,
    todayTransferredInBirds:   (m['today_transferred_in_birds']   as num?)?.toInt() ?? 0,
    todayTransferredOutBirds:  (m['today_transferred_out_birds']  as num?)?.toInt() ?? 0,
    todayMortalityBirdsLedger: (m['today_mortality_birds_ledger'] as num?)?.toInt() ?? 0,
    activeAgents:      (m['active_agents']        as num?)?.toInt() ?? 0,
    openShifts:        (m['open_shifts']          as num?)?.toInt() ?? 0,
    activeBatches:     (m['active_batches']       as num?)?.toInt() ?? 0,
    totalRetailers:    (m['total_retailers']      as num?)?.toInt() ?? 0,
    unreadAlerts:      (m['unread_alerts']        as num?)?.toInt() ?? 0,
    dayStatus:          m['day_status'] as String? ?? 'open',
    allClear:           m['all_clear'] as bool? ?? false,
    todayHighLossCount: (m['today_high_loss_count'] as num?)?.toInt() ?? 0,
    todayTotalLossKg:   (m['today_total_loss_kg']   as num?)?.toDouble() ?? 0,
    todayApprovedLossKg:(m['today_approved_loss_kg'] as num?)?.toDouble() ?? 0,
    todayPendingShifts: (m['today_pending_shifts']  as num?)?.toInt() ?? 0,
    // Deprecated — always 0 from new DB function
    todayDcWeightTotal: 0,
    todayMortalityBirds:(m['today_mortality_birds'] as num?)?.toInt() ?? 0,
    // Per-agent status
    agentStatus: ((m['agent_status'] as List?) ?? [])
        .map((a) => AgentStockStatus.fromMap(a as Map<String,dynamic>))
        .toList(),
  );

  bool get isDayClosed => dayStatus == 'closed' || dayStatus == 'locked';
}
