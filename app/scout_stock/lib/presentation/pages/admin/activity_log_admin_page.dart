import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scout_stock/presentation/widgets/dotted_background.dart';
import 'package:scout_stock/theme/app_theme.dart';

enum ActivityAction { checkOut, checkIn }

class ActivityLine {
  final int qty;
  final String itemName;
  final String bucketName;

  const ActivityLine({
    required this.qty,
    required this.itemName,
    required this.bucketName,
  });
}

class ActivityTxn {
  final String id;
  final String personName;
  final ActivityAction action;
  final int itemCount;
  final DateTime at;
  final List<ActivityLine> lines;

  const ActivityTxn({
    required this.id,
    required this.personName,
    required this.action,
    required this.itemCount,
    required this.at,
    required this.lines,
  });
}

/* ----------------------------- Fake backend (paged) ----------------------------- */

class ActivityPage {
  final List<ActivityTxn> items;
  final bool hasMore;

  const ActivityPage({required this.items, required this.hasMore});
}

class FakeActivityApi {
  FakeActivityApi({List<ActivityTxn>? seed})
    : _seed = List<ActivityTxn>.from(seed ?? _mockTransactions()) {
    _seed.sort((a, b) => b.at.compareTo(a.at)); // ✅ sort once
  }

  final List<ActivityTxn> _seed;

  Future<ActivityPage> fetchPage({
    required int offset,
    required int limit,
    String query = "",
  }) async {
    await Future.delayed(const Duration(milliseconds: 160));

    final q = query.trim().toLowerCase();
    final List<ActivityTxn> list = q.isEmpty
        ? _seed
        : _seed
              .where((t) {
                if (t.personName.toLowerCase().contains(q)) return true;
                final actionText = (t.action == ActivityAction.checkOut)
                    ? "checked out"
                    : "returned";
                if (actionText.contains(q)) return true;

                for (final line in t.lines) {
                  if (line.itemName.toLowerCase().contains(q)) return true;
                  if (line.bucketName.toLowerCase().contains(q)) return true;
                }
                return false;
              })
              .toList(growable: false);

    final start = offset.clamp(0, list.length);
    final end = (offset + limit).clamp(0, list.length);
    final slice = (start < end)
        ? list.sublist(start, end)
        : const <ActivityTxn>[];

    return ActivityPage(items: slice, hasMore: end < list.length);
  }
}

/* ---------------------------------- PAGE ---------------------------------- */

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String _query = "";

  final FakeActivityApi _api = FakeActivityApi(
    // seed: const [], // <- test empty state
  );

  static const int _pageSize = 10;
  final List<ActivityTxn> _loaded = <ActivityTxn>[];
  List<_ActivityRow> _rows = const <_ActivityRow>[];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;

  final Map<String, ValueNotifier<bool>> _expanded = {};
  int _reqId = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadInitial();
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

  void _clearExpandState() {
    for (final n in _expanded.values) {
      n.dispose();
    }
    _expanded.clear();
  }

  void _onScroll() {
    if (_initialLoading || _loadingMore || !_hasMore) return;
    if (!_scrollCtrl.hasClients) return;

    const threshold = 220.0;
    if (_scrollCtrl.position.extentAfter < threshold) {
      _loadMore();
    }
  }

  void _onSearchChanged(String v) {
    _query = v.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), _loadInitial);
    setState(() {}); // just to refresh header text field visuals if needed
  }

  void _rebuildRows() {
    _rows = _buildRows(_loaded);
  }

  Future<void> _loadInitial() async {
    final myReq = ++_reqId;

    setState(() {
      _initialLoading = true;
      _loadingMore = false;
      _hasMore = true;
      _offset = 0;
      _loaded.clear();
      _rows = const <_ActivityRow>[];
    });
    _clearExpandState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    });

    final page = await _api.fetchPage(
      offset: 0,
      limit: _pageSize,
      query: _query,
    );

    if (!mounted || myReq != _reqId) return;

    setState(() {
      _loaded.addAll(page.items);
      _offset = _loaded.length;
      _hasMore = page.hasMore;
      _initialLoading = false;
      _rebuildRows();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent == 0 &&
          _hasMore &&
          !_loadingMore) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_initialLoading || _loadingMore || !_hasMore) return;

    final myReq = _reqId;
    setState(() => _loadingMore = true);

    final page = await _api.fetchPage(
      offset: _offset,
      limit: _pageSize,
      query: _query,
    );

    if (!mounted || myReq != _reqId) return;

    setState(() {
      _loaded.addAll(page.items);
      _offset = _loaded.length;
      _hasMore = page.hasMore;
      _loadingMore = false;
      _rebuildRows();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final mediaTop = MediaQuery.of(context).padding.top;

    final isEmpty = !_initialLoading && _loaded.isEmpty;

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
                    child: ActivityLogHeader(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      onFilter: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Filter coming soon")),
                        );
                      },
                      onExport: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Export coming soon")),
                        );
                      },
                    ),
                  ),
                ),

                if (_initialLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyActivityState(query: _query),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final row = _rows[index];
                          if (row.kind == _RowKind.groupHeader) {
                            return _GroupHeaderRow(
                              titleLeft: row.titleLeft!,
                              titleRight: row.titleRight!,
                              topGap: row.topGap,
                            );
                          }

                          final txn = row.txn!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: RepaintBoundary(
                              child: _ExpandableTxnCard(
                                txn: txn,
                                expanded: _exp(txn.id),
                                radiusXl: tokens.radiusXl,
                              ),
                            ),
                          );
                        },
                        childCount: _rows.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        addSemanticIndexes: false,
                      ),
                    ),
                  ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_initialLoading && !isEmpty && _loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (!_initialLoading && !isEmpty && !_hasMore)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              "No more activity",
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ----------------------------- HEADER ----------------------------- */

