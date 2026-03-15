import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/state/providers/api_provider.dart';
import 'package:scout_stock/state/providers/transactions_provider.dart';
import '../../domain/models/item.dart';

enum MeFilterMode { all, borrowedOnly, returnedOnly }

class BorrowedRecord {
  const BorrowedRecord({
    required this.id,
    required this.checkedOutAt,
    required this.item,
    required this.managedBy,
  });

  final String id;
  final DateTime checkedOutAt;
  final String managedBy;

  /// [item.quantity] = how many the user wants to return (0..maxQuantity).
  /// [item.maxQuantity] = total borrowed.
  final Item item;

  BorrowedRecord copyWith({DateTime? checkedOutAt, Item? item, String? managedBy}) =>
      BorrowedRecord(
        id: id,
        checkedOutAt: checkedOutAt ?? this.checkedOutAt,
        item: item ?? this.item,
        managedBy: managedBy ?? this.managedBy,
      );
}

class ReturnedRecord {
  const ReturnedRecord({
    required this.id,
    required this.returnedAt,
    required this.item,
    required this.managedBy,
    this.status = 'normal',
  });

  final String id;
  final DateTime returnedAt;
  final Item item;
  final String managedBy;
  final String status; // 'normal', 'lost', 'damaged'
}

class MeState {
  const MeState({
    required this.mode,
    required this.submitting,
    required this.borrowed,
    required this.returned,
    this.loading = false,
    this.error,
  });

  final MeFilterMode mode;
  final bool submitting;
  final bool loading;
  final List<BorrowedRecord> borrowed;
  final List<ReturnedRecord> returned;
  final String? error;

  int get totalToReturn =>
      borrowed.fold<int>(0, (sum, r) => sum + r.item.quantity);

  bool get hasAny => borrowed.isNotEmpty || returned.isNotEmpty;

  MeState copyWith({
    MeFilterMode? mode,
    bool? submitting,
    bool? loading,
    List<BorrowedRecord>? borrowed,
    List<ReturnedRecord>? returned,
    String? error,
  }) {
    return MeState(
      mode: mode ?? this.mode,
      submitting: submitting ?? this.submitting,
      loading: loading ?? this.loading,
      borrowed: borrowed ?? this.borrowed,
      returned: returned ?? this.returned,
      error: error,
    );
  }
}

class MeNotifier extends Notifier<MeState> {
  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  @override
  MeState build() {
    // Trigger initial fetch
    _fetchData();

    return const MeState(
      mode: MeFilterMode.all,
      submitting: false,
      loading: true,
      borrowed: [],
      returned: [],
    );
  }

  Future<void> _fetchData() async {
    try {
      final res = await _api.get('/transactions/me');
      final data = res['data'] as Map<String, dynamic>;

      final borrowedRaw =
          (data['borrowed'] as List).cast<Map<String, dynamic>>();
      final historyRaw =
          (data['return_history'] as List).cast<Map<String, dynamic>>();

      final borrowed = borrowedRaw.map((b) {
        final checkedOutStr = b['checked_out_at'] as String?;
        final borrowedQty = b['borrowed'] as int;
        final bucketId = b['bucket_id'] as String;
        final bucketBarcode = b['bucket_barcode'] as String? ?? '';
        final managedBy = b['managed_by'] as String? ?? 'Unknown';

        return BorrowedRecord(
          id: 'br_${b['item_type_id']}',
          checkedOutAt: checkedOutStr != null
              ? DateTime.parse(checkedOutStr)
              : DateTime.now(),
          managedBy: managedBy,
          item: Item(
            id: b['item_type_id'] as String,
            name: b['item_name'] as String,
            bucketId: bucketId,             // ← UUID for API calls
            bucketBarcode: bucketBarcode,    // ← SSB-XXX-XXX for display
            bucketName: b['bucket_name'] as String,
            // quantity = how many user wants to return (starts at 0)
            quantity: 0,
            // maxQuantity = total borrowed by this user
            maxQuantity: borrowedQty,
            emoji: b['item_emoji'] as String,
          ),
        );
      }).toList();

      final returned = historyRaw.map((r) {
        final quantity = r['quantity'] as int;
        final bucketId = r['bucket_id'] as String;
        final bucketBarcode = r['bucket_barcode'] as String? ?? '';
        final managedBy = r['managed_by'] as String? ?? 'Unknown';

        return ReturnedRecord(
          id: 'rr_${r['transaction_id']}',
          returnedAt: DateTime.parse(r['created_at'] as String),
          status: r['status'] as String? ?? 'normal',
          managedBy: managedBy,
          item: Item(
            id: r['item_type_id'] as String,
            name: r['item_name'] as String,
            bucketId: bucketId,
            bucketBarcode: bucketBarcode,
            bucketName: r['bucket_name'] as String,
            quantity: quantity,
            maxQuantity: quantity,
            emoji: r['item_emoji'] as String,
          ),
        );
      }).toList();

      state = state.copyWith(
        loading: false,
        borrowed: borrowed,
        returned: returned,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  void toggleMode(MeFilterMode tapped) {
    final next = (state.mode == tapped) ? MeFilterMode.all : tapped;
    state = state.copyWith(mode: next);
  }

  void setToReturn(String borrowedRecordId, int next) {
    final borrowed = state.borrowed;
    final idx = borrowed.indexWhere((r) => r.id == borrowedRecordId);
    if (idx == -1) return;

    final r = borrowed[idx];
    final clamped = next.clamp(0, r.item.maxQuantity);
    if (clamped == r.item.quantity) return;

    final updated = [...borrowed];
    updated[idx] = r.copyWith(item: r.item.copyWith(quantity: clamped));
    state = state.copyWith(borrowed: updated);
  }

  Future<({bool ok, String? txnId, String? error})> submitReturn() async {
    if (state.submitting) return (ok: false, txnId: null, error: 'busy');
    if (state.totalToReturn == 0) {
      return (ok: false, txnId: null, error: 'empty');
    }

    state = state.copyWith(submitting: true);
    try {
      final itemsToReturn = state.borrowed
          .where((r) => r.item.quantity > 0)
          .map(
            (r) => {
              'bucket_id': r.item.bucketId,   // ← UUID, not barcode
              'item_type_id': r.item.id,
              'quantity': r.item.quantity,
            },
          )
          .toList();

      final txNotifier = ref.read(transactionsProvider.notifier);
      final txnId = await txNotifier.returnItems(itemsToReturn);

      // Refresh data from API
      await _fetchData();

      return (ok: true, txnId: txnId, error: null);
    } on ApiException catch (e) {
      String errorMsg;
      if (e.isConflict) {
        // 409 — trying to return more than borrowed
        errorMsg = e.message;
      } else if (e.isNotFound) {
        // 404 — item or bucket was deleted, but return should still work
        // via the backend's lenient handling. If we still get 404, it means
        // the user never had this item checked out.
        errorMsg = 'This item is no longer in the system. '
            'Please contact an admin.';
      } else {
        errorMsg = e.displayMessage;
      }
      return (ok: false, txnId: null, error: errorMsg);
    } catch (e) {
      return (ok: false, txnId: null, error: '$e');
    } finally {
      state = state.copyWith(submitting: false);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    await _fetchData();
  }
}