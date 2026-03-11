import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/bucket.dart';
import 'package:scout_stock/state/providers/api_provider.dart';

/// Manages the admin bucket list.
///
/// Lazy: `build()` fires `GET /buckets` only when first watched (i.e. when the
/// admin navigates to the Buckets tab). Mutations hit the API then patch local
/// state — no full refetch needed.
class BucketsNotifier extends AsyncNotifier<List<Bucket>> {
  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  // ── Initial fetch ──────────────────────────────────────────────────────

  @override
  Future<List<Bucket>> build() async {
    final res = await _api.get('/buckets');
    final raw = (res['data'] as List).cast<Map<String, dynamic>>();
    final buckets = raw.map(Bucket.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return buckets;
  }

  // ── Create ─────────────────────────────────────────────────────────────

  /// Creates a bucket with items. Returns the created bucket.
  ///
  /// The backend auto-generates a unique barcode from the abbreviation.
  Future<Bucket> createBucket({
    required String name,
    required String abbreviation,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _api.post(
      '/buckets',
      body: {'name': name, 'abbreviation': abbreviation, 'items': items},
    );

    final created = Bucket.fromJson(res['data'] as Map<String, dynamic>);
    state = AsyncData([created, ...state.requireValue]);
    return created;
  }

  // ── Update ─────────────────────────────────────────────────────────────

  /// Updates a bucket. Returns the updated bucket.
  ///
  /// Throws [ApiException] with 409 if quantity decrease is blocked
  /// by currently borrowed items.
  Future<Bucket> updateBucket(
    String bucketId, {
    String? name,
    List<Map<String, dynamic>>? items,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (items != null) body['items'] = items;

    if (body.isEmpty) throw ArgumentError('Nothing to update');

    final res = await _api.patch('/buckets/$bucketId', body: body);
    final updated = Bucket.fromJson(res['data'] as Map<String, dynamic>);

    final list = [...state.requireValue];
    final idx = list.indexWhere((b) => b.id == bucketId);
    if (idx != -1) {
      list[idx] = updated;
    }
    state = AsyncData(list);
    return updated;
  }

  // ── Delete ─────────────────────────────────────────────────────────────

  Future<void> deleteBucket(String bucketId) async {
    await _api.delete('/buckets/$bucketId');

    final list = state.requireValue.where((b) => b.id != bucketId).toList();
    state = AsyncData(list);
  }

  // ── Fetch single bucket by barcode (for scanning) ─────────────────────

  Future<Bucket> fetchByBarcode(String barcode) async {
    final res = await _api.get('/buckets/barcode/$barcode');
    return Bucket.fromJson(res['data'] as Map<String, dynamic>);
  }

  // ── Fetch borrowers for an item (admin resolution flow) ───────────────

  Future<List<BorrowerInfo>> fetchBorrowers(
    String bucketId,
    String itemTypeId,
  ) async {
    final res = await _api.get(
      '/buckets/$bucketId/items/$itemTypeId/borrowers',
    );
    final data = res['data'] as Map<String, dynamic>;
    final borrowers = (data['borrowers'] as List)
        .map((e) => BorrowerInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return borrowers;
  }

  // ── Resolve borrowed items (admin resolution flow) ────────────────────

  /// Resolves borrowed items for an item type. Each resolution creates a
  /// return transaction with the appropriate status.
  Future<void> resolveBorrowed(
    String bucketId,
    String itemTypeId, {
    required List<Map<String, dynamic>> resolutions,
  }) async {
    await _api.post(
      '/buckets/$bucketId/items/$itemTypeId/resolve',
      body: {'resolutions': resolutions},
    );

    // Invalidate state to trigger a re-fetch
    ref.invalidateSelf();
  }

  // ── Refresh ────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}
