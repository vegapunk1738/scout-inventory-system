import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/presentation/pages/admin/activity_log_admin_page.dart';
import 'package:scout_stock/presentation/pages/cart_page.dart';
import 'package:scout_stock/presentation/pages/me_page.dart';
import 'package:scout_stock/presentation/pages/scan_page.dart';
import 'package:scout_stock/presentation/widgets/admin_shell.dart';

import 'package:scout_stock/theme/app_theme.dart';

import 'state/providers/current_user_provider.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: userAsync.when(
        loading: () => const _AppLoadingScreen(),
        error: (e, _) => _AppErrorScreen(error: e.toString()),
        data: (user) {
          return user.role.isAdmin
              ? AdminShell(
                  pages: [
                    const ScanPage(),
                    const CartPage(),
                    MePage(),
                    const _PlaceholderPage(title: "Manage"),
                    const ActivityLogPage(),
                    const _PlaceholderPage(title: "Users"),
                  ],
                  initialIndex: 0,
                )
              : const ScanPage();
        },
      ),
    );
  }
}

class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AppErrorScreen extends StatelessWidget {
  const _AppErrorScreen({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Failed to load user:\n$error')));
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
