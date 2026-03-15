import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:scout_stock/presentation/widgets/checkout_result_dialog.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/presentation/widgets/glowing_action_button.dart';
import 'package:scout_stock/presentation/widgets/hold_icon_button.dart';
import 'package:scout_stock/state/notifiers/me_notifier.dart';
import 'package:scout_stock/state/providers/auth_providers.dart';
import 'package:scout_stock/state/providers/me_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Formats a DateTime to "2:30 PM" style in the device's local timezone.
String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$h12:$minute $period';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';

  if (parts.length == 1) {
    final s = parts.first;
    return (s.length >= 2 ? s.substring(0, 2) : s.substring(0, 1))
        .toUpperCase();
  }

  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _sectionTitle(DateTime d) {
  final today = _dateOnly(DateTime.now());
  final isToday = _dateOnly(d) == today;

  const months = [
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
  ];

  final base = '${months[d.month - 1]} ${d.day}';
  return isToday ? '$base (TODAY)' : base;
}

// ─── Page ───────────────────────────────────────────────────────────────────

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final notifier = ref.read(meProvider.notifier);
    final user = ref.watch(currentUserProvider);

    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final top = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final compact = MediaQuery.sizeOf(context).width < 380;

    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ]
        : const <BoxShadow>[];

    final displayName = user?.name ?? 'Loading…';
    final role = user == null ? '' : (user.role.isAdmin ? 'Admin' : 'Scout');
    final initials = _initials(displayName);

    final rows = _buildRows(
      mode: me.mode,
      borrowed: me.borrowed,
      returned: me.returned,
    );

    final rowsEmptyForMode = rows.isEmpty;

    String emptyTitle = 'Nothing here yet';
    String emptySubtitle =
        'Checked out and returned items will show up on this page';
    String emptyEmoji = '📦';

    if (!me.hasAny) {
      emptyTitle = 'Nothing here yet';
      emptySubtitle =
          'Checked out and returned items will show up on this page';
      emptyEmoji = '📦';
    } else if (me.mode == MeFilterMode.borrowedOnly && me.borrowed.isEmpty) {
      emptyTitle = 'No borrowed items';
      emptySubtitle = 'When you check out gear, it will appear here';
      emptyEmoji = '📤';
    } else if (me.mode == MeFilterMode.returnedOnly && me.returned.isEmpty) {
      emptyTitle = 'No returns yet';
      emptySubtitle =
          'Returned items will show up here once you bring them back';
      emptyEmoji = '📥';
    }

    Future<void> onReturn() async {
      if (me.submitting || me.totalToReturn == 0) return;

      final res = await notifier.submitReturn();
      if (!context.mounted) return;
      if (res.ok) {
        await showCheckoutResultDialog(
          context,
          child: CheckoutResultDialog.returnSuccess(
            itemCount: me.totalToReturn,
            onFinish: () {},
          ),
        );
      } else {
        await showCheckoutResultDialog(
          context,
          child: CheckoutResultDialog.failure(
            errorMessage: res.error,
            onRetry: () {},
            onClose: () {},
          ),
          barrierDismissible: true,
        );
      }
    }

    Future<void> onLogout() async {
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Log out?'),
            content: const Text(
              'You will need to sign in again to access Scout Stock.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Log out'),
              ),
            ],
          );
        },
      );

      if (shouldLogout != true) return;
      await ref.read(authControllerProvider.notifier).logout();
    }

    final showBottomReturn =
        (me.mode != MeFilterMode.returnedOnly) &&
        me.totalToReturn > 0 &&
        me.borrowed.isNotEmpty;

    final btnHeight = compact ? 62.0 : 66.0;
    final btnPadTop = compact ? 8.0 : 10.0;
    final btnPadBottom = compact ? 10.0 : 12.0;

    final bottomBarFootprint = showBottomReturn
        ? (btnHeight + btnPadTop + btnPadBottom + safeBottom)
        : 0.0;

    final double listBottomPadding = showBottomReturn
        ? (bottomBarFootprint + 12.0)
        : (safeBottom + 14.0);

    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final listSide = compact ? 12.0 : 14.0;
    final stickyExtent = (top + 12) + 44 + 14 + 56 + 12;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          Positioned.fill(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _MeStickyHeaderDelegate(
                    extent: stickyExtent,
                    top: top,
                    name: displayName,
                    role: role,
                    initials: initials,
                    mode: me.mode,
                    onTapBorrowed: () {
                      notifier.toggleMode(MeFilterMode.borrowedOnly);
                    },
                    onTapReturned: () {
                      notifier.toggleMode(MeFilterMode.returnedOnly);
                    },
                    onLogout: onLogout,
                  ),
                ),
                if (rowsEmptyForMode)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: safeBottom + 14),
                      child: _EmptyMeState(
                        emptyTitle: emptyTitle,
                        emptySubtitle: emptySubtitle,
                        emptyEmoji: emptyEmoji,
                        emojiBase: emojiBase,
                        titleStyle: t.titleLarge,
                        bodyStyle: t.bodyLarge?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
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
                            key: ValueKey('h_${r.header}'),
                            child: _DateHeader(
                              title: r.header!,
                              topGap: r.topGap,
                            ),
                          );
                        }

                        if (r.kind == _MeRowKind.borrowed) {
                          final line = r.borrowed!;
                          return Padding(
                            key: ValueKey('b_${line.id}'),
                            padding: EdgeInsets.only(bottom: compact ? 10 : 12),
                            child: RepaintBoundary(
                              child: _BorrowedCard(
                                record: line,
                                compact: compact,
                                tokens: tokens,
                                shadow: shadow,
                                textTheme: t,
                                emojiBase: emojiBase,
                                onChanged: (next) {
                                  notifier.setToReturn(line.id, next);
                                },
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
                          key: ValueKey('r_${line.id}'),
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
                SliverToBoxAdapter(child: SizedBox(height: listBottomPadding)),
              ],
            ),
          ),
          if (showBottomReturn) ...[
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
            Align(
              alignment: Alignment.bottomCenter,
              child: GlowingActionButton(
                label: me.totalToReturn == 1
                    ? 'Return Items (1)'
                    : 'Return Items (${me.totalToReturn})',
                icon: const Icon(Icons.keyboard_return_rounded),
                loading: me.submitting,
                onPressed: me.submitting ? null : onReturn,
                height: btnHeight,
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 16,
                  btnPadTop,
                  compact ? 14 : 16,
                  btnPadBottom,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Sticky header ──────────────────────────────────────────────────────────

class _MeStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MeStickyHeaderDelegate({
    required this.extent,
    required this.top,
    required this.name,
    required this.role,
    required this.initials,
    required this.mode,
    required this.onTapBorrowed,
    required this.onTapReturned,
    required this.onLogout,
  });

  final double extent;
  final double top;
  final String name;
  final String role;
  final String initials;
  final MeFilterMode mode;
  final VoidCallback onTapBorrowed;
  final VoidCallback onTapReturned;
  final VoidCallback onLogout;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final showShadow = overlapsContent || shrinkOffset > 0.5;

    final headerShadow = showShadow && tokens.cardShadow.isNotEmpty
        ? [tokens.cardShadow.first.copyWith(blurRadius: 10, offset: const Offset(0, 6))]
        : const <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(color: AppColors.background, boxShadow: headerShadow),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 12, 20, 12),
        child: Column(
          children: [
            _MeHeader(name: name, role: role, initials: initials, onLogout: onLogout),
            const SizedBox(height: 14),
            _BorrowReturnPills(mode: mode, onTapBorrowed: onTapBorrowed, onTapReturned: onTapReturned),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MeStickyHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent || top != oldDelegate.top ||
        name != oldDelegate.name || role != oldDelegate.role ||
        initials != oldDelegate.initials || mode != oldDelegate.mode ||
        onLogout != oldDelegate.onLogout;
  }
}

class _MeHeader extends StatelessWidget {
  const _MeHeader({required this.name, required this.role, required this.initials, required this.onLogout});
  final String name, role, initials;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.onPrimary,
          child: Text(initials, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headlineMedium?.copyWith(fontSize: 20)),
              const SizedBox(height: 2),
              Text(role, style: t.titleMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
        ),
        SizedBox(
          width: 44, height: 44,
          child: IconButton(onPressed: onLogout, icon: const Icon(Icons.logout_rounded), splashRadius: 22, tooltip: 'Logout'),
        ),
      ],
    );
  }
}

