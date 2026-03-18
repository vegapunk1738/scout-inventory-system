import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/state/notifiers/activity_notifier.dart';
import 'package:scout_stock/state/providers/activity_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Activity Log Page — connected to real backend with polling + animations
// ═══════════════════════════════════════════════════════════════════════════

class ActivityLogPage extends ConsumerStatefulWidget {
  const ActivityLogPage({super.key});

  @override
  ConsumerState<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends ConsumerState<ActivityLogPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    const threshold = 220.0;
    if (_scrollCtrl.position.extentAfter < threshold) {
      ref.read(activityProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String v) {
    ref.read(activityProvider.notifier).setSearchQuery(v.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activityProvider);
    final notifier = ref.read(activityProvider.notifier);
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);

    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final isEmpty = !state.loading && state.entries.isEmpty;
    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    final rows = _buildRows(state.entries);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: CustomScrollView(
              controller: _scrollCtrl,
              cacheExtent: 900,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, mediaTop + 10, 20, 0),
                    child: _ActivityHeader(newCount: state.newEntryIds.length),
                  ),
                ),

                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    height: 70,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: _SearchCard(
                        controller: _searchCtrl,
                        hintText: 'Search user, item, or bucket…',
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: _UnifiedFilterRow(
                      selected: state.filter,
                      onTap: notifier.setFilter,
                    ),
                  ),
                ),

                if (state.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyActivityState(
                      query: state.searchQuery,
                      emojiBase: emojiBase,
                      titleStyle: t.titleLarge,
                      bodyStyle: t.bodyLarge?.copyWith(color: AppColors.muted),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final row = rows[index];
                          if (row.kind == _RowKind.groupHeader) {
                            return _GroupHeaderRow(
                              titleLeft: row.titleLeft!,
                              titleRight: row.titleRight!,
                              topGap: row.topGap,
                            );
                          }

                          final entry = row.entry!;
                          final isNew = state.newEntryIds.contains(entry.id);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _GlowingEntryCard(
                                entry: entry,
                                isNew: isNew,
                                onGlowComplete: () =>
                                    notifier.markSeen(entry.id),
                                radiusXl: tokens.radiusXl,
                              ),
                            ),
                          );
                        },
                        childCount: rows.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!state.loading && !isEmpty && state.loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (!state.loading && !isEmpty && !state.hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              "No more activity",
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(child: SizedBox(height: bottomFootprint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Header
// ═══════════════════════════════════════════════════════════════════════════

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.newCount});
  final int newCount;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activity Log', style: t.titleLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'ADMIN VIEW',
                    style: t.labelMedium?.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 1.8,
                    ),
                  ),
                  if (newCount > 0) ...[
                    const SizedBox(width: 10),
                    _LiveDot(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = 0.4 + 0.6 * _ctrl.value;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: opacity),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4 * _ctrl.value),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Unified filter row
// ═══════════════════════════════════════════════════════════════════════════

class _UnifiedFilterRow extends StatelessWidget {
  const _UnifiedFilterRow({required this.selected, required this.onTap});

  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onTap;

