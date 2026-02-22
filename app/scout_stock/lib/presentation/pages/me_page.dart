import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';

import 'package:scout_stock/state/notifiers/me_notifier.dart';
import 'package:scout_stock/state/providers/me_provider.dart';
import 'package:scout_stock/state/providers/current_user_provider.dart';

import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/presentation/widgets/checkout_result_dialog.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final notifier = ref.read(meProvider.notifier);

    final userAsync = ref.watch(currentUserProvider);

    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final top = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final compact = MediaQuery.sizeOf(context).width < 380;

    // Match CartPage shadow
    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ]
        : const <BoxShadow>[];

    // Bottom button sizing identical to CartPage
    final btnHeight = compact ? 62.0 : 66.0;
    final btnPadding = EdgeInsets.fromLTRB(
      compact ? 14 : 16,
      compact ? 8 : 10,
      compact ? 14 : 16,
      compact ? 10 : 12,
    );

    final bottomBarFootprint = btnHeight + btnPadding.vertical + safeBottom;
    final listBottomSpacer = bottomBarFootprint + 12;

    // User-derived header info (global user)
    final displayName = userAsync.maybeWhen(
      data: (u) => u.name,
      orElse: () => 'Loading…',
    );

    final role = userAsync.maybeWhen(
      data: (u) => u.role.isAdmin ? 'Admin' : 'Scout',
      orElse: () => '',
    );

    final initials = _initials(displayName);

    // Build rows (headers + borrowed + returned)
    final rows = _buildRows(
      mode: me.mode,
      borrowed: me.borrowed,
      returned: me.returned,
    );

    final rowsEmptyForMode = rows.isEmpty;

    String emptyTitle = "Nothing here yet";
    String emptySubtitle =
        "Checked out and returned items will show up on this page.";

    if (!me.hasAny) {
      emptyTitle = "Nothing here yet";
      emptySubtitle =
          "Checked out and returned items will show up on this page.";
    } else if (me.mode == MeFilterMode.borrowedOnly && me.borrowed.isEmpty) {
      emptyTitle = "No borrowed items";
      emptySubtitle = "When you check out gear, it will appear here.";
    } else if (me.mode == MeFilterMode.returnedOnly && me.returned.isEmpty) {
      emptyTitle = "No returns yet";
      emptySubtitle =
          "Returned items will show up here once you bring them back.";
    }

    Future<void> onReturn() async {
      if (me.submitting || me.totalToReturn == 0) return;

      final res = await notifier.submitReturn();
      if (!context.mounted) return;

      if (res.ok) {
        await showCheckoutResultDialog(
          context,
          child: CheckoutResultDialog.success(
            transactionId: res.txnId!,
            title: "Return Complete",
            message: "Items successfully returned.",
            onFinish: () {},
          ),
        );
      } else {
        await showCheckoutResultDialog(
          context,
          child: CheckoutResultDialog.failure(
            errorCode: res.error,
            onRetry: () {},
            onClose: () {},
          ),
          barrierDismissible: true,
        );
      }
    }

    final showBottomReturn =
        (me.mode != MeFilterMode.returnedOnly) &&
        me.totalToReturn > 0 &&
        me.borrowed.isNotEmpty;

    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    // List padding identical to CartPage
    final listSide = compact ? 12.0 : 14.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          Positioned.fill(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, top + 12, 20, 14),
                    child: _MeHeader(
                      name: displayName,
                      role: role,
                      initials: initials,
                      onSettings: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Settings coming soon")),
                        );
                      },
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _BorrowReturnPills(
                      mode: me.mode,
                      onTapBorrowed: () =>
                          notifier.toggleMode(MeFilterMode.borrowedOnly),
                      onTapReturned: () =>
                          notifier.toggleMode(MeFilterMode.returnedOnly),
                    ),
                  ),
                ),
                if (rowsEmptyForMode)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyMeState(
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(listSide, 0, listSide, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, i) {
                        final r = rows[i];

                        if (r.kind == _MeRowKind.header) {
                          return KeyedSubtree(
                            key: ValueKey("h_${r.header}"),
                            child: _DateHeader(
                              title: r.header!,
                              topGap: r.topGap,
                            ),
                          );
                        }

                        if (r.kind == _MeRowKind.borrowed) {
                          final line = r.borrowed!;
                          return Padding(
                            key: ValueKey("b_${line.id}"),
                            padding: EdgeInsets.only(bottom: compact ? 10 : 12),
                            child: RepaintBoundary(
                              child: _BorrowedCard(
                                record: line,
                                compact: compact,
                                tokens: tokens,
                                shadow: shadow,
                                textTheme: t,
                                emojiBase: emojiBase,
                                onChanged: (next) =>
                                    notifier.setToReturn(line.id, next),
                              ),
                            ),
                          );
                        }

                        final crossline = me.mode == MeFilterMode.returnedOnly;
                        final faded =
                            (me.mode == MeFilterMode.all) ||
                            (me.mode == MeFilterMode.returnedOnly);

                        final line = r.returned!;
                        return Padding(
                          key: ValueKey("r_${line.id}"),
                          padding: EdgeInsets.only(bottom: compact ? 10 : 12),
                          child: RepaintBoundary(
                            child: _ReturnedCard(
                              record: line,
                              compact: compact,
                              tokens: tokens,
                              shadow: shadow,
                              textTheme: t,
                              emojiBase: emojiBase,
                              faded: faded,
                              crossline: crossline,
                            ),
                          ),
                        );
                      }, childCount: rows.length),
                    ),
                  ),

                // Spacer so last item can scroll fully above the fixed button
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: showBottomReturn ? listBottomSpacer : 22,
                  ),
                ),
              ],
            ),
          ),

          // Soft scrim behind the fixed bottom button (same idea as CartPage)
          if (showBottomReturn)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: bottomBarFootprint + 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withValues(alpha: 0.0),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (showBottomReturn)
            Align(
              alignment: Alignment.bottomCenter,
              child: GlowingActionButton(
                label: me.totalToReturn == 1
                    ? "Return Items (1)"
                    : "Return Items (${me.totalToReturn})",
                icon: const Icon(Icons.keyboard_return_rounded),
                loading: me.submitting,
                onPressed: me.submitting ? null : onReturn,
                padding: btnPadding, // identical to CartPage
                height: btnHeight, // identical to CartPage
              ),
            ),
        ],
      ),
    );
  }
}

