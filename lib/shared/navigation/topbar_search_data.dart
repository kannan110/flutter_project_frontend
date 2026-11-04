import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/router/app_router.dart';

enum TopbarSearchResultType { retailer, order, agent }

class TopbarSearchItem {
  const TopbarSearchItem({
    required this.id,
    required this.title,
    required this.type,
    required this.route,
    this.subtitle,
    this.badge,
    this.icon,
  });

  final String id;
  final String title;
  final TopbarSearchResultType type;
  final String route;
  final String? subtitle;
  final String? badge;
  final IconData? icon;
}

class TopbarSearchData {
  TopbarSearchData._();

  /// Searches Retailers/Customers, Orders, and Delivery Agents.
  /// Seamlessly matches customer name, owner name, phone number, order ID, or agent name.
  static Future<Map<TopbarSearchResultType, List<TopbarSearchItem>>> searchEntities({
    required SupabaseClient client,
    required String traderId,
    required String query,
  }) async {
    final lower = query.trim().toLowerCase();
    final cleanQ = lower.replaceAll(RegExp(r'[,%]'), ' ').trim();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    try {
      if (lower.isEmpty) {
        // Display recent Retailers, Orders, and Agents when first opened
        final futures = await Future.wait([
          client
              .from('retailers')
              .select('id, shop_name, owner_name, phone, address')
              .eq('trader_id', traderId)
              .order('shop_name')
              .limit(4),
          client
              .from('orders')
              .select('id, status, total_quantity, total_amount, created_at, retailers(shop_name)')
              .eq('trader_id', traderId)
              .order('created_at', ascending: false)
              .limit(4),
          client
              .from('delivery_agents')
              .select('id, name, phone, vehicle_no')
              .eq('trader_id', traderId)
              .order('name')
              .limit(3),
        ]);

        return {
          TopbarSearchResultType.retailer: _parseRetailers(futures[0] as List<dynamic>),
          TopbarSearchResultType.order: _parseOrders(futures[1] as List<dynamic>, currency),
          TopbarSearchResultType.agent: _parseAgents(futures[2] as List<dynamic>),
        };
      }

      // ── 1. Search Retailers / Customers by shop name, owner name, phone, or address
      List<dynamic> retailerData = [];
      try {
        retailerData = await client
            .from('retailers')
            .select('id, shop_name, owner_name, phone, address')
            .eq('trader_id', traderId)
            .or('shop_name.ilike.%$cleanQ%,owner_name.ilike.%$cleanQ%,phone.ilike.%$cleanQ%,address.ilike.%$cleanQ%')
            .limit(6);
      } catch (_) {
        // Safe fallback in case of syntax issues
        final all = await client
            .from('retailers')
            .select('id, shop_name, owner_name, phone, address')
            .eq('trader_id', traderId)
            .limit(100);
        retailerData = all.where((r) {
          final shop = (r['shop_name'] as String? ?? '').toLowerCase();
          final owner = (r['owner_name'] as String? ?? '').toLowerCase();
          final phone = (r['phone'] as String? ?? '').toLowerCase();
          final address = (r['address'] as String? ?? '').toLowerCase();
          return shop.contains(lower) || owner.contains(lower) || phone.contains(lower) || address.contains(lower);
        }).take(6).toList();
      }

      // ── 2. Search Orders by Order ID, Customer (Shop Name / Owner Name), or Status
      // (Fetching recent orders and filtering avoids Postgres UUID type cast errors on order ID)
      List<dynamic> orderData = [];
      try {
        final rawOrders = await client
            .from('orders')
            .select('id, status, total_quantity, total_amount, created_at, retailers(shop_name, owner_name, phone)')
            .eq('trader_id', traderId)
            .order('created_at', ascending: false)
            .limit(80);

        orderData = rawOrders.where((o) {
          final id = (o['id'] as String? ?? '').toLowerCase();
          final status = (o['status'] as String? ?? '').toLowerCase();
          final retailer = o['retailers'] as Map<String, dynamic>?;
          final shopName = (retailer?['shop_name'] as String? ?? '').toLowerCase();
          final ownerName = (retailer?['owner_name'] as String? ?? '').toLowerCase();
          final phone = (retailer?['phone'] as String? ?? '').toLowerCase();

          return id.contains(lower) ||
              shopName.contains(lower) ||
              ownerName.contains(lower) ||
              phone.contains(lower) ||
              status.contains(lower);
        }).take(6).toList();
      } catch (_) {
        orderData = [];
      }

      // ── 3. Search Delivery Agents by name, phone, or vehicle number
      List<dynamic> agentData = [];
      try {
        agentData = await client
            .from('delivery_agents')
            .select('id, name, phone, vehicle_no')
            .eq('trader_id', traderId)
            .or('name.ilike.%$cleanQ%,phone.ilike.%$cleanQ%,vehicle_no.ilike.%$cleanQ%')
            .limit(6);
      } catch (_) {
        final all = await client
            .from('delivery_agents')
            .select('id, name, phone, vehicle_no')
            .eq('trader_id', traderId)
            .limit(50);
        agentData = all.where((a) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          final phone = (a['phone'] as String? ?? '').toLowerCase();
          final vehicle = (a['vehicle_no'] as String? ?? '').toLowerCase();
          return name.contains(lower) || phone.contains(lower) || vehicle.contains(lower);
        }).take(6).toList();
      }

      return {
        TopbarSearchResultType.retailer: _parseRetailers(retailerData),
        TopbarSearchResultType.order: _parseOrders(orderData, currency),
        TopbarSearchResultType.agent: _parseAgents(agentData),
      };
    } catch (_) {
      return {
        TopbarSearchResultType.retailer: [],
        TopbarSearchResultType.order: [],
        TopbarSearchResultType.agent: [],
      };
    }
  }

  static List<TopbarSearchItem> _parseRetailers(List<dynamic> data) {
    return data.map((r) {
      final id = r['id']?.toString() ?? '';
      final shopName = r['shop_name']?.toString() ?? 'Retailer';
      final owner = r['owner_name']?.toString() ?? '';
      final phone = r['phone']?.toString() ?? '';
      final address = r['address']?.toString() ?? '';
      final parts = [
        if (owner.isNotEmpty) owner,
        if (phone.isNotEmpty) phone,
        if (address.isNotEmpty) address,
      ];

      return TopbarSearchItem(
        id: 'retailer_$id',
        title: shopName,
        subtitle: parts.join(' • '),
        type: TopbarSearchResultType.retailer,
        route: R.retailerDetailPath(id),
        badge: 'Customer',
        icon: Icons.storefront_rounded,
      );
    }).toList();
  }

  static List<TopbarSearchItem> _parseOrders(List<dynamic> data, NumberFormat currency) {
    return data.map((o) {
      final id = o['id']?.toString() ?? '';
      final shortId = id.length > 8 ? id.substring(0, 8) : id;
      final retailer = o['retailers'] as Map<String, dynamic>?;
      final shopName = retailer?['shop_name']?.toString() ?? 'Customer';
      final status = o['status']?.toString().toUpperCase() ?? '';
      final qty = o['total_quantity'] != null ? '${o['total_quantity']} kg' : '';
      final amount = o['total_amount'] != null
          ? currency.format(num.tryParse(o['total_amount'].toString()) ?? 0)
          : '';
      final parts = [
        if (status.isNotEmpty) status,
        if (qty.isNotEmpty) qty,
        if (amount.isNotEmpty) amount,
      ];

      return TopbarSearchItem(
        id: 'order_$id',
        title: 'Order #$shortId • $shopName',
        subtitle: parts.join(' • '),
        type: TopbarSearchResultType.order,
        route: R.orderDetailPath(id),
        badge: status,
        icon: Icons.receipt_rounded,
      );
    }).toList();
  }

  static List<TopbarSearchItem> _parseAgents(List<dynamic> data) {
    return data.map((a) {
      final id = a['id']?.toString() ?? '';
      final name = a['name']?.toString() ?? 'Agent';
      final phone = a['phone']?.toString() ?? '';
      final vehicle = a['vehicle_no']?.toString() ?? '';
      final parts = [
        if (phone.isNotEmpty) phone,
        if (vehicle.isNotEmpty) vehicle,
      ];

      return TopbarSearchItem(
        id: 'agent_$id',
        title: name,
        subtitle: parts.join(' • '),
        type: TopbarSearchResultType.agent,
        route: R.agentDetailPath(id),
        badge: 'Agent',
        icon: Icons.directions_bike_rounded,
      );
    }).toList();
  }
}
