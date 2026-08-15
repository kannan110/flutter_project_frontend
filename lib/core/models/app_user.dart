enum UserRole {
  superAdmin, traderAdmin, traderStaff, deliveryStaff, supervisor, retailerUser,
  unknown;

  static UserRole fromString(String? s) => switch (s) {
    'super_admin'    => superAdmin,
    'trader_admin'   => traderAdmin,
    'trader_staff'   => traderStaff,
    'delivery_staff' => deliveryStaff,
    'supervisor'     => supervisor,
    'retailer_user'  => retailerUser,
    _                => unknown,
  };

  String get dbValue => switch (this) {
    UserRole.superAdmin    => 'super_admin',
    UserRole.traderAdmin   => 'trader_admin',
    UserRole.traderStaff   => 'trader_staff',
    UserRole.deliveryStaff => 'delivery_staff',
    UserRole.supervisor    => 'supervisor',
    UserRole.retailerUser  => 'retailer_user',
    UserRole.unknown       => 'unknown',
  };

  String get label => switch (this) {
    UserRole.superAdmin    => 'Super Admin',
    UserRole.traderAdmin   => 'Trader Admin',
    UserRole.traderStaff   => 'Staff',
    UserRole.deliveryStaff => 'Delivery Agent',
    UserRole.supervisor    => 'Supervisor',
    UserRole.retailerUser  => 'Retailer',
    UserRole.unknown       => 'Unlinked',
  };
}

class AppUser {
  final String  userId;
  final String? traderId;
  final UserRole role;
  final String? companyName;
  final String? companyCode;
  final bool    isSubscriptionActive;
  final DateTime? subscriptionEndDate;
  final String? agentId;
  final String? retailerId;
  final String? shopName;
  // New fields for approval flow
  final String  traderStatus;      // active | pending_approval | suspended | blocked
  final String  approvalStatus;    // pending | approved | rejected | enterprise_contact
  final bool    isSuperAdmin;
  // Supervisor / Collection Agent module (Plug & Play)
  final String? supervisorId;          // supervisor_profiles.id, set only for role==supervisor
  final bool    supervisorModuleEnabled; // trader_features.supervisor_module — read for BOTH
  // trader_admin (to show/hide "Create Supervisor")
  // and supervisor (to gate access post-login)

  const AppUser({
    required this.userId,
    this.traderId,
    required this.role,
    this.companyName,
    this.companyCode,
    this.isSubscriptionActive = true,
    this.subscriptionEndDate,
    this.agentId,
    this.retailerId,
    this.shopName,
    this.traderStatus    = 'active',
    this.approvalStatus  = 'approved',
    this.isSuperAdmin    = false,
    this.supervisorId,
    this.supervisorModuleEnabled = false,
  });

  bool get isDeliveryAgent    => role == UserRole.deliveryStaff;
  bool get isSupervisor       => role == UserRole.supervisor;
  bool get isTraderAdmin      => role == UserRole.traderAdmin;
  bool get isRetailer         => role == UserRole.retailerUser;
  bool get canApprove         => isTraderAdmin || isSuperAdmin;
  bool get canManageAgents    => isTraderAdmin || isSuperAdmin;
  bool get isUnlinked         => role == UserRole.unknown || (traderId == null && !isSuperAdmin);
  bool get isPendingApproval  => traderStatus == 'pending_approval' || approvalStatus == 'pending';
  bool get isSuspended        => traderStatus == 'suspended' || traderStatus == 'blocked';
  bool get needsEnterpriseContact => approvalStatus == 'enterprise_contact';
  bool get isFullyActive      => traderStatus == 'active' && approvalStatus == 'approved';
}