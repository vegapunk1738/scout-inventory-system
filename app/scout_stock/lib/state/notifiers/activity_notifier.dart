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
    this.pollNewIds = const {},
    this.error,
  });

  final List<ActivityEntry> entries;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String query;
  final ActivityFilter filter;
  /// IDs of entries that just arrived via polling — used to trigger entrance animation.
  final Set<String> pollNewIds;
  final String? error;

  ActivityState copyWith({
    List<ActivityEntry>? entries,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? query,
    ActivityFilter? filter,
    Set<String>? pollNewIds,
    String? error,
  }) {
    return ActivityState(
      entries: entries ?? this.entries,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      query: query ?? this.query,
      filter: filter ?? this.filter,
      pollNewIds: pollNewIds ?? this.pollNewIds,
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

  /// Silent poll — fetches the latest page and prepends any new entries
  /// that aren't already in the list. No loading spinners, no scroll reset.
  /// Errors are silently swallowed (next poll will retry).
  Future<void> poll() async {
    // Don't poll while user is actively loading, searching, or filtering
    if (state.loading || state.loadingMore) return;

    try {
      final page = await _fetchPage(
        offset: 0,
        query: state.query,
        filter: state.filter,
      );

      if (page.items.isEmpty) return;

      final existingIds = state.entries.map((e) => e.id).toSet();
      final newItems =
          page.items.where((e) => !existingIds.contains(e.id)).toList();

      if (newItems.isEmpty) return;

      final newIds = newItems.map((e) => e.id).toSet();

      state = state.copyWith(
        entries: [...newItems, ...state.entries],
        pollNewIds: {...state.pollNewIds, ...newIds},
      );
    } catch (_) {
      // Silently ignore poll errors — next tick will retry
    }
  }

  /// Called by the UI after a poll-inserted card finishes its entrance animation.
  void markAnimated(String id) {
    if (!state.pollNewIds.contains(id)) return;
    final updated = Set<String>.from(state.pollNewIds)..remove(id);
    state = state.copyWith(pollNewIds: updated);
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