class ActivityLogHeader extends StatelessWidget {
  const ActivityLogHeader({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onFilter,
    this.onExport,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilter;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text("Activity Log", style: t.headlineMedium)),
            IconButton(
              onPressed: onFilter ?? () {},
              icon: const Icon(Icons.tune_rounded),
              splashRadius: 22,
            ),
            IconButton(
              onPressed: onExport ?? () {},
              icon: const Icon(Icons.download_rounded),
              splashRadius: 22,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Search card
        Container(
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
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.only(right: 16),
                    hintText: "Search SKU, user, or transaction...",
                    hintStyle: t.bodyLarge?.copyWith(
                      color: const Color(0xFFB9C0C8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/* ----------------------------- EMPTY STATE ----------------------------- */

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final title = query.isEmpty ? "No activity yet" : "No results";
    final subtitle = query.isEmpty
        ? "When scouts check out or return items,\nyou’ll see it here."
        : "Try a different keyword.";

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Center(
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
                Icons.history_rounded,
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

/* ----------------------------- FLAT ROWS (FAST) ----------------------------- */

enum _RowKind { groupHeader, txn }

class _ActivityRow {
  final _RowKind kind;
  final String? titleLeft;
  final String? titleRight;
  final ActivityTxn? txn;
  final double topGap;

  const _ActivityRow._({
    required this.kind,
    this.titleLeft,
    this.titleRight,
    this.txn,
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

  const _ActivityRow.txn(ActivityTxn txn)
    : this._(kind: _RowKind.txn, txn: txn);
}

List<_ActivityRow> _buildRows(List<ActivityTxn> txns) {
  if (txns.isEmpty) return const <_ActivityRow>[];

  final map = <DateTime, List<ActivityTxn>>{};
  for (final t in txns) {
    final key = _dateOnly(t.at);
    (map[key] ??= <ActivityTxn>[]).add(t);
  }

  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));

  final today = _dateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  final last7Start = today.subtract(const Duration(days: 6)); // inclusive

  String leftTitle(DateTime d) {
    if (d == today) return "TODAY";
    if (d == yesterday) return "YESTERDAY";
    if (!d.isBefore(last7Start)) return _weekdayName(d); // ✅ weekday for last 7
    return _prettyDate(d).toUpperCase(); // ✅ older => date
  }

  final rows = <_ActivityRow>[];
  for (int i = 0; i < keys.length; i++) {
    final day = keys[i];
    rows.add(
      _ActivityRow.header(
        titleLeft: leftTitle(day),
        titleRight: _prettyDate(day),
        topGap: i == 0 ? 0 : 16,
      ),
    );

    final items = map[day]!..sort((a, b) => b.at.compareTo(a.at));
    for (final txn in items) {
      rows.add(_ActivityRow.txn(txn));
    }
  }
  return rows;
}

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

/* ----------------------------- CARD ----------------------------- */

class _ExpandableTxnCard extends StatelessWidget {
  const _ExpandableTxnCard({
    required this.txn,
    required this.expanded,
    required this.radiusXl,
  });

  final ActivityTxn txn;
  final ValueNotifier<bool> expanded;
  final double radiusXl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    const blue = Color(0xFF2F6FED);
    final isCheckout = txn.action == ActivityAction.checkOut;
    final stripColor = isCheckout ? blue : AppColors.primary;

    final initials = _initials(txn.personName);
    final timeText = _formatTime(context, txn.at);

    final actionText = isCheckout ? "checked out" : "returned";
    final subtitle =
        "$actionText ${txn.itemCount} ${txn.itemCount == 1 ? "item" : "items"}";

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
          elevation: 2, // ✅ smoother than heavy boxShadow while scrolling
          shadowColor: const Color(0x14000000),
          borderRadius: BorderRadius.circular(radiusXl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => expanded.value = !expanded.value,
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
                          child: Text(
                            initials,
                            style: t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
                              isCheckout
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 12,
                              color: stripColor,
                            ),
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
                            Text(
                              txn.personName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: userNameStyle,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodyMedium?.copyWith(
                                color: AppColors.ink,
                              ),
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
                          Text(
                            timeText,
                            style: t.bodyMedium?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Icon(
                            isOpen
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  crossFadeState: isOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 160),
                  firstChild: const SizedBox.shrink(),
                  secondChild: _DetailsBlock(lines: txn.lines),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailsBlock extends StatelessWidget {
  const _DetailsBlock({required this.lines});
  final List<ActivityLine> lines;

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
            _DetailLine(
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.line,
    required this.qtyStyle,
    required this.itemStyle,
    required this.subStyle,
  });

  final ActivityLine line;
  final TextStyle? qtyStyle;
  final TextStyle? itemStyle;
  final TextStyle? subStyle;

  @override
  Widget build(BuildContext context) {
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
                "${line.qty}×",
                textAlign: TextAlign.right,
                style: qtyStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(line.itemName, style: itemStyle, softWrap: true),
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

/* ----------------------------- HELPERS ----------------------------- */

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
    TimeOfDay.fromDateTime(dt),
    alwaysUse24HourFormat: false,
  );
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _prettyDate(DateTime d) {
  const m = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return "${m[d.month - 1]} ${d.day}, ${d.year}";
}

String _weekdayName(DateTime d) {
  const w = [
    "MONDAY",
    "TUESDAY",
    "WEDNESDAY",
    "THURSDAY",
    "FRIDAY",
    "SATURDAY",
    "SUNDAY",
  ];
  return w[d.weekday - 1];
}

/* ----------------------------- MOCK DATA ----------------------------- */

List<ActivityTxn> _mockTransactions() {
  final now = DateTime.now();

  DateTime at(int daysAgo, int h, int m) {
    final base = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysAgo));
    return DateTime(base.year, base.month, base.day, h, m);
  }

  final seed = <ActivityTxn>[
    ActivityTxn(
      id: "t1",
      personName: "James Doe",
      action: ActivityAction.checkIn,
      itemCount: 5,
      at: at(0, 10, 42),
      lines: const [
        ActivityLine(
          qty: 2,
          itemName: "White cord 5 inch",
          bucketName: "White Cords 5 inch",
        ),
        ActivityLine(qty: 3, itemName: "Blue paper", bucketName: "Paper Mixed"),
      ],
    ),
    ActivityTxn(
      id: "t2",
      personName: "Sarah Smith",
      action: ActivityAction.checkOut,
      itemCount: 2,
      at: at(0, 9, 15),
      lines: const [
        ActivityLine(
          qty: 1,
          itemName: "Cooking Kit A",
          bucketName: "Cooking Kits",
        ),
        ActivityLine(qty: 1, itemName: "Large Pot", bucketName: "Pots & Pans"),
      ],
    ),
  ];

  for (int i = 3; i <= 120; i++) {
    seed.add(
      ActivityTxn(
        id: "t$i",
        personName: (i % 2 == 0) ? "Karim Nader" : "Maya Youssef",
        action: (i % 3 == 0) ? ActivityAction.checkIn : ActivityAction.checkOut,
        itemCount: (i % 5) + 1,
        at: at(i % 16, 12 + (i % 6), (i * 3) % 60),
        lines: [
          ActivityLine(
            qty: 1 + (i % 3),
            itemName: "Item Type #$i",
            bucketName: "Bucket ${(i % 7) + 1}",
          ),
          if (i % 4 == 0)
            ActivityLine(
              qty: 2,
              itemName: "Extra Item #$i",
              bucketName: "Mixed Bucket ${(i % 5) + 1}",
            ),
        ],
      ),
    );
  }

  return seed;
}
