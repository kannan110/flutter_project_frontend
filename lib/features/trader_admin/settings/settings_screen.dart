import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Profile
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color:AppTheme.primary,borderRadius:BorderRadius.circular(14)),
          child: Row(children: [
            CircleAvatar(backgroundColor:Colors.white24,radius:24,
              child: Text(user?.companyName?.substring(0,1).toUpperCase() ?? 'R',
                style: const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w700))),
            const SizedBox(width:14),
            Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(user?.companyName ?? 'Rooster Trader', style: const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700)),
              Text(user?.role.displayName ?? '—', style: const TextStyle(color:Colors.white70,fontSize:13)),
            ])),
          ])),
        const SizedBox(height:20),
        const SectionHeader('MANAGEMENT'),
        _Tile(Icons.store_outlined,          'Retailers',  'Manage your retail network',    () => context.go(Routes.retailers)),
        _Tile(Icons.person_outlined,         'Agents',     'Manage delivery agents',         () => context.go(Routes.agents)),
        _Tile(Icons.price_change_outlined,   'Set Rates',  'Set daily product rates',        () => context.go(Routes.rates)),
        _Tile(Icons.schedule_outlined,       'Shifts',     'Review agent shift reports',    () => context.go(Routes.shifts)),
        _Tile(Icons.inventory_2_outlined,    'Crates',     'Track crate balances',           () => context.go(Routes.crates)),
        const SizedBox(height:12),
        const SectionHeader('REPORTS'),
        _Tile(Icons.approval_outlined,       'Approvals',  'Review pending deliveries',      () => context.go(Routes.approvals)),
        _Tile(Icons.receipt_long_outlined,   'Invoices',   'All issued invoices',            () => context.go(Routes.invoices)),
        _Tile(Icons.bar_chart_outlined,      'Analytics',  'Business performance charts',   () => context.go(Routes.analytics)),
        const SizedBox(height:12),
        const SectionHeader('ACCOUNT'),
        _Tile(Icons.logout_outlined, 'Sign Out', 'Log out of this account', () async {
          final confirmed = await confirmDialog(context, title:'Sign Out', message:'Are you sure you want to sign out?', confirmText:'Sign Out');
          if (confirmed) ref.read(appUserProvider.notifier).signOut();
        }, color: AppTheme.errorRed),
        const SizedBox(height:20),
        Center(child: Text('Rooster Trader v2.0', style: TextStyle(fontSize:12,color:Colors.grey.shade400))),
      ]),
    );
  }
}
class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap, {this.color = AppTheme.primary});
  final IconData icon; final String title, subtitle; final VoidCallback onTap; final Color color;
  @override Widget build(BuildContext context) => ListTile(
    onTap: onTap, contentPadding: const EdgeInsets.symmetric(vertical:2,horizontal:4),
    leading: Container(width:40,height:40,decoration:BoxDecoration(color:color.withOpacity(0.1),borderRadius:BorderRadius.circular(10)),
      child: Icon(icon,color:color,size:20)),
    title: Text(title, style: const TextStyle(fontSize:14,fontWeight:FontWeight.w600)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize:12,color:Color(0xFF9E9E9E))),
    trailing: Icon(Icons.chevron_right,color:Colors.grey.shade400,size:18),
  );
}