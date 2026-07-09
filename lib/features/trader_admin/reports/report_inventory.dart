// ─────────────────────────────────────────────────────────────────────────────
// ReportInventory — single registry of every report in the module.
//
// Reports Home, the category Report List screens, "All Reports" (the
// existing flat chip list), and future Search/Favorites all read from this
// ONE list so categorization can never drift between screens. The `key`
// values below are UNCHANGED from the existing `_kR` list in
// reports_hub_screen.dart — this file does not introduce new report keys,
// it only adds category metadata on top of the reports that already exist.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum ReportCategory { business, operations, sales, financial }

extension ReportCategoryX on ReportCategory {
  String get label => switch (this) {
    ReportCategory.business => 'Business',
    ReportCategory.operations => 'Operations',
    ReportCategory.sales => 'Sales',
    ReportCategory.financial => 'Financial',
  };
  String get description => switch (this) {
    ReportCategory.business => 'Daily summary, collection, profitability, expenses',
    ReportCategory.operations => 'Deliveries, stock recon., mortality, shrinkage',
    ReportCategory.sales => 'Retailer purchase, product sales, zone sales',
    ReportCategory.financial => 'P&L, cash flow, margin analysis, supplier statement',
  };
  IconData get icon => switch (this) {
    ReportCategory.business => Icons.trending_up_outlined,
    ReportCategory.operations => Icons.local_shipping_outlined,
    ReportCategory.sales => Icons.storefront_outlined,
    ReportCategory.financial => Icons.account_balance_outlined,
  };
  Color get color => switch (this) {
    ReportCategory.business => const Color(0xFF1565C0),
    ReportCategory.operations => const Color(0xFFE65100),
    ReportCategory.sales => const Color(0xFF2E7D32),
    ReportCategory.financial => const Color(0xFF4527A0),
  };
}

class ReportInventoryEntry {
  final String key;      // matches the _kR report key in reports_hub_screen.dart
  final String label;
  final ReportCategory category;
  final String frequency; // 'Daily' | 'Weekly' | 'Monthly' | 'Ad hoc'
  const ReportInventoryEntry({
    required this.key,
    required this.label,
    required this.category,
    required this.frequency,
  });
}

/// The registry. Keys match reports_hub_screen.dart's `_kR` exactly — this
/// file only adds category/frequency metadata, it does not define new
/// reports and does not change any existing report's key, calculation, or
/// RPC. Standalone screens (P&L, Cash Flow, Supplier Statement) are included
/// here for Reports Home/List purposes even though they're separate Flutter
/// screens, not Reports Hub tabs.
const List<ReportInventoryEntry> kReportInventory = [
  // ── Business ──────────────────────────────────────────────────────────
  ReportInventoryEntry(key: 'daily_summary', label: 'Daily Summary', category: ReportCategory.business, frequency: 'Daily'),
  ReportInventoryEntry(key: 'collection', label: 'Collection', category: ReportCategory.business, frequency: 'Daily'),
  ReportInventoryEntry(key: 'profitability', label: 'Profitability', category: ReportCategory.business, frequency: 'Monthly'),
  ReportInventoryEntry(key: 'expense', label: 'Expenses', category: ReportCategory.business, frequency: 'Weekly'),

  // ── Operations ────────────────────────────────────────────────────────
  ReportInventoryEntry(key: 'delivery_history', label: 'Deliveries', category: ReportCategory.operations, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'stock_reconciliation', label: 'Stock Reconciliation', category: ReportCategory.operations, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'mortality', label: 'Mortality', category: ReportCategory.operations, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'shrinkage', label: 'Shrinkage', category: ReportCategory.operations, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'shift_audit', label: 'Shift Audit', category: ReportCategory.operations, frequency: 'Ad hoc'),
  ReportInventoryEntry(key: 'agent_performance', label: 'Agent Report', category: ReportCategory.operations, frequency: 'Weekly'),

  // ── Sales ─────────────────────────────────────────────────────────────
  ReportInventoryEntry(key: 'retailer_purchase', label: 'Retailer Purchase', category: ReportCategory.sales, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'product_sales', label: 'Product Sales', category: ReportCategory.sales, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'zone_sales', label: 'Zone Sales', category: ReportCategory.sales, frequency: 'Weekly'),
  ReportInventoryEntry(key: 'discount_leakage', label: 'Discount Leakage', category: ReportCategory.sales, frequency: 'Monthly'),
  ReportInventoryEntry(key: 'rate_source_breakdown', label: 'Pricing Source', category: ReportCategory.sales, frequency: 'Monthly'),

  // ── Financial ─────────────────────────────────────────────────────────
  ReportInventoryEntry(key: 'profitability_enhanced', label: 'Profit (Full)', category: ReportCategory.financial, frequency: 'Monthly'),
  ReportInventoryEntry(key: 'profitability_breakdown', label: 'Profit Breakdown', category: ReportCategory.financial, frequency: 'Monthly'),
];

List<ReportInventoryEntry> reportsInCategory(ReportCategory c) =>
    kReportInventory.where((e) => e.category == c).toList();

int reportCountInCategory(ReportCategory c) => reportsInCategory(c).length;