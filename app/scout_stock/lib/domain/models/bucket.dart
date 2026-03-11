/// Represents a single item type within a bucket.
class BucketItem {
  const BucketItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.quantity,
    required this.borrowed,
    required this.available,
  });

  final String id;
  final String name;
  final String emoji;

  /// Total stock set by admin.
  final int quantity;

  /// Currently checked out across all users.
  final int borrowed;

  /// quantity - borrowed (never negative).
  final int available;

  factory BucketItem.fromJson(Map<String, dynamic> json) {
    return BucketItem(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      quantity: json['quantity'] as int,
      borrowed: json['borrowed'] as int? ?? 0,
      available: json['available'] as int? ?? (json['quantity'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'quantity': quantity,
  };

  BucketItem copyWith({
    String? name,
    String? emoji,
    int? quantity,
    int? borrowed,
    int? available,
  }) {
    return BucketItem(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      quantity: quantity ?? this.quantity,
      borrowed: borrowed ?? this.borrowed,
      available: available ?? this.available,
    );
  }
}

/// Represents a bucket with its items and stock state.
class Bucket {
  const Bucket({
    required this.id,
    required this.name,
    required this.barcode,
    required this.createdAt,
    required this.createdBy,
    required this.itemTypeCount,
    required this.stockState,
    required this.items,
  });

  final String id;
  final String name;
  final String barcode;
  final String createdAt;
  final String createdBy;
  final int itemTypeCount;
  final BucketStockState stockState;
  final List<BucketItem> items;

  factory Bucket.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List?)
            ?.map((e) => BucketItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return Bucket(
      id: json['id'] as String,
      name: json['name'] as String,
      barcode: json['barcode'] as String,
      createdAt: json['created_at'] as String,
      createdBy: json['created_by'] as String,
      itemTypeCount: json['item_type_count'] as int? ?? items.length,
      stockState: BucketStockState.fromString(
        json['stock_state'] as String? ?? 'out_of_stock',
      ),
      items: items,
    );
  }

  Bucket copyWith({
    String? name,
    List<BucketItem>? items,
    int? itemTypeCount,
    BucketStockState? stockState,
  }) {
    return Bucket(
      id: id,
      name: name ?? this.name,
      barcode: barcode,
      createdAt: createdAt,
      createdBy: createdBy,
      itemTypeCount: itemTypeCount ?? this.itemTypeCount,
      stockState: stockState ?? this.stockState,
      items: items ?? this.items,
    );
  }
}

enum BucketStockState {
  fullyStocked,
  inUse,
  outOfStock;

  static BucketStockState fromString(String value) {
    switch (value) {
      case 'fully_stocked':
        return BucketStockState.fullyStocked;
      case 'in_use':
        return BucketStockState.inUse;
      case 'out_of_stock':
      default:
        return BucketStockState.outOfStock;
    }
  }
}

/// A borrower entry returned when admin tries to decrease quantity
/// below currently borrowed amount.
class BorrowerInfo {
  const BorrowerInfo({
    required this.userId,
    required this.fullName,
    required this.scoutId,
    required this.borrowed,
  });

  final String userId;
  final String fullName;
  final String scoutId;
  final int borrowed;

  factory BorrowerInfo.fromJson(Map<String, dynamic> json) {
    return BorrowerInfo(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      scoutId: json['scout_id'] as String,
      borrowed: json['borrowed'] as int,
    );
  }
}

/// Conflict response when quantity decrease is blocked.
class QuantityConflict {
  const QuantityConflict({
    required this.itemTypeId,
    required this.itemName,
    required this.requestedQuantity,
    required this.currentlyBorrowed,
    required this.borrowers,
  });

  final String itemTypeId;
  final String itemName;
  final int requestedQuantity;
  final int currentlyBorrowed;
  final List<BorrowerInfo> borrowers;

  factory QuantityConflict.fromJson(Map<String, dynamic> json) {
    return QuantityConflict(
      itemTypeId: json['item_type_id'] as String,
      itemName: json['item_name'] as String,
      requestedQuantity: json['requested_quantity'] as int,
      currentlyBorrowed: json['currently_borrowed'] as int,
      borrowers: (json['borrowers'] as List)
          .map((e) => BorrowerInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}