// app_user.dart — AppUser data class + UserRole enum
// FIX Bug #2: added agentName field and displayName getter

class AppUser {
  final String userId;
  final String? traderId;
  final UserRole role;
  final String? companyName;
  final String? companyCode;
  final bool isSubscriptionActive;
  final DateTime? subscriptionEndDate;
  final String? agentId;
  final String? agentName; // FIX Bug #2: agent's own display name

  const AppUser({
    required this.userId,
    this.traderId,
    required this.role,
    this.companyName,
    this.companyCode,
    this.isSubscriptionActive = true,
    this.subscriptionEndDate,
    this.agentId,
    this.agentName,
  });

  bool get isDeliveryAgent => role == UserRole.deliveryStaff;
  bool get isTraderAdmin   => role == UserRole.traderAdmin;
  bool get isSuperAdmin    => role == UserRole.superAdmin;
  bool get canApprove      => isTraderAdmin || isSuperAdmin;
  bool get canManageAgents => isTraderAdmin || isSuperAdmin;

  /// For agents: shows their own name. For traders: shows company name.
  String get displayName => agentName ?? companyName ?? '';
}

enum UserRole {
  superAdmin, traderAdmin, traderStaff, deliveryStaff, retailerUser;

  static UserRole fromString(String? s) => switch (s) {
    'super_admin'    => superAdmin,
    'trader_admin'   => traderAdmin,
    'trader_staff'   => traderStaff,
    'delivery_staff' => deliveryStaff,
    'retailer_user'  => retailerUser,
    _                => traderStaff,
  };

  String get dbValue => switch (this) {
    UserRole.superAdmin    => 'super_admin',
    UserRole.traderAdmin   => 'trader_admin',
    UserRole.traderStaff   => 'trader_staff',
    UserRole.deliveryStaff => 'delivery_staff',
    UserRole.retailerUser  => 'retailer_user',
  };

  String get label => switch (this) {
    UserRole.superAdmin    => 'Super Admin',
    UserRole.traderAdmin   => 'Trader Admin',
    UserRole.traderStaff   => 'Staff',
    UserRole.deliveryStaff => 'Delivery Agent',
    UserRole.retailerUser  => 'Retailer',
  };
}
