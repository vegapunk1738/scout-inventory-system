import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scout_stock/router/app_router.dart';
import 'package:scout_stock/presentation/widgets/app_toast.dart';
import 'package:scout_stock/presentation/widgets/session_guard.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';
import 'package:scout_stock/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Lock to portrait on mobile — no-op on web (handled by max-width constraint).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      // Constrain to mobile width only on wide screens (desktop / web browser).
      // On iPhone / iPad the child renders full-width with zero overhead.
      builder: (context, child) {
        // Session heartbeat — refreshes JWT on app resume + every 5 min.
        // Toast overlay — stacking notifications, non-blocking.
        final guarded = AppToastOverlay(
          child: SessionGuard(child: child!),
        );

        final screenWidth = MediaQuery.sizeOf(context).width;
        const tabletMax = 1024.0;
        const mobileMax = 430.0;

        // Phone or tablet — no wrapper, no extra layers.
        if (screenWidth <= tabletMax) return guarded;

        // Desktop / wide web — centered column with blurry edge shadow.
        return ColoredBox(
          color: AppColors.background,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: mobileMax),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.08),
                    blurRadius: 60,
                    spreadRadius: 8,
                  ),
                ],
              ),
              clipBehavior: Clip.none,
              child: guarded,
            ),
          ),
        );
      },
    );
  }
}