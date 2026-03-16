import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/state/providers/api_provider.dart';
import 'package:scout_stock/state/providers/me_provider.dart';
import 'package:scout_stock/state/providers/transactions_provider.dart';
import 'package:uuid/uuid.dart';

// ─── Models ─────────────────────────────────────────────────────────────────

class BorrowedItem {
  const BorrowedItem({
    required this.itemTypeId,
    required this.bucketId,
    required this.itemName,
    required this.itemEmoji,
    required this.bucketName,
    required this.bucketBarcode,
    required this.borrowed,
    required this.itemTotalQuantity,
    this.checkedOutAt,
  });

  final String itemTypeId;
  final String bucketId;
  final String itemName;
  final String itemEmoji;
  final String bucketName;
  final String bucketBarcode;
  final int borrowed;
  final int itemTotalQuantity;
  final String? checkedOutAt;

  factory BorrowedItem.fromJson(Map<String, dynamic> json) {
    return BorrowedItem(
      itemTypeId: json['item_type_id'] as String,
      bucketId: json['bucket_id'] as String,
      itemName: json['item_name'] as String? ?? 'Unknown',
      itemEmoji: json['item_emoji'] as String? ?? '📦',
      bucketName: json['bucket_name'] as String? ?? 'Unknown',
      bucketBarcode: json['bucket_barcode'] as String? ?? '',
      borrowed: json['borrowed'] as int,
      itemTotalQuantity: json['item_total_quantity'] as int? ?? 0,
      checkedOutAt: json['checked_out_at'] as String?,
    );
  }
}

class ReturnHistoryItem {
  const ReturnHistoryItem({
    required this.transactionId,
    required this.createdAt,
    required this.itemTypeId,
    required this.bucketId,
    required this.itemName,
    required this.itemEmoji,
    required this.bucketName,
    required this.bucketBarcode,
    required this.managedBy,
    required this.quantity,
    required this.status,
  });

  final String transactionId;
  final String createdAt;
  final String itemTypeId;
  final String bucketId;
  final String itemName;
  final String itemEmoji;
  final String bucketName;
  final String bucketBarcode;
  final String managedBy;
  final int quantity;
  final String status;

  factory ReturnHistoryItem.fromJson(Map<String, dynamic> json) {
    return ReturnHistoryItem(
      transactionId: json['transaction_id'] as String,
      createdAt: json['created_at'] as String,
      itemTypeId: json['item_type_id'] as String,
      bucketId: json['bucket_id'] as String,
      itemName: json['item_name'] as String? ?? 'Unknown',
      itemEmoji: json['item_emoji'] as String? ?? '📦',
      bucketName: json['bucket_name'] as String? ?? 'Unknown',
      bucketBarcode: json['bucket_barcode'] as String? ?? '',
      managedBy: json['managed_by'] as String? ?? 'Unknown',
      quantity: json['quantity'] as int,
      status: json['status'] as String? ?? 'normal',
    );
  }
}

class MyTransactionsState {
  const MyTransactionsState({
    required this.borrowed,
    required this.returnHistory,
  });

  final List<BorrowedItem> borrowed;
  final List<ReturnHistoryItem> returnHistory;

  int get totalBorrowed => borrowed.fold<int>(0, (sum, b) => sum + b.borrowed);
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class TransactionsNotifier extends AsyncNotifier<MyTransactionsState> {
  ApiClient get _api {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not authenticated');
    return client;
  }

  @override
  Future<MyTransactionsState> build() async {
    final res = await _api.get('/transactions/me');
    final data = res['data'] as Map<String, dynamic>;

    final borrowed = (data['borrowed'] as List)
        .map((e) => BorrowedItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final history = (data['return_history'] as List)
        .map((e) => ReturnHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return MyTransactionsState(borrowed: borrowed, returnHistory: history);
  }

  /// Checkout items from cart. Returns the transaction ID.
  ///
  /// IMPORTANT: Uses [Item.bucketId] (the UUID) for the API call,
  /// NOT [Item.bucketBarcode] (the SSB-XXX-XXX display string).
  Future<String> checkout(List<Item> cartItems) async {
    final idempotencyKey = const Uuid().v4();

    final res = await _api.post(
      '/transactions/checkout',
      body: {
        'idempotency_key': idempotencyKey,
        'items': cartItems
            .map(
              (item) => {
                'bucket_id': item.bucketId,       // ← UUID, not barcode
                'item_type_id': item.id,
                'quantity': item.quantity,
              },
            )
            .toList(),
      },
    );

    final txId =
        (res['data'] as Map<String, dynamic>)['transaction_id'] as String;

    // Refresh own state
    ref.invalidateSelf();

    // Refresh Me page so new borrowed items show immediately
    ref.read(meProvider.notifier).refresh();

    return txId;
  }

  /// Return items. Each entry must include bucket_id (UUID), item_type_id, quantity.
  Future<String> returnItems(List<Map<String, dynamic>> items) async {
    final idempotencyKey = const Uuid().v4();

    final res = await _api.post(
      '/transactions/return',
      body: {'idempotency_key': idempotencyKey, 'items': items},
    );

    final txId =
        (res['data'] as Map<String, dynamic>)['transaction_id'] as String;

    // Refresh own state
    ref.invalidateSelf();

    // Refresh Me page so returned items show immediately
    ref.read(meProvider.notifier).refresh();

    return txId;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}