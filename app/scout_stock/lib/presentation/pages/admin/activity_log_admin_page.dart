import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/state/providers/activity_provider.dart';
import 'package:scout_stock/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Activity Log Page — wired to real API via activityProvider
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

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
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
      for (final n in _expanded.values) {
        n.dispose();
      }
      _expanded.clear();
    });
    setState(() {});
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

                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    height: 72,
                    child: Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _SearchCard(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        hintText: 'Search user, item, or bucket…',
                      ),
                    ),
                  ),
                ),

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
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _ExpandableActivityCard(
                                entry: entry,
                                expanded: _exp(entry.id),
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
              Text(
                'ADMIN VIEW',
                style: t.labelMedium?.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 1.8,
                ),
              ),
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
  Widget build(BuildContext c, double shrinkOffset, bool overlapsContent) =>
      child;

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

  const _ActivityRow.header({
    required String titleLeft,
    required String titleRight,
    double topGap = 0,
  }) : this._(
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
      topGap: i == 0 ? 0 : 16,
    ));
    final items = map[day]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final e in items) {
      rows.add(_ActivityRow.entry(e));
    }
  }
  return rows;
}

// ═══════════════════════════════════════════════════════════════════════════
// Group Header Row
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
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expandable Activity Card
// ═══════════════════════════════════════════════════════════════════════════

class _ExpandableActivityCard extends StatelessWidget {
  const _ExpandableActivityCard({
    required this.entry,
    required this.expanded,
    required this.radiusXl,
  });

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
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );

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
                        // ✅ Always initials from actor name
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.background,
                          child: Text(
                            initials,
                            style: t.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        // ✅ Badge snug at bottom-right of avatar
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
                            // ✅ summary comes from backend
                            Text(
                              entry.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  t.bodyMedium?.copyWith(color: AppColors.ink),
                            ),
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
                              color: AppColors.muted,
                            )
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
    case 'item_resolved':
      return const Color(0xFF7C3AED);
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
    case 'item_resolved':
      return Icons.gavel_rounded;
    default:
      return Icons.info_rounded;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expanded Content Builder
// ═══════════════════════════════════════════════════════════════════════════

Widget _buildExpandedContent(ActivityEntry entry) {
  switch (entry.action) {
    case 'checkout':
    case 'return':
      return _CheckoutReturnDetails(items: entry.items);
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
  const _CheckoutReturnDetails({required this.items});
  final List<ActivityItemDetail> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final qtyStyle = t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: AppColors.ink,
        height: 1.1);
    final itemStyle = t.bodyLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
        height: 1.2);
    final subStyle = t.bodyMedium
        ?.copyWith(fontSize: 13, color: AppColors.muted, height: 1.25);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.outline))),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text("${items[i].quantity}×",
                          textAlign: TextAlign.right, style: qtyStyle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(items[i].itemName,
                            style: itemStyle, softWrap: true)),
                  ],
                ),
                if (items[i].bucketName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 46),
                    child: Text("from ${items[i].bucketName}",
                        style: subStyle, softWrap: true),
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
// Bucket Created detail (items added)
// ═══════════════════════════════════════════════════════════════════════════

class _BucketCreatedDetails extends StatelessWidget {
  const _BucketCreatedDetails({required this.items});
  final List<ActivityItemDetail> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final changeStyle = t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        height: 1.35);
    final labelStyle = t.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("added ", style: labelStyle),
                Expanded(
                  child: Text("${items[i].quantity}× ${items[i].itemName}",
                      style: changeStyle),
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
    final changeStyle = t.bodyMedium?.copyWith(
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
          for (int i = 0; i < changes.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _changeIcon(changes[i].kind),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(changes[i].description, style: changeStyle)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _changeIcon(String kind) {
    final Color color;
    final IconData icon;

    switch (kind) {
      case 'renamed':
      case 'name_changed':
        color = const Color(0xFFFF9800);
        icon = Icons.swap_horiz_rounded;
      case 'item_added':
        color = AppColors.primary;
        icon = Icons.add_rounded;
      case 'item_removed':
        color = const Color(0xFFD92D20);
        icon = Icons.remove_rounded;
      case 'item_increased':
        color = AppColors.primary;
        icon = Icons.trending_up_rounded;
      case 'item_decreased':
        color = const Color(0xFFFF9800);
        icon = Icons.trending_down_rounded;
      case 'role_changed':
        color = const Color(0xFF2F6FED);
        icon = Icons.shield_rounded;
      case 'password_reset':
        color = AppColors.muted;
        icon = Icons.lock_reset_rounded;
      default:
        color = AppColors.muted;
        icon = Icons.info_rounded;
    }

    return Icon(icon, size: 16, color: color);
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