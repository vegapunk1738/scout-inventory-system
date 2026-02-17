import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/pages/activity_log_admin_page.dart';
import 'package:scout_stock/pages/cart_page.dart';
import 'package:scout_stock/pages/scan_page.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/widgets/admin_shell.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const bool isAdmin = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: isAdmin
          ? AdminShell(
              pages: const [
                ScanPage(),
                CartPage(),
                _PlaceholderPage(title: "Me"),
                _PlaceholderPage(title: "Manage"),
                ActivityLogPage(),
                _PlaceholderPage(title: "Users"),
              ],
              initialIndex: 0,
            )
          : const ScanPage(),
    );
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
