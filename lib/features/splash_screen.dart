import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/session_provider.dart';
import '../core/router/app_router.dart';
import '../core/theme/app_theme.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Force status bar to be transparent with light icons over red bg
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final session = ref.watch(appUserProvider);

    return session.when(
      loading: () => _buildSplash(),
      error: (e, st) => _buildError(context, ref, e),
      data: (user) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (user == null)                    context.go(R.login);
          else if (user.isSuperAdmin)          context.go(R.superAdmin);
          else if (user.isDeliveryAgent)       context.go(R.agentHome);
          else if (user.isUnlinked)            context.go(R.traderSetup);
          else                                 context.go(R.dashboard);
        });
        return _buildSplash();
      },
    );
  }

  Widget _buildSplash() => Scaffold(
    backgroundColor: kPrimary,
    body: Stack(children: [
      // Red background
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFC41C2E), Color(0xFFAA0E1E)],
          ))),

      // Main content
      Column(children: [
        const Spacer(flex: 2),

        // Logo circle
        Center(child: Container(
          width: 160, height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 24, offset: const Offset(0, 8)),
            ]),
          child: Stack(alignment: Alignment.center, children: [
            // Rooster icon using layered shapes
            CustomPaint(size: const Size(110, 110), painter: _RoosterPainter()),
          ]))),
        const SizedBox(height: 28),

        // App name
        const Text('ROOSTER',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 6,
              height: 1,
            )),
        const SizedBox(height: 6),
        Text('TRADER',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 4,
            )),

        const Spacer(flex: 3),

        // Loading indicator
        SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 32),

        // Grey wave footer
        ClipPath(
          clipper: _WaveClipper(),
          child: Container(
            height: 140,
            color: const Color(0xFFE8E8E8),
            child: Padding(
              padding: const EdgeInsets.only(top: 36, bottom: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Developed by',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF666666),
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  // TEAM4YOU logo text
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('TEAM',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900,
                            color: Color(0xFF1A2B6B), letterSpacing: 1)),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      width: 28, height: 28,
                      decoration: const BoxDecoration(
                          color: Color(0xFFBF1B2C), shape: BoxShape.circle),
                      child: const Center(child: Text('4',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              color: Colors.white)))),
                    const Text('YOU',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900,
                            color: Color(0xFF1A2B6B), letterSpacing: 1)),
                  ]),
                ],
              ))),
        ),
      ]),
    ]),
  );

  Widget _buildError(BuildContext context, WidgetRef ref, Object e) => Scaffold(
    backgroundColor: kPrimary,
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
            child: const Center(
                child: Icon(Icons.error_outline, color: Colors.white, size: 40))),
        const SizedBox(height: 24),
        const Text('Connection Error',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: Colors.white)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Text(
            e.toString()
                .replaceAll('Exception: ', '')
                .replaceAll('PostgrestException(message: ', '')
                .replaceAll(')', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13,
                height: 1.5))),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPrimary,
              minimumSize: const Size(200, 50)),
          onPressed: () => ref.read(appUserProvider.notifier).reload(),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () async {
            await ref.read(appUserProvider.notifier).signOut();
            if (context.mounted) context.go(R.login);
          },
          child: const Text('Sign Out',
              style: TextStyle(color: Colors.white70, fontSize: 13,
                  fontWeight: FontWeight.w600))),
      ]))));
}

// Wave clipper for footer
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 30);
    path.quadraticBezierTo(size.width * 0.25, 0, size.width * 0.5, 20);
    path.quadraticBezierTo(size.width * 0.75, 40, size.width, 10);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }
  @override bool shouldReclip(_) => false;
}

// Custom rooster icon painter
class _RoosterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Navy blue outer ring / eye ring
    final ringPaint = Paint()
      ..color = const Color(0xFF1A2B6B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 50, ringPaint);

    // White inner circle
    final whitePaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 36, whitePaint);

    // Red iris
    final redPaint = Paint()
      ..color = const Color(0xFFBF1B2C)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 26, redPaint);

    // Dark pupil
    final pupilPaint = Paint()..color = const Color(0xFF1A1A1A)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy + 2), 12, pupilPaint);

    // Red comb (top)
    final combPaint = Paint()..color = const Color(0xFFBF1B2C)..style = PaintingStyle.fill;
    final combPath = Path()
      ..moveTo(cx - 14, cy - 36)
      ..quadraticBezierTo(cx - 20, cy - 55, cx - 10, cy - 60)
      ..quadraticBezierTo(cx - 4,  cy - 50, cx,     cy - 38)
      ..quadraticBezierTo(cx + 6,  cy - 52, cx + 14, cy - 56)
      ..quadraticBezierTo(cx + 18, cy - 44, cx + 10, cy - 36)
      ..close();
    canvas.drawPath(combPath, combPaint);

    // Small beak / wattle
    final beakPath = Path()
      ..moveTo(cx + 36, cy + 5)
      ..lineTo(cx + 48, cy + 12)
      ..lineTo(cx + 36, cy + 20)
      ..close();
    canvas.drawPath(beakPath, Paint()..color = const Color(0xFFE8A020));

    // Red wattle below beak
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 38, cy + 26), width: 12, height: 16),
      Paint()..color = const Color(0xFFBF1B2C));
  }

  @override bool shouldRepaint(_) => false;
}
