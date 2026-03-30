import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

final _analyticsProvider = FutureProvider.autoDispose.family<Map<String,dynamic>,String>((ref,traderId) async {
  final res = await Supabase.instance.client.rpc('analytics_summary',params:{'p_trader_id':traderId});
  return Map<String,dynamic>.from(res as Map);
});

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(appUserProvider);
    if (userAsync.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final traderId = userAsync.valueOrNull?.traderId ?? '';
    final async = traderId.isNotEmpty ? ref.watch(_analyticsProvider(traderId)) : const AsyncValue<Map<String,dynamic>>.data({});
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e,_) => Center(child: Text('Error: \$e')),
        data: (d) {
          final revenue = _parsePoints(d['revenue_trend']);
          final orders  = _parsePoints(d['orders_trend']);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_analyticsProvider(traderId).future),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _ChartCard('Revenue (30 days)', revenue, AppTheme.primary),
              const SizedBox(height:16),
              _ChartCard('Orders (14 days)', orders, Colors.blue),
            ]),
          );
        },
      ),
    );
  }
  List<FlSpot> _parsePoints(dynamic raw) {
    if (raw == null) return [];
    final list = raw as List;
    return List.generate(list.length, (i) => FlSpot(i.toDouble(), (list[i]['value'] as num?)?.toDouble() ?? 0));
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(this.title, this.spots, this.color);
  final String title; final List<FlSpot> spots; final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(12),border:const Border.fromBorderSide(BorderSide(color:Color(0xFFEEEEEE)))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize:14,fontWeight:FontWeight.w600)),
      const SizedBox(height:16),
      SizedBox(height:160, child: spots.isEmpty
        ? const Center(child: Text('No data', style: TextStyle(color:Color(0xFF9E9E9E))))
        : LineChart(LineChartData(
            gridData: const FlGridData(show:false),
            titlesData: const FlTitlesData(show:false),
            borderData: FlBorderData(show:false),
            lineBarsData: [LineChartBarData(
              spots: spots, isCurved: true, color: color,
              barWidth: 2.5,
              belowBarData: BarAreaData(show:true, color: color.withOpacity(0.1)),
              dotData: const FlDotData(show:false),
            )],
          ))),
    ]),
  );
}