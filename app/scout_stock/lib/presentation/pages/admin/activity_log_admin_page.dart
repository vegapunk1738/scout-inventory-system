import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/state/notifiers/activity_notifier.dart';
import 'package:scout_stock/state/providers/activity_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Activity Log Page
// ═══════════════════════════════════════════════════════════════════════════

class ActivityLogPage extends ConsumerStatefulWidget {
  const ActivityLogPage({super.key});

  @override
  ConsumerState<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends ConsumerState<ActivityLogPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final Map<String, ValueNotifier<bool>> _expanded = {};
  Timer? _searchDebounce;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(activityProvider.notifier).poll(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    for (final n in _expanded.values) {
      n.dispose();
    }
    _expanded.clear();
    super.dispose();
  }

  ValueNotifier<bool> _exp(String id) =>
      _expanded.putIfAbsent(id, () => ValueNotifier<bool>(false));

  void _clearExpandState() {
    for (final n in _expanded.values) {
      n.dispose();
    }
    _expanded.clear();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    const threshold = 220.0;
    if (_scrollCtrl.position.extentAfter < threshold) {
      ref.read(activityProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(activityProvider.notifier).search(v.trim());
      _clearExpandState();
    });
    setState(() {});
  }

  void _onFilterChanged(ActivityFilter filter) {
    ref.read(activityProvider.notifier).setFilter(filter);
    _clearExpandState();
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emojiBase = GoogleFonts.notoColorEmoji(height: 1);
    final mediaTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    const navHeight = 78.0;
    const navPad = 12.0;
    final bottomFootprint = safeBottom + navHeight + navPad + 10;

    final activity = ref.watch(activityProvider);
    final entries = activity.entries;
    final rows = _buildRows(entries);
    final isEmpty = !activity.loading && entries.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: DottedBackground()),
          SafeArea(
            top: false,
            child: CustomScrollView(
              controller: _scrollCtrl,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: mediaTop + 16)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ActivityHeader(
                      onFilter: () {},
                      onExport: () {},
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // ── Search + Filter Chips (sticky) ──
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    height: 72 + 52, // search + chips
                    child: Container(
                      color: AppColors.background,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: _SearchCard(
                              controller: _searchCtrl,
                              onChanged: _onSearchChanged,
                              hintText: 'Search user, item, or bucket…',
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: _FilterChips(
                              selected: activity.filter,
                              onChanged: _onFilterChanged,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Content ──
                if (activity.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (activity.error != null && entries.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('😵',
                                style: emojiBase.copyWith(fontSize: 54)),
                            const SizedBox(height: 12),
                            Text('Failed to load activity',
                                style: t.titleLarge,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(activity.error!,
                                style: t.bodyLarge
                                    ?.copyWith(color: AppColors.muted),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyActivityState(
                      query: activity.query,
                      filter: activity.filter,
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
                          final isPollNew =
                              activity.pollNewIds.contains(entry.id);
                          final card = Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _ExpandableActivityCard(
                                entry: entry,
                                expanded: _exp(entry.id),
                                radiusXl: tokens.radiusXl,
                              ),
                            ),
                          );
                          if (isPollNew) {
                            return _AnimatedEntrance(
                              key: ValueKey('anim_${entry.id}'),
                              onComplete: () => ref
                                  .read(activityProvider.notifier)
                                  .markAnimated(entry.id),
                              child: card,
                            );
                          }
                          return card;
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
                        if (!activity.loading &&
                            !isEmpty &&
                            activity.loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (!activity.loading &&
                            !isEmpty &&
                            !activity.hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              "No more activity",
                              style: t.bodyMedium
                                  ?.copyWith(color: AppColors.muted),
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
// Filter Chips
// ═══════════════════════════════════════════════════════════════════════════

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});
  final ActivityFilter selected;
  final ValueChanged<ActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: ActivityFilter.values.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final filter = ActivityFilter.values[index];
        final isSelected = filter == selected;

        final IconData icon;
        switch (filter) {
          case ActivityFilter.all:
            icon = Icons.grid_view_rounded;
          case ActivityFilter.items:
            icon = Icons.swap_vert_rounded;
          case ActivityFilter.resolves:
            icon = Icons.gavel_rounded;
          case ActivityFilter.buckets:
            icon = Icons.inventory_2_rounded;
          case ActivityFilter.users:
            icon = Icons.group_rounded;
        }

        return GestureDetector(
          onTap: () => onChanged(filter),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.outline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  filter.label,
                  style: t.labelMedium?.copyWith(
                    color: isSelected ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Header
// ═══════════════════════════════════════════════════════════════════════════

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.onFilter, required this.onExport});
  final VoidCallback onFilter;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    Widget invisibleCircleButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: tokens.glowShadow,
          ),
          child: SizedBox(
            width: 42,
            height: 42,
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.white),
              splashRadius: 28,
              tooltip: tooltip,
              style: IconButton.styleFrom(
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Activity Log', style: t.titleLarge),
              const SizedBox(height: 4),
              Text('ADMIN VIEW',
                  style: t.labelMedium?.copyWith(
                      color: AppColors.primary, letterSpacing: 1.8)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            invisibleCircleButton(
                icon: Icons.tune_rounded,
                tooltip: 'Filter',
                onPressed: onFilter),
            const SizedBox(width: 10),
            invisibleCircleButton(
                icon: Icons.download_rounded,
                tooltip: 'Export',
                onPressed: onExport),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Search Card
// ═══════════════════════════════════════════════════════════════════════════

class _SearchCard extends StatelessWidget {
  const _SearchCard(
      {required this.controller,
      required this.onChanged,
      required this.hintText});
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
          highlightColor: Colors.transparent),
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
                    color: AppColors.ink, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(right: 16),
                  hintText: hintText,
                  hintStyle: t.bodyLarge?.copyWith(
                      color: const Color(0xFFB9C0C8),
                      fontWeight: FontWeight.w700),
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
                    highlightColor: Colors.transparent),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sticky Header Delegate
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
  Widget build(BuildContext c, double s, bool o) => child;
  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate old) =>
      old.height != height || old.child != child;
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState({
    required this.query,
    required this.filter,
    required this.emojiBase,
    required this.titleStyle,
    required this.bodyStyle,
  });
  final String query;
  final ActivityFilter filter;
  final TextStyle emojiBase;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final hasSearch = query.isNotEmpty;
    final hasFilter = filter != ActivityFilter.all;

    final String title;
    final String subtitle;

    if (hasSearch) {
      title = "No results";
      subtitle = "Try a different keyword";
    } else if (hasFilter) {
      title = "No ${filter.label.toLowerCase()} activity";
      subtitle = "Nothing matches this filter yet";
    } else {
      title = "No activity yet";
      subtitle = "When scouts check out or return items,\nyou'll see it here";
    }

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
// Row Model + Builder
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

  const _ActivityRow.header(
      {required String titleLeft,
      required String titleRight,
      double topGap = 0})
      : this._(
            kind: _RowKind.groupHeader,
            titleLeft: titleLeft,
            titleRight: titleRight,
            topGap: topGap);

  const _ActivityRow.entry(ActivityEntry entry)
      : this._(kind: _RowKind.entry, entry: entry);
}

List<_ActivityRow> _buildRows(List<ActivityEntry> entries) {
  if (entries.isEmpty) return const <_ActivityRow>[];

  final map = <DateTime, List<ActivityEntry>>{};
  for (final e in entries) {
    final key = _dateOnly(e.createdAt);
    (map[key] ??= <ActivityEntry>[]).add(e);
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
        topGap: i == 0 ? 0 : 16));
    final items = map[day]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final e in items) {
      rows.add(_ActivityRow.entry(e));
    }
  }
  return rows;
}

// ═══════════════════════════════════════════════════════════════════════════
// Group Header
// ═══════════════════════════════════════════════════════════════════════════

class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow(
      {required this.titleLeft,
      required this.titleRight,
      required this.topGap});
  final String titleLeft;
  final String titleRight;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isToday = titleLeft == "TODAY";

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: 12),
      child: Column(children: [
        Row(children: [
          Text(titleLeft,
              style: t.labelMedium?.copyWith(
                  color: isToday ? AppColors.primary : AppColors.muted)),
          const Spacer(),
          Text(titleRight,
              style: t.titleMedium?.copyWith(color: AppColors.muted)),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expandable Activity Card
// ═══════════════════════════════════════════════════════════════════════════

class _ExpandableActivityCard extends StatelessWidget {
  const _ExpandableActivityCard(
      {required this.entry, required this.expanded, required this.radiusXl});

  final ActivityEntry entry;
  final ValueNotifier<bool> expanded;
  final double radiusXl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final stripColor = _stripColorFor(entry.action);
    final badgeIcon = _badgeIconFor(entry.action);
    final initials = _initials(entry.actorName);
    final timeText = _formatTime(context, entry.createdAt);
    final canExpand = entry.hasExpandableContent;

    final userNameStyle = t.titleMedium?.copyWith(
        fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink);

    return ValueListenableBuilder<bool>(
      valueListenable: expanded,
      builder: (context, isOpen, _) {
        return Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: const Color(0x14000000),
          borderRadius: BorderRadius.circular(radiusXl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canExpand ? () => expanded.value = !expanded.value : null,
            splashFactory: NoSplash.splashFactory,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(width: 6, height: 84, color: stripColor),
                    const SizedBox(width: 14),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.background,
                          child: Text(initials,
                              style: t.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        Positioned(
                          right: -4,
                          bottom: -3,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child:
                                Icon(badgeIcon, size: 12, color: stripColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.actorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: userNameStyle),
                            const SizedBox(height: 4),
                            Text(entry.summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyMedium
                                    ?.copyWith(color: AppColors.ink)),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(timeText,
                              style: t.bodyMedium
                                  ?.copyWith(color: AppColors.muted)),
                          const SizedBox(height: 8),
                          if (canExpand)
                            Icon(
                                isOpen
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: AppColors.muted)
                          else
                            const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
                if (canExpand)
                  AnimatedCrossFade(
                    crossFadeState: isOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 160),
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildExpandedContent(entry),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Strip color / badge icon per action
// ═══════════════════════════════════════════════════════════════════════════

Color _stripColorFor(String action) {
  switch (action) {
    case 'checkout':
      return const Color(0xFF2F6FED);
    case 'return':
      return AppColors.primary;
    case 'resolve':
      return const Color(0xFF7C3AED);
    case 'bucket_created':
    case 'user_created':
      return AppColors.primary;
    case 'bucket_updated':
    case 'user_updated':
    case 'item_updated':
      return const Color(0xFFFF9800);
    case 'bucket_deleted':
    case 'user_deleted':
      return const Color(0xFFD92D20);
    default:
      return AppColors.muted;
  }
}

IconData _badgeIconFor(String action) {
  switch (action) {
    case 'checkout':
      return Icons.arrow_downward_rounded;
    case 'return':
      return Icons.arrow_upward_rounded;
    case 'resolve':
      return Icons.gavel_rounded;
    case 'bucket_created':
      return Icons.add_rounded;
    case 'bucket_updated':
      return Icons.edit_rounded;
    case 'bucket_deleted':
      return Icons.delete_rounded;
    case 'user_created':
      return Icons.person_add_rounded;
    case 'user_updated':
      return Icons.edit_rounded;
    case 'user_deleted':
      return Icons.person_remove_rounded;
    default:
      return Icons.info_rounded;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expanded Content Router
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildExpandedContent(ActivityEntry entry) {
  switch (entry.action) {
    case 'checkout':
      return _CheckoutReturnDetails(items: entry.items, isCheckout: true);
    case 'return':
      return _CheckoutReturnDetails(items: entry.items, isCheckout: false);
    case 'resolve':
      return _ResolveDetails(items: entry.items);
    case 'bucket_created':
      return _BucketCreatedDetails(items: entry.items);
    case 'bucket_updated':
    case 'user_updated':
      return _ChangeListDetails(changes: entry.changes);
    default:
      return const SizedBox.shrink();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Checkout / Return detail lines
// ═══════════════════════════════════════════════════════════════════════════

class _CheckoutReturnDetails extends StatelessWidget {
  const _CheckoutReturnDetails({required this.items, required this.isCheckout});
  final List<ActivityItemDetail> items;
  final bool isCheckout;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final actionStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w700, height: 1.35);
    final detailStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.35);

    final actionColor = isCheckout ? const Color(0xFF2F6FED) : AppColors.primary;
    final actionIcon = isCheckout
        ? Icons.arrow_downward_rounded
        : Icons.arrow_upward_rounded;
    final actionLabel = isCheckout ? 'checked out' : 'returned';
    final preposition = isCheckout ? 'from' : 'to';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(actionIcon, size: 16, color: actionColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: '$actionLabel ',
                      style: actionStyle?.copyWith(color: actionColor),
                    ),
                    TextSpan(
                      text: '×${items[i].quantity} of ${items[i].itemName}',
                      style: detailStyle,
                    ),
                    if (items[i].bucketName != null)
                      TextSpan(
                        text: ' $preposition ${items[i].bucketName}',
                        style: detailStyle?.copyWith(color: AppColors.muted),
                      ),
                  ])),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Resolve detail lines
// ═══════════════════════════════════════════════════════════════════════════

class _ResolveDetails extends StatelessWidget {
  const _ResolveDetails({required this.items});
  final List<ActivityItemDetail> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final actionStyle = t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.35);
    final detailStyle = t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        height: 1.35);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            _buildResolveLine(items[i], actionStyle, detailStyle),
          ],
        ],
      ),
    );
  }

  Widget _buildResolveLine(
    ActivityItemDetail item,
    TextStyle? actionStyle,
    TextStyle? detailStyle,
  ) {
    final label = item.resolveActionLabel;
    final isReturned = item.status == 'normal';

    // Color the action label
    final Color actionColor;
    final IconData actionIcon;
    switch (item.status) {
      case 'lost':
        actionColor = const Color(0xFFD92D20);
        actionIcon = Icons.cancel_rounded;
      case 'damaged':
        actionColor = const Color(0xFFFF9800);
        actionIcon = Icons.warning_rounded;
      default: // normal = returned
        actionColor = AppColors.primary;
        actionIcon = Icons.check_circle_rounded;
    }

    // Build: "returned ×3 of Rope to Tent Pegs" or "marked lost ×2 of Rope"
    final suffix = isReturned && item.bucketName != null
        ? ' to ${item.bucketName}'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(actionIcon, size: 16, color: actionColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$label ',
                style: actionStyle?.copyWith(color: actionColor),
              ),
              TextSpan(
                text: '×${item.quantity} of ${item.itemName}$suffix',
                style: detailStyle,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Bucket Created detail (items added)
// ═══════════════════════════════════════════════════════════════════════════

class _BucketCreatedDetails extends StatelessWidget {
  const _BucketCreatedDetails({required this.items});
  final List<ActivityItemDetail> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final actionStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w700, height: 1.35);
    final detailStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.35);

    const actionColor = AppColors.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.add_circle_rounded, size: 16, color: actionColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: 'added ',
                      style: actionStyle?.copyWith(color: actionColor),
                    ),
                    TextSpan(
                      text: '×${items[i].quantity} ${items[i].itemName}',
                      style: detailStyle,
                    ),
                  ])),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Change List (bucket update / user update)
// ═══════════════════════════════════════════════════════════════════════════

class _ChangeListDetails extends StatelessWidget {
  const _ChangeListDetails({required this.changes});
  final List<ActivityChangeDetail> changes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final actionStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w700, height: 1.35);
    final detailStyle = t.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.35);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < changes.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            _buildChangeLine(changes[i], actionStyle, detailStyle),
          ],
        ],
      ),
    );
  }

  Widget _buildChangeLine(
    ActivityChangeDetail change,
    TextStyle? actionStyle,
    TextStyle? detailStyle,
  ) {
    final info = _changeInfo(change.kind);

    // Split description into action word + detail for rich styling.
    // e.g. "increased third item from 4× to 7×" → label="increased" detail="third item from 4× to 7×"
    // e.g. "removed 10× fourth item" → label="removed" detail="10× fourth item"
    // e.g. "changed role from Scout to Admin" → label="changed role" detail="from Scout to Admin"
    final desc = change.description;
    final label = info.label;

    // Try to split: if description starts with the action word, split there
    String detail;
    if (desc.toLowerCase().startsWith(label.toLowerCase())) {
      detail = desc.substring(label.length).trimLeft();
    } else {
      detail = desc;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(info.icon, size: 16, color: info.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(
              text: '$label ',
              style: actionStyle?.copyWith(color: info.color),
            ),
            TextSpan(
              text: detail,
              style: detailStyle,
            ),
          ])),
        ),
      ],
    );
  }

  _ChangeLineInfo _changeInfo(String kind) {
    switch (kind) {
      case 'renamed':
        return const _ChangeLineInfo(
          label: 'updated',
          icon: Icons.swap_horiz_rounded,
          color: Color(0xFFFF9800),
        );
      case 'name_changed':
        return const _ChangeLineInfo(
          label: 'updated',
          icon: Icons.swap_horiz_rounded,
          color: Color(0xFFFF9800),
        );
      case 'item_added':
        return const _ChangeLineInfo(
          label: 'added',
          icon: Icons.add_circle_rounded,
          color: AppColors.primary,
        );
      case 'item_removed':
        return const _ChangeLineInfo(
          label: 'removed',
          icon: Icons.remove_circle_rounded,
          color: Color(0xFFD92D20),
        );
      case 'item_increased':
        return const _ChangeLineInfo(
          label: 'increased',
          icon: Icons.trending_up_rounded,
          color: AppColors.primary,
        );
      case 'item_decreased':
        return const _ChangeLineInfo(
          label: 'decreased',
          icon: Icons.trending_down_rounded,
          color: Color(0xFFFF9800),
        );
      case 'role_changed':
        return const _ChangeLineInfo(
          label: 'changed role',
          icon: Icons.shield_rounded,
          color: Color(0xFF2F6FED),
        );
      case 'password_reset':
        return const _ChangeLineInfo(
          label: 'password',
          icon: Icons.lock_reset_rounded,
          color: AppColors.muted,
        );
      default:
        return const _ChangeLineInfo(
          label: '',
          icon: Icons.info_rounded,
          color: AppColors.muted,
        );
    }
  }
}

class _ChangeLineInfo {
  const _ChangeLineInfo({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;
}

// ═══════════════════════════════════════════════════════════════════════════
// Animated Entrance — fade + slide for poll-inserted cards
// ═══════════════════════════════════════════════════════════════════════════

class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({
    super.key,
    required this.child,
    required this.onComplete,
  });

  final Widget child;
  final VoidCallback onComplete;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: widget.child,
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

DateTime _dateOnly(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

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