import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

// ─── Filter types ───────────────────────────────────────────────────────────

enum ActivityEntityFilter { all, item, bucket, user }

enum ActivityActionFilter {
  all,
  checkout,
  returned, // 'return' is a keyword
  resolved,
  created,
  updated,
  deleted,
}

extension ActivityEntityFilterX on ActivityEntityFilter {
  String get queryValue {
    switch (this) {
      case ActivityEntityFilter.all:
        return 'all';
      case ActivityEntityFilter.item:
        return 'item';
      case ActivityEntityFilter.bucket:
        return 'bucket';
      case ActivityEntityFilter.user:
        return 'user';
    }
  }

  String get label {
    switch (this) {
      case ActivityEntityFilter.all:
        return 'All';
      case ActivityEntityFilter.item:
        return 'Items';
      case ActivityEntityFilter.bucket:
        return 'Buckets';
      case ActivityEntityFilter.user:
        return 'Users';
    }
  }
}

extension ActivityActionFilterX on ActivityActionFilter {
  String get queryValue {
    switch (this) {
      case ActivityActionFilter.all:
        return 'all';
      case ActivityActionFilter.checkout:
        return 'checkout';
      case ActivityActionFilter.returned:
        return 'return';
      case ActivityActionFilter.resolved:
        return 'resolved';
      case ActivityActionFilter.created:
        return 'created';
      case ActivityActionFilter.updated:
        return 'updated';
      case ActivityActionFilter.deleted:
        return 'deleted';
    }
  }

  String get label {
    switch (this) {
      case ActivityActionFilter.all:
        return 'All';
      case ActivityActionFilter.checkout:
        return 'Checkout';
      case ActivityActionFilter.returned:
        return 'Return';
      case ActivityActionFilter.resolved:
        return 'Resolved';
      case ActivityActionFilter.created:
        return 'Created';
      case ActivityActionFilter.updated:
        return 'Updated';
      case ActivityActionFilter.deleted:
        return 'Deleted';
    }
  }
}

// ─── Derived action filters per entity ──────────────────────────────────────

List<ActivityActionFilter> actionsForEntity(ActivityEntityFilter entity) {
  switch (entity) {
    case ActivityEntityFilter.all:
      return ActivityActionFilter.values;
    case ActivityEntityFilter.item:
      return [
        ActivityActionFilter.all,
        ActivityActionFilter.checkout,
        ActivityActionFilter.returned,
        ActivityActionFilter.resolved,
      ];
    case ActivityEntityFilter.bucket:
      return [
        ActivityActionFilter.all,
        ActivityActionFilter.created,
        ActivityActionFilter.updated,
        ActivityActionFilter.deleted,
      ];
    case ActivityEntityFilter.user:
      return [
        ActivityActionFilter.all,
        ActivityActionFilter.created,
        ActivityActionFilter.updated,
        ActivityActionFilter.deleted,
      ];
  }
}

// ─── State ──────────────────────────────────────────────────────────────────

class ActivityState {
  const ActivityState({
    this.entries = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.total = 0,
    this.entityFilter = ActivityEntityFilter.all,
    this.actionFilter = ActivityActionFilter.all,
    this.searchQuery = '',
    this.error,
    this.newEntryIds = const {},
    this.lastPollAt,
  });

  final List<ActivityEntry> entries;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int total;
  final ActivityEntityFilter entityFilter;
  final ActivityActionFilter actionFilter;
  final String searchQuery;
  final String? error;

  /// IDs of entries that arrived via polling (for glow animation).
  final Set<String> newEntryIds;

  /// Timestamp of the last poll check. Used as the `since` param.
  final String? lastPollAt;