  static const _icons = <ActivityFilter, IconData>{
    ActivityFilter.all: Icons.dashboard_rounded,
    ActivityFilter.checkouts: Icons.arrow_upward_rounded,
    ActivityFilter.returns: Icons.arrow_downward_rounded,
    ActivityFilter.resolved: Icons.search_off_rounded,
    ActivityFilter.admin: Icons.shield_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: ActivityFilter.values.map((f) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterChip(
                label: f.label,
                icon: _icons[f],
                isSelected: f == selected,
                onTap: () => onTap(f),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Filter chip
// ═══════════════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bg = isSelected ? AppColors.primary : Colors.white;
    final fg = isSelected ? Colors.white : AppColors.ink;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outline,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 0,
                    offset: Offset.zero,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: t.titleMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Search card
// ═══════════════════════════════════════════════════════════════════════════

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          boxShadow: tokens.cardShadow,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search_rounded, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: t.bodyLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(right: 16),
                  hintText: hintText,
                  hintStyle: t.bodyLarge?.copyWith(
                    color: const Color(0xFFB9C0C8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
                splashRadius: 20,
                tooltip: 'Clear',
                style: IconButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  hoverColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sticky header delegate
// ═══════════════════════════════════════════════════════════════════════════

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.height, required this.child});
  final double height;
  final Widget child;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Glowing entry card
// ═══════════════════════════════════════════════════════════════════════════

class _GlowingEntryCard extends StatefulWidget {
  const _GlowingEntryCard({
    required this.entry,
    required this.isNew,
    required this.onGlowComplete,
    required this.radiusXl,
  });

  final ActivityEntry entry;
  final bool isNew;
  final VoidCallback onGlowComplete;
  final double radiusXl;

  @override
  State<_GlowingEntryCard> createState() => _GlowingEntryCardState();
}

class _GlowingEntryCardState extends State<_GlowingEntryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _glowAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0.6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 2),
    ]).animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut));

    if (widget.isNew) {
      _glowCtrl.forward().then((_) {
        if (mounted) widget.onGlowComplete();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GlowingEntryCard old) {
    super.didUpdateWidget(old);
    if (widget.isNew && !old.isNew) {
      _glowCtrl.forward(from: 0).then((_) {
        if (mounted) widget.onGlowComplete();
      });
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        final v = _glowAnim.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radiusXl),
            boxShadow: v > 0.01
                ? [
                    BoxShadow(
                      color: _stripColor(entry).withValues(alpha: 0.45 * v),
                      blurRadius: 20 * v,
                      spreadRadius: 2 * v,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: _EntryCardContent(
        entry: entry,
        expanded: _expanded,
        onTap: () => setState(() => _expanded = !_expanded),
        radiusXl: widget.radiusXl,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Entry card content
// ═══════════════════════════════════════════════════════════════════════════

class _EntryCardContent extends StatelessWidget {
  const _EntryCardContent({
    required this.entry,
    required this.expanded,
    required this.onTap,
    required this.radiusXl,
  });

  final ActivityEntry entry;
  final bool expanded;
  final VoidCallback onTap;
  final double radiusXl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stripColor = _stripColor(entry);
    final initials = _initials(entry.actorName);
    final timeText = _formatTime(context, entry.createdAt);
    final hasDetails = entry.isTransaction && entry.lineItems.isNotEmpty;

    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x14000000),
      borderRadius: BorderRadius.circular(radiusXl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasDetails ? onTap : null,
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          children: [
            // ── Main row ────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Color strip ─────────────────────────────────────
                  Container(
                    width: 6,
                    constraints: const BoxConstraints(minHeight: 84),
                    color: stripColor,
                  ),
                  const SizedBox(width: 14),

                  // ── Avatar (pinned to top) ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.background,
                          child: entry.isTransaction
                              ? Text(
                                  initials,
                                  style: t.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : Icon(
                                  _entityIcon(entry),
                                  size: 20,
                                  color: stripColor,
                                ),
                        ),
                        Positioned(
                          left: -2,
                          bottom: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Icon(
                              _actionIcon(entry),
                              size: 12,
                              color: stripColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Text content ────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.actorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.detailLabel,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Time (pinned to top) ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 14, right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeText,
                          style: t.bodyMedium?.copyWith(color: AppColors.muted),
                        ),
                        if (hasDetails) ...[
                          const SizedBox(height: 8),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.muted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Expandable details ──────────────────────────────────
            AnimatedCrossFade(
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 160),
              firstChild: const SizedBox.shrink(),
              secondChild: hasDetails
                  ? _DetailsBlock(lines: entry.lineItems)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Details block (transaction line items)
// ═══════════════════════════════════════════════════════════════════════════

class _DetailsBlock extends StatelessWidget {
  const _DetailsBlock({required this.lines});
  final List<ActivityLineItem> lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final qtyStyle = t.bodyMedium?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w900,
      color: AppColors.ink,
      height: 1.1,
    );
    final itemStyle = t.bodyLarge?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
      height: 1.2,
    );
    final subStyle = t.bodyMedium?.copyWith(
      fontSize: 13,
      color: AppColors.muted,
      height: 1.25,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < lines.length; i++) ...[
            if (i != 0) const SizedBox(height: 14),
            _DetailLineWidget(
              line: lines[i],
              qtyStyle: qtyStyle,
              itemStyle: itemStyle,
              subStyle: subStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLineWidget extends StatelessWidget {
  const _DetailLineWidget({
    required this.line,
    required this.qtyStyle,
    required this.itemStyle,
    required this.subStyle,
  });

  final ActivityLineItem line;
  final TextStyle? qtyStyle;
  final TextStyle? itemStyle;
  final TextStyle? subStyle;

  @override
  Widget build(BuildContext context) {
    final statusSuffix = line.status != 'normal' ? ' (${line.status})' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                "${line.quantity}×",
                textAlign: TextAlign.right,
                style: qtyStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${line.itemName}$statusSuffix',
                style: itemStyle,
                softWrap: true,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 46),
          child: Text(
            "from ${line.bucketName}",
            style: subStyle,
            softWrap: true,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty state
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState({
    required this.query,
    required this.emojiBase,
    required this.titleStyle,
    required this.bodyStyle,
  });

  final String query;
  final TextStyle emojiBase;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final title = query.isEmpty ? "No activity yet" : "No results";
    final subtitle = query.isEmpty
        ? "When scouts check out or return items,\nyou'll see it here"
        : "Try a different keyword";

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📜', style: emojiBase.copyWith(fontSize: 54)),
            const SizedBox(height: 10),
            Text(title, style: titleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: bodyStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Row building (date-grouped)
// ═══════════════════════════════════════════════════════════════════════════

enum _RowKind { groupHeader, entry }

class _ActivityRow {
  final _RowKind kind;
  final String? titleLeft;
  final String? titleRight;
  final ActivityEntry? entry;
  final double topGap;

  const _ActivityRow._({
    required this.kind,
    this.titleLeft,
    this.titleRight,
    this.entry,
    this.topGap = 0,
  });

  const _ActivityRow.header({
    required String titleLeft,
    required String titleRight,
    double topGap = 0,
  }) : this._(
         kind: _RowKind.groupHeader,
         titleLeft: titleLeft,
         titleRight: titleRight,
         topGap: topGap,
       );

  const _ActivityRow.entry(ActivityEntry entry)
    : this._(kind: _RowKind.entry, entry: entry);
}

List<_ActivityRow> _buildRows(List<ActivityEntry> entries) {
  if (entries.isEmpty) return const [];

  final map = <DateTime, List<ActivityEntry>>{};
  for (final e in entries) {
    final key = _dateOnly(e.createdAt);
    (map[key] ??= []).add(e);
  }

  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));

  final today = _dateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  final last7Start = today.subtract(const Duration(days: 6));

  String leftTitle(DateTime d) {
    if (d == today) return "TODAY";
    if (d == yesterday) return "YESTERDAY";
    if (!d.isBefore(last7Start)) return _weekdayName(d);
    return _prettyDate(d).toUpperCase();
  }

  final rows = <_ActivityRow>[];
  for (int i = 0; i < keys.length; i++) {
    final day = keys[i];
    rows.add(_ActivityRow.header(
      titleLeft: leftTitle(day),
      titleRight: _prettyDate(day),
      topGap: i == 0 ? 0 : 16,
    ));

    final items = map[day]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final entry in items) {
      rows.add(_ActivityRow.entry(entry));
    }
  }
  return rows;
}

// ═══════════════════════════════════════════════════════════════════════════
// Group header row
// ═══════════════════════════════════════════════════════════════════════════

class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow({
    required this.titleLeft,
    required this.titleRight,
    required this.topGap,
  });

  final String titleLeft;
  final String titleRight;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isToday = titleLeft == "TODAY";

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                titleLeft,
                style: t.labelMedium?.copyWith(
                  color: isToday ? AppColors.primary : AppColors.muted,
                ),
              ),
              const Spacer(),
              Text(
                titleRight,
                style: t.titleMedium?.copyWith(color: AppColors.muted),
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

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

String _initials(String name) {
  final parts = name.trim().split(RegExp(r"\s+"));
  if (parts.isEmpty) return "?";
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return "${parts.first.characters.first}${parts.last.characters.first}"
      .toUpperCase();
}

String _formatTime(BuildContext context, DateTime dt) {
  final loc = MaterialLocalizations.of(context);
  return loc.formatTimeOfDay(
    TimeOfDay.fromDateTime(dt.toLocal()),
    alwaysUse24HourFormat: false,
  );
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _prettyDate(DateTime d) {
  const m = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return "${m[d.month - 1]} ${d.day}, ${d.year}";
}

String _weekdayName(DateTime d) {
  const w = [
    "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
    "FRIDAY", "SATURDAY", "SUNDAY",
  ];
  return w[d.weekday - 1];
}

Color _stripColor(ActivityEntry entry) {
  const blue = Color(0xFF2F6FED);
  const red = Color(0xFFE53935);
  const orange = Color(0xFFF57C00);
  const purple = Color(0xFF7C4DFF);

  if (entry.isCheckout) return blue;
  if (entry.isReturn) return AppColors.primary;
  if (entry.kind == 'resolved_lost') return red;
  if (entry.kind == 'resolved_damaged') return orange;
  if (entry.isBucketEvent) return purple;
  if (entry.isUserEvent) return const Color(0xFF00897B);
  return AppColors.muted;
}

IconData _actionIcon(ActivityEntry entry) {
  switch (entry.kind) {
    case 'checkout':
      return Icons.arrow_upward_rounded;
    case 'return':
      return Icons.arrow_downward_rounded;
    case 'resolved_lost':
      return Icons.search_off_rounded;
    case 'resolved_damaged':
      return Icons.broken_image_rounded;
    case 'bucket_created':
    case 'user_created':
      return Icons.add_rounded;
    case 'bucket_updated':
    case 'user_updated':
      return Icons.edit_rounded;
    case 'bucket_deleted':
    case 'user_deleted':
      return Icons.delete_rounded;
    default:
      return Icons.info_rounded;
  }
}

IconData _entityIcon(ActivityEntry entry) {
  if (entry.isBucketEvent) return Icons.category_rounded;
  if (entry.isUserEvent) return Icons.person_rounded;
  return Icons.info_rounded;
}