/* ----------------------------- Header ----------------------------- */

class _MeHeader extends StatelessWidget {
  const _MeHeader({
    required this.name,
    required this.role,
    required this.initials,
    required this.onSettings,
  });

  final String name;
  final String role;
  final String initials;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.onPrimary,
          child: Text(
            initials,
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.headlineMedium?.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                role,
                style: t.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Visibility(
          visible: false,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(color: AppColors.outline),
            ),
            child: IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.settings_rounded),
              splashRadius: 22,
            ),
          ),
        ),
      ],
    );
  }
}

/* ----------------------------- Filter Pills ----------------------------- */

class _BorrowReturnPills extends StatelessWidget {
  const _BorrowReturnPills({
    required this.mode,
    required this.onTapBorrowed,
    required this.onTapReturned,
  });

  final MeFilterMode mode;
  final VoidCallback onTapBorrowed;
  final VoidCallback onTapReturned;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final borrowedSelected = mode == MeFilterMode.borrowedOnly;
    final returnedSelected = mode == MeFilterMode.returnedOnly;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        border: Border.all(color: AppColors.outline),
        boxShadow: tokens.cardShadow,
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: _Pill(
              label: "Borrowed",
              selected: borrowedSelected,
              selectedBg: AppColors.primary,
              selectedFg: Colors.white,
              unselectedFg: AppColors.muted,
              textStyle: t.titleMedium,
              onTap: onTapBorrowed,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _Pill(
              label: "Returned",
              selected: returnedSelected,
              selectedBg: AppColors.ink.withValues(alpha: 0.72),
              selectedFg: Colors.white,
              unselectedFg: AppColors.muted,
              textStyle: t.titleMedium,
              onTap: onTapReturned,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.selectedFg,
    required this.unselectedFg,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBg;
  final Color selectedFg;
  final Color unselectedFg;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusXl),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusXl),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: (textStyle ?? const TextStyle()).copyWith(
            color: selected ? selectedFg : unselectedFg,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/* ----------------------------- Rows ----------------------------- */

enum _MeRowKind { header, borrowed, returned }

class _MeRow {
  const _MeRow.header(this.header, {this.topGap = 0})
    : kind = _MeRowKind.header,
      borrowed = null,
      returned = null;

  const _MeRow.borrowed(this.borrowed)
    : kind = _MeRowKind.borrowed,
      header = null,
      returned = null,
      topGap = 0;

  const _MeRow.returned(this.returned)
    : kind = _MeRowKind.returned,
      header = null,
      borrowed = null,
      topGap = 0;

  final _MeRowKind kind;
  final String? header;
  final BorrowedRecord? borrowed;
  final ReturnedRecord? returned;
  final double topGap;
}

List<_MeRow> _buildRows({
  required MeFilterMode mode,
  required List<BorrowedRecord> borrowed,
  required List<ReturnedRecord> returned,
}) {
  final includeBorrowed = mode != MeFilterMode.returnedOnly;
  final includeReturned = mode != MeFilterMode.borrowedOnly;

  final map = <DateTime, List<_MeRow>>{};

  if (includeBorrowed) {
    for (final b in borrowed) {
      final key = _dateOnly(b.checkedOutAt);
      (map[key] ??= <_MeRow>[]).add(_MeRow.borrowed(b));
    }
  }

  if (includeReturned) {
    for (final r in returned) {
      final key = _dateOnly(r.returnedAt);
      (map[key] ??= <_MeRow>[]).add(_MeRow.returned(r));
    }
  }

  if (map.isEmpty) return const <_MeRow>[];

  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));

