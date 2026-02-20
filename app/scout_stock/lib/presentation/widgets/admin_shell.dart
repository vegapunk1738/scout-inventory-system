import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.pages, this.initialIndex = 0});
  final List<Widget> pages;
  final int initialIndex;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

/// Lets any page know which bottom-nav tab is active.
class AdminShellScope extends InheritedNotifier<ValueNotifier<int>> {
  const AdminShellScope({
    super.key,
    required ValueNotifier<int> indexListenable,
    required super.child,
  }) : super(notifier: indexListenable);

  static ValueNotifier<int>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AdminShellScope>()
        ?.notifier;
  }
}

class _AdminShellState extends State<AdminShell> {
  late final ValueNotifier<int> _index = ValueNotifier<int>(
    widget.initialIndex,
  );

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminShellScope(
      indexListenable: _index,
      child: Scaffold(
        extendBody: true, // lets camera show behind glass nav
        body: ValueListenableBuilder<int>(
          valueListenable: _index,
          builder: (_, i, _) => IndexedStack(index: i, children: widget.pages),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: _index,
          builder: (_, i, _) =>
              _AdminBottomNav(index: i, onTap: (next) => _index.value = next),
        ),
      ),
    );
  }
}

/* ----------------------------- NAV ----------------------------- */
class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final transparent = index == 0; // only Scan

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
              ? _GlassNav(
                  key: const ValueKey("glass"),
                  index: index,
                  onTap: onTap,
                )
              : _SolidNav(
                  key: const ValueKey("solid"),
                  index: index,
                  onTap: onTap,
                ),
        ),
      ),
    );
  }
}

class _SolidNav extends StatelessWidget {
  const _SolidNav({super.key, required this.index, required this.onTap});

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
            SizedBox(
              height: 44,
              child: VerticalDivider(
                width: 18,
                thickness: 1,
                color: AppColors.outline,
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.inventory_2_outlined,
                label: "Manage",
                selected: index == 3,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(3),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.access_time_rounded,
                label: "Activity",
                selected: index == 4,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(4),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.group_rounded,
                label: "Users",
                selected: index == 5,
                labelStyle: t.labelMedium,
                selectedColor: AppColors.primary,
                unselectedColor: AppColors.muted,
                onTap: () => onTap(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassNav extends StatelessWidget {
  const _GlassNav({super.key, required this.index, required this.onTap});

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
        // Lower blur = much cheaper, still looks “glass”.
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
              SizedBox(
                height: 44,
                child: VerticalDivider(
                  width: 18,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.inventory_2_outlined,
                  label: "Manage",
                  selected: index == 3,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.access_time_rounded,
                  label: "Activity",
                  selected: index == 4,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(4),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.group_rounded,
                  label: "Users",
                  selected: index == 5,
                  labelStyle: t.labelMedium,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
