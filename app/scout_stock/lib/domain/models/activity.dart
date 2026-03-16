/// Represents a single entry in the unified activity feed.
///
/// Covers both transaction events (checkout, return, resolved) and
/// audit events (bucket/user CRUD).
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.actorId,
    required this.actorName,
    required this.entity,
    required this.summary,
    required this.createdAt,
    this.meta,
  });

  final String id;

  /// One of: checkout, return, resolved_lost, resolved_damaged,
  /// bucket_created, bucket_updated, bucket_deleted,
  /// user_created, user_updated, user_deleted
  final String kind;

  final String actorId;
  final String actorName;

  /// 'item' | 'bucket' | 'user'
  final String entity;

  /// Human-readable summary, e.g. "Jean Dupont checked out 3 item(s)"
  final String summary;

  /// Parsed JSON metadata. For transactions this is a list of line items.
  /// For audit logs it may contain extra context.
  final dynamic meta;

  final DateTime createdAt;

  // ── Derived helpers ───────────────────────────────────────────────────

  bool get isCheckout => kind == 'checkout';
  bool get isReturn => kind == 'return';
  bool get isResolved => kind.startsWith('resolved');
  bool get isTransaction => isCheckout || isReturn || isResolved;

  bool get isBucketEvent => kind.startsWith('bucket_');
  bool get isUserEvent => kind.startsWith('user_');

  /// Number of line items (for transaction entries).
  int get itemCount {
    if (meta is List) return (meta as List).length;
    return 0;
  }

  /// Transaction line items parsed from meta.
  List<ActivityLineItem> get lineItems {
    if (meta is! List) return const [];
    return (meta as List).map((e) {
      final m = e as Map<String, dynamic>;
      return ActivityLineItem(
        itemName: m['item_name'] as String? ?? 'Unknown',
        itemEmoji: m['item_emoji'] as String? ?? '📦',
        bucketName: m['bucket_name'] as String? ?? 'Unknown',
        bucketBarcode: m['bucket_barcode'] as String? ?? '',
        quantity: m['quantity'] as int? ?? 0,
        status: m['status'] as String? ?? 'normal',
      );
    }).toList();
  }

  /// Friendly action label for display.
  String get actionLabel {
    switch (kind) {
      case 'checkout':
        return 'checked out';
      case 'return':
        return 'returned';
      case 'resolved_lost':
        return 'resolved (lost)';
      case 'resolved_damaged':
        return 'resolved (damaged)';
      case 'bucket_created':
        return 'created bucket';
      case 'bucket_updated':
        return 'updated bucket';
      case 'bucket_deleted':
        return 'deleted bucket';
      case 'user_created':
        return 'created user';
      case 'user_updated':
        return 'updated user';
      case 'user_deleted':
        return 'deleted user';
      default:
        return kind;
    }
  }

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String,
      kind: json['kind'] as String,
      actorId: json['actor_id'] as String,
      actorName: json['actor_name'] as String? ?? 'Unknown',
      entity: json['entity'] as String,
      summary: json['summary'] as String? ?? '',
      meta: json['meta'],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ActivityLineItem {
  const ActivityLineItem({
    required this.itemName,
    required this.itemEmoji,
    required this.bucketName,
    required this.bucketBarcode,
    required this.quantity,
    required this.status,
  });

  final String itemName;
  final String itemEmoji;
  final String bucketName;
  final String bucketBarcode;
  final int quantity;
  final String status; // 'normal', 'lost', 'damaged'
}