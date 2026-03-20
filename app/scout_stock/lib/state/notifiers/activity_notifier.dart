import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

// ─── Filter enum ────────────────────────────────────────────────────────────

enum ActivityFilter {
  all,
  items,
  resolves,
  buckets,
  users;

  /// Value sent to the backend ?filter= param. Null means no filter.
  String? get apiValue {
    switch (this) {
      case ActivityFilter.all:
        return null;
      case ActivityFilter.items:
        return 'items';
      case ActivityFilter.resolves:
        return 'resolves';
      case ActivityFilter.buckets:
        return 'buckets';
      case ActivityFilter.users:
        return 'users';
    }
  }

  String get label {
    switch (this) {
      case ActivityFilter.all:
        return 'All';
      case ActivityFilter.items:
        return 'Checkouts/Returns';
      case ActivityFilter.resolves:
        return 'Resolves';
      case ActivityFilter.buckets:
        return 'Buckets';
      case ActivityFilter.users:
        return 'Users';
    }
  }
}

// ─── State ──────────────────────────────────────────────────────────────────

class ActivityState {
  const ActivityState({
    this.entries = const [],
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.query = '',
    this.filter = ActivityFilter.all,
    this.error,
  });

  final List<ActivityEntry> entries;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String query;
  final ActivityFilter filter;
  final String? error;

  ActivityState copyWith({
    List<ActivityEntry>? entries,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? query,
    ActivityFilter? filter,
    String? error,
  }) {
    return ActivityState(
      entries: entries ?? this.entries,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      error: error,
    );
  }
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class ActivityNotifier extends Notifier<ActivityState> {
  static const int _pageSize = 20;

  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  @override
  ActivityState build() {
    Future.microtask(() => loadInitial());
    return const ActivityState(loading: true);
  }

  /// Loads the first page. Resets all state.
  Future<void> loadInitial({String? query, ActivityFilter? filter}) async {
    final q = query ?? state.query;
    final f = filter ?? state.filter;

    state = ActivityState(loading: true, query: q, filter: f);

    try {
      final page = await _fetchPage(offset: 0, query: q, filter: f);
      state = state.copyWith(
        entries: page.items,
        hasMore: page.hasMore,
        loading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e is ApiException ? e.displayMessage : e.toString(),
      );
    }
  }

  /// Loads the next page (append).
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;

    state = state.copyWith(loadingMore: true);

    try {
      final page = await _fetchPage(
        offset: state.entries.length,
        query: state.query,
        filter: state.filter,
      );
      state = state.copyWith(
        entries: [...state.entries, ...page.items],
        hasMore: page.hasMore,
        loadingMore: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        loadingMore: false,
        error: e is ApiException ? e.displayMessage : e.toString(),
      );
    }
  }

  /// Search with a new query. Resets pagination.
  Future<void> search(String query) async {
    await loadInitial(query: query.trim());
  }

  /// Set filter. Resets pagination.
  Future<void> setFilter(ActivityFilter filter) async {
    await loadInitial(filter: filter);
  }

  /// Refresh (re-fetch from scratch keeping current query + filter).
  Future<void> refresh() async {
    await loadInitial();
  }

  Future<ActivityPageResponse> _fetchPage({
    required int offset,
    required String query,
    required ActivityFilter filter,
  }) async {
    final queryParams = <String, String>{
      'offset': offset.toString(),
      'limit': _pageSize.toString(),
    };
    if (query.isNotEmpty) {
      queryParams['q'] = query;
    }
    final apiFilter = filter.apiValue;
    if (apiFilter != null) {
      queryParams['filter'] = apiFilter;
    }

    final qs = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final res = await _api.get('/activity?$qs');

    final rawItems = (res['data'] as List?) ?? [];
    final items = rawItems
        .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final hasMore = res['has_more'] as bool? ?? false;

    return ActivityPageResponse(items: items, hasMore: hasMore);
  }
}