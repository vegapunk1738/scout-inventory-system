import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scout_stock/theme/app_theme.dart';

/// Provides current selected scout tab index to descendant widgets.
class ScoutShellScope extends InheritedNotifier<ValueNotifier<int>> {
  const ScoutShellScope({
    super.key,
    required ValueNotifier<int> indexListenable,
    required super.child,
  }) : super(notifier: indexListenable);

  static ValueNotifier<int>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ScoutShellScope>()
        ?.notifier;
  }
}

/// ---------------------------------------------------------------------------
/// GoRouter shell for **scout** (non-admin) users.
/// 3 tabs: Scan · Cart · Me
/// Same glass/solid animated nav style as [AdminRouterShell].
/// ---------------------------------------------------------------------------
class ScoutRouterShell extends StatefulWidget {
  const ScoutRouterShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<ScoutRouterShell> createState() => _ScoutRouterShellState();
}

class _ScoutRouterShellState extends State<ScoutRouterShell> {
  late final ValueNotifier<int> _index =
      ValueNotifier<int>(widget.navigationShell.currentIndex);

  @override
  void didUpdateWidget(covariant ScoutRouterShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.navigationShell.currentIndex;
    if (_index.value != current) {
      _index.value = current;
    }
  }

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  void _onTap(int next) {
    final current = widget.navigationShell.currentIndex;
    final bool goToInitial = next == current;

    _index.value = next;
    widget.navigationShell.goBranch(
      next,
      initialLocation: goToInitial,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScoutShellScope(
      indexListenable: _index,
      child: Scaffold(
        extendBody: true,
        body: widget.navigationShell,
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: _index,
          builder: (_, i, _) => _ScoutBottomNav(index: i, onTap: _onTap),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom nav — animated glass / solid switch (identical style to admin nav)
// ---------------------------------------------------------------------------

class _ScoutBottomNav extends StatelessWidget {
  const _ScoutBottomNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final transparent = index == 0; // glass on Scan tab

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          reverseDuration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.bottomCenter,
              children: <Widget>[...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: transparent
              ? _ScoutGlassNav(
                  key: const ValueKey("glass"),
                  index: index,
                  onTap: onTap,
                )
              : _ScoutSolidNav(
                  key: const ValueKey("solid"),
                  index: index,
                  onTap: onTap,
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Solid variant (white background)
// ---------------------------------------------------------------------------

class _ScoutSolidNav extends StatelessWidget {
  const _ScoutSolidNav({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(tokens.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          border: Border.all(color: AppColors.outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.qr_code_scanner_rounded,
                label: "Scan",
                selected: index == 0,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(0),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.shopping_cart_outlined,
                label: "Cart",
                selected: index == 1,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(1),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.person_rounded,
                label: "Me",
                selected: index == 2,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass variant (frosted dark background — used on the Scan tab)
// ---------------------------------------------------------------------------

class _ScoutGlassNav extends StatelessWidget {
  const _ScoutGlassNav({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final selectedColor = AppColors.primary;
    final unselectedColor = Colors.white.withValues(alpha: 0.70);

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.qr_code_scanner_rounded,
                  label: "Scan",
                  selected: index == 0,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.shopping_cart_outlined,
                  label: "Cart",
                  selected: index == 1,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.person_rounded,
                  label: "Me",
                  selected: index == 2,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared nav item (identical to admin_shell.dart's _NavItem)
// ---------------------------------------------------------------------------

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.labelStyle,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final TextStyle? labelStyle;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;

    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: SizedBox(
        height: 58,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: (labelStyle ?? const TextStyle()).copyWith(
                  color: color,
                  letterSpacing: 0,
                  fontSize: 10.0,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}