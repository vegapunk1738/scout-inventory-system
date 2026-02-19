import 'dart:math';
import 'package:flutter/material.dart';
import 'package:scout_stock/theme/app_theme.dart';
import 'package:scout_stock/widgets/checkout_result_dialog.dart';
import 'package:scout_stock/widgets/glowing_action_button.dart';

enum MeFilterMode { all, borrowedOnly, returnedOnly }

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.isAdmin,
    this.displayName = "Alex Smith",
  });

  final bool isAdmin;
  final String displayName;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  MeFilterMode _mode = MeFilterMode.all;
  bool _submitting = false;

  late List<_BorrowedLine> _borrowed;
  late List<_ReturnedLine> _returned;

  final ValueNotifier<int> _totalToReturnVN = ValueNotifier<int>(0);

  List<_MeRow>? _rowsCache;
  MeFilterMode? _rowsCacheMode;
  int _borrowedVersion = 0;
  int _returnedVersion = 0;
  int _rowsCacheBorrowedVersion = -1;
  int _rowsCacheReturnedVersion = -1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    DateTime d(int daysAgo) {
      final base = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: daysAgo));
      return base;
    }

    _borrowed = <_BorrowedLine>[
      _BorrowedLine(
        id: "b1",
        checkedOutAt: d(0),
        itemName: "Ultralight Tent",
        bucketName: "Tents",
        bucketId: "BKT-TENTS",
        emoji: "🏕️",
        emojiBg: const Color(0xFFEAF2FF),
        outQty: 1,
        initialToReturn: 0,
      ),
      _BorrowedLine(
        id: "b2",
        checkedOutAt: d(0),
        itemName: "Alloy Tent Pegs",
        bucketName: "Stakes",
        bucketId: "BKT-STAKES",
        emoji: "📌",
        emojiBg: const Color(0xFFFFF4E5),
        outQty: 10,
        initialToReturn: 0,
      ),
      _BorrowedLine(
        id: "b3",
        checkedOutAt: d(1),
        itemName: "Cast Iron Skillet",
        bucketName: "Cooking",
        bucketId: "BKT-COOK",
        emoji: "🍳",
        emojiBg: const Color(0xFFEFFAF3),
        outQty: 1,
        initialToReturn: 0,
      ),
    ];

    _returned = <_ReturnedLine>[
      _ReturnedLine(
        id: "r1",
        returnedAt: d(6),
        itemName: "Osprey Pack 65L",
        bucketName: "Packs",
        bucketId: "BKT-PACKS",
        emoji: "🎒",
        emojiBg: const Color(0xFFEAF2FF),
        qty: 1,
      ),
    ];

    _recalcTotalToReturn();
  }

  @override
  void dispose() {
    for (final b in _borrowed) {
      b.dispose();
    }
    _totalToReturnVN.dispose();
    super.dispose();
  }

  Future<({bool ok, String? txnId, String? error})> _returnRequest() async {
    await Future.delayed(const Duration(milliseconds: 650));
    final ok = Random().nextBool();
    if (ok) {
      return (
        ok: true,
        txnId: "#RTN-${Random().nextInt(90000) + 10000}",
        error: null,
      );
    }
    return (ok: false, txnId: null, error: "E-RTN-500");
  }

  void _toggleMode(MeFilterMode tapped) {
    setState(() {
      _mode = (_mode == tapped) ? MeFilterMode.all : tapped;
      _invalidateRowsCache();
    });
  }

  void _setToReturn(_BorrowedLine line, int next) {
    final clamped = next.clamp(0, line.outQty);
    if (clamped == line.toReturn.value) return;

    final prev = line.toReturn.value;
    line.toReturn.value = clamped;

    final delta = clamped - prev;
    _totalToReturnVN.value = (_totalToReturnVN.value + delta).clamp(0, 1 << 30);
  }

  void _recalcTotalToReturn() {
    int sum = 0;
    for (final b in _borrowed) {
      sum += b.toReturn.value;
    }
    _totalToReturnVN.value = sum;
  }

  void _invalidateRowsCache() {
    _rowsCache = null;
    _rowsCacheMode = null;
  }

  List<_MeRow> _getRows() {
    final cacheOk =
        _rowsCache != null &&
        _rowsCacheMode == _mode &&
        _rowsCacheBorrowedVersion == _borrowedVersion &&
        _rowsCacheReturnedVersion == _returnedVersion;

    if (cacheOk) return _rowsCache!;

    final rows = _buildRows(
      mode: _mode,
      borrowed: _borrowed,
      returned: _returned,
    );

    _rowsCache = rows;
    _rowsCacheMode = _mode;
    _rowsCacheBorrowedVersion = _borrowedVersion;
    _rowsCacheReturnedVersion = _returnedVersion;

    return rows;
  }

  Future<void> _onReturn() async {
    if (_submitting || _totalToReturnVN.value == 0) return;

    setState(() => _submitting = true);
    try {
      final res = await _returnRequest();
      if (!mounted) return;

      if (res.ok) {
        final now = DateTime.now();

        final newReturned = <_ReturnedLine>[];
        final updatedBorrowed = <_BorrowedLine>[];

        for (final b in _borrowed) {
          final selected = b.toReturn.value;

          if (selected <= 0) {
            updatedBorrowed.add(b);
            continue;
          }

          newReturned.add(
            _ReturnedLine(
              id: "r_${now.microsecondsSinceEpoch}_${b.id}",
              returnedAt: now,
              itemName: b.itemName,
              bucketName: b.bucketName,
              bucketId: b.bucketId,
              emoji: b.emoji,
              emojiBg: b.emojiBg,
              qty: selected,
            ),
          );

          final remaining = b.outQty - selected;

          if (remaining > 0) {
            b.toReturn.value = 0;
            updatedBorrowed.add(b.copyWith(outQty: remaining));
          } else {
            b.dispose();
          }
        }

        setState(() {
          _borrowed = updatedBorrowed;
          _returned = [...newReturned, ..._returned];

          _borrowedVersion++;
          _returnedVersion++;
          _invalidateRowsCache();
        });

        _recalcTotalToReturn();

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
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final top = MediaQuery.of(context).padding.top;

    final compact = MediaQuery.sizeOf(context).width < 380;

    final shadow = tokens.cardShadow.isNotEmpty
        ? [
            tokens.cardShadow.first.copyWith(
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ]
        : const <BoxShadow>[];

    final role = widget.isAdmin ? "Admin" : "Scout";
    final initials = _initials(widget.displayName);

    final rows = _getRows();

    final hasAny = _borrowed.isNotEmpty || _returned.isNotEmpty;
    final rowsEmptyForMode = rows.isEmpty;

    String emptyTitle = "Nothing here yet";
    String emptySubtitle =
        "Checked out and returned items will show up on this page.";

    if (!hasAny) {
      emptyTitle = "Nothing here yet";
      emptySubtitle =
          "Checked out and returned items will show up on this page.";
    } else if (_mode == MeFilterMode.borrowedOnly && _borrowed.isEmpty) {
      emptyTitle = "No borrowed items";
      emptySubtitle = "When you check out gear, it will appear here.";
    } else if (_mode == MeFilterMode.returnedOnly && _returned.isEmpty) {
      emptyTitle = "No returns yet";
      emptySubtitle =
          "Returned items will show up here once you bring them back.";
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, top + 12, 20, 14),
                    child: _MeHeader(
                      name: widget.displayName,
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
                      mode: _mode,
                      onTapBorrowed: () =>
                          _toggleMode(MeFilterMode.borrowedOnly),
                      onTapReturned: () =>
                          _toggleMode(MeFilterMode.returnedOnly),
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
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _BorrowedCard(
                                line: line,
                                tokens: tokens,
                                compact: compact,
                                shadow: shadow,
                                onChanged: (next) => _setToReturn(line, next),
                              ),
                            ),
                          );
                        }

                        final crossline = _mode == MeFilterMode.returnedOnly;
                        final faded =
                            (_mode == MeFilterMode.all) ||
                            (_mode == MeFilterMode.returnedOnly);

                        final line = r.returned!;
                        return Padding(
                          key: ValueKey("r_${line.id}"),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RepaintBoundary(
                            child: _ReturnedCard(
                              line: line,
                              tokens: tokens,
                              compact: compact,
                              shadow: shadow,
                              faded: faded,
                              crossline: crossline,
                            ),
                          ),
                        );
                      }, childCount: rows.length),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _totalToReturnVN,
                      builder: (context, total, _) {
                        final showBottomReturn =
                            (_mode != MeFilterMode.returnedOnly) &&
                            total > 0 &&
                            _borrowed.isNotEmpty;

                        return SizedBox(height: showBottomReturn ? 120 : 22);
                      },
                    ),
                  ),
                ],
              ],
            ),

            ValueListenableBuilder<int>(
              valueListenable: _totalToReturnVN,
              builder: (context, total, _) {
                final showBottomReturn =
                    (_mode != MeFilterMode.returnedOnly) &&
                    total > 0 &&
                    _borrowed.isNotEmpty;

                if (!showBottomReturn) return const SizedBox.shrink();

                return Align(
                  alignment: Alignment.bottomCenter,
                  child: GlowingActionButton(
                    label: total == 1
                        ? "Return Items (1)"
                        : "Return Items ($total)",
                    icon: const Icon(Icons.keyboard_return_rounded),
                    loading: _submitting,
                    onPressed: _submitting ? null : _onReturn,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    height: 74,
                  ),
                );
              },
            ),
          ],
        ),
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
        Container(
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
  final _BorrowedLine? borrowed;
  final _ReturnedLine? returned;
  final double topGap;
}

