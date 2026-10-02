import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rooster_trader/shared/widgets/common/horizontalscroll_wheel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge system UI — only meaningful on Android/iOS.
  // On web/desktop these are no-ops, so safe to call unconditionally.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:              Colors.transparent,
    statusBarIconBrightness:     Brightness.light,
    systemNavigationBarColor:    Colors.transparent,
  ));

  // Portrait lock — Android phone only.
  // On web, macOS, Windows, Linux: allow free rotation / resizing.
  // On iOS we also respect free rotation (tablet landscape is common).
  final isAndroidPhone = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (isAndroidPhone) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  SupabaseConfig.assertConfigured();
  await Supabase.initialize(
    url:     SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType:    AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );
  runApp(const ProviderScope(child: RoosterTraderApp()));
}

class RoosterTraderApp extends ConsumerWidget {
  const RoosterTraderApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title:                    'Rooster Commerce OS',
    debugShowCheckedModeBanner: false,
    theme:                    AppTheme.light,
    scrollBehavior:           const AppScrollBehavior(),
    routerConfig:             ref.watch(appRouterProvider),
  );
}