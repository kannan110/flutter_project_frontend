
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
  // Stock
  final int stockBirds;
  final double stockKg;
  final int remainingBirds;
  final double remainingKg;
  final int deliveredBirds;
  final int returnedBirds;
  final int mortalityBirds;
  final int todayReturnsBirds;
  final double todayReturnsKg;
  // DC
  final int todayDcCount;
  final int todayDcBirds;
  final double todayDcWeight;
  // Operational
  final int activeAgents;
  final int openShifts;
  final int activeBatches;
  final int totalRetailers;
  final int unreadAlerts;
  final String dayStatus;
  final bool allClear;

  const DashboardData({
    this.pendingOrders=0, this.activeDeliveries=0, this.todayDelivered=0,
    this.pendingApprovals=0, this.pendingReturns=0,
    this.todayRevenue=0, this.totalOutstanding=0, this.todayCollected=0,
    this.todayCashCollected=0, this.todayUpiCollected=0,
    this.stockBirds=0, this.stockKg=0, this.remainingBirds=0, this.remainingKg=0,
    this.deliveredBirds=0, this.returnedBirds=0, this.mortalityBirds=0,
    this.todayReturnsBirds=0, this.todayReturnsKg=0,
    this.todayDcCount=0, this.todayDcBirds=0, this.todayDcWeight=0,
    this.activeAgents=0, this.openShifts=0, this.activeBatches=0,
    this.totalRetailers=0, this.unreadAlerts=0,
    this.dayStatus='open', this.allClear=false,
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
    activeAgents:      (m['active_agents']        as num?)?.toInt() ?? 0,
    openShifts:        (m['open_shifts']          as num?)?.toInt() ?? 0,
    activeBatches:     (m['active_batches']       as num?)?.toInt() ?? 0,
    totalRetailers:    (m['total_retailers']      as num?)?.toInt() ?? 0,
    unreadAlerts:      (m['unread_alerts']        as num?)?.toInt() ?? 0,
    dayStatus:         m['day_status'] as String? ?? 'open',
    allClear:          m['all_clear'] as bool? ?? false,
  );

  bool get isDayClosed => dayStatus == 'closed' || dayStatus == 'locked';
}