class _BorrowReturnPills extends StatelessWidget {
  const _BorrowReturnPills({required this.mode, required this.onTapBorrowed, required this.onTapReturned});
  final MeFilterMode mode;
  final VoidCallback onTapBorrowed, onTapReturned;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;
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
          Expanded(child: _Pill(label: 'Borrowed', selected: mode == MeFilterMode.borrowedOnly, selectedBg: AppColors.primary, selectedFg: Colors.white, unselectedFg: AppColors.muted, textStyle: t.titleMedium, onTap: onTapBorrowed)),
          const SizedBox(width: 6),
          Expanded(child: _Pill(label: 'Returned', selected: mode == MeFilterMode.returnedOnly, selectedBg: AppColors.ink.withValues(alpha: 0.72), selectedFg: Colors.white, unselectedFg: AppColors.muted, textStyle: t.titleMedium, onTap: onTapReturned)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.selectedBg, required this.selectedFg, required this.unselectedFg, required this.textStyle, required this.onTap});
  final String label;
  final bool selected;
  final Color selectedBg, selectedFg, unselectedFg;
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
        decoration: BoxDecoration(color: selected ? selectedBg : Colors.transparent, borderRadius: BorderRadius.circular(tokens.radiusXl)),
        alignment: Alignment.center,
        child: Text(label, style: (textStyle ?? const TextStyle()).copyWith(color: selected ? selectedFg : unselectedFg, fontWeight: FontWeight.w800, fontSize: 14)),
      ),
    );
  }
}