  ActivityState copyWith({
    List<ActivityEntry>? entries,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? total,
    ActivityEntityFilter? entityFilter,
    ActivityActionFilter? actionFilter,
    String? searchQuery,
    String? error,
    Set<String>? newEntryIds,
    String? lastPollAt,
  }) {
    return ActivityState(
      entries: entries ?? this.entries,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
      entityFilter: entityFilter ?? this.entityFilter,
      actionFilter: actionFilter ?? this.actionFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
      newEntryIds: newEntryIds ?? this.newEntryIds,
      lastPollAt: lastPollAt ?? this.lastPollAt,
    );
  }
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class ActivityNotifier extends Notifier<ActivityState> {
  static const int _pageSize = 20;
  static const Duration _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  int _reqId = 0;
  Timer? _searchDebounce;

  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  @override
  ActivityState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _searchDebounce?.cancel();
    });

    // IMPORTANT: Schedule the initial fetch AFTER build() returns the
    // initial state. Calling _fetchInitial() synchronously here would
    // try to read/write `state` before it's been set, causing
    // "Tried to read the state of an uninitialized provider".
    Future.microtask(() => _fetchInitial());

    return const ActivityState(loading: true);
  }

  // ── Public API ──────────────────────────────────────────────────────────

  void setEntityFilter(ActivityEntityFilter filter) {
    if (filter == state.entityFilter) return;

    final validActions = actionsForEntity(filter);
    final newAction = validActions.contains(state.actionFilter)
        ? state.actionFilter
        : ActivityActionFilter.all;

    state = state.copyWith(
      entityFilter: filter,
      actionFilter: newAction,
    );
    _fetchInitial();
  }

  void setActionFilter(ActivityActionFilter filter) {
    if (filter == state.actionFilter) return;
    state = state.copyWith(actionFilter: filter);
    _fetchInitial();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _fetchInitial);
  }

  void clearNewEntryIds() {
    state = state.copyWith(newEntryIds: const {});
  }

  void markSeen(String id) {
    final updated = Set<String>.from(state.newEntryIds)..remove(id);
    state = state.copyWith(newEntryIds: updated);
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;

    state = state.copyWith(loadingMore: true);

    try {
      final page = await _fetchPage(offset: state.entries.length);
      state = state.copyWith(
        entries: [...state.entries, ...page.entries],
        hasMore: page.hasMore,
        total: page.total,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: '$e');
    }
  }

  Future<void> refresh() async {
    await _fetchInitial();
  }

  // ── Internal ────────────────────────────────────────────────────────────

  Future<void> _fetchInitial() async {
    final myReq = ++_reqId;

    state = state.copyWith(loading: true, error: null);

    try {
      final page = await _fetchPage(offset: 0);
      if (myReq != _reqId) return;

      final latestAt = page.entries.isNotEmpty
          ? page.entries.first.createdAt.toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String();

      state = state.copyWith(
        entries: page.entries,
        hasMore: page.hasMore,
        total: page.total,
        loading: false,
        lastPollAt: latestAt,
        newEntryIds: const {},
      );

      _startPolling();
    } catch (e) {
      if (myReq != _reqId) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<_ActivityPage> _fetchPage({required int offset}) async {
    final params = <String, String>{
      'limit': '$_pageSize',
      'offset': '$offset',
      'entity': state.entityFilter.queryValue,
      'action': state.actionFilter.queryValue,
    };
    if (state.searchQuery.isNotEmpty) {
      params['q'] = state.searchQuery;
    }

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final res = await _api.get('/activity?$query');

    final data = res['data'] as List;
    final entries = data
        .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    return _ActivityPage(
      entries: entries,
      hasMore: res['has_more'] as bool? ?? false,
      total: res['total'] as int? ?? 0,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final since = state.lastPollAt;
    if (since == null) return;

    try {
      final pollRes = await _api.get(
        '/activity/poll?since=${Uri.encodeComponent(since)}',
      );
      final newCount = pollRes['new_count'] as int? ?? 0;

      if (newCount == 0) return;

      final params = <String, String>{
        'limit': '$newCount',
        'offset': '0',
        'since': since,
        'entity': state.entityFilter.queryValue,
        'action': state.actionFilter.queryValue,
      };
      if (state.searchQuery.isNotEmpty) {
        params['q'] = state.searchQuery;
      }
      final query = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final res = await _api.get('/activity?$query');

      final data = res['data'] as List;
      if (data.isEmpty) return;

      final newEntries = data
          .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      final existingIds = state.entries.map((e) => e.id).toSet();
      final trulyNew =
          newEntries.where((e) => !existingIds.contains(e.id)).toList();

      if (trulyNew.isEmpty) return;

      final latestAt = trulyNew.first.createdAt.toUtc().toIso8601String();

      state = state.copyWith(
        entries: [...trulyNew, ...state.entries],
        total: state.total + trulyNew.length,
        lastPollAt: latestAt,
        newEntryIds: {
          ...state.newEntryIds,
          ...trulyNew.map((e) => e.id),
        },
      );
    } catch (_) {
      // Polling failures are silent — retry next interval
    }
  }
}

class _ActivityPage {
  final List<ActivityEntry> entries;
  final bool hasMore;
  final int total;

  const _ActivityPage({
    required this.entries,
    required this.hasMore,
    required this.total,
  });
}