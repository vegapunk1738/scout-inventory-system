import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

// ─── Unified filter ─────────────────────────────────────────────────────────

enum ActivityFilter {
  all,
  checkouts,
  returns,
  resolved,
  admin,
}

extension ActivityFilterX on ActivityFilter {
  String get label {
    switch (this) {
      case ActivityFilter.all:
        return 'All';
      case ActivityFilter.checkouts:
        return 'Checkouts';
      case ActivityFilter.returns:
        return 'Returns';
      case ActivityFilter.resolved:
        return 'Resolved';
      case ActivityFilter.admin:
        return 'Admin';
    }
  }

  /// Maps this filter to backend query params: { entity, action }.
  Map<String, String> get queryParams {
    switch (this) {
      case ActivityFilter.all:
        return {'entity': 'all', 'action': 'all'};
      case ActivityFilter.checkouts:
        return {'entity': 'item', 'action': 'checkout'};
      case ActivityFilter.returns:
        return {'entity': 'item', 'action': 'return'};
      case ActivityFilter.resolved:
        return {'entity': 'item', 'action': 'resolved'};
      case ActivityFilter.admin:
        return {'entity': 'admin', 'action': 'all'};
    }
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
    this.filter = ActivityFilter.all,
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
  final ActivityFilter filter;
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
    ActivityFilter? filter,
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
      filter: filter ?? this.filter,
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

    // Schedule the initial fetch AFTER build() returns the initial state.
    Future.microtask(() => _fetchInitial());

    return const ActivityState(loading: true);
  }

  // ── Public API ──────────────────────────────────────────────────────────

  void setFilter(ActivityFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
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
    final filterParams = state.filter.queryParams;

    final params = <String, String>{
      'limit': '$_pageSize',
      'offset': '$offset',
      ...filterParams,
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

      final filterParams = state.filter.queryParams;

      final params = <String, String>{
        'limit': '$newCount',
        'offset': '0',
        'since': since,
        ...filterParams,
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