// ─── Row model ──────────────────────────────────────────────────────────────

enum _MeRowKind { header, borrowed, returned }

class _MeRow {
  const _MeRow.header(this.header, {this.topGap = 0}) : kind = _MeRowKind.header, borrowed = null, returned = null;
  const _MeRow.borrowed(this.borrowed) : kind = _MeRowKind.borrowed, header = null, returned = null, topGap = 0;
  const _MeRow.returned(this.returned) : kind = _MeRowKind.returned, header = null, borrowed = null, topGap = 0;

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
    final borrowedRows = bucket.where((x) => x.kind == _MeRowKind.borrowed).toList();
    final returnedRows = bucket.where((x) => x.kind == _MeRowKind.returned).toList();

    borrowedRows.sort((a, b) => a.borrowed!.item.name.compareTo(b.borrowed!.item.name));
    returnedRows.sort((a, b) => a.returned!.item.name.compareTo(b.returned!.item.name));

    rows.addAll(borrowedRows);
    rows.addAll(returnedRows);
  }

  return rows;
}

// ─── Date header ────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.title, required this.topGap});
  final String title;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isToday = title.contains('(TODAY)');
    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 12),
      child: Column(
        children: [
          Row(children: [
            Text(title, style: t.labelMedium?.copyWith(color: isToday ? AppColors.primary : AppColors.muted, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Metadata pill (right side) ─────────────────────────────────────────────

class _MetaInfoColumn extends StatelessWidget {
  const _MetaInfoColumn({
    required this.managedBy,
    required this.actionLabel,
    required this.timeString,
    required this.compact,
  });

  final String managedBy;
  final String actionLabel;
  final String timeString;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final labelStyle = t.bodySmall?.copyWith(
      color: AppColors.muted,
      fontWeight: FontWeight.w600,
      fontSize: compact ? 9.5 : 10,
      height: 1.2,
    );
    final valueStyle = t.bodySmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w700,
      fontSize: compact ? 10 : 10.5,
      height: 1.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Managed by', style: labelStyle, textAlign: TextAlign.right),
        const SizedBox(height: 1),
        Text(managedBy, style: valueStyle, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(actionLabel, style: labelStyle, textAlign: TextAlign.right),
        const SizedBox(height: 1),
        Text(timeString, style: valueStyle, textAlign: TextAlign.right),
      ],
    );
  }
}

// ─── Borrowed card ──────────────────────────────────────────────────────────

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
                width: tile, height: tile,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: Text(item.emoji, style: emojiBase.copyWith(fontSize: emojiSize)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(fontSize: compact ? 15 : 16, height: 1.15)),
                      const SizedBox(height: 4),
                      Text('${item.bucketName} | ${item.bucketBarcode}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 12, height: 1.1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MetaInfoColumn(
                managedBy: record.managedBy,
                actionLabel: 'Borrowed at',
                timeString: _formatTime(record.checkedOutAt),
                compact: compact,
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          _ReturnQtyStepperHold(value: item.quantity, max: item.maxQuantity, compact: compact, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─── Returned card ──────────────────────────────────────────────────────────

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
                width: tile, height: tile,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(color: AppColors.outline),
                ),
                alignment: Alignment.center,
                child: Text(item.emoji, style: emojiBase.copyWith(fontSize: emojiSize)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: compact ? 15 : 16, height: 1.15,
                          color: AppColors.muted,
                          decoration: crossline ? TextDecoration.lineThrough : TextDecoration.none,
                        )),
                      const SizedBox(height: 4),
                      Text('${item.bucketName} | ${item.bucketBarcode}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w700, fontSize: compact ? 11.5 : 12, height: 1.1,
                        )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MetaInfoColumn(
                managedBy: record.managedBy,
                actionLabel: 'Returned at',
                timeString: _formatTime(record.returnedAt),
                compact: compact,
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          _ReturnedQtyBar(returned: item.quantity, max: item.maxQuantity, compact: compact),
        ],
      ),
    );

    return faded ? Opacity(opacity: 0.45, child: base) : base;
  }
}