  final rows = <_MeRow>[];
  for (int i = 0; i < keys.length; i++) {
    final day = keys[i];
    rows.add(_MeRow.header(_sectionTitle(day), topGap: i == 0 ? 0 : 18));

    final bucket = map[day]!;
    final borrowedRows = bucket
        .where((x) => x.kind == _MeRowKind.borrowed)
        .toList();
    final returnedRows = bucket
        .where((x) => x.kind == _MeRowKind.returned)
        .toList();

    borrowedRows.sort(
      (a, b) => a.borrowed!.item.name.compareTo(b.borrowed!.item.name),
    );
    returnedRows.sort(
      (a, b) => a.returned!.item.name.compareTo(b.returned!.item.name),
    );

    rows.addAll(borrowedRows);
    rows.addAll(returnedRows);
  }

  return rows;
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.title, required this.topGap});

  final String title;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isToday = title.contains("(TODAY)");

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: t.labelMedium?.copyWith(
                  color: isToday ? AppColors.primary : AppColors.muted,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/* ----------------------------- Borrowed Card (MATCH CART SCALE) ----------------------------- */

class _BorrowedCard extends StatelessWidget {
  const _BorrowedCard({
    required this.record,
    required this.compact,
    required this.tokens,
    required this.shadow,
    required this.textTheme,
    required this.emojiBase,
    required this.onChanged,
  });

  final BorrowedRecord record;
  final bool compact;
  final AppTokens tokens;
  final List<BoxShadow> shadow;
  final TextTheme textTheme;
  final TextStyle emojiBase;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 42.0 : 48.0;
    final emojiSize = compact ? 22.0 : 26.0;

    final item = record.item;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 10 : 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.emoji,
                  style: emojiBase.copyWith(fontSize: emojiSize),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 15 : 16,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.bucketName} | ${item.bucketId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 11.5 : 12,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),

          // ✅ tap + hold accelerator
          _ReturnQtyStepperHold(
            value: item.quantity,
            max: item.maxQuantity,
            compact: compact,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Returned Card (MATCH CART SCALE) ----------------------------- */

class _ReturnedCard extends StatelessWidget {
  const _ReturnedCard({
    required this.record,
    required this.compact,
    required this.tokens,
    required this.shadow,
    required this.textTheme,
    required this.emojiBase,
    required this.faded,
    required this.crossline,
  });

  final ReturnedRecord record;
  final bool compact;
  final AppTokens tokens;
  final List<BoxShadow> shadow;
  final TextTheme textTheme;
  final TextStyle emojiBase;
  final bool faded;
  final bool crossline;

  @override
  Widget build(BuildContext context) {
    final tile = compact ? 42.0 : 48.0;
    final emojiSize = compact ? 22.0 : 26.0;

    final item = record.item;

    final base = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 10 : 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.emoji,
                  style: emojiBase.copyWith(fontSize: emojiSize),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 15 : 16,
                          height: 1.15,
                          color: AppColors.muted,
                          decoration: crossline
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.bucketName} | ${item.bucketId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 11.5 : 12,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(compact: compact),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          _ReturnedQtyBar(
            returned: item.quantity,
            max: item.maxQuantity,
            compact: compact,
          ),
        ],
      ),
    );

    return faded ? Opacity(opacity: 0.45, child: base) : base;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final box = compact ? 34.0 : 38.0;
    final iconSize = compact ? 18.0 : 20.0;

    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.check_rounded, size: iconSize, color: AppColors.muted),
    );
  }
}