List<_MeRow> _buildRows({
  required MeFilterMode mode,
  required List<_BorrowedLine> borrowed,
  required List<_ReturnedLine> returned,
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
      (a, b) => a.borrowed!.itemName.compareTo(b.borrowed!.itemName),
    );
    returnedRows.sort(
      (a, b) => a.returned!.itemName.compareTo(b.returned!.itemName),
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

/* ----------------------------- Borrowed Card (Cart style + big stepper) ----------------------------- */

class _BorrowedCard extends StatelessWidget {
  const _BorrowedCard({
    required this.line,
    required this.tokens,
    required this.compact,
    required this.shadow,
    required this.onChanged,
  });

  final _BorrowedLine line;
  final AppTokens tokens;
  final bool compact;
  final List<BoxShadow> shadow;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final tile = compact ? 48.0 : 54.0;
    final emojiSize = compact ? 24.0 : 28.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: line.emojiBg,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                ),
                alignment: Alignment.center,
                child: Text(
                  line.emoji,
                  style: TextStyle(
                    fontSize: emojiSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.itemName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                          fontSize: compact ? 16 : 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bucket: ${line.bucketName} • ${line.bucketId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 12 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          ValueListenableBuilder<int>(
            valueListenable: line.toReturn,
            builder: (context, value, _) {
              return _ReturnQtyStepperBig(
                value: value,
                max: line.outQty,
                compact: compact,
                onMinus: () => onChanged(value - 1),
                onPlus: () => onChanged(value + 1),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReturnQtyStepperBig extends StatelessWidget {
  const _ReturnQtyStepperBig({
    required this.value,
    required this.max,
    required this.compact,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final int max;
  final bool compact;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final t = Theme.of(context).textTheme;

    final canMinus = value > 0;
    final canPlus = value < max;

    final height = compact ? 56.0 : 62.0;
    final btnSize = compact ? 46.0 : 50.0;
    final iconSize = compact ? 22.0 : 24.0;

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
          _StepIconButton(
            icon: Icons.remove_rounded,
            size: btnSize,
            iconSize: iconSize,
            enabled: canMinus,
            onTap: canMinus ? onMinus : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: (compact ? t.headlineSmall : t.headlineMedium)
                        ?.copyWith(fontWeight: FontWeight.w900, height: 1),
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
          _StepIconButton(
            icon: Icons.add_rounded,
            size: btnSize,
            iconSize: iconSize,
            enabled: canPlus,
            onTap: canPlus ? onPlus : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _StepIconButton extends StatelessWidget {
  const _StepIconButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final fg = enabled
        ? AppColors.primary
        : AppColors.muted.withValues(alpha: 0.45);

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );
  }
}

/* ----------------------------- Returned Card (Cart style) ----------------------------- */

class _ReturnedCard extends StatelessWidget {
  const _ReturnedCard({
    required this.line,
    required this.tokens,
    required this.compact,
    required this.shadow,
    required this.faded,
    required this.crossline,
  });

  final _ReturnedLine line;
  final AppTokens tokens;
  final bool compact;
  final List<BoxShadow> shadow;
  final bool faded;
  final bool crossline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final tile = compact ? 48.0 : 54.0;
    final emojiSize = compact ? 24.0 : 28.0;

    final base = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: shadow,
      ),
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              color: line.emojiBg,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
            ),
            alignment: Alignment.center,
            child: Text(
              line.emoji,
              style: TextStyle(
                fontSize: emojiSize,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(
                      fontSize: compact ? 16 : 18,
                      color: AppColors.muted,
                      decoration: crossline
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bucket: ${line.bucketName} • ${line.bucketId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                      color: AppColors.muted.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12 : 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "Returned",
                style: t.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${line.qty} / ${line.qty}",
                style: t.bodySmall?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return faded ? Opacity(opacity: 0.45, child: base) : base;
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

/* ----------------------------- Models + Helpers ----------------------------- */

class _BorrowedLine {
  _BorrowedLine({
    required this.id,
    required this.checkedOutAt,
    required this.itemName,
    required this.bucketName,
    required this.bucketId,
    required this.emoji,
    required this.emojiBg,
    required this.outQty,
    required int initialToReturn,
  }) : toReturn = ValueNotifier<int>(initialToReturn);

  final String id;
  final DateTime checkedOutAt;

  final String itemName;
  final String bucketName;
  final String bucketId;

  final String emoji;
  final Color emojiBg;

  final int outQty;

  final ValueNotifier<int> toReturn;

  void dispose() => toReturn.dispose();

  _BorrowedLine copyWith({int? outQty}) => _BorrowedLine(
    id: id,
    checkedOutAt: checkedOutAt,
    itemName: itemName,
    bucketName: bucketName,
    bucketId: bucketId,
    emoji: emoji,
    emojiBg: emojiBg,
    outQty: outQty ?? this.outQty,
    initialToReturn: toReturn.value,
  );
}

class _ReturnedLine {
  const _ReturnedLine({
    required this.id,
    required this.returnedAt,
    required this.itemName,
    required this.bucketName,
    required this.bucketId,
    required this.emoji,
    required this.emojiBg,
    required this.qty,
  });

  final String id;
  final DateTime returnedAt;

  final String itemName;
  final String bucketName;
  final String bucketId;

  final String emoji;
  final Color emojiBg;

  final int qty;
}

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