// ─── Stepper / qty widgets ──────────────────────────────────────────────────

class _ReturnQtyStepperHold extends StatelessWidget {
  const _ReturnQtyStepperHold({required this.value, required this.max, required this.compact, required this.onChanged});
  final int value, max;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;
    final canMinus = value > 0;
    final canPlus = value < max;
    final height = compact ? 50.0 : 56.0;
    final btnSize = compact ? 40.0 : 44.0;
    final iconSize = compact ? 20.0 : 22.0;
    final disabledFg = AppColors.muted.withValues(alpha: 0.45);
    int clampNext(int next) => next.clamp(0, max);

    return Container(
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(tokens.radiusLg), border: Border.all(color: AppColors.outline)),
      child: Row(
        children: [
          const SizedBox(width: 6),
          HoldIconButton(enabled: canMinus, maxCount: max, icon: Icons.remove_rounded, iconColor: canMinus ? AppColors.primary : disabledFg, fill: AppColors.background, border: Colors.transparent, width: btnSize, height: btnSize, iconSize: iconSize, radius: tokens.radiusLg, onTap: canMinus ? () => onChanged(clampNext(value - 1)) : null, onHoldTick: canMinus ? (step) => onChanged(clampNext(value - step)) : null),
          const SizedBox(width: 6),
          Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$value', style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(height: 2),
            Text('of $max to be returned', style: t.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700, height: 1)),
          ]))),
          const SizedBox(width: 6),
          HoldIconButton(enabled: canPlus, maxCount: max, icon: Icons.add_rounded, iconColor: canPlus ? AppColors.primary : disabledFg, fill: AppColors.background, border: Colors.transparent, width: btnSize, height: btnSize, iconSize: iconSize, radius: tokens.radiusLg, onTap: canPlus ? () => onChanged(clampNext(value + 1)) : null, onHoldTick: canPlus ? (step) => onChanged(clampNext(value + step)) : null),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _ReturnedQtyBar extends StatelessWidget {
  const _ReturnedQtyBar({required this.returned, required this.max, required this.compact});
  final int returned, max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;
    final height = compact ? 50.0 : 56.0;
    return Container(
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(tokens.radiusLg), border: Border.all(color: AppColors.outline)),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$returned', style: (compact ? t.titleLarge : t.headlineSmall)?.copyWith(fontWeight: FontWeight.w900, height: 1)),
        const SizedBox(height: 2),
        Text('of $max returned', style: t.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700, height: 1)),
      ]),
    );
  }
}

// ─── Empty state ────────────────────────────────────────────────────────────

class _EmptyMeState extends StatelessWidget {
  const _EmptyMeState({required this.emptyTitle, required this.emptySubtitle, required this.emptyEmoji, required this.emojiBase, required this.titleStyle, required this.bodyStyle});
  final String emptyTitle, emptySubtitle, emptyEmoji;
  final TextStyle emojiBase;
  final TextStyle? titleStyle, bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emptyEmoji, style: emojiBase.copyWith(fontSize: 54)),
          const SizedBox(height: 10),
          Text(emptyTitle, style: titleStyle, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(emptySubtitle, style: bodyStyle, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}