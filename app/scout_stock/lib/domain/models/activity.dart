/// Represents a single activity feed item from the backend.
///
/// The backend merges two sources into one feed:
/// - `audit_logs` rows → action like "bucket_created", "user_updated", etc.
/// - `transactions` rows → action is "checkout", "return", or "resolve"
///
/// Both share the same shape: id, action, actor_name, summary, meta, created_at.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.action,
    required this.actorId,
    required this.actorName,
    required this.summary,
    required this.meta,
    required this.createdAt,
    required this.source,
  });

  final String id;

  /// e.g. "bucket_created", "bucket_updated", "user_created",
  ///      "checkout", "return", "resolve", "bucket_deleted", etc.
  final String action;

  final String actorId;
  final String actorName;

  /// Human-readable one-liner from the backend
  final String summary;

  /// Structured detail for the expandable area. Shape varies by action.
  final Map<String, dynamic> meta;

  final DateTime createdAt;

  /// "audit" or "transaction"
  final String source;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String,
      action: json['action'] as String,
      actorId: json['actor_id'] as String,
      actorName: json['actor_name'] as String,
      summary: json['summary'] as String? ?? '',
      meta: json['meta'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      source: json['source'] as String? ?? 'audit',
    );
  }

  // ── Expandable content helpers ────────────────────────────────────────

  /// Items list for checkout/return and bucket_created
  List<ActivityItemDetail> get items {
    final raw = meta['items'] as List?;
    if (raw == null) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((e) => ActivityItemDetail.fromJson(e))
        .toList();
  }

  /// Changes list for bucket_updated / user_updated.
  /// Handles both legacy format (plain strings) and new structured format.
  List<ActivityChangeDetail> get changes {
    final raw = meta['changes'] as List?;
    if (raw == null) return const [];
    return raw.map((e) {
      if (e is Map<String, dynamic>) {
        return ActivityChangeDetail.fromJson(e);
      }
      return ActivityChangeDetail(
        kind: 'unknown',
        description: e.toString(),
      );
    }).toList();
  }

  /// Whether this entry has expandable content
  bool get hasExpandableContent {
    switch (action) {
      case 'checkout':
      case 'return':
      case 'resolve':
        return items.isNotEmpty;
      case 'bucket_created':
        return items.isNotEmpty;
      case 'bucket_updated':
      case 'user_updated':
        return changes.isNotEmpty;
      default:
        return false;
    }
  }
}

/// Item detail within a checkout/return/bucket_created/resolve event.
class ActivityItemDetail {
  const ActivityItemDetail({
    required this.quantity,
    required this.itemName,
    this.itemEmoji,
    this.bucketName,
    this.bucketBarcode,
    this.status,
  });

  final int quantity;
  final String itemName;
  final String? itemEmoji;
  final String? bucketName;
  final String? bucketBarcode;

  /// For resolve items: "normal" (returned), "lost", "damaged"
  final String? status;

  factory ActivityItemDetail.fromJson(Map<String, dynamic> json) {
    return ActivityItemDetail(
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      itemName: json['item_name'] as String? ?? json['name'] as String? ?? 'Unknown',
      itemEmoji: json['item_emoji'] as String? ?? json['emoji'] as String?,
      bucketName: json['bucket_name'] as String?,
      bucketBarcode: json['bucket_barcode'] as String?,
      status: json['status'] as String?,
    );
  }

  /// Human-readable resolve action label
  String get resolveActionLabel {
    switch (status) {
      case 'normal':
        return 'returned';
      case 'lost':
        return 'marked lost';
      case 'damaged':
        return 'marked damaged';
      default:
        return 'resolved';
    }
  }
}

/// Change detail within a bucket_updated / user_updated event.
class ActivityChangeDetail {
  const ActivityChangeDetail({
    required this.kind,
    required this.description,
  });

  final String kind;
  final String description;

  factory ActivityChangeDetail.fromJson(Map<String, dynamic> json) {
    return ActivityChangeDetail(
      kind: json['kind'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '',
    );
  }
}

/// Paginated response wrapper.
class ActivityPageResponse {
  const ActivityPageResponse({
    required this.items,
    required this.hasMore,
  });

  final List<ActivityEntry> items;
  final bool hasMore;
}