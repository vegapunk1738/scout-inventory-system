import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/activity.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

/// State for the activity log page.
class ActivityState {
  const ActivityState({
    this.entries = const [],
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.query = '',
    this.error,
  });

  final List<ActivityEntry> entries;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String query;
  final String? error;

  ActivityState copyWith({
    List<ActivityEntry>? entries,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? query,
    String? error,
  }) {
    return ActivityState(
      entries: entries ?? this.entries,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      query: query ?? this.query,
      error: error,
    );
  }
}

/// Notifier that manages the admin activity log.
///
/// Supports paginated loading and search filtering.
class ActivityNotifier extends Notifier<ActivityState> {
  static const int _pageSize = 20;

  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  @override
  ActivityState build() {
    // Kick off initial load
    Future.microtask(() => loadInitial());
    return const ActivityState(loading: true);
  }

  /// Loads the first page of activity. Resets all state.
  Future<void> loadInitial({String? query}) async {
    final q = query ?? state.query;

    state = ActivityState(loading: true, query: q);

    try {
      final page = await _fetchPage(offset: 0, query: q);
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

  /// Refresh (re-fetch from scratch keeping current query).
  Future<void> refresh() async {
    await loadInitial();
  }

  Future<ActivityPageResponse> _fetchPage({
    required int offset,
    required String query,
  }) async {
    final queryParams = <String, String>{
      'offset': offset.toString(),
      'limit': _pageSize.toString(),
    };
    if (query.isNotEmpty) {
      queryParams['q'] = query;
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