/* ----------------------------- Return Stepper (tap + hold) ----------------------------- */

class _ReturnQtyStepperHold extends StatelessWidget {
  const _ReturnQtyStepperHold({
    required this.value,
    required this.max,
    required this.compact,
    required this.onChanged,
  });

  final int value;
  final int max;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canMinus = value > 0;
    final canPlus = value < max;

    // identical to CartPage stepper sizing
    final height = compact ? 50.0 : 56.0;
    final btnSize = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;

    final disabledFg = AppColors.muted.withValues(alpha: 0.45);

    int clampNext(int next) => next.clamp(0, max);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const SizedBox(width: 6),

          // MINUS (tap + hold)
          HoldIconButton(
            enabled: canMinus,
            maxCount: max,
            icon: Icons.remove_rounded,
            iconColor: canMinus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canMinus ? () => onChanged(clampNext(value - 1)) : null,
            onHoldTick: canMinus
                ? (step) => onChanged(clampNext(value - step))
                : null,
          ),

          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'of $max to be returned',
                    style: t.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // PLUS (tap + hold)
          HoldIconButton(
            enabled: canPlus,
            maxCount: max,
            icon: Icons.add_rounded,
            iconColor: canPlus ? AppColors.primary : disabledFg,
            fill: AppColors.background,
            border: Colors.transparent,
            width: btnSize,
            height: btnSize,
            iconSize: iconSize,
            radius: tokens.radiusLg,
            onTap: canPlus ? () => onChanged(clampNext(value + 1)) : null,
            onHoldTick: canPlus
                ? (step) => onChanged(clampNext(value + step))
                : null,
          ),

          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _ReturnedQtyBar extends StatelessWidget {
  const _ReturnedQtyBar({
    required this.returned,
    required this.max,
    required this.compact,
  });

  final int returned;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final height = compact ? 50.0 : 56.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: AppColors.outline),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$returned',
            style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'of $max returned',
            style: t.bodySmall?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- Empty ----------------------------- */

class _EmptyMeState extends StatelessWidget {
  const _EmptyMeState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.outline),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.muted,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: t.bodyMedium?.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/* ----------------------------- Helpers ----------------------------- */

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r"\s+"))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return "?";
  if (parts.length == 1) {
    final s = parts.first;
    return (s.length >= 2 ? s.substring(0, 2) : s.substring(0, 1))
        .toUpperCase();
  }
  return "${parts.first[0]}${parts.last[0]}".toUpperCase();
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _sectionTitle(DateTime d) {
  final today = _dateOnly(DateTime.now());
  final isToday = _dateOnly(d) == today;

  const months = [
    "JANUARY",
    "FEBRUARY",
    "MARCH",
    "APRIL",
    "MAY",
    "JUNE",
    "JULY",
    "AUGUST",
    "SEPTEMBER",
    "OCTOBER",
    "NOVEMBER",
    "DECEMBER",
  ];

  final base = "${months[d.month - 1]} ${d.day}";
  return isToday ? "$base (TODAY)" : base;
}
